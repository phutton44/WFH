import {
  AlertCircle,
  BarChart3,
  Building2,
  CalendarDays,
  ChevronLeft,
  ChevronRight,
  Cloud,
  Download,
  Home,
  Lock,
  LogOut,
  Moon,
  RefreshCw,
  Settings,
  SlidersHorizontal,
  Sun,
  Unlock,
} from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { api } from "../lib/api";
import {
  activeProfile,
  allowanceForYear,
  assignableDatesForMonth,
  isBeforeRecordingStart,
  isMonthLocked,
  kindForDate,
  leaveBreakdown,
  metrics,
  monthKeyForRef,
  monthMetrics,
  officeDaysNeededForTarget,
  officeShare,
  recordingStartMonthKey,
  recordingStartParts,
  setMonthLocked,
  updateActiveProfile,
  yearStartMonth,
} from "../lib/attendance";
import {
  currentMonth,
  forEachDate,
  gridDays,
  isBankHoliday,
  iso,
  monthBounds,
  monthKey,
  monthNames,
  monthTitle,
  readableDate,
  reportingQuarter,
  reportingYear,
  reportingYearBounds,
  reportingYearMonths,
  shiftMonth,
  todayISO,
} from "../lib/date";
import type { AppTab, AttendanceProfile, DayKind, LeaveShortfallWarning, Metrics, MonthRef } from "../lib/types";
import { useAttendanceApp } from "./useAttendanceApp";

const dayActions: Array<{ kind: DayKind; label: string; icon: typeof Building2 }> = [
  { kind: "office", label: "Office", icon: Building2 },
  { kind: "wfh", label: "WFH", icon: Home },
  { kind: "leave", label: "Leave", icon: Sun },
  { kind: "sickness", label: "Sick", icon: AlertCircle },
  { kind: "nwd", label: "NWD", icon: Moon },
];

const tabItems: Array<{ id: AppTab; label: string; icon: typeof CalendarDays }> = [
  { id: "record", label: "Record", icon: CalendarDays },
  { id: "month", label: "Month", icon: BarChart3 },
  { id: "year", label: "Year", icon: Cloud },
  { id: "settings", label: "Settings", icon: SlidersHorizontal },
];

export function App() {
  const app = useAttendanceApp();
  const [visibleMonth, setVisibleMonth] = useState<MonthRef>(() => currentMonth());
  const [yearMonth, setYearMonth] = useState<MonthRef>(() => currentMonth());
  const workspaceYears = selectableYears(app.profile);
  const workspaceYear = app.tab === "year" ? yearMonth.year : visibleMonth.year;
  const pageTitle =
    app.tab === "record" ? `Record · ${monthTitle(visibleMonth)}` :
    app.tab === "month" ? `Month insight · ${monthTitle(visibleMonth)}` :
    app.tab === "year" ? `Year report · ${yearMonth.year}` :
    "Settings";

  function setWorkspaceYear(year: number) {
    if (app.tab === "year") setYearMonth({ ...yearMonth, year });
    else setVisibleMonth({ ...visibleMonth, year });
  }

  useEffect(() => {
    if (!app.signedIn) return;
    const start = recordingStartMonthKey(app.profile);
    if (monthKeyForRef(visibleMonth) < start) {
      setVisibleMonth(recordingStartParts(app.profile));
    }
  }, [app.profile, app.signedIn, visibleMonth]);

  if (!app.signedIn) {
    return <AuthScreen signIn={app.signIn} finishSocialSignIn={app.finishSocialSignIn} enterPreview={app.enterPreview} />;
  }

  return (
    <div className="app">
      <aside className="app-rail" aria-label="Workspace">
        <div className="rail-brand">
          <div className="brand-mark">
            <CalendarDays size={22} />
          </div>
          <div>
            <strong>Work Attendance</strong>
            <span>{app.isPreview ? "Local preview" : (app.user?.email ?? "Signed in")}</span>
          </div>
        </div>
        <nav className="tabbar" aria-label="Primary">
          {tabItems.map((item) => {
            const Icon = item.icon;
            return (
              <button key={item.id} className={app.tab === item.id ? "active" : ""} type="button" onClick={() => app.setTab(item.id)}>
                <Icon size={18} />
                <span>{item.label}</span>
              </button>
            );
          })}
        </nav>
        <div className="rail-footer">
          <button className="rail-link" type="button" onClick={() => void app.loadCloudState()}>
            <RefreshCw size={16} />
            Refresh
          </button>
          <button className="rail-link danger" type="button" onClick={app.signOut}>
            <LogOut size={16} />
            Sign out
          </button>
        </div>
      </aside>
      <header className="shell-header">
        <div className="brand-lockup">
          <div className="brand-mark">
            <CalendarDays size={24} />
          </div>
          <div>
            <p>Work Attendance</p>
            <h1>{pageTitle}</h1>
          </div>
        </div>
        <div className="header-actions">
          <select
            className="workspace-year-select"
            aria-label="Year"
            value={workspaceYear}
            onChange={(event) => setWorkspaceYear(Number(event.target.value))}
          >
            {workspaceYears.map((year) => <option key={year}>{year}</option>)}
          </select>
          <button className="icon-button" type="button" onClick={() => void app.loadCloudState()} title="Refresh">
            <RefreshCw size={18} />
          </button>
          <button className="icon-button danger" type="button" onClick={app.signOut} title="Sign out">
            <LogOut size={18} />
          </button>
        </div>
      </header>

      {app.message ? (
        <div className="notice">
          <span>{app.message}</span>
          {app.hasUndo ? (
            <button type="button" onClick={app.undoBulk}>
              Undo
            </button>
          ) : null}
          <button type="button" onClick={() => app.setMessage("")}>
            Dismiss
          </button>
        </div>
      ) : null}

      <main className="main-grid">
        {app.tab === "record" ? (
          <RecordView
            profile={app.profile}
            month={visibleMonth}
            setMonth={setVisibleMonth}
            applyDates={app.applyDates}
            replaceProfile={(profile) => app.replaceState(updateActiveProfile(app.state, () => profile))}
          />
        ) : null}
        {app.tab === "month" ? <InsightView profile={app.profile} scope="month" month={visibleMonth} setMonth={setVisibleMonth} userEmail={app.user?.email} /> : null}
        {app.tab === "year" ? <InsightView profile={app.profile} scope="year" month={yearMonth} setMonth={setYearMonth} userEmail={app.user?.email} /> : null}
        {app.tab === "settings" ? (
          <SettingsView
            userEmail={app.user?.email ?? ""}
            profile={app.profile}
            state={app.state}
            replaceState={app.replaceState}
            signOut={app.signOut}
          />
        ) : null}
      </main>
      {app.leaveWarning ? (
        <LeaveShortfallDialog warning={app.leaveWarning} onDismiss={app.dismissLeaveWarning} />
      ) : null}
    </div>
  );
}

function LeaveShortfallDialog({
  warning,
  onDismiss,
}: {
  warning: LeaveShortfallWarning;
  onDismiss: () => void;
}) {
  return (
    <div className="modal-backdrop" role="presentation">
      <section
        className="leave-warning-dialog"
        role="alertdialog"
        aria-modal="true"
        aria-labelledby="leave-warning-title"
        aria-describedby="leave-warning-copy"
      >
        <div className="leave-warning-icon" aria-hidden="true">
          <AlertCircle size={44} />
        </div>
        <div className="leave-warning-copy">
          <h2 id="leave-warning-title">Hold up</h2>
          <p id="leave-warning-copy">You do not have enough annual leave left for {warning.year}.</p>
        </div>
        <div className="leave-warning-stats">
          <LeaveWarningStat label="Left" value={warning.remaining} tone="safe" />
          <LeaveWarningStat label="Requested" value={warning.requested} tone="leave" />
          <LeaveWarningStat label="Deficit" value={warning.deficit} tone="danger" />
        </div>
        <p className="leave-warning-help">
          Reduce the selected leave by {warning.deficit} day{warning.deficit === 1 ? "" : "s"}, or increase your annual allowance in Settings.
        </p>
        <button type="button" onClick={onDismiss}>
          Got it
        </button>
      </section>
    </div>
  );
}

