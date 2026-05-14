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
  const authModeLabel = document.getElementById("auth-mode-label");
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
    const skipAuth = Boolean(options.skipAuth);
    const token = skipAuth ? null : sessionStorage.getItem(JWT_STORAGE);
    if (token) {
      headers.Authorization = `Bearer ${token}`;
    }
    const { skipAuth: _omit, ...fetchOpts } = options;
    const res = await fetch(apiUrl(path), {
      ...fetchOpts,
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
    const urgent = Boolean(isError && text);
    authMessage.textContent = text || "";
    authMessage.classList.toggle("auth-message--error", urgent);
    if (urgent) {
      authMessage.setAttribute("role", "alert");
      authMessage.setAttribute("aria-live", "assertive");
    } else {
      authMessage.setAttribute("role", "status");
      authMessage.setAttribute("aria-live", "polite");
    }
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
    if (authModeLabel) {
      authModeLabel.textContent = mode === "signin" ? "Sign in" : "Create account";
    }
    if (authToggle) {
      authToggle.textContent =
        mode === "signin" ? "Need an account? Register" : "Already have an account? Sign in";
    }
    if (authSubmit) {
      authSubmit.textContent = mode === "signin" ? "Sign in" : "Create account";
    }
    if (authPassword) {
      authPassword.setAttribute("autocomplete", mode === "signin" ? "current-password" : "new-password");
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

  /** Drop globals only so a refresh can retry `/api/auth/me` without re-entering password. */
  function clearInMemoryAuth() {
    window.__attendanceToken = null;
    window.__attendanceUser = null;
  }

  async function enterApp(user) {
    enteredApp = true;
    hideApiHelp();
    if (typeof window.startAttendanceApp !== "function") {
      setMessage("App failed to load. Refresh the page.", true);
      enteredApp = false;
      return;
    }
    setMessage("Loading your calendar…", false);
    try {
      await window.startAttendanceApp({ user });
      setMessage("", false);
      if (authGate) {
        authGate.hidden = true;
      }
      if (mainApp) {
        mainApp.hidden = false;
      }
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

  function isValidEmail(value) {
    return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(value || "").trim());
  }

  async function handleSubmit(event) {
    event.preventDefault();
    const email = (authEmail?.value || "").trim();
    const password = authPassword?.value || "";
    if (!email || !password) {
      setMessage("Enter the email and password you used to register.", true);
      return;
    }
    if (!isValidEmail(email)) {
      setMessage("Use your email address (with @), not a username.", true);
      return;
    }

    if (!authSubmit) {
      return;
    }

    const defaultSubmitLabel = mode === "signin" ? "Sign in" : "Create account";
    const busyLabel = mode === "signin" ? "Signing in…" : "Creating account…";
    authSubmit.disabled = true;
    authSubmit.textContent = busyLabel;
    if (authForm) {
      authForm.setAttribute("aria-busy", "true");
    }
    setMessage("");

    try {
      if (mode === "signin") {
        sessionStorage.removeItem(JWT_STORAGE);
        sessionStorage.removeItem(USER_STORAGE);
        window.__attendanceToken = null;
        window.__attendanceUser = null;
        const { ok, status, data } = await apiFetch("/api/auth/login", {
          method: "POST",
          body: { email, password },
          skipAuth: true,
        });
        if (!ok) {
          if (status >= 500) {
            showApiHelp();
          }
          if (status === 401) {
            throw new Error(
              "Wrong email or password — or this database is new and that account was never created here. Try Register if unsure.",
            );
          }
          throw new Error(data?.error || "Sign-in failed.");
        }
        if (!data?.token || !data?.user?.id) {
          throw new Error("Invalid response from server. Try again.");
        }
        persistSession(data.token, data.user);
        await enterApp(data.user);
        return;
      }

      sessionStorage.removeItem(JWT_STORAGE);
      sessionStorage.removeItem(USER_STORAGE);
      window.__attendanceToken = null;
      window.__attendanceUser = null;
      const { ok, status, data } = await apiFetch("/api/auth/register", {
        method: "POST",
        body: { email, password },
        skipAuth: true,
      });
      if (!ok) {
        if (status >= 500) {
          showApiHelp();
        }
        throw new Error(data?.error || "Registration failed.");
      }
      if (!data?.token || !data?.user?.id) {
        throw new Error("Invalid response from server. Try again.");
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
      if (authSubmit) {
        authSubmit.disabled = false;
        authSubmit.textContent = defaultSubmitLabel;
      }
      if (authForm) {
        authForm.removeAttribute("aria-busy");
      }
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

    let ok;
    let status = 0;
    let data = null;
    try {
      const res = await apiFetch("/api/auth/me", { method: "GET" });
      ok = res.ok;
      status = res.status;
      data = res.data;
    } catch (err) {
      console.error(err);
      if (err?.name === "TypeError" && String(err.message).includes("fetch")) {
        showApiHelp();
        setMessage("Could not reach the API. Use `vercel dev` locally or deploy to Vercel.", true);
      } else {
        showApiHelp();
        setMessage("Could not verify your session (network error). Your saved login was kept; try refreshing.", true);
      }
      clearInMemoryAuth();
      return;
    }

    if (ok && data?.user) {
      persistSession(token, data.user);
      await enterApp(data.user);
      return;
    }

    if (status === 401 || status === 403) {
      clearSession();
      setMessage("Previous session expired. Sign in again.", true);
      return;
    }

    if (status >= 500) {
      showApiHelp();
      setMessage(
        "Could not verify your session (server error). Your saved login was kept—try refreshing in a moment.",
        true,
      );
      clearInMemoryAuth();
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
