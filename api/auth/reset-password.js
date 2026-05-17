"use strict";

const crypto = require("crypto");
const bcrypt = require("bcryptjs");
const { getPool, methodNotAllowed, parseJsonBody, ensureAppSchema } = require("../_shared.js");
const { validatePassword } = require("../passwordPolicy.js");

function hashToken(raw) {
  return crypto.createHash("sha256").update(String(raw), "utf8").digest("hex");
}

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
  const token = String(body?.token || "").trim();
  const password = String(body?.password || "");
  if (!token) {
    return res.status(400).json({ error: "Reset token required" });
  }
  const v = validatePassword(password);
  if (!v.ok) {
    return res.status(400).json({ error: v.error });
  }

  const tokenHash = hashToken(token);
  const client = await getPool().connect();
  try {
    await ensureAppSchema();
    await client.query("BEGIN");
    const { rows } = await client.query(
      `select id, user_id from public.password_reset_tokens
       where token_hash = $1 and used_at is null and expires_at > now()
       for update`,
      [tokenHash],
    );
    const row = rows[0];
    if (!row) {
      await client.query("ROLLBACK");
      return res.status(400).json({ error: "Invalid or expired reset link. Request a new one." });
    }
    const passwordHash = bcrypt.hashSync(password, 10);
    await client.query(`update public.users set password_hash = $1 where id = $2`, [passwordHash, row.user_id]);
    await client.query(`update public.password_reset_tokens set used_at = now() where id = $1`, [row.id]);
    await client.query("COMMIT");
    return res.status(200).json({ ok: true });
  } catch (err) {
    await client.query("ROLLBACK").catch(() => {});
    console.error(err);
    return res.status(500).json({ error: "Could not reset password" });
  } finally {
    client.release();
  }
};