function LeaveWarningStat({
  label,
  value,
  tone,
}: {
  label: string;
  value: number;
  tone: "safe" | "leave" | "danger";
}) {
  return (
    <div className={`leave-warning-stat tone-${tone}`}>
      <span>{label}</span>
      <strong>{value}</strong>
    </div>
  );
}

function AuthScreen({
  signIn,
  finishSocialSignIn,
  enterPreview,
}: {
  signIn: (email: string, password: string) => Promise<void>;
  finishSocialSignIn: (response: { token: string; user: { id: string; email: string } }) => Promise<void>;
  enterPreview: () => void;
}) {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [mode, setMode] = useState<"signin" | "signup" | "forgot">("signin");
  const [showEmailForm, setShowEmailForm] = useState(false);
  const [message, setMessage] = useState("");
  const [busy, setBusy] = useState(false);
  const [googleReady, setGoogleReady] = useState(false);
  const googleId = String(window.WFH_API?.googleClientId ?? "").trim();
  const appleClientId = String(window.WFH_API?.appleClientId ?? "").trim();
  const appleRedirectURI = String(window.WFH_API?.appleRedirectURI ?? window.location.origin).trim();

  useEffect(() => {
    setShowEmailForm(mode !== "signin");
  }, [mode]);

  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    const token = params.get("verify");
    if (!token) return;
    let cancelled = false;
    setBusy(true);
    setMessage("Confirming your email...");
    void api.verifyEmail(token)
      .then((response) => {
        if (cancelled) return;
        setMode("signin");
        setMessage(response.message || "Email confirmed. You can sign in now.");
        params.delete("verify");
        const next = `${window.location.pathname}${params.toString() ? `?${params}` : ""}${window.location.hash}`;
        window.history.replaceState({}, "", next);
      })
      .catch((error) => {
        if (!cancelled) setMessage(error instanceof Error ? error.message : "Could not confirm email.");
      })
      .finally(() => {
        if (!cancelled) setBusy(false);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    if (!googleId || mode !== "signin") return;
    let cancelled = false;
    let attempts = 0;
    const initGoogle = () => {
      if (cancelled) return;
      if (!window.google?.accounts?.id) {
        attempts += 1;
        if (attempts < 50) window.setTimeout(initGoogle, 100);
        return;
      }
      window.google.accounts.id.initialize({
        client_id: googleId,
        callback: async (response: { credential?: string }) => {
          if (!response.credential) {
            setMessage("Google did not return a sign-in credential. Try again.");
            return;
          }
          try {
            setBusy(true);
            await finishSocialSignIn(await api.google(response.credential));
          } catch (error) {
            setMessage(error instanceof Error ? error.message : "Google sign-in failed.");
          } finally {
            setBusy(false);
          }
        },
      });
      setGoogleReady(true);
    };
    initGoogle();
    return () => {
      cancelled = true;
    };
  }, [finishSocialSignIn, googleId, mode]);

  function signInWithGoogle() {
    if (!googleId) {
      setMessage("Google sign-in is not configured for this web deployment.");
      return;
    }
    if (!window.google?.accounts?.id || !googleReady) {
      setMessage("Google sign-in is still loading. Try again in a moment.");
      return;
    }
    setMessage("");
    window.google.accounts.id.prompt();
  }

  useEffect(() => {
    if (!appleClientId || mode !== "signin") return;
    let cancelled = false;
    let attempts = 0;
    const initApple = () => {
      if (cancelled) return;
      if (!window.AppleID?.auth) {
        attempts += 1;
        if (attempts < 50) window.setTimeout(initApple, 100);
        return;
      }
      window.AppleID.auth.init({
        clientId: appleClientId,
        scope: "name email",
        redirectURI: appleRedirectURI || window.location.origin,
        usePopup: true,
      });
    };
    initApple();
    return () => {
      cancelled = true;
    };
  }, [appleClientId, appleRedirectURI, mode]);

  async function signInWithApple() {
    if (!appleClientId) {
      setMessage("Apple sign-in is not configured for this web deployment.");
      return;
    }
    if (!window.AppleID?.auth) {
      setMessage("Apple sign-in is still loading. Try again in a moment.");
      return;
    }
    setBusy(true);
    setMessage("");
    try {
      const response = await window.AppleID.auth.signIn();
      const idToken = response.authorization?.id_token;
      if (!idToken) throw new Error("Apple did not return an identity token.");
      await finishSocialSignIn(await api.apple(idToken));
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Apple sign-in failed.");
    } finally {
      setBusy(false);
    }
  }

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    setBusy(true);
    setMessage("");
    try {
      if (mode === "forgot") {
        await api.forgotPassword(email);
        setMessage("If that account exists, a reset email is on its way.");
      } else if (mode === "signup") {
        if (password !== confirmPassword) {
          setMessage("Passwords do not match.");
          return;
        }
        const response = await api.register(email, password);
        setMessage(response.message || "Account created. Check your email to confirm it before signing in.");
        setMode("signin");
        setPassword("");
        setConfirmPassword("");
      } else {
        await signIn(email, password);
      }
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Sign-in failed.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="auth-page">
      <section className="auth-panel">
        <div className="brand-lockup">
          <div className="brand-mark">
            <CalendarDays size={24} />
          </div>
          <div>
            <p>Work Attendance</p>
            <h1>{mode === "forgot" ? "Reset password" : mode === "signup" ? "Create account" : "Sign in"}</h1>
          </div>
        </div>
        {mode === "signin" ? (
          <div className="provider-stack" aria-label="Social sign-in">
            <div className="auth-splash-copy">
              <h2>Welcome back</h2>
              <p>Use your Google or Apple account to open your attendance record.</p>
            </div>
            {googleId ? (
              <button className="provider-button social-button google-provider" type="button" onClick={signInWithGoogle} disabled={busy || !googleReady}>
                <GoogleLogo />
                Continue with Google
              </button>
            ) : (
              <button className="provider-button social-button google-provider" type="button" disabled>
                <GoogleLogo />
                Continue with Google unavailable
              </button>
            )}
            <button className="provider-button social-button apple" type="button" onClick={signInWithApple} disabled={busy || !appleClientId}>
              <AppleLogo />
              {appleClientId ? "Continue with Apple" : "Continue with Apple unavailable"}
            </button>
            <button className="provider-button email-provider" type="button" onClick={() => setShowEmailForm((current) => !current)}>
              Email and password
            </button>
            {!googleId || !appleClientId ? (
              <p className="provider-note">
                {!googleId && !appleClientId
                  ? "Google and Apple sign-in need web client IDs in the deployment config."
                  : !googleId
                    ? "Google sign-in needs GOOGLE_CLIENT_ID or WFH_GOOGLE_CLIENT_ID."
                    : "Apple sign-in needs APPLE_WEB_CLIENT_ID or WFH_APPLE_WEB_CLIENT_ID."}
              </p>
            ) : null}
          </div>
        ) : null}
        {showEmailForm ? (
          <form onSubmit={submit} className="auth-form">
            <label>
              Email
              <input value={email} onChange={(event) => setEmail(event.target.value)} type="email" autoComplete="email" required />
            </label>
            {mode !== "forgot" ? (
              <label>
                Password
                <input
                  value={password}
                  onChange={(event) => setPassword(event.target.value)}
                  type="password"
                  autoComplete={mode === "signup" ? "new-password" : "current-password"}
                  minLength={mode === "signup" ? 12 : undefined}
                  required
                />
              </label>
            ) : null}
            {mode === "signup" ? (
              <label>
                Confirm password
                <input value={confirmPassword} onChange={(event) => setConfirmPassword(event.target.value)} type="password" autoComplete="new-password" minLength={12} required />
              </label>
            ) : null}
            {message ? <p className="form-message">{message}</p> : null}
            <button className="primary" type="submit" disabled={busy}>
              {busy ? "Working..." : mode === "forgot" ? "Send reset link" : mode === "signup" ? "Create account" : "Sign in"}
            </button>
          </form>
        ) : message ? (
          <p className="form-message auth-message">{message}</p>
        ) : null}
        <div className="auth-links">
          <button type="button" onClick={() => setMode(mode === "signin" ? "signup" : "signin")}>
            {mode === "signin" ? "Create account" : "Back to sign in"}
          </button>
          <button type="button" onClick={() => setMode(mode === "forgot" ? "signin" : "forgot")}>
            {mode === "forgot" ? "Back to sign in" : "Forgot password?"}
          </button>
          <button type="button" onClick={enterPreview}>
            Enter preview
          </button>
        </div>
      </section>
    </main>
  );
}

