"use strict";

const { methodNotAllowed } = require("../_shared.js");

module.exports = async (req, res) => {
  if (req.method !== "POST") {
    return methodNotAllowed(res, "POST");
  }
  return res.status(410).json({
    error: "Email/password registration is closed. Continue with Apple ID or Google.",
  });
};
