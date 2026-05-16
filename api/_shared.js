"use strict";

const { Pool } = require("pg");
const jwt = require("jsonwebtoken");

let pool;

/**
 * Neon (and other hosts) usually set `DATABASE_URL`. Some Vercel templates expose `POSTGRES_URL`
 * instead — treat it as the same pooled Postgres URL.
 */
function getDatabaseUrl() {
  const candidates = [
    process.env.DATABASE_URL,
    process.env.POSTGRES_URL,
    process.env.POSTGRES_PRISMA_URL,
    process.env.POSTGRES_URL_NON_POOLING,
  ];
  for (const c of candidates) {
    const s = String(c || "").trim();
    if (s) {
      return s;
    }
  }
  return "";
}

/**
 * Prefer `JWT_SECRET`. `SUPABASE_JWT_SECRET` is only a fallback env name used by some Vercel
 * project templates — this app does not use the Supabase JS client.
 */
function getJwtSecretRaw() {
  const candidates = [process.env.JWT_SECRET, process.env.SUPABASE_JWT_SECRET];
  for (const c of candidates) {
    const s = String(c || "").trim();
    if (s) {
      return s;
    }
  }
  return "";
}

/**
 * Pooler URLs often include `sslmode=verify-full` (or similar). Node `pg` then verifies the
 * chain and can throw `SELF_SIGNED_CERT_IN_CHAIN` even when we pass `rejectUnauthorized: false`.
 * Strip sslmode so our explicit `ssl` option controls TLS for serverless → managed Postgres.
 */
function normalizeConnectionStringForNodePg(url) {
  const raw = String(url).trim();
  try {
    const normalized = raw.replace(/^postgres(ql)?:\/\//i, "http://");
    const u = new URL(normalized);
    u.searchParams.delete("sslmode");
    let rebuilt = u.toString().replace(/^http:\/\//i, "postgresql://");
    if (/^postgres:\/\//i.test(raw)) {
      rebuilt = rebuilt.replace(/^postgresql:\/\//i, "postgres://");
    }
    return rebuilt;
  } catch {
    return raw
      .replace(/([?&])sslmode=[^&]*/gi, "$1")
      .replace(/\?&/g, "?")
      .replace(/&&/g, "&")
      .replace(/\?$/, "");
  }
}

function getPool() {
  if (!pool) {
    const connectionString = normalizeConnectionStringForNodePg(getDatabaseUrl());
    if (!connectionString) {
      throw new Error("No database URL: set DATABASE_URL or connect a Postgres integration (POSTGRES_URL).");
    }
    const useSsl = !/localhost|127\.0\.0\.1/i.test(connectionString);
    pool = new Pool({
      connectionString,
      max: 2,
      idleTimeoutMillis: 20000,
      connectionTimeoutMillis: 15000,
      ssl: useSsl ? { rejectUnauthorized: false } : false,
    });
  }
  return pool;
}

function getJwtSecret() {
  const s = getJwtSecretRaw();
  if (!s || s.length < 16) {
    throw new Error(
      "No signing secret: set JWT_SECRET (≥16 chars) on Vercel, or the legacy SUPABASE_JWT_SECRET name if your template uses it.",
    );
  }
  return s;
}

function signToken(user) {
  return jwt.sign({ sub: user.id, email: user.email }, getJwtSecret(), { expiresIn: "30d" });
}

function requireAuth(req) {
  const header = req.headers.authorization || "";
  const token = header.startsWith("Bearer ") ? header.slice(7) : null;
  if (!token) {
    return { error: "Missing bearer token", status: 401 };
  }
  try {
    const payload = jwt.verify(token, getJwtSecret());
    return { userId: payload.sub, email: payload.email };
  } catch {
    return { error: "Invalid or expired token", status: 401 };
  }
}

function normalizeEmail(email) {
  return String(email || "")
    .trim()
    .toLowerCase();
}

let schemaDone = false;
let resetTokenSchemaDone = false;

/**
 * Idempotent DDL for `public.users` + `public.app_state` (matches `neon/schema.sql`).
 * Runs on first DB use so Vercel + managed Postgres integrations work without a manual SQL step.
 */
async function ensureAppSchema() {
  const pool = getPool();
  const client = await pool.connect();
  try {
    if (!schemaDone) {
      await client.query('create extension if not exists "pgcrypto"');
      await client.query(`
        create table if not exists public.users (
          id uuid primary key default gen_random_uuid(),
          email text not null unique,
          password_hash text,
          google_sub text unique,
          auth_provider text not null default 'password',
          created_at timestamptz not null default now()
        )`);
      await client.query(`alter table public.users alter column password_hash drop not null`);
      await client.query(`alter table public.users add column if not exists google_sub text`);
      await client.query(`alter table public.users add column if not exists auth_provider text not null default 'password'`);
      await client.query(
        `create unique index if not exists users_google_sub_idx on public.users (google_sub) where google_sub is not null`,
      );
      await client.query(
        `create index if not exists users_email_lower_idx on public.users (lower(email))`,
      );
      await client.query(`
        create table if not exists public.app_state (
          user_id uuid primary key references public.users (id) on delete cascade,
          payload jsonb not null,
          updated_at timestamptz not null default now()
        )`);
      await client.query(
        `create index if not exists app_state_updated_at_idx on public.app_state (updated_at desc)`,
      );
      schemaDone = true;
    }
    if (!resetTokenSchemaDone) {
      await client.query(`
        create table if not exists public.password_reset_tokens (
          id uuid primary key default gen_random_uuid(),
          user_id uuid not null references public.users (id) on delete cascade,
          token_hash text not null,
          expires_at timestamptz not null,
          used_at timestamptz,
          created_at timestamptz not null default now()
        )`);
      await client.query(
        `create index if not exists password_reset_tokens_hash_idx on public.password_reset_tokens (token_hash)`,
      );
      await client.query(
        `create index if not exists password_reset_tokens_user_idx on public.password_reset_tokens (user_id)`,
      );
      resetTokenSchemaDone = true;
    }
  } finally {
    client.release();
  }
}

function getRequestOrigin(req) {
  const proto = String(req.headers["x-forwarded-proto"] || "https").split(",")[0].trim();
  const host = String(req.headers["x-forwarded-host"] || req.headers.host || "")
    .split(",")[0]
    .trim();
  if (!host) {
    return "";
  }
  return `${proto}://${host}`.replace(/\/$/, "");
}

module.exports = { getPool, signToken, requireAuth, normalizeEmail, ensureAppSchema, getRequestOrigin };
