import {
  currentMonthKey,
  forEachDate,
  isAssignableWorkday,
  isBankHoliday,
  isWeekend,
  monthBounds,
  monthKey,
  monthKeyFromISO,
  monthParts,
  monthStartISO,
  reportingYear,
  reportingYearBounds,
  todayISO,
  validMonthKey,
} from "./date";
import type { AttendanceProfile, AttendanceState, DayKind, LeaveBreakdown, LeaveShortfallWarning, Metrics, MonthRef } from "./types";

export const emptyMetrics = (): Metrics => ({
  workingDays: 0,
  office: 0,
  wfh: 0,
  leave: 0,
  sickness: 0,
  nwd: 0,
  unassigned: 0,
  tracked: 0,
});

export function defaultState(): AttendanceState {
  const profile = defaultProfile();
  return { activeProfileId: profile.id, profiles: [profile] };
}

export function defaultProfile(): AttendanceProfile {
  return {
    id: `p-${Date.now()}`,
    name: "Default profile",
    createdAtISO: todayISO(),
    settings: {
      targetPct: 40,
      leaveAllowances: { [String(new Date().getFullYear())]: 25 },
      recordingStartMonth: currentMonthKey(),
      yearStartMonth: 1,
    },
    officeMarks: [],
    leaveMarks: [],
    wfhMarks: [],
    sicknessMarks: [],
    nwdMarks: [],
    lockedMonths: [],
  };
}

export function normalizeState(state: AttendanceState | null | undefined): AttendanceState {
  if (!state?.profiles?.length) return defaultState();
  const profiles = state.profiles.map(normalizeProfile);
  const activeProfileId = profiles.some((profile) => profile.id === state.activeProfileId)
    ? state.activeProfileId
    : profiles[0].id;
  return { activeProfileId, profiles };
}

export function normalizeProfile(profile: AttendanceProfile): AttendanceProfile {
  const settings = profile.settings ?? { targetPct: 40, leaveAllowances: {}, yearStartMonth: 1 };
  const unique = (values?: string[]) => Array.from(new Set(values ?? [])).sort();
  return {
    id: profile.id || `p-${Date.now()}`,
    name: profile.name || "Default profile",
    createdAtISO: profile.createdAtISO ?? todayISO(),
    settings: {
      targetPct: Number.isFinite(settings.targetPct) ? settings.targetPct : 40,
      leaveAllowances: settings.leaveAllowances ?? {},
      recordingStartMonth: validMonthKey(settings.recordingStartMonth) ?? currentMonthKey(),
      yearStartMonth: settings.yearStartMonth ?? 1,
    },
    officeMarks: unique(profile.officeMarks),
    leaveMarks: unique(profile.leaveMarks),
    wfhMarks: unique(profile.wfhMarks),
    sicknessMarks: unique(profile.sicknessMarks),
    nwdMarks: unique(profile.nwdMarks),
    lockedMonths: unique(profile.lockedMonths),
  };
}

export function activeProfile(state: AttendanceState): AttendanceProfile {
  return state.profiles.find((profile) => profile.id === state.activeProfileId) ?? state.profiles[0];
}

export function updateActiveProfile(state: AttendanceState, updater: (profile: AttendanceProfile) => AttendanceProfile): AttendanceState {
  return normalizeState({
    ...state,
    profiles: state.profiles.map((profile) => (profile.id === state.activeProfileId ? updater(profile) : profile)),
  });
}

export function markIndex(profile: AttendanceProfile) {
  return {
    office: new Set(profile.officeMarks),
    leave: new Set(profile.leaveMarks),
    wfh: new Set(profile.wfhMarks),
    sickness: new Set(profile.sicknessMarks),
    nwd: new Set(profile.nwdMarks),
  };
}

export function kindForDate(profile: AttendanceProfile, date: string): DayKind {
  const marks = markIndex(profile);
  if (marks.office.has(date)) return "office";
  if (marks.leave.has(date)) return "leave";
  if (marks.sickness.has(date)) return "sickness";
  if (marks.wfh.has(date)) return "wfh";
  if (isBankHoliday(date)) return "bankHoliday";
  if (isWeekend(date)) return "weekend";
  if (marks.nwd.has(date)) return "nwd";
  return "unassigned";
}

