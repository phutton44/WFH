"use strict";

const crypto = require("crypto");
const bcrypt = require("bcryptjs");
const {
  getPool,
  methodNotAllowed,
  parseJsonBody,
  normalizeEmail,
  ensureAppSchema,
  getRequestOrigin,
} = require("../_shared.js");
const { escapeHtml, sendEmail } = require("../email.js");
const { validatePassword } = require("../passwordPolicy.js");

function hashToken(raw) {
  return crypto.createHash("sha256").update(String(raw), "utf8").digest("hex");
}

async function sendVerificationEmail({ req, to, token }) {
  let origin = String(process.env.WFH_PUBLIC_ORIGIN || "").trim().replace(/\/$/, "");
  if (!origin) origin = getRequestOrigin(req);
  if (!origin) {
    console.warn("[WFH] Could not determine public URL; set WFH_PUBLIC_ORIGIN on Vercel.");
    return;
  }
  const verifyUrl = `${origin}/?verify=${encodeURIComponent(token)}`;
  const safeUrl = escapeHtml(verifyUrl);
  const html = `<p>Welcome to Work Attendance.</p>
<p>Please confirm this email address before signing in:</p>
<p><a href="${safeUrl}">Confirm your account</a> (link valid for 24 hours).</p>
<p>If you did not create this account, you can ignore this email.</p>`;
  await sendEmail({ to, subject: "Confirm your Work Attendance account", html });
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
  const password = String(body?.password || "");
  if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return res.status(400).json({ error: "Enter a valid email address." });
  }
  const v = validatePassword(password);
  if (!v.ok) {
    return res.status(400).json({ error: v.error });
  }

  const client = await getPool().connect();
  try {
    await ensureAppSchema();
    const passwordHash = bcrypt.hashSync(password, 10);
    const raw = crypto.randomBytes(32).toString("base64url");
    const tokenHash = hashToken(raw);
    const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();

    await client.query("BEGIN");
    const existing = await client.query(
      `select id, email, email_verified_at, password_hash from public.users where lower(email) = lower($1) for update`,
      [email],
    );
    const row = existing.rows[0];
    if (row?.email_verified_at) {
      await client.query("ROLLBACK");
      return res.status(409).json({ error: "An account already exists for that email. Sign in or reset your password." });
    }
    const user = row
      ? (
          await client.query(
            `update public.users
                set password_hash = $1,
                    auth_provider = case when auth_provider in ('google', 'apple') then auth_provider else 'password' end
              where id = $2
              returning id, email`,
            [passwordHash, row.id],
          )
        ).rows[0]
      : (
          await client.query(
            `insert into public.users (email, password_hash, auth_provider)
             values ($1, $2, 'password')
             returning id, email`,
            [email, passwordHash],
          )
        ).rows[0];

    await client.query(`delete from public.email_verification_tokens where user_id = $1 and used_at is null`, [user.id]);
    await client.query(
      `insert into public.email_verification_tokens (user_id, token_hash, expires_at)
       values ($1, $2, $3::timestamptz)`,
      [user.id, tokenHash, expiresAt],
    );
    await client.query("COMMIT");

    await sendVerificationEmail({ req, to: user.email, token: raw });
    return res.status(201).json({
      ok: true,
      message: "Account created. Check your email to confirm the account before signing in.",
    });
  } catch (err) {
    await client.query("ROLLBACK").catch(() => {});
    if (err?.code === "23505") {
      return res.status(409).json({ error: "An account already exists for that email. Sign in or reset your password." });
    }
    console.error(err);
    return res.status(500).json({ error: "Could not create account" });
  } finally {
    client.release();
  }
};
