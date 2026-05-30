import bankHolidayData from "../../../bank-holidays-england-wales.json";
import type { CalendarDay, MonthRef } from "./types";

export const monthNames = [
  "January",
  "February",
  "March",
  "April",
  "May",
  "June",
  "July",
  "August",
  "September",
  "October",
  "November",
  "December",
];

const holidayMap = bankHolidayData as Record<string, string[]>;
const bankHolidays = new Set(Object.values(holidayMap).flat());

export function todayParts(): { year: number; month: number; day: number } {
  const formatter = new Intl.DateTimeFormat("en-GB", {
    timeZone: "Europe/London",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  });
  const parts = Object.fromEntries(formatter.formatToParts(new Date()).map((part) => [part.type, part.value]));
  return {
    year: Number(parts.year),
    month: Number(parts.month),
    day: Number(parts.day),
  };
}

export function todayISO(): string {
  const parts = todayParts();
  return iso(parts.year, parts.month, parts.day);
}

export function currentMonth(): MonthRef {
  const parts = todayParts();
  return { year: parts.year, month: parts.month };
}

export function iso(year: number, month: number, day: number): string {
  return `${String(year).padStart(4, "0")}-${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
}

export function monthKey(year: number, month: number): string {
  return `${String(year).padStart(4, "0")}-${String(clampMonth(month)).padStart(2, "0")}`;
}

export function currentMonthKey(): string {
  const parts = todayParts();
  return monthKey(parts.year, parts.month);
}

export function clampMonth(month: number): number {
  return Math.min(Math.max(Math.trunc(month || 1), 1), 12);
}

export function validMonthKey(key?: string | null): string | null {
  if (!key) return null;
  const parts = monthParts(key);
  return parts ? monthKey(parts.year, parts.month) : null;
}

export function monthParts(key: string): MonthRef | null {
  const match = /^(\d{4})-(\d{2})$/.exec(key);
  if (!match) return null;
  const month = Number(match[2]);
  if (month < 1 || month > 12) return null;
  return { year: Number(match[1]), month };
}

export function monthKeyFromISO(value: string): string | null {
  return validMonthKey(value.slice(0, 7));
}

export function monthStartISO(key: string): string {
  return `${validMonthKey(key) ?? currentMonthKey()}-01`;
}

export function monthTitle(month: MonthRef): string {
  return `${monthNames[month.month - 1]} ${month.year}`;
}

export function monthBounds(month: MonthRef): { startISO: string; endISO: string } {
  return {
    startISO: iso(month.year, month.month, 1),
    endISO: iso(month.year, month.month, daysInMonth(month.year, month.month)),
  };
}

export function daysInMonth(year: number, month: number): number {
  return new Date(Date.UTC(year, month, 0)).getUTCDate();
}

export function parseISODate(value: string): Date | null {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!match) return null;
  return new Date(Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3])));
}

export function mondayLeadSlots(year: number, month: number): number {
  const weekday = new Date(Date.UTC(year, month - 1, 1)).getUTCDay();
  return (weekday + 6) % 7;
}

export function gridDays(month: MonthRef): CalendarDay[] {
  const lead = mondayLeadSlots(month.year, month.month);
  const days = daysInMonth(month.year, month.month);
  return [
    ...Array.from({ length: lead }, (_, slot) => ({ id: `empty-${slot}`, day: 0, iso: null })),
    ...Array.from({ length: days }, (_, index) => {
      const day = index + 1;
      const date = iso(month.year, month.month, day);
      return { id: date, day, iso: date };
    }),
  ];
}

export function shiftMonth(month: MonthRef, offset: number): MonthRef {
  const date = new Date(Date.UTC(month.year, month.month - 1 + offset, 1));
  return { year: date.getUTCFullYear(), month: date.getUTCMonth() + 1 };
}

export function isWeekend(value: string): boolean {
  const date = parseISODate(value);
  if (!date) return false;
  const weekday = date.getUTCDay();
  return weekday === 0 || weekday === 6;
}

export function isBankHoliday(value: string): boolean {
  return bankHolidays.has(value) && !isWeekend(value);
}

export function isAssignableWorkday(value: string, nwd: Set<string>): boolean {
  return !isWeekend(value) && !isBankHoliday(value) && !nwd.has(value);
}

export function forEachDate(start: string, end: string, body: (isoDate: string) => void): void {
  const cursor = parseISODate(start);
  const final = parseISODate(end);
  if (!cursor || !final) return;
  while (cursor <= final) {
    body(iso(cursor.getUTCFullYear(), cursor.getUTCMonth() + 1, cursor.getUTCDate()));
    cursor.setUTCDate(cursor.getUTCDate() + 1);
  }
}

export function reportingYear(value: string, startMonth: number): number {
  const month = clampMonth(startMonth);
  const parts = value.split("-").map(Number);
  return parts[1] < month ? parts[0] - 1 : parts[0];
}

export function reportingYearBounds(year: number, startMonth: number): { startISO: string; endISO: string } {
  const month = clampMonth(startMonth);
  const endYear = month === 1 ? year : year + 1;
  const endMonth = month === 1 ? 12 : month - 1;
  return {
    startISO: iso(year, month, 1),
    endISO: iso(endYear, endMonth, daysInMonth(endYear, endMonth)),
  };
}

export function reportingYearMonths(year: number, startMonth: number): MonthRef[] {
  const start = clampMonth(startMonth);
  return Array.from({ length: 12 }, (_, offset) => shiftMonth({ year, month: start }, offset));
}

export function reportingQuarter(value: string, startMonth: number): number {
  const parts = value.split("-").map(Number);
  const offset = (parts[1] - clampMonth(startMonth) + 12) % 12;
  return Math.floor(offset / 3) + 1;
}

export function isoWeekNumber(value: string): number {
  const date = parseISODate(value);
  if (!date) return 0;
  const target = new Date(date.valueOf());
  const dayNr = (date.getUTCDay() + 6) % 7;
  target.setUTCDate(target.getUTCDate() - dayNr + 3);
  const firstThursday = new Date(Date.UTC(target.getUTCFullYear(), 0, 4));
  const firstDayNr = (firstThursday.getUTCDay() + 6) % 7;
  firstThursday.setUTCDate(firstThursday.getUTCDate() - firstDayNr + 3);
  return 1 + Math.round((target.valueOf() - firstThursday.valueOf()) / 604800000);
}

export function readableDate(value: string): string {
  const parts = value.split("-").map(Number);
  if (parts.length !== 3) return value;
  return `${parts[2]} ${monthNames[parts[1] - 1]} ${parts[0]}`;
}