function GoogleLogo() {
  return (
    <svg className="provider-logo" viewBox="0 0 24 24" aria-hidden="true" focusable="false">
      <path fill="#4285F4" d="M22.1 12.2c0-.8-.1-1.5-.2-2.2H12v4.2h5.7c-.2 1.3-1 2.4-2.1 3.1V20h3.4c2-1.8 3.1-4.5 3.1-7.8Z" />
      <path fill="#34A853" d="M12 22c2.8 0 5.2-.9 6.9-2.5l-3.4-2.7c-.9.6-2.1 1-3.5 1-2.7 0-5-1.8-5.8-4.3H2.7v2.8C4.4 19.7 7.9 22 12 22Z" />
      <path fill="#FBBC05" d="M6.2 13.5c-.2-.6-.3-1.2-.3-1.9s.1-1.3.3-1.9V6.9H2.7C2 8.3 1.6 9.9 1.6 11.6s.4 3.3 1.1 4.7l3.5-2.8Z" />
      <path fill="#EA4335" d="M12 5.4c1.5 0 2.9.5 4 1.6l3-3C17.2 2.3 14.8 1.3 12 1.3 7.9 1.3 4.4 3.7 2.7 6.9l3.5 2.8C7 7.2 9.3 5.4 12 5.4Z" />
    </svg>
  );
}

function AppleLogo() {
  return (
    <svg className="provider-logo" viewBox="0 0 24 24" aria-hidden="true" focusable="false">
      <path
        fill="currentColor"
        d="M16.2 13.1c0-2.2 1.8-3.3 1.9-3.4-1-1.5-2.6-1.7-3.2-1.7-1.4-.1-2.6.8-3.3.8s-1.8-.8-2.9-.8c-1.5 0-2.9.9-3.7 2.2-1.6 2.8-.4 7 1.1 9.3.8 1.1 1.7 2.4 2.9 2.3 1.2 0 1.6-.8 3-.8s1.8.8 3 .8c1.3 0 2.1-1.1 2.8-2.3.9-1.3 1.2-2.5 1.2-2.6 0-.1-2.8-1.1-2.8-3.8ZM14 6.6c.6-.7 1-1.7.9-2.6-.9 0-2 .6-2.6 1.3-.6.7-1.1 1.7-.9 2.6 1 0 2-.5 2.6-1.3Z"
      />
    </svg>
  );
}

function RecordView({
  profile,
  month,
  setMonth,
  applyDates,
  replaceProfile,
}: {
  profile: AttendanceProfile;
  month: MonthRef;
  setMonth: (month: MonthRef) => void;
  applyDates: (dates: Set<string>, kind: DayKind, allowUndo?: boolean) => void;
  replaceProfile: (profile: AttendanceProfile) => void;
}) {
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [selectedByAll, setSelectedByAll] = useState(false);
  const key = monthKeyForRef(month);
  const metric = monthMetrics(profile, month);
  const locked = isMonthLocked(profile, key);
  const beforeStart = isBeforeRecordingStart(profile, key);
  const editable = !locked && !beforeStart;
  const canGoPrevious = key > recordingStartMonthKey(profile);
  const assignable = useMemo(() => assignableDatesForMonth(month), [month]);
  const allWorkdaysSelected = assignable.length > 0 && assignable.every((date) => selected.has(date));
  const hasSelection = selected.size > 0;
  const years = selectableYears(profile);

  function move(offset: number) {
    const next = shiftMonth(month, offset);
    if (monthKeyForRef(next) < recordingStartMonthKey(profile)) return;
    setMonth(next);
    setSelected(new Set());
    setSelectedByAll(false);
  }

  function toggleDate(date: string) {
    if (!editable) return;
    const kind = kindForDate(profile, date);
    if (kind === "weekend" || kind === "bankHoliday") return;
    setSelected((current) => {
      const next = new Set(current);
      if (next.has(date)) next.delete(date);
      else next.add(date);
      return next;
    });
    setSelectedByAll(false);
  }

  function toggleAllWorkdays() {
    if (!editable) return;
    if (allWorkdaysSelected) {
      setSelected(new Set());
      setSelectedByAll(false);
      return;
    }
    setSelected(new Set(assignable));
    setSelectedByAll(true);
  }

  return (
    <section className="record-layout">
      <div className="panel target-card-panel">
        <MonthTargetPanel metric={metric} target={profile.settings.targetPct} />
      </div>

      <DayTypeLegend />

      <div className="panel calendar-panel">
        <div className="record-hero-head">
          <MonthNav
            month={month}
            years={years}
            canGoPrevious={canGoPrevious}
            onMove={move}
            onYear={(year) => setMonth({ ...month, year })}
            showTitle={false}
            showYearSelect={false}
          />
          <div className="calendar-toolbar compact">
            <button
              type="button"
              disabled={beforeStart}
              aria-pressed={locked}
              aria-label={locked ? "Unlock month" : "Lock month"}
              onClick={() => replaceProfile(setMonthLocked(profile, key, !locked))}
            >
              {locked ? <Lock size={16} /> : <Unlock size={16} />}
              {locked ? "Unlock" : "Lock"}
            </button>
            <button
              type="button"
              disabled={!editable}
              onClick={toggleAllWorkdays}
            >
              {allWorkdaysSelected ? "Unselect all workdays" : "Select all workdays"}
            </button>
          </div>
        </div>
        <div className="calendar-toolbar secondary-toolbar">
          <button
            type="button"
            disabled={beforeStart}
            aria-pressed={locked}
            aria-label={locked ? "Unlock month" : "Lock month"}
            onClick={() => replaceProfile(setMonthLocked(profile, key, !locked))}
          >
            {locked ? <Lock size={16} /> : <Unlock size={16} />}
            {locked ? "Unlock" : "Lock"}
          </button>
          <button
            type="button"
            disabled={!editable}
            onClick={toggleAllWorkdays}
          >
            {allWorkdaysSelected ? "Unselect all workdays" : "Select all workdays"}
          </button>
          <button type="button" disabled={!selected.size} onClick={() => setSelected(new Set())}>
            Clear selection
          </button>
        </div>
        {beforeStart ? <div className="locked-banner">This month is before your recording start date.</div> : null}
        {locked ? <div className="locked-banner">This month is locked. Unlock it before editing.</div> : null}
        <div className="weekday-grid">{["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"].map((day) => <span key={day}>{day}</span>)}</div>
        <div className="calendar-grid">
          {gridDays(month).map((day) =>
            day.iso ? (
              <button
                key={day.id}
                type="button"
                className={`day-tile kind-${kindForDate(profile, day.iso)} ${selected.has(day.iso) ? "selected" : ""}`}
                onClick={() => toggleDate(day.iso!)}
              >
                <span>{day.day}</span>
                <strong>{dayLabel(kindForDate(profile, day.iso))}</strong>
              </button>
            ) : (
              <span key={day.id} className="day-tile empty" />
            ),
          )}
        </div>
        {hasSelection && editable ? (
          <div className="action-sheet">
            <p>{selected.size} selected</p>
            <div>
              {dayActions.map((action) => {
                const Icon = action.icon;
                return (
                  <button
                    key={action.kind}
                    type="button"
                    className={`action-kind action-kind-${action.kind}`}
                    onClick={() => {
                      applyDates(selected, action.kind, selectedByAll);
                      setSelected(new Set());
                      setSelectedByAll(false);
                    }}
                  >
                    <Icon size={16} />
                    {action.label}
                  </button>
                );
              })}
              <button
                type="button"
                className="action-kind action-kind-unassigned"
                onClick={() => {
                  applyDates(selected, "unassigned");
                  setSelected(new Set());
                  setSelectedByAll(false);
                }}
              >
                Clear entries
              </button>
            </div>
          </div>
        ) : null}
      </div>

      {!hasSelection ? (
        <div className="panel glance-card-panel">
          <MonthAtGlancePanel
            month={month}
            metric={metric}
            bankHolidays={countBankHolidays(monthBounds(month).startISO, monthBounds(month).endISO)}
          />
        </div>
      ) : null}
    </section>
  );
}

