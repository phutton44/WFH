/**
 * Email / password via Supabase Auth; data in PostgreSQL (`app_state`) through the Supabase client.
 * Requires `config.js` (from `config.example.js`) and the Supabase JS bundle on the page.
 */
(function () {
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
  let supabaseClient = null;
  let enteredApp = false;

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

  async function enterApp(supabase, user) {
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
    try {
      await window.startAttendanceApp({ supabase, user });
    } catch (err) {
      console.error(err);
      if (!err?.skipAuthMessage) {
        setMessage(err?.message || "Could not load your data.", true);
      }
      enteredApp = false;
      if (supabaseClient) {
        await supabaseClient.auth.signOut();
      }
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
    if (!supabaseClient) {
      setMessage("Sign-in is not set up yet. See the instructions above.", true);
      return;
    }

    authSubmit.disabled = true;
    setMessage("");

    try {
      if (mode === "signin") {
        const { data, error } = await supabaseClient.auth.signInWithPassword({ email, password });
        if (error) {
          throw error;
        }
        if (data.session?.user) {
          await enterApp(supabaseClient, data.session.user);
          return;
        }
        const {
          data: { session: recovered },
        } = await supabaseClient.auth.getSession();
        if (recovered?.user) {
          await enterApp(supabaseClient, recovered.user);
          return;
        }
        setMessage("Signed in…", false);
      } else {
        const origin = typeof window !== "undefined" ? window.location.origin : "";
        const { data, error } = await supabaseClient.auth.signUp({
          email,
          password,
          options: origin ? { emailRedirectTo: `${origin}/` } : undefined,
        });
        if (error) {
          throw error;
        }
        if (data.session?.user) {
          await enterApp(supabaseClient, data.session.user);
          return;
        }
        setMessage(
          "Account created. Check your email and click the confirmation link, then come back and sign in. " +
            "If nothing arrives, look in Spam—or in Supabase go to Authentication → Providers → Email and turn off “Confirm email” for instant sign-in while testing.",
          false,
        );
      }
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
    const url = String(cfg.url || "").trim();
    const anonKey = String(cfg.anonKey || "").trim();
    if (!url || !anonKey) {
      return false;
    }
    if (url.includes("YOUR_PROJECT") || anonKey.includes("YOUR_SUPABASE")) {
      return false;
    }
    try {
      const u = new URL(url);
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

  /**
   * Invalid Supabase session / RLS auth failure: sign out and return to the gate.
   */
  window.wfhInvalidateSession = async function wfhInvalidateSession(message) {
    enteredApp = false;
    window.__attendanceSupabase = null;
    window.__attendanceUser = null;
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
        "Your session is no longer valid. Please sign in again.",
      true,
    );
    if (supabaseClient) {
      try {
        await supabaseClient.auth.signOut();
      } catch (e) {
        console.error(e);
      }
    }
  };

  async function init() {
    const cfg = window.WFH_SUPABASE;
    if (!isConfigReady(cfg)) {
      showConfigMissing();
      return;
    }

    const createClient = window.supabase?.createClient;
    if (typeof createClient !== "function") {
      setMessage("Supabase library failed to load.", true);
      return;
    }

    supabaseClient = createClient(String(cfg.url).trim(), String(cfg.anonKey).trim(), {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
      },
    });

    if (authToggle) {
      authToggle.addEventListener("click", () => {
        setMode(mode === "signin" ? "signup" : "signin");
      });
    }

    if (authForm) {
      authForm.addEventListener("submit", handleSubmit);
    }

    const {
      data: { session },
    } = await supabaseClient.auth.getSession();

    if (session?.user) {
      await enterApp(supabaseClient, session.user);
    }

    supabaseClient.auth.onAuthStateChange(async (event, session) => {
      if (event === "SIGNED_IN" && session?.user) {
        await enterApp(supabaseClient, session.user);
      }
      if (event === "SIGNED_OUT") {
        leaveApp();
      }
    });
  }

  window.wfhSignOut = async function wfhSignOut() {
    if (typeof window.flushAttendanceCloudNow === "function") {
      try {
        await window.flushAttendanceCloudNow();
      } catch (e) {
        console.error(e);
      }
    }
    if (supabaseClient) {
      await supabaseClient.auth.signOut();
    }
    leaveApp();
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
