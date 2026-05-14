"use strict";

const bcrypt = require("bcryptjs");
const { getPool, signToken, normalizeEmail, ensureAppSchema } = require("../_shared.js");
const { validatePassword } = require("../passwordPolicy.js");

module.exports = async (req, res) => {
  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
    return res.status(405).json({ error: "Method not allowed" });
  }
  let body = req.body;
  if (typeof body === "string") {
    try {
      body = JSON.parse(body || "{}");
    } catch {
      return res.status(400).json({ error: "Invalid JSON" });
    }
  }
  const email = normalizeEmail(body?.email);
  const password = String(body?.password || "");
  if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return res.status(400).json({ error: "Valid email required" });
  }
  const pv = validatePassword(password);
  if (!pv.ok) {
    return res.status(400).json({ error: pv.error });
  }
  const passwordHash = bcrypt.hashSync(password, 10);
  try {
    await ensureAppSchema();
    const { rows } = await getPool().query(
      `insert into public.users (email, password_hash) values ($1, $2) returning id, email`,
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
};
