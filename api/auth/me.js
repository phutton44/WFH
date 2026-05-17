"use strict";

const { getPool, requireAuth, methodNotAllowed, ensureAppSchema } = require("../_shared.js");

module.exports = async (req, res) => {
  if (req.method !== "GET") {
    return methodNotAllowed(res, "GET");
  }
  const auth = requireAuth(req);
  if (auth.error) {
    return res.status(auth.status).json({ error: auth.error });
  }
  try {
    await ensureAppSchema();
    const { rows } = await getPool().query(`select id, email from public.users where id = $1`, [auth.userId]);
    const user = rows[0];
    if (!user) {
      return res.status(401).json({ error: "User not found" });
    }
    return res.status(200).json({ user: { id: user.id, email: user.email } });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ error: "Could not load user" });
  }
};
