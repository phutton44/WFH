export type DayKind =
  | "office"
  | "wfh"
  | "leave"
  | "sickness"
  | "nwd"
  | "unassigned"
  | "weekend"
  | "bankHoliday";

export type AppTab = "record" | "month" | "year" | "settings";

export interface AuthUser {
  id: string;
  email: string;
}

export interface AuthResponse {
  token: string;
  user: AuthUser;
}

export interface StateResponse {
  payload: AttendanceState | null;
  updatedAt?: string;
}

export interface AttendanceState {
  activeProfileId: string;
  profiles: AttendanceProfile[];
}

export interface AttendanceProfile {
  id: string;
  name: string;
  createdAtISO?: string;
  settings: ProfileSettings;
  officeMarks: string[];
  leaveMarks: string[];
  wfhMarks: string[];
  sicknessMarks: string[];
  nwdMarks: string[];
  lockedMonths: string[];
}

export interface ProfileSettings {
  targetPct: number;
  leaveAllowances: Record<string, number>;
  recordingStartMonth?: string;
  yearStartMonth?: number;
}

export interface MonthRef {
  year: number;
  month: number;
}

export interface CalendarDay {
  id: string;
  day: number;
  iso: string | null;
}

export interface Metrics {
  workingDays: number;
  office: number;
  wfh: number;
  leave: number;
  sickness: number;
  nwd: number;
  unassigned: number;
  tracked: number;
}

export interface LeaveBreakdown {
  taken: number;
  booked: number;
  allowance: number;
  remaining: number;
}

export interface LeaveShortfallWarning {
  year: number;
  remaining: number;
  requested: number;
  deficit: number;
}
