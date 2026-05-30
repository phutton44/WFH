"use strict";

const { Resend } = require("resend");

function escapeHtml(value) {
  return String(value || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

async function sendEmail({ to, subject, html }) {
  const key = String(process.env.RESEND_API_KEY || "").trim();
  const from = String(process.env.RESEND_FROM_EMAIL || process.env.RESEND_FROM || "").trim();
  if (!key || !from) {
    console.warn("[WFH] Missing RESEND_API_KEY or RESEND_FROM_EMAIL — email not sent.");
    return { sent: false, reason: "missing_config" };
  }
  try {
    const resend = new Resend(key);
    const { error } = await resend.emails.send({
      from,
      to: [to],
      subject,
      html,
    });
    if (error) {
      console.error("[WFH] Resend API error", error);
      return { sent: false, reason: "resend_error" };
    }
    return { sent: true };
  } catch (err) {
    console.error("[WFH] Resend send failed", err);
    return { sent: false, reason: "send_failed" };
  }
}

module.exports = {
  escapeHtml,
  sendEmail,
};
