"use strict";

const crypto = require("crypto");
const { getPool, signToken, methodNotAllowed, parseJsonBody, normalizeEmail, ensureAppSchema } = require("../_shared.js");

let appleKeys;
let appleKeysExpiresAt = 0;

function uniqueTruthy(values) {
  return Array.from(new Set(values.map((value) => String(value || "").trim()).filter(Boolean)));
}

function getAppleAudiences() {
  return uniqueTruthy([
    process.env.APPLE_CLIENT_ID,
    process.env.WFH_APPLE_CLIENT_ID,
    process.env.APPLE_BUNDLE_ID,
    process.env.APPLE_IOS_BUNDLE_ID,
    process.env.WFH_APPLE_IOS_BUNDLE_ID,
    "com.paulhutton.wfhattendance.ios",
  ]);
}

function decodeBase64UrlJson(part) {
  return JSON.parse(Buffer.from(String(part), "base64url").toString("utf8"));
}

async function getAppleKey(kid) {
  const now = Date.now();
  if (!appleKeys || now >= appleKeysExpiresAt) {
    const res = await fetch("https://appleid.apple.com/auth/keys");
    if (!res.ok) {
      throw new Error("Could not fetch Apple signing keys");
    }
    const data = await res.json();
    appleKeys = new Map((data.keys || []).map((key) => [key.kid, key]));
    appleKeysExpiresAt = now + 6 * 60 * 60 * 1000;
  }
  const jwk = appleKeys.get(kid);
  if (!jwk) {
    throw new Error("Unknown Apple signing key");
  }
  return crypto.createPublicKey({ key: jwk, format: "jwk" });
}

async function verifyAppleIdToken(idToken) {
  const audiences = getAppleAudiences();
  if (audiences.length === 0) {
    const err = new Error("Apple sign-in is not configured.");
    err.status = 503;
    throw err;
  }

  const parts = String(idToken || "").split(".");
  if (parts.length !== 3) {
    const err = new Error("Invalid Apple credential.");
    err.status = 400;
    throw err;
  }

  const [encodedHeader, encodedPayload, encodedSignature] = parts;
  const header = decodeBase64UrlJson(encodedHeader);
  const payload = decodeBase64UrlJson(encodedPayload);
  if (header.alg !== "ES256" || !header.kid) {
    const err = new Error("Invalid Apple credential.");
    err.status = 400;
    throw err;
  }

  const key = await getAppleKey(header.kid);
  const rawSignature = Buffer.from(encodedSignature, "base64url");
  const ok = rawSignature.length === 64
    && crypto.verify(
      "sha256",
      Buffer.from(`${encodedHeader}.${encodedPayload}`),
      { key, dsaEncoding: "ieee-p1363" },
      rawSignature,
    );
  if (!ok) {
    const err = new Error("Invalid Apple credential.");
    err.status = 401;
    throw err;
  }

  const now = Math.floor(Date.now() / 1000);
  if (payload.iss !== "https://appleid.apple.com") {
    const err = new Error("Invalid Apple issuer.");
    err.status = 401;
    throw err;
  }
  if (!audiences.includes(payload.aud)) {
    const err = new Error("Invalid Apple audience.");
    err.status = 401;
    throw err;
  }
  if (!payload.exp || Number(payload.exp) <= now) {
    const err = new Error("Apple credential expired.");
    err.status = 401;
    throw err;
  }
  if (!payload.sub) {
    const err = new Error("Apple account is invalid.");
    err.status = 401;
    throw err;
  }

  const email = normalizeEmail(payload.email);
  return { sub: String(payload.sub), email: email || null };
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

  try {
    const appleUser = await verifyAppleIdToken(body?.credential || body?.idToken);
    await ensureAppSchema();
    const client = await getPool().connect();
    try {
      await client.query("BEGIN");
      let { rows } = await client.query(
        `select id, email, apple_sub from public.users where apple_sub = $1 for update`,
        [appleUser.sub],
      );
      let user = rows[0];

      if (!user && appleUser.email) {
        ({ rows } = await client.query(
          `select id, email, apple_sub from public.users where lower(email) = lower($1) for update`,
          [appleUser.email],
        ));
        user = rows[0];
        if (user?.apple_sub && user.apple_sub !== appleUser.sub) {
          await client.query("ROLLBACK");
          return res.status(409).json({ error: "That email is linked to another Apple ID." });
        }
        if (user) {
          ({ rows } = await client.query(
            `update public.users
             set apple_sub = coalesce(apple_sub, $2),
                 auth_provider = case
                   when password_hash is null then 'apple'
                   when auth_provider = 'password' then 'password_apple'
                   else auth_provider
                 end
             where id = $1
             returning id, email`,
            [user.id, appleUser.sub],
          ));
          user = rows[0];
        }
      }

      if (!user) {
        const email = appleUser.email || `apple-${appleUser.sub}@privaterelay.appleid.com`;
        ({ rows } = await client.query(
          `insert into public.users (email, password_hash, apple_sub, auth_provider)
           values ($1, null, $2, 'apple')
           returning id, email`,
          [email, appleUser.sub],
        ));
        user = rows[0];
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
    console.error("Apple sign-in failed", {
      message: err.message,
      status,
    });
    return res.status(status).json({ error: err.message || "Apple sign-in failed" });
  }
};
