/**
 * Email / password gate using the WFH API (Railway PostgreSQL behind REST + JWT).
 * Requires `config.js` (from config.example.js) with your deployed API base URL.
 */
(function () {
  const TOKEN_KEY = "wfh.attendance.jwt";

  const authGate = document.getElementById("auth-gate");
  const mainApp = document.getElementById("main-app");
  const authForm = document.getElementById("auth-form");
  const authEmail = document.getElementById("auth-email");
  const authPassword = document.getElementById("auth-password");
  const authSubmit = document.getElementById("auth-submit");
  const authToggle = document.getElementById("auth-toggle-mode");
  const authMessage = document.getElementById("auth-message");
  const authConfigError = document.getElementById("auth-config-error");

  let mode = "signin";
  let enteredApp = false;

  function getApiBase() {
    const cfg = window.WFH_API;
    const raw = String(cfg?.baseUrl || "").trim();
    return raw.replace(/\/$/, "");
  }

  function setMessage(text, isError) {
    if (!authMessage) {
      return;
    }
    authMessage.textContent = text || "";
    authMessage.classList.toggle("auth-message--error", Boolean(isError && text));
  }

  function showConfigMissing() {
    if (authConfigError) {
      authConfigError.hidden = false;
    }
    if (authForm) {
      authForm.hidden = true;
    }
    setMessage("");
  }

  function setMode(next) {
    mode = next;
    if (authToggle) {
      authToggle.textContent =
        mode === "signin" ? "Need an account? Register" : "Already have an account? Sign in";
    }
    if (authSubmit) {
      authSubmit.textContent = mode === "signin" ? "Sign in" : "Create account";
    }
    setMessage("");
  }

  async function enterApp(user, token) {
    if (enteredApp) {
      return;
    }
    enteredApp = true;
    if (authGate) {
      authGate.hidden = true;
    }
    if (mainApp) {
      mainApp.hidden = false;
    }
    if (typeof window.startAttendanceApp !== "function") {
      setMessage("App failed to load. Refresh the page.", true);
      enteredApp = false;
      return;
    }
    sessionStorage.setItem(TOKEN_KEY, token);
    try {
      await window.startAttendanceApp({
        user,
        token,
        apiBaseUrl: getApiBase(),
      });
    } catch (err) {
      console.error(err);
      if (!err?.skipAuthMessage) {
        setMessage(err?.message || "Could not load your data.", true);
      }
      enteredApp = false;
      sessionStorage.removeItem(TOKEN_KEY);
      if (authGate) {
        authGate.hidden = false;
      }
      if (mainApp) {
        mainApp.hidden = true;
      }
    }
  }

  function leaveApp() {
    enteredApp = false;
    if (mainApp) {
      mainApp.hidden = true;
    }
    if (authGate) {
      authGate.hidden = false;
    }
    if (authForm) {
      authForm.hidden = false;
    }
    setMessage("Signed out.");
  }

  async function handleSubmit(event) {
    event.preventDefault();
    const email = (authEmail?.value || "").trim();
    const password = authPassword?.value || "";
    if (!email || !password) {
      setMessage("Enter email and password.", true);
      return;
    }
    const base = getApiBase();
    if (!base) {
      setMessage("API URL is not set up yet. See the instructions above.", true);
      return;
    }

    authSubmit.disabled = true;
    setMessage("");

    try {
      const path = mode === "signin" ? "/api/auth/login" : "/api/auth/register";
      const response = await fetch(`${base}${path}`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email, password }),
      });
      const data = await response.json().catch(() => ({}));
      if (!response.ok) {
        throw new Error(data.error || (mode === "signin" ? "Sign-in failed" : "Registration failed"));
      }
      if (!data.token || !data.user?.id) {
        throw new Error("Unexpected response from server.");
      }
      setMessage(mode === "signin" ? "Signed in…" : "Welcome…", false);
      await enterApp(data.user, data.token);
    } catch (err) {
      setMessage(err?.message || "Something went wrong.", true);
    } finally {
      authSubmit.disabled = false;
    }
  }

  function isConfigReady(cfg) {
    if (!cfg) {
      return false;
    }
    const baseUrl = String(cfg.baseUrl || "").trim();
    if (!baseUrl || baseUrl.includes("YOUR_RAILWAY") || baseUrl.includes("your-app.up.railway.app")) {
      return false;
    }
    try {
      const u = new URL(baseUrl);
      if (u.protocol === "https:") {
        return true;
      }
      if (u.protocol === "http:" && (u.hostname === "localhost" || u.hostname === "127.0.0.1")) {
        return true;
      }
      return false;
    } catch {
      return false;
    }
  }

  async function tryResumeSession() {
    const token = sessionStorage.getItem(TOKEN_KEY);
    if (!token) {
      return;
    }
    const base = getApiBase();
    if (!base) {
      sessionStorage.removeItem(TOKEN_KEY);
      return;
    }
    try {
      const response = await fetch(`${base}/api/auth/me`, {
        headers: { Authorization: `Bearer ${token}` },
      });
      if (!response.ok) {
        sessionStorage.removeItem(TOKEN_KEY);
        return;
      }
      const data = await response.json();
      if (data?.user?.id) {
        await enterApp(data.user, token);
      } else {
        sessionStorage.removeItem(TOKEN_KEY);
      }
    } catch {
      sessionStorage.removeItem(TOKEN_KEY);
    }
  }

  /**
   * Called when the API rejects the JWT (401). Clears token and returns to the sign-in screen.
   */
  window.wfhInvalidateSession = function (message) {
    sessionStorage.removeItem(TOKEN_KEY);
    enteredApp = false;
    window.__attendanceToken = null;
    window.__attendanceUser = null;
    window.__attendanceApiBase = "";
    if (mainApp) {
      mainApp.hidden = true;
    }
    if (authGate) {
      authGate.hidden = false;
    }
    if (authForm) {
      authForm.hidden = false;
    }
    setMessage(
      message ||
        "Your sign-in is no longer valid (wrong secret, expired token, or account reset). Please sign in again.",
      true,
    );
  };

  async function init() {
    const cfg = window.WFH_API;
    if (!isConfigReady(cfg)) {
      showConfigMissing();
      return;
    }

    if (authToggle) {
      authToggle.addEventListener("click", () => {
        setMode(mode === "signin" ? "signup" : "signin");
      });
    }

    if (authForm) {
      authForm.addEventListener("submit", handleSubmit);
    }

    await tryResumeSession();
  }

  window.wfhSignOut = async function wfhSignOut() {
    if (typeof window.flushAttendanceCloudNow === "function") {
      try {
        await window.flushAttendanceCloudNow();
      } catch (e) {
        console.error(e);
      }
    }
    sessionStorage.removeItem(TOKEN_KEY);
    leaveApp();
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
