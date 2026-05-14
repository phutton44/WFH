"use strict";

const { Pool } = require("pg");
const jwt = require("jsonwebtoken");

let pool;

function getPool() {
  if (!pool) {
    const connectionString = process.env.DATABASE_URL;
    if (!connectionString || String(connectionString).trim() === "") {
      throw new Error("DATABASE_URL is not set");
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
  const s = process.env.JWT_SECRET;
  if (!s || String(s).length < 16) {
    throw new Error("JWT_SECRET must be set and at least 16 characters");
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

module.exports = { getPool, signToken, requireAuth, normalizeEmail };
