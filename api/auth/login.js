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
      `select u.id,
              u.email,
              u.password_hash,
              u.email_verified_at,
              exists (
                select 1
                  from public.email_verification_tokens evt
                 where evt.user_id = u.id
                   and evt.used_at is null
              ) as needs_email_verification
         from public.users u
        where lower(u.email) = lower($1)`,
      [email],
    );
    const row = rows[0];
    if (!row) {
      return res.status(401).json({ error: "Invalid email or password" });
    }
    if (!row.password_hash) {
      return res.status(401).json({ error: "This account uses Google sign-in." });
    }
    if (!row.email_verified_at && row.needs_email_verification) {
      return res.status(403).json({ error: "Please confirm your email address before signing in." });
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