function MonthTargetPanel({ metric, target }: { metric: Metrics; target: number }) {
  const share = officeShare(metric);
  const needed = officeDaysNeededForTarget(metric, target);
  const officeOffset = Math.min(Math.max(share, 0), 100);
  const targetOffset = Math.min(Math.max(target, 0), 100);
  const assigned = metric.workingDays > 0 ? ((metric.workingDays - metric.unassigned) / metric.workingDays) * 100 : 0;
  const onTarget = share >= target;
  return (
    <section className="target-panel" aria-label="Office target outlook">
      <div className="target-head">
        <div>
          <strong>{Math.round(share)}</strong>
          <span>% in office</span>
        </div>
        <em className={onTarget ? "good" : "hot"}>{onTarget ? "On target" : "Below target"}</em>
      </div>
      <div className="temperature-track">
        <i className="target-marker" style={{ left: `${targetOffset}%` }} />
        <b className="office-marker" style={{ left: `calc(${officeOffset}% - 13px)` }} />
      </div>
      <div className="temperature-labels">
        <span>All WFH</span>
        <strong>{Math.round(target)}% target</strong>
        <span>All office</span>
      </div>
      <div className="completion-row">
        <span>{metric.unassigned} unassigned</span>
        <span>{metric.workingDays} working days</span>
      </div>
      <div className="completion-track">
        <i style={{ width: `${assigned}%` }} />
      </div>
      <p className="target-help">{targetHelpText(metric, target, needed)}</p>
      <div className="target-mini-counts">
        <span className="legend-chip office">Office {metric.office}</span>
        <span className="legend-chip wfh">WFH {metric.wfh}</span>
      </div>
    </section>
  );
}

function MonthAtGlancePanel({
  month,
  metric,
  bankHolidays,
}: {
  month: MonthRef;
  metric: Metrics;
  bankHolidays: number;
}) {
  const total = Math.max(
    metric.office + metric.wfh + metric.leave + metric.sickness + metric.nwd + bankHolidays + metric.unassigned,
    1,
  );
  const segments = [
    ["office", metric.office],
    ["wfh", metric.wfh],
    ["leave", metric.leave],
    ["sickness", metric.sickness],
    ["nwd", metric.nwd],
    ["bankHoliday", bankHolidays],
    ["unassigned", metric.unassigned],
  ] as const;
  const stats = [
    ["Office", metric.office, "office"],
    ["WFH", metric.wfh, "wfh"],
    ["Leave", metric.leave, "leave"],
    ["Sick", metric.sickness, "sickness"],
    ["NWD", metric.nwd, "nwd"],
    ["Bank holiday", bankHolidays, "bankHoliday"],
    ["Unassigned", metric.unassigned, "unassigned"],
  ] as const;
  return (
    <section className="glance-panel" aria-label={`${monthTitle(month)} at a glance`}>
      <p className="eyebrow">{monthNames[month.month - 1]} at a glance</p>
      <h2>{metric.tracked} of {metric.workingDays} working days tracked.</h2>
      <div className="composition-bar" aria-hidden="true">
        {segments.map(([kind, value]) => value > 0 ? <i key={kind} className={`segment-${kind}`} style={{ width: `${(value / total) * 100}%` }} /> : null)}
      </div>
      <div className="glance-stats">
        {stats.map(([label, value, kind]) => (
          <div key={label} className="glance-stat">
            <i className={`stat-stripe kind-${kind}`} />
            <div>
              <strong>{value}</strong>
              <span>{label}</span>
            </div>
          </div>
        ))}
      </div>
    </section>
  );
}

function targetHelpText(metric: Metrics, target: number, needed: number): string {
  if (metric.workingDays === 0) return "No working days in this month.";
  if (needed <= 0) {
    if (metric.unassigned === 0) return `Month complete and on target for ${Math.round(target)}%.`;
    return `On target so far. ${metric.unassigned} day${metric.unassigned === 1 ? "" : "s"} still to assign.`;
  }
  if (needed > metric.unassigned) return `${needed} more office day${needed === 1 ? "" : "s"} needed for ${Math.round(target)}%.`;
  return `${needed} office day${needed === 1 ? "" : "s"} needed for ${Math.round(target)}%.`;
}

function InsightView({
  profile,
  scope,
  month,
  setMonth,
  userEmail,
}: {
  profile: AttendanceProfile;
  scope: "month" | "year";
  month: MonthRef;
  setMonth: (month: MonthRef) => void;
  userEmail?: string;
}) {
  const bounds = scope === "year" ? yearBoundsForProfile(profile, month.year) : monthBounds(month);
  const end = bounds.endISO;
  const metric = metrics(profile, bounds.startISO, end, true);
  const reportYear = scope === "year" ? month.year : reportingYear(monthBounds(month).startISO, yearStartMonth(profile));
  const leave = leaveBreakdown(profile, reportYear);
  const quarters = [1, 2, 3, 4].map((quarter) => quarterMetrics(profile, reportYear, quarter));
  const bankHolidays = countBankHolidays(bounds.startISO, end);

  function move(offset: number) {
    if (scope === "year") setMonth({ ...month, year: month.year + offset });
    else setMonth(shiftMonth(month, offset));
  }

  return (
    <section className={`insight-layout ${scope === "year" ? "year-insight-layout" : ""}`}>
      <div className="panel hero-panel insight-hero">
        <div className="insight-control-row">
          <MonthNav
            month={month}
            years={selectableYears(profile)}
            canGoPrevious
            onMove={move}
            onYear={(year) => setMonth({ ...month, year })}
            scope={scope}
            showYearSelect={false}
          />
          {scope === "month" ? (
            <div className="range-actions">
              <button type="button" onClick={() => window.print()}>
                <Download size={16} />
                Print report
              </button>
            </div>
          ) : null}
          {scope === "year" ? (
            <div className="range-actions">
              <button type="button" onClick={() => window.print()}>
                <Download size={16} />
                Print report
              </button>
            </div>
          ) : null}
        </div>
        <Donut metric={metric} target={profile.settings.targetPct} />
      </div>

      {scope === "month" ? (
        <MonthViewPanel profile={profile} month={month} cutoffISO={null} />
      ) : null}

      {scope === "month" ? (
        <MonthCompositionPanel
          title={`${monthNames[month.month - 1]} composition`}
          metric={metric}
          bankHolidays={bankHolidays}
          rangeLabel="Logged data"
        />
      ) : null}

      {scope === "year" ? (
        <MonthCompositionPanel
          title={`${reportYear} composition`}
          subtitle={`${metric.tracked} of ${metric.workingDays} working days logged`}
          metric={metric}
          bankHolidays={bankHolidays}
        />
      ) : null}

      <div className="panel quarter-panel">
        <h2>Quarterly Outlook</h2>
        <div className="quarter-grid">
          {quarters.map((quarter) => {
            const officePct = Math.round(recordedOfficeShare(quarter.metric));
            const wfhPct = Math.round(recordedWfhShare(quarter.metric));
            return (
              <div key={quarter.label} className={scope === "month" && quarter.number === reportingQuarter(monthBounds(month).startISO, yearStartMonth(profile)) ? "quarter active" : "quarter"}>
                <div className="quarter-head">
                  <span>{quarter.label}</span>
                  <em>{quarter.metric.workingDays} days</em>
                </div>
                <div className="quarter-score">
                  <strong>{officePct}%</strong>
                  <span>office</span>
                </div>
                <div className="quarter-split" aria-label={`${officePct}% office, ${wfhPct}% WFH`}>
                  <i className="segment-office" style={{ width: `${officePct}%` }} />
                  <i className="segment-wfh" style={{ width: `${wfhPct}%` }} />
                </div>
                <div className="quarter-kpis">
                  <span className="office-dot">{quarter.metric.office} office</span>
                  <span className="wfh-dot">{quarter.metric.wfh} WFH</span>
                </div>
              </div>
            );
          })}
        </div>
      </div>

      <div className="panel leave-panel">
        <div className="infographic-head">
          <div>
            <h2>Annual leave</h2>
            <p>{leave.taken} taken from {leave.allowance} allowance</p>
          </div>
          <strong>{leave.remaining}</strong>
        </div>
        <div className="leave-progress" aria-label={`${leave.taken} days taken from ${leave.allowance} days allowance`}>
          <i style={{ width: `${(leave.taken / Math.max(leave.allowance, 1)) * 100}%` }} />
        </div>
        <div className="leave-grid">
          <Metric label="Taken" value={String(leave.taken)} />
          <Metric label="Booked" value={String(leave.booked)} />
          <Metric label="Allowance" value={String(leave.allowance)} />
          <Metric label="Remaining" value={String(leave.remaining)} accent="green" />
        </div>
      </div>

      {scope === "year" ? <YearMonthsPanel profile={profile} year={reportYear} /> : null}
      {scope === "month" ? (
        <MonthPrintReport
          profile={profile}
          month={month}
          metric={metric}
          target={profile.settings.targetPct}
          bankHolidays={bankHolidays}
          cutoffISO={null}
          rangeLabel="Logged data"
          userEmail={userEmail}
        />
      ) : null}
      {scope === "year" ? (
        <YearPrintReport
          profile={profile}
          year={reportYear}
          metric={metric}
          target={profile.settings.targetPct}
          leave={leave}
          quarters={quarters}
          bankHolidays={bankHolidays}
          userEmail={userEmail}
        />
      ) : null}
    </section>
  );
}

