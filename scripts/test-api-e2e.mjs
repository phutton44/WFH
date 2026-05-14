#!/usr/bin/env node
/**
 * Smoke-test deployed (or local) auth + state API without a browser.
 * Usage:
 *   WFH_TEST_URL=https://your-app.vercel.app npm test
 * Defaults to https://wfh-one.vercel.app if WFH_TEST_URL is unset.
 */
const base = (process.env.WFH_TEST_URL || "https://wfh-one.vercel.app").replace(/\/$/, "");
const email = `ci-e2e-${Date.now()}@example.com`;
const password = "ci-e2e-pass-9chars";

async function req(method, path, { headers = {}, body } = {}) {
  const url = `${base}${path.startsWith("/") ? path : `/${path}`}`;
  const h = { ...headers };
  let b;
  if (body != null && typeof body === "object") {
    h["Content-Type"] = "application/json";
    b = JSON.stringify(body);
  }
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), 35000);
  try {
    const res = await fetch(url, { method, headers: h, body: b, signal: ctrl.signal });
    const text = await res.text();
    let data = null;
    try {
      data = text ? JSON.parse(text) : null;
    } catch {
      data = { _raw: text };
    }
    return { ok: res.ok, status: res.status, data };
  } finally {
    clearTimeout(t);
  }
}

function fail(msg) {
  console.error(msg);
  process.exit(1);
}

async function main() {
  console.log("WFH API E2E against", base);

  const h = await req("GET", "/api/health");
  if (!h.ok || h.data?.ok !== true) {
    fail(`health: expected 200 {ok:true}, got ${h.status} ${JSON.stringify(h.data)}`);
  }
  console.log("  ✓ GET /api/health");

  const reg = await req("POST", "/api/auth/register", {
    body: { email, password },
  });
  if (!reg.ok || !reg.data?.token || !reg.data?.user?.id) {
    fail(`register: expected 201 + token, got ${reg.status} ${JSON.stringify(reg.data)}`);
  }
  const token = reg.data.token;
  console.log("  ✓ POST /api/auth/register");

  const st = await req("GET", "/api/state", {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!st.ok || !("payload" in (st.data || {}))) {
    fail(`state GET: expected 200 + payload field, got ${st.status} ${JSON.stringify(st.data)}`);
  }
  console.log("  ✓ GET /api/state");

  const login = await req("POST", "/api/auth/login", {
    body: { email, password },
  });
  if (!login.ok || !login.data?.token) {
    fail(`login: expected 200 + token, got ${login.status} ${JSON.stringify(login.data)}`);
  }
  console.log("  ✓ POST /api/auth/login");

  const me = await req("GET", "/api/auth/me", {
    headers: { Authorization: `Bearer ${login.data.token}` },
  });
  if (!me.ok || me.data?.user?.email !== email) {
    fail(`me: expected 200 + user email, got ${me.status} ${JSON.stringify(me.data)}`);
  }
  console.log("  ✓ GET /api/auth/me");

  console.log("All API checks passed.");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
