(function () {
  const params = new URLSearchParams(window.location.search);
  const token = params.get("token") || "";
  const form = document.getElementById("reset-form");
  const passwordEl = document.getElementById("reset-password");
  const confirmEl = document.getElementById("reset-password-confirm");
  const submitBtn = document.getElementById("reset-submit");
  const messageEl = document.getElementById("reset-message");

  function apiUrl(path) {
    const base = String(window.WFH_API?.apiBase ?? "").trim().replace(/\/$/, "");
    return `${base}${path.startsWith("/") ? path : `/${path}`}`;
  }

  function setMessage(text, isError) {
    messageEl.textContent = text || "";
    messageEl.classList.toggle("error", Boolean(isError && text));
  }

  function validatePassword(password) {
    if (password.length < 12) return "Use at least 12 characters for your password.";
    if (!/[A-Z]/.test(password)) return "Add at least one capital letter.";
    if (!/[!-\/:-@\[-`{-~]/.test(password)) return "Add at least one special character.";
    return "";
  }

  async function submit(event) {
    event.preventDefault();
    if (!token) {
      setMessage("This reset link is missing a token. Request a new email from the sign-in page.", true);
      return;
    }
    const password = passwordEl.value || "";
    const confirm = confirmEl.value || "";
    const error = validatePassword(password);
    if (error) return setMessage(error, true);
    if (password !== confirm) return setMessage("Passwords do not match.", true);

    submitBtn.disabled = true;
    submitBtn.textContent = "Updating...";
    setMessage("");
    try {
      const response = await fetch(apiUrl("/api/auth/reset-password"), {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ token, password }),
      });
      const text = await response.text();
      const data = text ? JSON.parse(text) : {};
      if (!response.ok) throw new Error(data.error || "Reset failed.");
      setMessage("Password updated. You can sign in now.");
      form.hidden = true;
    } catch (error) {
      setMessage(error?.message || "Something went wrong.", true);
    } finally {
      submitBtn.disabled = false;
      submitBtn.textContent = "Update password";
    }
  }

  if (!token) setMessage("Invalid or missing reset link. Open the link from your email, or request a new reset.", true);
  form.addEventListener("submit", submit);
})();
