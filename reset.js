/**
 * Password reset completion (token from email link). Same-origin `/api/auth/reset-password`.
 */
(function () {
  const params = new URLSearchParams(window.location.search);
  const token = params.get("token") || "";

  const form = document.getElementById("reset-form");
  const passwordEl = document.getElementById("reset-password");
  const confirmEl = document.getElementById("reset-password-confirm");
  const submitBtn = document.getElementById("reset-submit");
  const messageEl = document.getElementById("reset-message");

  function apiUrl(path) {
    const base = String(window.WFH_API?.apiBase ?? "")
      .trim()
      .replace(/\/$/, "");
    const p = path.startsWith("/") ? path : `/${path}`;
    return `${base}${p}`;
  }

  function setMsg(text, isError) {
    if (!messageEl) {
      return;
    }
    messageEl.textContent = text || "";
    messageEl.classList.toggle("auth-message--error", Boolean(isError && text));
  }

  function validatePassword(p) {
    const s = String(p || "");
    if (s.length < 12) {
      return "Password must be at least 12 characters.";
    }
    if (!/[A-Z]/.test(s)) {
      return "Password must include at least one uppercase letter (A–Z).";
    }
    if (!/[!-\/:-@\[-`{-~]/.test(s)) {
      return "Password must include a special character (e.g. ! @ # $ %).";
    }
    return "";
  }

  async function handleSubmit(e) {
    e.preventDefault();
    if (!token) {
      setMsg("This reset link is missing a token. Request a new email from the sign-in page.", true);
      return;
    }
    const password = passwordEl?.value || "";
    const confirm = confirmEl?.value || "";
    const err = validatePassword(password);
    if (err) {
      setMsg(err, true);
      return;
    }
    if (password !== confirm) {
      setMsg("Passwords do not match.", true);
      return;
    }
    submitBtn.disabled = true;
    submitBtn.textContent = "Updating…";
    setMsg("");
    try {
      const res = await fetch(apiUrl("/api/auth/reset-password"), {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ token, password }),
      });
      const text = await res.text();
      let data = null;
      try {
        data = text ? JSON.parse(text) : null;
      } catch {
        data = { error: text || "Invalid response" };
      }
      if (!res.ok) {
        throw new Error(data?.error || "Reset failed.");
      }
      setMsg("Password updated. You can close this tab and sign in on the main page.", false);
      if (form) {
        form.hidden = true;
      }
    } catch (err) {
      setMsg(err?.message || "Something went wrong.", true);
    } finally {
      submitBtn.disabled = false;
      submitBtn.textContent = "Update password";
    }
  }

  if (!token) {
    setMsg("Invalid or missing reset link. Open the link from your email, or request a new reset.", true);
  }

  if (form) {
    form.addEventListener("submit", handleSubmit);
  }
})();
