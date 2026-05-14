"use strict";

const { getPool, requireAuth, ensureAppSchema } = require("./_shared.js");

module.exports = async (req, res) => {
  const auth = requireAuth(req);
  if (auth.error) {
    return res.status(auth.status).json({ error: auth.error });
  }

  try {
    await ensureAppSchema();
  } catch (err) {
    console.error(err);
    return res.status(500).json({ error: "Database unavailable" });
  }

  if (req.method === "GET") {
    try {
      const { rows } = await getPool().query(
        `select payload, updated_at from public.app_state where user_id = $1`,
        [auth.userId],
      );
      const row = rows[0];
      if (!row) {
        return res.status(200).json({ payload: null });
      }
      return res.status(200).json({ payload: row.payload, updatedAt: row.updated_at });
    } catch (err) {
      console.error(err);
      return res.status(500).json({ error: "Could not load state" });
    }
  }

  if (req.method === "PUT") {
    let body = req.body;
    if (typeof body === "string") {
      try {
        body = JSON.parse(body || "{}");
      } catch {
        return res.status(400).json({ error: "Invalid JSON" });
      }
    }
    const payload = body?.payload;
    if (payload === undefined || payload === null) {
      return res.status(400).json({ error: "payload required" });
    }
    if (typeof payload !== "object" || Array.isArray(payload)) {
      return res.status(400).json({ error: "payload must be a JSON object" });
    }
    try {
      await getPool().query(
        `insert into public.app_state (user_id, payload, updated_at)
         values ($1, $2::jsonb, now())
         on conflict (user_id) do update set
           payload = excluded.payload,
           updated_at = now()`,
        [auth.userId, JSON.stringify(payload)],
      );
      return res.status(200).json({ ok: true });
    } catch (err) {
      console.error(err);
      return res.status(500).json({ error: "Could not save state" });
    }
  }

  res.setHeader("Allow", "GET, PUT");
  return res.status(405).json({ error: "Method not allowed" });
};