function MonthViewPanel({ profile, month, cutoffISO }: { profile: AttendanceProfile; month: MonthRef; cutoffISO: string | null }) {
  const rows = monthInsightRows(profile, month, cutoffISO);
  return (
    <div className="panel month-view-panel">
      <div className="panel-title-row">
        <h2>{monthNames[month.month - 1]} month view</h2>
        <span className="current-date">Current date {readableDate(todayISO())}</span>
      </div>
      <div className="month-view-weekdays">
        {["M", "T", "W", "T", "F", "S", "S"].map((day, index) => <span key={`${day}-${index}`}>{day}</span>)}
      </div>
      <div className="month-view-grid">
        {rows.flat().map((cell) => (
          <span
            key={cell.id}
            className={`month-view-cell ${cell.inMonth ? `kind-${cell.kind}` : "out"} ${cell.isToday ? "today" : ""}`}
          >
            {cell.day ?? ""}
          </span>
        ))}
      </div>
      <div className="month-view-legend">
        <span className="legend-chip office">Office</span>
        <span className="legend-chip wfh">WFH</span>
        <span className="legend-chip leave">Leave</span>
        <span className="legend-chip sick">Sick</span>
        <span className="legend-chip nwd">NWD</span>
        <span className="legend-chip holiday">Bank holiday</span>
      </div>
    </div>
  );
}

function YearMonthsPanel({ profile, year }: { profile: AttendanceProfile; year: number }) {
  const months = reportingYearMonths(year, yearStartMonth(profile));
  return (
    <div className="panel year-months-panel">
      <div className="panel-title-row">
        <div>
          <h2>{year} 12 month view</h2>
          <p className="muted">Reporting year at a glance</p>
        </div>
        <span className="current-date">Current date {readableDate(todayISO())}</span>
      </div>
      <div className="year-months-grid">
        {months.map((month) => (
          <div key={monthKeyForRef(month)} className="year-mini-month">
            <div className="year-mini-title">
              <strong>{monthNames[month.month - 1].slice(0, 3)}</strong>
              <span>{month.year}</span>
            </div>
            <div className="year-mini-weekdays">
              {["M", "T", "W", "T", "F", "S", "S"].map((day, index) => <span key={`${day}-${index}`}>{day}</span>)}
            </div>
            <div className="year-mini-grid">
              {monthInsightRows(profile, month, null).flat().map((cell) => (
                <span
                  key={cell.id}
                  className={`year-mini-cell ${cell.inMonth ? `kind-${cell.kind}` : "out"} ${cell.isToday ? "today" : ""}`}
                >
                  {cell.day ?? ""}
                </span>
              ))}
            </div>
          </div>
        ))}
      </div>
      <div className="month-view-legend">
        <span className="legend-chip office">Office</span>
        <span className="legend-chip wfh">WFH</span>
        <span className="legend-chip leave">Leave</span>
        <span className="legend-chip sick">Sick</span>
        <span className="legend-chip nwd">NWD</span>
        <span className="legend-chip holiday">Bank holiday</span>
      </div>
    </div>
  );
}

function MonthPrintReport({
  profile,
  month,
  metric,
  target,
  bankHolidays,
  cutoffISO,
  rangeLabel,
  userEmail,
}: {
  profile: AttendanceProfile;
  month: MonthRef;
  metric: Metrics;
  target: number;
  bankHolidays: number;
  cutoffISO: string | null;
  rangeLabel: string;
  userEmail?: string;
}) {
  const title = monthTitle(month);
  const share = Math.round(officeShare(metric));
  const wfhPct = Math.round(recordedWfhShare(metric));
  const needed = officeDaysNeededForTarget(metric, target);
  const assigned = Math.max(metric.workingDays - metric.unassigned, 0);
  const worked = metric.office + metric.wfh;
  const completion = metric.workingDays > 0 ? Math.round((assigned / metric.workingDays) * 100) : 0;
  const action =
    metric.workingDays === 0
      ? "No working days are in scope for this month."
      : needed <= 0
        ? metric.unassigned === 0
          ? "The month is fully assigned and currently meets the office target."
          : `${metric.unassigned} working day${metric.unassigned === 1 ? "" : "s"} still need assigning, but the month is currently on target.`
        : needed > metric.unassigned
          ? `${needed} more office day${needed === 1 ? "" : "s"} would be needed, which is more than the ${metric.unassigned} unassigned day${metric.unassigned === 1 ? "" : "s"} remaining.`
          : `Mark ${needed} of the remaining ${metric.unassigned} unassigned working day${metric.unassigned === 1 ? "" : "s"} as office to reach the ${Math.round(target)}% target.`;
  const rows = monthInsightRows(profile, month, cutoffISO);
  const totalComposition = Math.max(metric.workingDays + metric.leave + metric.nwd + bankHolidays, 1);

  return (
    <article className="print-report month-print-report" aria-hidden="true">
      <header className="print-header">
        <div>
          <p>Work Attendance</p>
          <h1>{title}</h1>
          <span>{rangeLabel} report</span>
        </div>
        <div>
          <strong>{userEmail ?? "Local preview"}</strong>
          <span>Generated {readableDate(todayISO())}</span>
        </div>
      </header>

      <section className="print-hero-grid">
        <div className="print-card print-score-card">
          <span className="print-eyebrow">Office score</span>
          <div className="print-ring" style={{ background: `conic-gradient(#0aa9e8 ${share * 3.6}deg, #7d55ff 0 250deg, #d7e1ea 0)` }}>
            <strong>{share}%</strong>
          </div>
          <p>Target {Math.round(target)}%</p>
          <b className={needed <= 0 ? "positive" : "warning"}>{needed <= 0 ? "On target" : `${needed} office days needed`}</b>
        </div>
        <div className="print-card print-insight-card">
          <h2>{share >= target ? "Month is on target" : "Month is below target"}</h2>
          <p>{targetHelpText(metric, target, needed)}</p>
          <div className="print-chip-grid">
            <PrintChip label="Assigned" value={`${assigned}/${metric.workingDays}`} />
            <PrintChip label="Office" value={String(metric.office)} />
            <PrintChip label="WFH" value={String(metric.wfh)} />
            <PrintChip label="Unassigned" value={String(metric.unassigned)} />
          </div>
        </div>
      </section>

      <section className="print-card print-target-panel">
        <div>
          <h2>Office target outlook</h2>
          <p>A clear view of the month position and what needs to happen with remaining unassigned days.</p>
        </div>
        <div className="print-target-columns">
          <div>
            <span className="print-eyebrow">Current office share</span>
            <strong>{share}%</strong>
            <PrintProgress value={share} marker={target} />
            <p>Office {metric.office} / WFH {metric.wfh} across {worked} assigned work-location days.</p>
          </div>
          <div>
            <span className="print-eyebrow">Remaining plan</span>
            <strong>{metric.unassigned}</strong>
            <PrintProgress value={Math.min(needed, metric.unassigned)} max={Math.max(metric.unassigned, 1)} />
            <p>{action}</p>
          </div>
        </div>
      </section>

      <section className="print-two-column">
        <div className="print-card print-calendar-panel">
          <div className="print-panel-title">
            <h2>Month map</h2>
            <span>{rangeLabel}</span>
          </div>
          <div className="print-weekdays">
            {["M", "T", "W", "T", "F", "S", "S"].map((day, index) => <span key={`${day}-${index}`}>{day}</span>)}
          </div>
          <div className="print-calendar-grid">
            {rows.flat().map((cell) => (
              <span key={cell.id} className={`print-day ${cell.inMonth ? `kind-${cell.kind}` : "out"} ${cell.isToday ? "today" : ""}`}>
                {cell.day ?? ""}
              </span>
            ))}
          </div>
          <PrintLegend />
        </div>

        <div className="print-card print-balance-panel">
          <h2>Office / WFH balance</h2>
          <p>{worked > 0 ? `${share}% office and ${wfhPct}% WFH across assigned location days.` : "No office or WFH days have been assigned yet."}</p>
          <div className="print-split-bar">
            <i className="segment-office" style={{ width: `${share}%` }} />
            <i className="segment-wfh" style={{ width: `${wfhPct}%` }} />
          </div>
          <div className="print-chip-grid three">
            <PrintChip label="Office share" value={`${share}%`} />
            <PrintChip label="WFH share" value={`${wfhPct}%`} />
            <PrintChip label="Assigned" value={`${assigned}/${metric.workingDays}`} />
          </div>
        </div>
      </section>

      <section className="print-two-column">
        <div className="print-card">
          <h2>Progress</h2>
          <p>{assigned} of {metric.workingDays} working days have been assigned.</p>
          <PrintProgress value={completion} />
          <div className="print-progress-row">
            <span>Completion</span>
            <strong>{completion}%</strong>
          </div>
          <PrintProgress value={share} marker={target} />
          <div className="print-progress-row">
            <span>Office target</span>
            <strong>{share}% / {Math.round(target)}%</strong>
          </div>
        </div>

        <div className="print-card">
          <h2>What this means</h2>
          <p>{action}</p>
          <div className="print-chip-grid three">
            <PrintChip label="Need" value={String(Math.max(needed, 0))} />
            <PrintChip label="Open" value={String(metric.unassigned)} />
            <PrintChip label="Working days" value={String(metric.workingDays)} />
          </div>
        </div>
      </section>

      <section className="print-card print-footer-grid">
        <PrintChip label="Office" value={String(metric.office)} />
        <PrintChip label="WFH" value={String(metric.wfh)} />
        <PrintChip label="Leave" value={String(metric.leave)} />
        <PrintChip label="Sick" value={String(metric.sickness)} />
        <PrintChip label="NWD" value={String(metric.nwd)} />
        <PrintChip label="Bank holiday" value={String(bankHolidays)} />
        <PrintChip label="Unassigned" value={String(metric.unassigned)} />
      </section>

      <footer className="print-note">
        Leave, bank holidays and non-working days are excluded from office-target working-day totals.
      </footer>
    </article>
  );
}

