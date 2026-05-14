"use strict";

const { Pool } = require("pg");
const jwt = require("jsonwebtoken");

let pool;

/**
 * Vercel Postgres / Supabase / Neon integrations often expose `POSTGRES_URL` (pooled)
 * instead of `DATABASE_URL`. Prefer explicit `DATABASE_URL` when set.
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
 * Custom deploys use `JWT_SECRET`. Vercel Supabase integration exposes `SUPABASE_JWT_SECRET`.
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
    throw new Error("No signing secret: set JWT_SECRET (≥16 chars) or use Supabase integration (SUPABASE_JWT_SECRET).");
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

/**
 * Idempotent DDL for `public.users` + `public.app_state` (matches `neon/schema.sql`).
 * Runs on first DB use so Vercel + managed Postgres integrations work without a manual SQL step.
 */
async function ensureAppSchema() {
  if (schemaDone) {
    return;
  }
  const pool = getPool();
  const client = await pool.connect();
  try {
    await client.query('create extension if not exists "pgcrypto"');
    await client.query(`
      create table if not exists public.users (
        id uuid primary key default gen_random_uuid(),
        email text not null unique,
        password_hash text not null,
        created_at timestamptz not null default now()
      )`);
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
  } finally {
    client.release();
  }
  schemaDone = true;
}

module.exports = { getPool, signToken, requireAuth, normalizeEmail, ensureAppSchema };