export function yearStartMonth(profile: AttendanceProfile): number {
  return Math.min(Math.max(profile.settings.yearStartMonth ?? 1, 1), 12);
}

export function allowanceForYear(profile: AttendanceProfile, year: number): number {
  return profile.settings.leaveAllowances[String(year)] ?? profile.settings.leaveAllowances[String(new Date().getFullYear())] ?? 25;
}

export function recordingStartMonthKey(profile: AttendanceProfile): string {
  const earliest = [
    ...profile.officeMarks,
    ...profile.leaveMarks,
    ...profile.wfhMarks,
    ...profile.sicknessMarks,
    ...profile.nwdMarks,
  ]
    .map(monthKeyFromISO)
    .filter(Boolean)
    .sort()[0];
  return validMonthKey(profile.settings.recordingStartMonth) ?? earliest ?? monthKeyFromISO(profile.createdAtISO ?? "") ?? currentMonthKey();
}

export function recordingStartParts(profile: AttendanceProfile): MonthRef {
  return monthParts(recordingStartMonthKey(profile)) ?? { year: new Date().getFullYear(), month: 1 };
}

export function isMonthLocked(profile: AttendanceProfile, key: string): boolean {
  return profile.lockedMonths.includes(key);
}

export function isBeforeRecordingStart(profile: AttendanceProfile, key: string): boolean {
  return key < recordingStartMonthKey(profile);
}

export function setMonthLocked(profile: AttendanceProfile, key: string, locked: boolean): AttendanceProfile {
  const lockedMonths = locked ? [...profile.lockedMonths, key] : profile.lockedMonths.filter((item) => item !== key);
  return normalizeProfile({ ...profile, lockedMonths });
}

export function setDateKind(profile: AttendanceProfile, date: string, kind: DayKind): AttendanceProfile {
  const key = date.slice(0, 7);
  if (isBeforeRecordingStart(profile, key)) throw new Error("This month is before your recording start date.");
  if (isMonthLocked(profile, key)) throw new Error("This month is locked. Unlock it before editing.");

  const next: AttendanceProfile = {
    ...profile,
    officeMarks: profile.officeMarks.filter((item) => item !== date),
    leaveMarks: profile.leaveMarks.filter((item) => item !== date),
    wfhMarks: profile.wfhMarks.filter((item) => item !== date),
    sicknessMarks: profile.sicknessMarks.filter((item) => item !== date),
    nwdMarks: profile.nwdMarks.filter((item) => item !== date),
  };

  if (kind === "unassigned" || kind === "weekend" || kind === "bankHoliday") return normalizeProfile(next);
  if (kind === "nwd") {
    if (isWeekend(date) || isBankHoliday(date)) throw new Error("NWD can only be set on a weekday.");
    return normalizeProfile({ ...next, nwdMarks: [...next.nwdMarks, date] });
  }
  const nwd = new Set(next.nwdMarks);
  if (!isAssignableWorkday(date, nwd)) throw new Error("That day is not an assignable working day.");
  if (kind === "leave") {
    const year = reportingYear(date, yearStartMonth(profile));
    const bounds = reportingYearBounds(year, yearStartMonth(profile));
    const used = next.leaveMarks.filter((item) => item >= bounds.startISO && item <= bounds.endISO).length;
    if (used >= allowanceForYear(profile, year)) throw new Error(`Leave allowance reached for ${year}.`);
    return normalizeProfile({ ...next, leaveMarks: [...next.leaveMarks, date] });
  }
  if (kind === "office") return normalizeProfile({ ...next, officeMarks: [...next.officeMarks, date] });
  if (kind === "wfh") return normalizeProfile({ ...next, wfhMarks: [...next.wfhMarks, date] });
  if (kind === "sickness") return normalizeProfile({ ...next, sicknessMarks: [...next.sicknessMarks, date] });
  return normalizeProfile(next);
}

