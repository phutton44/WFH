"use strict";

/**
 * Shared password rules for register + reset-password.
 * Minimum 12 characters, at least one uppercase Latin letter, one special character.
 */
const SPECIAL_RE = /[!-\/:-@\[-`{-~]/;

function validatePassword(password) {
  const p = String(password || "");
  if (p.length < 12) {
    return { ok: false, error: "Use at least 12 characters for your password." };
  }
  if (!/[A-Z]/.test(p)) {
    return { ok: false, error: "Add at least one capital letter (A–Z)." };
  }
  if (!SPECIAL_RE.test(p)) {
    return {
      ok: false,
      error: "Add at least one special character (for example ! @ # $ % ^ & *).",
    };
  }
  return { ok: true };
}

module.exports = { validatePassword };
