"use strict";

const bcrypt = require("bcryptjs");
const { getPool, signToken, methodNotAllowed, parseJsonBody, normalizeEmail, ensureAppSchema } = require("../_shared.js");

module.exports = async (req, res) => {
  if (req.method !== "POST") {
    return methodNotAllowed(res, "POST");
  }
  let body;
  try {
    body = parseJsonBody(req);
  } catch (err) {
    return res.status(err.status || 400).json({ error: err.message });
  }
  const email = normalizeEmail(body?.email);
  const password = String(body?.password || "");
  if (!email || !password) {
    return res.status(400).json({ error: "Email and password required" });
  }
  try {
    await ensureAppSchema();
    const { rows } = await getPool().query(
      `select id, email, password_hash from public.users where lower(email) = lower($1)`,
      [email],
    );
    const row = rows[0];
    if (!row) {
      return res.status(401).json({ error: "Invalid email or password" });
    }
    if (!row.password_hash) {
      return res.status(401).json({ error: "This account uses Google sign-in." });
    }
    const match = bcrypt.compareSync(password, row.password_hash);
    if (!match) {
      return res.status(401).json({ error: "Invalid email or password" });
    }
    const token = signToken({ id: row.id, email: row.email });
    return res.status(200).json({ token, user: { id: row.id, email: row.email } });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ error: "Login failed" });
  }
};
