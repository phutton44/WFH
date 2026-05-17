"use strict";

const crypto = require("crypto");
const { Resend } = require("resend");
const { getPool, methodNotAllowed, parseJsonBody, normalizeEmail, ensureAppSchema, getRequestOrigin } = require("../_shared.js");

function hashToken(raw) {
  return crypto.createHash("sha256").update(String(raw), "utf8").digest("hex");
}

/**
 * Password-reset mail is sent only via [Resend](https://resend.com) (`RESEND_API_KEY` + `RESEND_FROM_EMAIL`).
 * Missing env or API errors are logged; the HTTP handler still returns a generic success body.
 */
async function sendPasswordResetEmail({ to, resetUrl }) {
  const key = String(process.env.RESEND_API_KEY || "").trim();
  const from = String(process.env.RESEND_FROM_EMAIL || process.env.RESEND_FROM || "").trim();
  if (!key || !from) {
    console.warn("[WFH] Missing RESEND_API_KEY or RESEND_FROM_EMAIL — password reset email not sent.");
    return;
  }
  const safeUrl = resetUrl.replace(/&/g, "&amp;").replace(/"/g, "&quot;");
  const html = `<p>We received a request to reset your password.</p>
<p><a href="${safeUrl}">Set a new password</a> (link valid for 1 hour).</p>
<p>If you did not ask for this, you can ignore this email.</p>`;
  try {
    const resend = new Resend(key);
    const { error } = await resend.emails.send({
      from,
      to: [to],
      subject: "Reset your attendance tracker password",
      html,
    });
    if (error) {
      console.error("[WFH] Resend API error", error);
    }
  } catch (err) {
    console.error("[WFH] Resend send failed", err);
  }
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
