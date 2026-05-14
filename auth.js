/**
 * Email/password via this repo’s Vercel serverless API; attendance JSON in Neon (`app_state`).
 * Same-origin `fetch` to `/api/*` by default; optional `window.WFH_API.apiBase` from `config.js`.
 */
(function () {
  const JWT_STORAGE = "WFH_JWT";
  const USER_STORAGE = "WFH_USER";

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

  function apiUrl(path) {
    const base = String(window.WFH_API?.apiBase ?? "")
      .trim()
      .replace(/\/$/, "");
    const p = path.startsWith("/") ? path : `/${path}`;
    return `${base}${p}`;
  }

  async function apiFetch(path, options = {}) {
    const headers = { ...(options.headers || {}) };
    let body = options.body;
    if (body != null && typeof body === "object" && !(body instanceof FormData)) {
      headers["Content-Type"] = "application/json";
      body = JSON.stringify(body);
    }
    const token = sessionStorage.getItem(JWT_STORAGE);
    if (token) {
      headers.Authorization = `Bearer ${token}`;
    }
    const res = await fetch(apiUrl(path), {
      ...options,
      headers,
      body,
    });
    const text = await res.text();
    let data = null;
    try {
      data = text ? JSON.parse(text) : null;
    } catch {
      data = { error: text || "Invalid response" };
    }
    return { ok: res.ok, status: res.status, data };
  }

  function setMessage(text, isError) {
    if (!authMessage) {
      return;
    }
    authMessage.textContent = text || "";
    authMessage.classList.toggle("auth-message--error", Boolean(isError && text));
  }

  function showApiHelp() {
    if (authConfigError) {
      authConfigError.hidden = false;
    }
  }

  function hideApiHelp() {
    if (authConfigError) {
      authConfigError.hidden = true;
    }
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

  function persistSession(token, user) {
    sessionStorage.setItem(JWT_STORAGE, token);
    sessionStorage.setItem(USER_STORAGE, JSON.stringify(user));
    window.__attendanceToken = token;
    window.__attendanceUser = user;
  }

  function clearSession() {
    sessionStorage.removeItem(JWT_STORAGE);
    sessionStorage.removeItem(USER_STORAGE);
    window.__attendanceToken = null;
    window.__attendanceUser = null;
  }

  async function enterApp(user) {
    if (enteredApp) {
      return;
    }
    enteredApp = true;
    hideApiHelp();
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
    try {
      await window.startAttendanceApp({ user });
    } catch (err) {
      console.error(err);
      if (!err?.skipAuthMessage) {
        setMessage(err?.message || "Could not load your data.", true);
      }
      enteredApp = false;
      clearSession();
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

    authSubmit.disabled = true;
    setMessage("");

    try {
      if (mode === "signin") {
        const { ok, status, data } = await apiFetch("/api/auth/login", {
          method: "POST",
          body: { email, password },
        });
        if (!ok) {
          if (status >= 500) {
            showApiHelp();
          }
          throw new Error(data?.error || "Sign-in failed.");
        }
        persistSession(data.token, data.user);
        await enterApp(data.user);
        return;
      }

      const { ok, status, data } = await apiFetch("/api/auth/register", {
        method: "POST",
        body: { email, password },
      });
      if (!ok) {
        if (status >= 500) {
          showApiHelp();
        }
        throw new Error(data?.error || "Registration failed.");
      }
      persistSession(data.token, data.user);
      await enterApp(data.user);
    } catch (err) {
      if (err?.name === "TypeError" && String(err.message).includes("fetch")) {
        showApiHelp();
        setMessage("Could not reach the API. Use `vercel dev` locally or deploy to Vercel.", true);
      } else {
        setMessage(err?.message || "Something went wrong.", true);
      }
    } finally {
      authSubmit.disabled = false;
    }
  }

  /**
   * Invalid JWT or rejected session: clear storage and return to the gate.
   */
  window.wfhInvalidateSession = async function wfhInvalidateSession(message) {
    enteredApp = false;
    clearSession();
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
      message || "Your session is no longer valid. Please sign in again.",
      true,
    );
  };

  async function tryResumeSession() {
    const token = sessionStorage.getItem(JWT_STORAGE);
    const rawUser = sessionStorage.getItem(USER_STORAGE);
    if (!token || !rawUser) {
      return;
    }
    let user;
    try {
      user = JSON.parse(rawUser);
    } catch {
      clearSession();
      return;
    }
    window.__attendanceToken = token;
    window.__attendanceUser = user;
    const { ok, data } = await apiFetch("/api/auth/me", { method: "GET" });
    if (ok && data?.user) {
      persistSession(token, data.user);
      await enterApp(data.user);
      return;
    }
    clearSession();
  }

  async function init() {
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
    clearSession();
    leaveApp();
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
