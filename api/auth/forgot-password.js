"use strict";

const crypto = require("crypto");
const { getPool, methodNotAllowed, parseJsonBody, normalizeEmail, ensureAppSchema, getRequestOrigin } = require("../_shared.js");
const { escapeHtml, sendEmail } = require("../email.js");

function hashToken(raw) {
  return crypto.createHash("sha256").update(String(raw), "utf8").digest("hex");
}

async function sendPasswordResetEmail({ to, resetUrl }) {
  const safeUrl = escapeHtml(resetUrl);
  const html = `<p>We received a request to reset your password.</p>
<p><a href="${safeUrl}">Set a new password</a> (link valid for 1 hour).</p>
<p>If you did not ask for this, you can ignore this email.</p>`;
  await sendEmail({ to, subject: "Reset your attendance tracker password", html });
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
  const email = normalizeEmail(body?.email);
  const generic = { ok: true, message: "If that email is registered, a reset link was sent." };

  if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return res.status(200).json(generic);
  }

  try {
    await ensureAppSchema();
    const { rows } = await getPool().query(`select id, email from public.users where lower(email) = lower($1)`, [
      email,
    ]);
    const user = rows[0];
    if (user) {
      const raw = crypto.randomBytes(32).toString("base64url");
      const tokenHash = hashToken(raw);
      const expiresAt = new Date(Date.now() + 60 * 60 * 1000).toISOString();
      await getPool().query(`delete from public.password_reset_tokens where user_id = $1 and used_at is null`, [
        user.id,
      ]);
      await getPool().query(
        `insert into public.password_reset_tokens (user_id, token_hash, expires_at) values ($1, $2, $3::timestamptz)`,
        [user.id, tokenHash, expiresAt],
      );
      let origin = String(process.env.WFH_PUBLIC_ORIGIN || "").trim().replace(/\/$/, "");
      if (!origin) {
        origin = getRequestOrigin(req);
      }
      if (origin) {
        const resetUrl = `${origin}/reset.html?token=${encodeURIComponent(raw)}`;
        await sendPasswordResetEmail({ to: user.email, resetUrl });
      } else {
        console.warn("[WFH] Could not determine public URL; set WFH_PUBLIC_ORIGIN on Vercel.");
      }
    }
    return res.status(200).json(generic);
  } catch (err) {
    console.error(err);
    return res.status(500).json({ error: "Could not process reset request" });
  }
};