function PrintChip({ label, value }: { label: string; value: string }) {
  return (
    <span className="print-chip">
      <em>{label}</em>
      <strong>{value}</strong>
    </span>
  );
}

function PrintProgress({ value, marker, max = 100 }: { value: number; marker?: number; max?: number }) {
  const pct = Math.max(0, Math.min(100, (value / Math.max(max, 1)) * 100));
  const markerPct = marker === undefined ? null : Math.max(0, Math.min(100, (marker / Math.max(max, 1)) * 100));
  return (
    <div className="print-progress">
      <i style={{ width: `${pct}%` }} />
      {markerPct === null ? null : <b style={{ left: `${markerPct}%` }} />}
    </div>
  );
}

function PrintLegend() {
  return (
    <div className="print-legend">
      <span className="office-dot">Office</span>
      <span className="wfh-dot">WFH</span>
      <span className="leave-dot">Leave</span>
      <span className="sick-dot">Sick</span>
      <span className="nwd-dot">NWD</span>
      <span className="holiday-dot">Bank holiday</span>
    </div>
  );
}

function YearPrintReport({
  profile,
  year,
  metric,
  target,
  leave,
  quarters,
  bankHolidays,
  userEmail,
}: {
  profile: AttendanceProfile;
  year: number;
  metric: Metrics;
  target: number;
  leave: ReturnType<typeof leaveBreakdown>;
  quarters: ReturnType<typeof quarterMetrics>[];
  bankHolidays: number;
  userEmail?: string;
}) {
  const bounds = reportingYearBounds(year, yearStartMonth(profile));
  const share = Math.round(officeShare(metric));
  const needed = officeDaysNeededForTarget(metric, target);
  const logged = metric.office + metric.wfh + metric.leave + metric.sickness + metric.nwd;
  const compositionTotal = Math.max(metric.office + metric.wfh + metric.leave + metric.sickness + metric.nwd + metric.unassigned, 1);
  const months = reportingYearMonths(year, yearStartMonth(profile));
  const action =
    needed <= 0
      ? "No immediate office catch-up is needed. Keep future months balanced as they are logged."
      : metric.unassigned === 0
        ? "The target shortfall cannot be recovered from unassigned days because all working days have already been assigned."
        : `Use the remaining unassigned days deliberately: ${needed} of ${metric.unassigned} need to become office days to land the year at ${Math.round(target)}%.`;
  const bestMonth = months
    .map((period) => ({ period, metric: monthMetrics(profile, period) }))
    .filter((item) => item.metric.workingDays > 0)
    .sort((a, b) => officeShare(b.metric) - officeShare(a.metric))[0];

  return (
    <article className="print-report year-print-report" aria-hidden="true">
      <section className="print-page">
        <header className="print-header">
          <div>
            <p>Work Attendance</p>
            <h1>{readableDate(bounds.startISO)} - {readableDate(bounds.endISO)}</h1>
            <span>Annual Attendance Insights</span>
          </div>
          <div>
            <strong>{userEmail ?? "Local preview"}</strong>
            <span>Generated {readableDate(todayISO())}</span>
          </div>
        </header>

        <section className="print-hero-grid">
          <div className="print-card print-score-card">
            <span className="print-eyebrow">Office score</span>
            <div className="print-ring" style={{ background: `conic-gradient(#0aa9e8 ${share * 3.6}deg, #7d55ff 0 250deg, #d7e1ea 0)` }}>
              <strong>{share}%</strong>
            </div>
            <p>Target {Math.round(target)}%</p>
            <b className={needed <= 0 ? "positive" : "warning"}>{needed <= 0 ? "On target" : `${needed} office days needed`}</b>
          </div>
          <div className="print-card print-insight-card">
            <h2>{needed <= 0 ? `On track for ${Math.round(target)}%` : `${needed} office days needed for target`}</h2>
            <p>{needed <= 0 ? "Office attendance is meeting the target. Keep an eye on unassigned days so the final mix does not drift late in the year." : `There are ${metric.unassigned} unassigned working days left in the report. Mark ${needed} of them as office to bring the year back to target.`}</p>
            <div className="print-chip-grid">
              <PrintChip label="Logged" value={`${logged}/${compositionTotal}`} />
              <PrintChip label="Office" value={String(metric.office)} />
              <PrintChip label="WFH" value={String(metric.wfh)} />
              <PrintChip label="Unassigned" value={String(metric.unassigned)} />
            </div>
          </div>
        </section>

        <section className="print-card print-target-panel">
          <div>
            <h2>Office target outlook</h2>
            <p>A cleaner view of where the year stands and how the remaining unassigned days need to land.</p>
          </div>
          <div className="print-target-columns">
            <div>
              <span className="print-eyebrow">Current office share</span>
              <strong>{share}%</strong>
              <PrintProgress value={share} marker={target} />
              <p>{bestMonth ? `Best logged month: ${monthNames[bestMonth.period.month - 1].slice(0, 3)} at ${Math.round(officeShare(bestMonth.metric))}%.` : "No working-day data is available for this year yet."}</p>
            </div>
            <div>
              <span className="print-eyebrow">Remaining unassigned days</span>
              <strong>{metric.unassigned}</strong>
              <PrintProgress value={Math.min(needed, metric.unassigned)} max={Math.max(metric.unassigned, 1)} />
              <p>{needed <= 0 ? `${metric.unassigned} days remain flexible.` : `${needed} office + ${Math.max(metric.unassigned - needed, 0)} flexible days.`}</p>
            </div>
          </div>
        </section>

        <section className="print-two-column">
          <div className="print-card">
            <h2>Year composition</h2>
            <div className="print-composition-strip">
              {[
                ["office", metric.office],
                ["wfh", metric.wfh],
                ["leave", metric.leave],
                ["sickness", metric.sickness],
                ["nwd", metric.nwd],
                ["unassigned", metric.unassigned],
              ].map(([kind, value]) => Number(value) > 0 ? <i key={kind} className={`segment-${kind}`} style={{ width: `${(Number(value) / compositionTotal) * 100}%` }} /> : null)}
            </div>
            <div className="print-chip-grid three">
              <PrintChip label="Office" value={String(metric.office)} />
              <PrintChip label="WFH" value={String(metric.wfh)} />
              <PrintChip label="Leave" value={String(metric.leave)} />
              <PrintChip label="Sick" value={String(metric.sickness)} />
              <PrintChip label="NWD" value={String(metric.nwd)} />
              <PrintChip label="Unassigned" value={String(metric.unassigned)} />
            </div>
          </div>
          <div className="print-card">
            <h2>What this means</h2>
            <p>{action}</p>
            <div className="print-chip-grid three">
              <PrintChip label="Need" value={String(Math.max(needed, 0))} />
              <PrintChip label="Unassigned" value={String(metric.unassigned)} />
              <PrintChip label="Pace" value={needed <= 0 ? "OK" : metric.unassigned > 0 ? `${Math.ceil((needed / metric.unassigned) * 100)}%` : "n/a"} />
            </div>
          </div>
        </section>

        <section className="print-card print-quarter-table">
          <div className="print-panel-title">
            <h2>Quarterly Outlook</h2>
            <span>Office / WFH and working-day totals</span>
          </div>
          <div className="print-quarter-grid">
            {quarters.map((quarter) => (
              <div key={quarter.label}>
                <strong>{quarter.label}</strong>
                <span>{Math.round(recordedOfficeShare(quarter.metric))}% office</span>
                <PrintProgress value={recordedOfficeShare(quarter.metric)} />
                <p>{quarter.metric.office} office / {quarter.metric.wfh} WFH · {quarter.metric.workingDays} working days</p>
              </div>
            ))}
          </div>
        </section>

        <section className="print-card print-footer-grid">
          <PrintChip label="Taken leave" value={String(leave.taken)} />
          <PrintChip label="Booked leave" value={String(leave.booked)} />
          <PrintChip label="Remaining" value={String(leave.remaining)} />
          <PrintChip label="Allowance" value={String(leave.allowance)} />
          <PrintChip label="Bank holidays" value={String(bankHolidays)} />
          <PrintChip label="Other absence" value={String(metric.sickness + metric.nwd)} />
          <PrintChip label="Working days" value={String(metric.workingDays)} />
        </section>
      </section>

      <section className="print-page print-month-map-page">
        <header className="print-header">
          <div>
            <p>Work Attendance</p>
            <h1>Year Month Maps</h1>
            <span>Recording start: {monthTitle(recordingStartParts(profile))} · Year starts {monthNames[yearStartMonth(profile) - 1]}</span>
          </div>
          <div>
            <strong>{userEmail ?? "Local preview"}</strong>
            <span>Generated {readableDate(todayISO())}</span>
          </div>
        </header>
        <div className="print-year-map-grid">
          {months.map((period) => (
            <div key={monthKeyForRef(period)} className="print-year-month-card">
              <div className="print-panel-title">
                <h2>{monthNames[period.month - 1].slice(0, 3)}</h2>
                <span>{period.year}</span>
              </div>
              <div className="print-weekdays">
                {["M", "T", "W", "T", "F", "S", "S"].map((day, index) => <span key={`${day}-${index}`}>{day}</span>)}
              </div>
              <div className="print-calendar-grid mini">
                {monthInsightRows(profile, period, null).flat().map((cell) => (
                  <span key={cell.id} className={`print-day mini ${cell.inMonth ? `kind-${cell.kind}` : "out"} ${cell.isToday ? "today" : ""}`}>
                    {cell.day ?? ""}
                  </span>
                ))}
              </div>
            </div>
          ))}
        </div>
        <PrintLegend />
        <footer className="print-note">Months before the recording start are shown out of scope and excluded from annual totals.</footer>
      </section>
    </article>
  );
}

