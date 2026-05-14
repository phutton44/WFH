"use strict";

/**
 * Shared password rules for register + reset-password.
 * Minimum 12 characters, at least one uppercase Latin letter, one special character.
 */
const SPECIAL_RE = /[!-\/:-@\[-`{-~]/;

function validatePassword(password) {
  const p = String(password || "");
  if (p.length < 12) {
    return { ok: false, error: "Password must be at least 12 characters." };
  }
  if (!/[A-Z]/.test(p)) {
    return { ok: false, error: "Password must include at least one uppercase letter (A–Z)." };
  }
  if (!SPECIAL_RE.test(p)) {
    return {
      ok: false,
      error: "Password must include at least one special character (e.g. ! @ # $ % ^ & *).",
    };
  }
  return { ok: true };
}

module.exports = { validatePassword };
