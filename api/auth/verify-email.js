"use strict";

const crypto = require("crypto");
const { getPool, methodNotAllowed, parseJsonBody, ensureAppSchema } = require("../_shared.js");

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
  if (!token) {
    return res.status(400).json({ error: "Verification token required" });
  }

  const client = await getPool().connect();
  try {
    await ensureAppSchema();
    await client.query("BEGIN");
    const { rows } = await client.query(
      `select id, user_id from public.email_verification_tokens
       where token_hash = $1 and used_at is null and expires_at > now()
       for update`,
      [hashToken(token)],
    );
    const row = rows[0];
    if (!row) {
      await client.query("ROLLBACK");
      return res.status(400).json({ error: "Invalid or expired confirmation link. Create the account again to receive a new link." });
    }
    await client.query(`update public.users set email_verified_at = coalesce(email_verified_at, now()) where id = $1`, [
      row.user_id,
    ]);
    await client.query(`update public.email_verification_tokens set used_at = now() where id = $1`, [row.id]);
    await client.query("COMMIT");
    return res.status(200).json({ ok: true, message: "Email confirmed. You can sign in now." });
  } catch (err) {
    await client.query("ROLLBACK").catch(() => {});
    console.error(err);
    return res.status(500).json({ error: "Could not confirm email" });
  } finally {
    client.release();
  }
};