function MonthCompositionPanel({
  title,
  metric,
  bankHolidays,
  rangeLabel,
  subtitle,
}: {
  title: string;
  metric: Metrics;
  bankHolidays: number;
  rangeLabel?: string;
  subtitle?: string;
}) {
  return (
    <div className="panel month-composition-panel">
      <div className="panel-title-row">
        <div>
          <h2>{title}</h2>
          <p className="muted">{subtitle ?? `${metric.office + metric.wfh + metric.sickness} of ${metric.workingDays} working days logged`}</p>
        </div>
        <strong>{Math.round(officeShare(metric))}%</strong>
      </div>
      {rangeLabel ? <span className="range-chip">{rangeLabel}</span> : null}
      <div className="composition-bar" aria-hidden="true">
        {[
          ["office", metric.office],
          ["wfh", metric.wfh],
          ["leave", metric.leave],
          ["sickness", metric.sickness],
          ["nwd", metric.nwd],
          ["bankHoliday", bankHolidays],
          ["unassigned", metric.unassigned],
        ].map(([kind, value]) => Number(value) > 0 ? <i key={kind} className={`segment-${kind}`} style={{ width: `${(Number(value) / Math.max(metric.workingDays + metric.leave + metric.nwd + bankHolidays, 1)) * 100}%` }} /> : null)}
      </div>
      <div className="composition-pills">
        {[
          ["Office", metric.office, "office"],
          ["WFH", metric.wfh, "wfh"],
          ["Leave", metric.leave, "leave"],
          ["Sick", metric.sickness, "sickness"],
          ["NWD", metric.nwd, "nwd"],
          ["Bank holiday", bankHolidays, "bankHoliday"],
          ["Unassigned", metric.unassigned, "unassigned"],
        ].map(([label, value, kind]) => (
          <span key={label} className={`composition-pill kind-${kind}`}>
            {label} <strong>{value}</strong>
          </span>
        ))}
      </div>
    </div>
  );
}