export function leaveShortfall(profile: AttendanceProfile, dates: Set<string>): LeaveShortfallWarning | null {
  const marks = markIndex(profile);
  const effectiveNwd = new Set([...marks.nwd].filter((date) => !dates.has(date)));
  const requestedByYear = new Map<number, number>();
  for (const date of dates) {
    if (!isAssignableWorkday(date, effectiveNwd) || kindForDate(profile, date) === "leave") continue;
    const year = reportingYear(date, yearStartMonth(profile));
    requestedByYear.set(year, (requestedByYear.get(year) ?? 0) + 1);
  }
  for (const year of [...requestedByYear.keys()].sort()) {
    const bounds = reportingYearBounds(year, yearStartMonth(profile));
    const used = profile.leaveMarks.filter((date) => date >= bounds.startISO && date <= bounds.endISO).length;
    const remaining = Math.max(allowanceForYear(profile, year) - used, 0);
    const requested = requestedByYear.get(year) ?? 0;
    if (requested > remaining) return { year, remaining, requested, deficit: requested - remaining };
  }
  return null;
}

export function hasAssignedDays(profile: AttendanceProfile, dates: Set<string>): boolean {
  return [...dates].some((date) => ["office", "wfh", "leave", "sickness", "nwd"].includes(kindForDate(profile, date)));
}

export function metrics(profile: AttendanceProfile, start: string, end: string, respectingRecordingStart = true): Metrics {
  const result = emptyMetrics();
  const marks = markIndex(profile);
  const effectiveStart = respectingRecordingStart ? maxISO(start, monthStartISO(recordingStartMonthKey(profile))) : start;
  if (effectiveStart > end) return result;
  forEachDate(effectiveStart, end, (date) => {
    const working = isAssignableWorkday(date, marks.nwd);
    const kind = kindForDate(profile, date);
    if (kind === "office" && working) {
      result.workingDays += 1;
      result.office += 1;
      result.tracked += 1;
    } else if (kind === "wfh" && working) {
      result.workingDays += 1;
      result.wfh += 1;
      result.tracked += 1;
    } else if (kind === "leave" && working) {
      result.leave += 1;
    } else if (kind === "sickness" && working) {
      result.workingDays += 1;
      result.sickness += 1;
    } else if (kind === "nwd") {
      result.nwd += 1;
    } else if (kind === "unassigned" && working) {
      result.workingDays += 1;
      result.unassigned += 1;
    }
  });
  return result;
}

export function monthMetrics(profile: AttendanceProfile, month: MonthRef): Metrics {
  const bounds = monthBounds(month);
  return metrics(profile, bounds.startISO, bounds.endISO, true);
}

export function officeShare(metric: Metrics): number {
  return metric.workingDays > 0 ? (metric.office / metric.workingDays) * 100 : 0;
}

export function trackedShare(metric: Metrics): number | null {
  return metric.tracked > 0 ? (metric.office / metric.tracked) * 100 : null;
}

export function officeDaysNeededForTarget(metric: Metrics, target: number): number {
  if (target <= 0 || target >= 100 || metric.workingDays <= 0) return 0;
  return Math.max(0, Math.ceil((target / 100) * metric.workingDays - metric.office));
}

export function leaveBreakdown(profile: AttendanceProfile, year: number, today = todayISO()): LeaveBreakdown {
  const bounds = reportingYearBounds(year, yearStartMonth(profile));
  let taken = 0;
  let booked = 0;
  for (const date of profile.leaveMarks) {
    if (date < bounds.startISO || date > bounds.endISO) continue;
    if (date <= today) taken += 1;
    else booked += 1;
  }
  const allowance = allowanceForYear(profile, year);
  return { taken, booked, allowance, remaining: allowance - taken - booked };
}

export function assignableDatesForMonth(month: MonthRef): string[] {
  const bounds = monthBounds(month);
  const dates: string[] = [];
  forEachDate(bounds.startISO, bounds.endISO, (date) => {
    if (!isWeekend(date) && !isBankHoliday(date)) dates.push(date);
  });
  return dates;
}

export function maxISO(a: string, b: string): string {
  return a > b ? a : b;
}

export function monthKeyForRef(month: MonthRef): string {
  return monthKey(month.year, month.month);
}
