"use strict";

const crypto = require("crypto");
const { getPool, signToken, normalizeEmail, ensureAppSchema } = require("../_shared.js");

let googleKeys;
let googleKeysExpiresAt = 0;

function getGoogleClientIds() {
  return [
    process.env.GOOGLE_CLIENT_ID,
    process.env.WFH_GOOGLE_CLIENT_ID,
    process.env.GOOGLE_IOS_CLIENT_ID,
    process.env.WFH_GOOGLE_IOS_CLIENT_ID,
  ]
    .map((value) => String(value || "").trim())
    .filter(Boolean);
}

function decodeBase64UrlJson(part) {
  return JSON.parse(Buffer.from(String(part), "base64url").toString("utf8"));
}

async function getGoogleKey(kid) {
  const now = Date.now();
  if (!googleKeys || now >= googleKeysExpiresAt) {
    const res = await fetch("https://www.googleapis.com/oauth2/v3/certs");
    if (!res.ok) {
      throw new Error("Could not fetch Google signing keys");
    }
    const cacheControl = String(res.headers.get("cache-control") || "");
    const maxAgeMatch = cacheControl.match(/max-age=(\d+)/i);
    const maxAgeMs = maxAgeMatch ? Number(maxAgeMatch[1]) * 1000 : 60 * 60 * 1000;
    const data = await res.json();
    googleKeys = new Map((data.keys || []).map((key) => [key.kid, key]));
    googleKeysExpiresAt = now + maxAgeMs;
  }
  const jwk = googleKeys.get(kid);
  if (!jwk) {
    throw new Error("Unknown Google signing key");
  }
  return crypto.createPublicKey({ key: jwk, format: "jwk" });
}

async function verifyGoogleIdToken(idToken) {
  const clientIds = getGoogleClientIds();
  if (clientIds.length === 0) {
    const err = new Error("Google sign-in is not configured.");
    err.status = 503;
    throw err;
  }

  const parts = String(idToken || "").split(".");
  if (parts.length !== 3) {
    const err = new Error("Invalid Google credential.");
    err.status = 400;
    throw err;
  }

  const [encodedHeader, encodedPayload, encodedSignature] = parts;
  const header = decodeBase64UrlJson(encodedHeader);
  const payload = decodeBase64UrlJson(encodedPayload);
  if (header.alg !== "RS256" || !header.kid) {
    const err = new Error("Invalid Google credential.");
    err.status = 400;
    throw err;
  }

  const key = await getGoogleKey(header.kid);
  const ok = crypto.verify(
    "RSA-SHA256",
    Buffer.from(`${encodedHeader}.${encodedPayload}`),
    key,
    Buffer.from(encodedSignature, "base64url"),
  );
  if (!ok) {
    const err = new Error("Invalid Google credential.");
    err.status = 401;
    throw err;
  }

  const now = Math.floor(Date.now() / 1000);
  if (!["accounts.google.com", "https://accounts.google.com"].includes(payload.iss)) {
    const err = new Error("Invalid Google issuer.");
    err.status = 401;
    throw err;
  }
  if (!clientIds.includes(payload.aud)) {
    const err = new Error("Invalid Google audience.");
    err.status = 401;
    throw err;
  }
  if (!payload.exp || Number(payload.exp) <= now) {
    const err = new Error("Google credential expired.");
    err.status = 401;
    throw err;
  }
  if (!payload.sub || payload.email_verified !== true) {
    const err = new Error("Google account email is not verified.");
    err.status = 401;
    throw err;
  }

  const email = normalizeEmail(payload.email);
  if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    const err = new Error("Google account email is invalid.");
    err.status = 400;
    throw err;
  }
  return { sub: String(payload.sub), email };
}

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

  try {
    const googleUser = await verifyGoogleIdToken(body?.credential || body?.idToken);
    await ensureAppSchema();
    const client = await getPool().connect();
    try {
      await client.query("BEGIN");
      let { rows } = await client.query(
        `select id, email, google_sub from public.users where google_sub = $1 for update`,
        [googleUser.sub],
      );
      let user = rows[0];

      if (!user) {
        ({ rows } = await client.query(
          `select id, email, google_sub from public.users where lower(email) = lower($1) for update`,
          [googleUser.email],
        ));
        user = rows[0];
        if (user?.google_sub && user.google_sub !== googleUser.sub) {
          await client.query("ROLLBACK");
          return res.status(409).json({ error: "That email is linked to another Google account." });
        }
        if (user) {
          ({ rows } = await client.query(
            `update public.users
             set google_sub = coalesce(google_sub, $2),
                 auth_provider = case
                   when password_hash is null then 'google'
                   when auth_provider = 'password' then 'password_google'
                   else auth_provider
                 end
             where id = $1
             returning id, email`,
            [user.id, googleUser.sub],
          ));
          user = rows[0];
        } else {
          ({ rows } = await client.query(
            `insert into public.users (email, password_hash, google_sub, auth_provider)
             values ($1, null, $2, 'google')
             returning id, email`,
            [googleUser.email, googleUser.sub],
          ));
          user = rows[0];
        }
      }

      await client.query("COMMIT");
      const token = signToken({ id: user.id, email: user.email });
      return res.status(200).json({ token, user: { id: user.id, email: user.email } });
    } catch (err) {
      await client.query("ROLLBACK").catch(() => {});
      throw err;
    } finally {
      client.release();
    }
  } catch (err) {
    const status = err.status || 500;
    if (status >= 500) {
      console.error(err);
    }
    return res.status(status).json({ error: err.message || "Google sign-in failed" });
  }
};