function SettingsView({
  userEmail,
  profile,
  state,
  replaceState,
  signOut,
}: {
  userEmail: string;
  profile: AttendanceProfile;
  state: { activeProfileId: string; profiles: AttendanceProfile[] };
  replaceState: (state: { activeProfileId: string; profiles: AttendanceProfile[] }) => void;
  signOut: () => void;
}) {
  const [leaveYear, setLeaveYear] = useState(() => reportingYear(todayISO(), yearStartMonth(profile)));
  const startParts = recordingStartParts(profile);
  const leaveYears = selectableYears(profile);

  function patchProfile(patch: Partial<AttendanceProfile>) {
    replaceState(updateActiveProfile(state, (current) => ({ ...current, ...patch })));
  }

  function patchSettings(settings: Partial<AttendanceProfile["settings"]>) {
    patchProfile({ settings: { ...profile.settings, ...settings } });
  }

  return (
    <section className="settings-layout">
      <div className="panel settings-card">
        <h2>Profile</h2>
        <label>
          Name
          <input value={profile.name} onChange={(event) => patchProfile({ name: event.target.value })} />
        </label>
      </div>
      <div className="panel settings-card">
        <h2>Office target</h2>
        <div className="slider-row">
          <input
            type="range"
            min="0"
            max="100"
            value={profile.settings.targetPct}
            onChange={(event) => patchSettings({ targetPct: Number(event.target.value) })}
          />
          <strong>{Math.round(profile.settings.targetPct)}%</strong>
        </div>
      </div>
      <div className="panel settings-card">
        <h2>Recording start</h2>
        <div className="form-grid">
          <select value={startParts.month} onChange={(event) => patchSettings({ recordingStartMonth: monthKey(startParts.year, Number(event.target.value)) })}>
            {monthNames.map((name, index) => <option key={name} value={index + 1}>{name}</option>)}
          </select>
          <select value={startParts.year} onChange={(event) => patchSettings({ recordingStartMonth: monthKey(Number(event.target.value), startParts.month) })}>
            {Array.from({ length: 12 }, (_, index) => new Date().getFullYear() - 6 + index).map((year) => <option key={year}>{year}</option>)}
          </select>
        </div>
      </div>
      <div className="panel settings-card">
        <h2>Year starts</h2>
        <select value={yearStartMonth(profile)} onChange={(event) => patchSettings({ yearStartMonth: Number(event.target.value) })}>
          {monthNames.map((name, index) => <option key={name} value={index + 1}>{name}</option>)}
        </select>
      </div>
      <div className="panel settings-card">
        <h2>Annual leave</h2>
        <div className="form-grid">
          <select value={leaveYear} onChange={(event) => setLeaveYear(Number(event.target.value))}>
            {leaveYears.map((year) => <option key={year}>{year}</option>)}
          </select>
          <input
            type="number"
            min="0"
            max="60"
            value={allowanceForYear(profile, leaveYear)}
            onChange={(event) => patchSettings({ leaveAllowances: { ...profile.settings.leaveAllowances, [String(leaveYear)]: Number(event.target.value) } })}
          />
        </div>
      </div>
      <div className="panel settings-card">
        <h2>Account</h2>
        <p className="muted">{userEmail}</p>
        <button className="danger full" type="button" onClick={signOut}>
          <LogOut size={16} />
          Sign out
        </button>
      </div>
    </section>
  );
}

function MonthNav({
  month,
  years,
  canGoPrevious,
  onMove,
  onYear,
  scope = "month",
  showTitle = true,
  showYearSelect = true,
}: {
  month: MonthRef;
  years: number[];
  canGoPrevious: boolean;
  onMove: (offset: number) => void;
  onYear: (year: number) => void;
  scope?: "month" | "year";
  showTitle?: boolean;
  showYearSelect?: boolean;
}) {
  return (
    <div className={`month-nav ${showTitle ? "" : "month-nav-controls-only"} ${showYearSelect ? "" : "month-nav-no-select"}`}>
      <button className="icon-button" type="button" disabled={!canGoPrevious} onClick={() => onMove(-1)}>
        <ChevronLeft size={18} />
      </button>
      {showTitle ? (
        <div>
          <p>{scope === "year" ? "Reporting year" : "Visible month"}</p>
          <h2>{scope === "year" ? month.year : monthTitle(month)}</h2>
        </div>
      ) : null}
      {!showTitle && !showYearSelect ? (
        <strong className="month-nav-compact-label">{scope === "year" ? month.year : monthNames[month.month - 1]}</strong>
      ) : null}
      {showYearSelect ? (
        <select value={month.year} onChange={(event) => onYear(Number(event.target.value))}>
          {years.map((year) => <option key={year}>{year}</option>)}
        </select>
      ) : null}
      <button className="icon-button" type="button" onClick={() => onMove(1)}>
        <ChevronRight size={18} />
      </button>
    </div>
  );
}

function Donut({ metric, target }: { metric: Metrics; target: number }) {
  const pct = Math.round(officeShare(metric));
  return (
    <div className="donut-row">
      <div className="donut" style={{ background: `conic-gradient(var(--office) ${pct * 3.6}deg, var(--wfh) 0 250deg, var(--line) 0)` }}>
        <span>{pct}%</span>
      </div>
      <div>
        <h2>{pct >= target ? "On target" : "Below target"}</h2>
        <p className="muted">{metric.office} office days from {metric.workingDays} tracked working days.</p>
      </div>
    </div>
  );
}

function Metric({ label, value, accent }: { label: string; value: string; accent?: "cyan" | "green" }) {
  return (
    <div className={`metric ${accent ? `accent-${accent}` : ""}`}>
      <span>{label}</span>
      <strong>{value}</strong>
    </div>
  );
}

function SyncStatus({ status }: { status: string }) {
  return <span className={`sync-pill status-${status}`}>{status === "syncing" ? "Syncing" : status === "error" ? "Sync issue" : "Synced"}</span>;
}

function DayTypeLegend() {
  return (
    <div className="panel legend">
      {[
        ["office", "Office", "Physically in the office."],
        ["wfh", "WFH", "Working from home."],
        ["leave", "Leave", "Annual leave day."],
        ["sickness", "Sickness", "Sick leave, excluded from target pressure."],
        ["nwd", "NWD", "Non-working weekday."],
        ["bankHoliday", "Bank holiday", "England and Wales bank holiday."],
      ].map(([kind, title, desc]) => (
        <div key={kind}>
          <span className={`legend-dot kind-${kind}`} />
          <strong>{title}</strong>
          <p>{desc}</p>
        </div>
      ))}
    </div>
  );
}

function dayLabel(kind: DayKind): string {
  return {
    office: "OFFICE",
    wfh: "WFH",
    leave: "LEAVE",
    sickness: "SICK",
    nwd: "NWD",
    unassigned: "",
    weekend: "",
    bankHoliday: "BH",
  }[kind];
}

function selectableYears(profile: AttendanceProfile): number[] {
  const start = recordingStartParts(profile).year;
  const end = new Date().getFullYear() + 3;
  return Array.from({ length: Math.max(1, end - start + 1) }, (_, index) => start + index);
}

function countBankHolidays(start: string, end: string): number {
  let count = 0;
  forEachDate(start, end, (date) => {
    if (isBankHoliday(date)) count += 1;
  });
  return count;
}

function minISO(a: string, b: string): string {
  return a < b ? a : b;
}

function yearBoundsForProfile(profile: AttendanceProfile, year: number) {
  const bounds = reportingYearBounds(year, yearStartMonth(profile));
  return { startISO: bounds.startISO > `${recordingStartMonthKey(profile)}-01` ? bounds.startISO : `${recordingStartMonthKey(profile)}-01`, endISO: bounds.endISO };
}

function quarterMetrics(profile: AttendanceProfile, year: number, quarter: number) {
  const months = reportingYearMonths(year, yearStartMonth(profile)).slice((quarter - 1) * 3, quarter * 3);
  const start = monthBounds(months[0]).startISO;
  const end = monthBounds(months[2]).endISO;
  return { number: quarter, label: `Q${quarter}`, metric: metrics(profile, start, end, true) };
}

function recordedOfficeShare(metric: Metrics): number {
  return metric.office + metric.wfh > 0 ? (metric.office / (metric.office + metric.wfh)) * 100 : 0;
}

function recordedWfhShare(metric: Metrics): number {
  return metric.office + metric.wfh > 0 ? (metric.wfh / (metric.office + metric.wfh)) * 100 : 0;
}

function monthInsightRows(profile: AttendanceProfile, month: MonthRef, cutoffISO: string | null) {
  const cells = gridDays(month).map((day) => {
    if (!day.iso) return { id: day.id, day: null, kind: "unassigned" as DayKind, inMonth: false, isToday: false };
    const actualKind = kindForDate(profile, day.iso);
    const kind = cutoffISO && day.iso > cutoffISO && !["weekend", "bankHoliday"].includes(actualKind) ? "unassigned" : actualKind;
    return { id: day.iso, day: day.day, kind: kind as DayKind, inMonth: true, isToday: day.iso === todayISO() };
  });
  while (cells.length % 7 !== 0) {
    cells.push({ id: `empty-tail-${cells.length}`, day: null, kind: "unassigned", inMonth: false, isToday: false });
  }
  return Array.from({ length: cells.length / 7 }, (_, index) => cells.slice(index * 7, index * 7 + 7));
}
