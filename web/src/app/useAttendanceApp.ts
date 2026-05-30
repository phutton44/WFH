import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { api, clearSession, loadToken, loadUser, saveSession } from "../lib/api";
import {
  activeProfile,
  defaultState,
  hasAssignedDays,
  leaveShortfall,
  normalizeState,
  setDateKind,
  updateActiveProfile,
} from "../lib/attendance";
import type { AppTab, AttendanceState, AuthUser, DayKind, LeaveShortfallWarning } from "../lib/types";

type SyncStatus = "idle" | "syncing" | "offline" | "error";

export function useAttendanceApp() {
  const [user, setUser] = useState<AuthUser | null>(() => loadUser<AuthUser>());
  const [state, setState] = useState<AttendanceState>(() => defaultState());
  const [tab, setTab] = useState<AppTab>("record");
  const [syncStatus, setSyncStatus] = useState<SyncStatus>("idle");
  const [message, setMessage] = useState("");
  const [leaveWarning, setLeaveWarning] = useState<LeaveShortfallWarning | null>(null);
  const [isPreview, setIsPreview] = useState(false);
  const saveTimer = useRef<number | null>(null);
  const undoState = useRef<AttendanceState | null>(null);

  const profile = useMemo(() => activeProfile(state), [state]);
  const signedIn = Boolean(user && loadToken()) || isPreview;

  const saveNow = useCallback(
    async (payload: AttendanceState) => {
      if (isPreview) {
        localStorage.setItem("WFH_WEB_PREVIEW_STATE", JSON.stringify(payload));
        return;
      }
      if (!loadToken()) return;
      setSyncStatus("syncing");
      try {
        await api.saveState(payload);
        setSyncStatus("idle");
      } catch (error) {
        setSyncStatus("error");
        setMessage(error instanceof Error ? error.message : "Could not save state.");
      }
    },
    [isPreview],
  );

  const scheduleSave = useCallback(
    (next: AttendanceState) => {
      if (saveTimer.current) window.clearTimeout(saveTimer.current);
      saveTimer.current = window.setTimeout(() => void saveNow(next), 650);
    },
    [saveNow],
  );

  const replaceState = useCallback(
    (next: AttendanceState, shouldSave = true) => {
      const normalized = normalizeState(next);
      setState(normalized);
      if (shouldSave) scheduleSave(normalized);
    },
    [scheduleSave],
  );

  const loadCloudState = useCallback(async () => {
    if (isPreview || !loadToken()) return;
    setSyncStatus("syncing");
    try {
      const response = await api.loadState();
      const next = normalizeState(response.payload ?? defaultState());
      setState(next);
      if (!response.payload) await api.saveState(next);
      setSyncStatus("idle");
    } catch (error) {
      setSyncStatus("error");
      setMessage(error instanceof Error ? error.message : "Could not load state.");
    }
  }, [isPreview]);

  useEffect(() => {
    if (loadToken() && user && !isPreview) void loadCloudState();
  }, [isPreview, loadCloudState, user]);

  useEffect(() => {
    if (!signedIn || isPreview) return;
    const id = window.setInterval(() => void loadCloudState(), 120000);
    return () => window.clearInterval(id);
  }, [isPreview, loadCloudState, signedIn]);

  const signIn = useCallback(
    async (email: string, password: string) => {
      setMessage("");
      const response = await api.signIn(email, password);
      saveSession(response.token, response.user);
      setUser(response.user);
      await loadCloudState();
    },
    [loadCloudState],
  );

  const finishSocialSignIn = useCallback(
    async (response: { token: string; user: AuthUser }) => {
      saveSession(response.token, response.user);
      setUser(response.user);
      setIsPreview(false);
      await loadCloudState();
    },
    [loadCloudState],
  );

  const enterPreview = useCallback(() => {
    const saved = localStorage.getItem("WFH_WEB_PREVIEW_STATE");
    setState(saved ? normalizeState(JSON.parse(saved)) : defaultState());
    setUser({ id: "preview", email: "local-preview" });
    setIsPreview(true);
    setMessage("");
  }, []);

  const signOut = useCallback(() => {
    clearSession();
    setUser(null);
    setIsPreview(false);
    setState(defaultState());
    setMessage("");
  }, []);

  const applyDates = useCallback(
    (dates: Set<string>, kind: DayKind, allowUndo = false) => {
      if (!dates.size) return;
      const currentProfile = activeProfile(state);
      if (kind === "leave") {
        const warning = leaveShortfall(currentProfile, dates);
        if (warning) {
          setLeaveWarning(warning);
          setMessage("");
          return;
        }
      }
      let nextProfile = currentProfile;
      try {
        for (const date of [...dates].sort()) {
          nextProfile = setDateKind(nextProfile, date, kind);
        }
      } catch (error) {
        setMessage(error instanceof Error ? error.message : "Could not update dates.");
        return;
      }
      if (allowUndo && hasAssignedDays(currentProfile, dates)) {
        undoState.current = state;
        setMessage(`Updated ${dates.size} days. Undo is available.`);
      } else {
        undoState.current = null;
        setMessage("");
      }
      replaceState(updateActiveProfile(state, () => nextProfile));
    },
    [replaceState, state],
  );

  const undoBulk = useCallback(() => {
    if (!undoState.current) return;
    replaceState(undoState.current);
    undoState.current = null;
    setMessage("Bulk change undone.");
  }, [replaceState]);

  return {
    user,
    state,
    profile,
    tab,
    setTab,
    signedIn,
    syncStatus,
    message,
    setMessage,
    leaveWarning,
    dismissLeaveWarning: () => setLeaveWarning(null),
    isPreview,
    signIn,
    finishSocialSignIn,
    enterPreview,
    signOut,
    loadCloudState,
    replaceState,
    applyDates,
    undoBulk,
    hasUndo: Boolean(undoState.current),
  };
}
