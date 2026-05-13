"use strict";

require("dotenv").config();

const express = require("express");
const cors = require("cors");
const bcrypt = require("bcrypt");
const jwt = require("jsonwebtoken");
const { Pool } = require("pg");

const PORT = Number(process.env.PORT) || 3000;
const JWT_SECRET = process.env.JWT_SECRET;
const DATABASE_URL = process.env.DATABASE_URL;

if (!JWT_SECRET || JWT_SECRET.length < 16) {
  console.error("Set JWT_SECRET (at least 16 characters) in the environment.");
  process.exit(1);
}
if (!DATABASE_URL) {
  console.error("Set DATABASE_URL in the environment.");
  process.exit(1);
}

const pool = new Pool({
  connectionString: DATABASE_URL,
  ssl: /localhost|127\.0\.0\.1|railway\.internal/i.test(DATABASE_URL)
    ? false
    : { rejectUnauthorized: false },
});

const app = express();
app.set("trust proxy", 1);
app.use(express.json({ limit: "2mb" }));

const corsOrigins = (process.env.CORS_ORIGIN || "")
  .split(",")
  .map((s) => s.trim())
  .filter(Boolean);
app.use(
  cors({
    origin: corsOrigins.length ? corsOrigins : true,
    credentials: false,
  }),
);

function signToken(user) {
  return jwt.sign({ sub: user.id, email: user.email }, JWT_SECRET, { expiresIn: "30d" });
}

function requireAuth(req, res, next) {
  const header = req.headers.authorization || "";
  const token = header.startsWith("Bearer ") ? header.slice(7) : null;
  if (!token) {
    return res.status(401).json({ error: "Missing bearer token" });
  }
  try {
    const payload = jwt.verify(token, JWT_SECRET);
    req.userId = payload.sub;
    req.userEmail = payload.email;
    return next();
  } catch {
    return res.status(401).json({ error: "Invalid or expired token" });
  }
}

function normalizeEmail(email) {
  return String(email || "")
    .trim()
    .toLowerCase();
}

app.get("/health", (_req, res) => {
  res.json({ ok: true });
});

app.post("/api/auth/register", async (req, res) => {
  const email = normalizeEmail(req.body?.email);
  const password = String(req.body?.password || "");
  if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return res.status(400).json({ error: "Valid email required" });
  }
  if (password.length < 6) {
    return res.status(400).json({ error: "Password must be at least 6 characters" });
  }
  const passwordHash = await bcrypt.hash(password, 10);
  try {
    const { rows } = await pool.query(
      `insert into public.users (email, password_hash) values ($1, $2)
       returning id, email, created_at`,
      [email, passwordHash],
    );
    const user = rows[0];
    const token = signToken({ id: user.id, email: user.email });
    return res.status(201).json({ token, user: { id: user.id, email: user.email } });
  } catch (err) {
    if (err.code === "23505") {
      return res.status(409).json({ error: "Email already registered" });
    }
    console.error(err);
    return res.status(500).json({ error: "Registration failed" });
  }
});

app.post("/api/auth/login", async (req, res) => {
  const email = normalizeEmail(req.body?.email);
  const password = String(req.body?.password || "");
  if (!email || !password) {
    return res.status(400).json({ error: "Email and password required" });
  }
  try {
    const { rows } = await pool.query(
      `select id, email, password_hash from public.users where lower(email) = lower($1)`,
      [email],
    );
    const row = rows[0];
    if (!row) {
      return res.status(401).json({ error: "Invalid email or password" });
    }
    const match = await bcrypt.compare(password, row.password_hash);
    if (!match) {
      return res.status(401).json({ error: "Invalid email or password" });
    }
    const token = signToken({ id: row.id, email: row.email });
    return res.json({ token, user: { id: row.id, email: row.email } });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ error: "Login failed" });
  }
});

app.get("/api/auth/me", requireAuth, async (req, res) => {
  try {
    const { rows } = await pool.query(`select id, email from public.users where id = $1`, [req.userId]);
    const user = rows[0];
    if (!user) {
      return res.status(401).json({ error: "User not found" });
    }
    return res.json({ user: { id: user.id, email: user.email } });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ error: "Could not load user" });
  }
});

app.get("/api/state", requireAuth, async (req, res) => {
  try {
    const { rows } = await pool.query(`select payload, updated_at from public.app_state where user_id = $1`, [
      req.userId,
    ]);
    const row = rows[0];
    if (!row) {
      return res.json({ payload: null });
    }
    return res.json({ payload: row.payload, updatedAt: row.updated_at });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ error: "Could not load state" });
  }
});

app.put("/api/state", requireAuth, async (req, res) => {
  const payload = req.body?.payload;
  if (payload === undefined || payload === null) {
    return res.status(400).json({ error: "payload required" });
  }
  if (typeof payload !== "object" || Array.isArray(payload)) {
    return res.status(400).json({ error: "payload must be a JSON object" });
  }
  try {
    await pool.query(
      `insert into public.app_state (user_id, payload, updated_at)
       values ($1, $2::jsonb, now())
       on conflict (user_id) do update set
         payload = excluded.payload,
         updated_at = now()`,
      [req.userId, JSON.stringify(payload)],
    );
    return res.json({ ok: true });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ error: "Could not save state" });
  }
});

app.use((err, _req, res, _next) => {
  console.error(err);
  res.status(500).json({ error: "Server error" });
});

app.listen(PORT, () => {
  console.log(`WFH API listening on port ${PORT}`);
});
