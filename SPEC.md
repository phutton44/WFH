# In-office attendance tracker — product specification (single document)

## 1. Purpose

A **local-first** web application for **multiple user profiles**. Each user logs **days physically in the office**, **WFH**, and **annual leave**. Metrics are based on **counts of working weekdays** in a **calendar month** and **calendar year (1 January – 31 December)**. The app accounts for **England & Wales bank holidays** and **annual leave** the user sets and logs. It provides **month calendars**, a **dashboard** with month and year summary cards, a **KPI strip** (YTD office/WFH and annual-leave visuals), and a **banner** for leave vs allowance. **No financial year** is used anywhere: all years are **January–December**.

---

## 2. Time periods

| Period | Definition |
|--------|------------|
| **Calendar year** | **1 January – 31 December**. Used for leave allowance, leave booked vs remaining (banner and year card), and validation when adding leave. |
| **Attendance summaries (dashboard cards)** | **Month card:** the **full** calendar month shown in the calendar (not tied to “today”). **Year card:** always the **current** calendar year’s **year-to-date** through **today** (Europe/London), aligned with the KPI strip; leave vs allowance still uses the **full** current calendar year. |
| **Financial year** | **Not used** — removed from product and UI. |

---

## 3. Definitions

**Weekday**  
Monday–Friday (default; configurable working week).

**Bank holiday (non-working)**  
England & Wales public holidays for the relevant calendar year. Preloaded (e.g. JSON); **weekday bank holidays** are excluded from **working weekdays** for default-WFH logic. Weekends are non-working.

**Annual leave**  
Days the user marks as **leave** in the app. User sets an **allowance in whole days** per **calendar year**.

**Unassigned**  
A **working weekday** that is not a weekday bank holiday and has **no** explicit **office**, **WFH**, or **leave** mark. Does **not** count toward **tracked** or WFH totals until the user assigns a label.

**WFH (explicit)**  
User must explicitly mark **WFH** for a day (bulk bar or future controls). There is **no** implicit default WFH.

**Tracked days (office + explicit WFH)**  
Days in the range that count as **in office** or **explicit WFH**. Denominator for **office attendance %**: `in office ÷ tracked × 100`.

**Office days (numerator)**  
Calendar days in the range where the user logged **in office** for that day.

**v1 rule — full day only**  
Any **in-office** mark for a day counts as **1 office day** for that date (no half-day office in v1 unless extended later).

---

## 4. Percentages and targets

**Monthly card (dashboard)**  
Uses the **full viewed calendar month** (first through last day of that month on screen). Office attendance = `office ÷ tracked` over that range (see §3). Unassigned working weekdays in that month are **not** tracked until labeled.

**Year card (dashboard)**  
Always the **current** calendar year (same as “today”’s year): **office / WFH / tracked / %** from **1 January through today** only. **Leave** on the card uses the **full** **1 Jan–31 Dec** of that year for **allowance vs booked** (including future booked leave). Does **not** switch when you navigate the calendar to another year’s month—the month card reflects the viewed month; the year card stays live YTD.

**KPI strip and banner**  
**Year-to-date** from **1 January** of the **current** calendar year through **today** for office, WFH, and related KPIs; leave booked vs allowance uses the **full** current calendar year for booked days.

**Targets**  
- Default **target: 40%** (office share of tracked).  
- Configurable per profile (target % in settings).

---

## 5. Annual leave

**Allowance**  
User enters **total leave days** for each **calendar year** (Jan–Dec).

**Logging**  
User marks specific dates as **annual leave** on the calendar (and can choose **WFH** or **in office** explicitly where relevant).

**Effect**  
- Leave marks update **month** and **year** views, **dashboard**, **KPI/banner**, and **remaining** allowance.  
- **Capacity check** when adding leave uses **used leave in that calendar year** vs allowance (full Jan–Dec).

**Rules**  
- **Bank holiday**: validation rules in code apply when marking leave on those dates.  
- **Weekend**: not a working day; marking behaviour follows implementation.  
- **Conflict**: user **must not** mark the same day as incompatible states; **block** with a message where implemented.

---

## 6. Bank holidays

- **Jurisdiction**: **England & Wales** only.  
- Loaded per calendar year; **weekday** bank holidays are excluded from normal working-day counts where implemented.  
- Shown clearly on the calendar.

---

## 7. Logging and editing

- User selects day(s) on the calendar and applies **in office**, **explicit WFH**, **annual leave**, or **Unassigned** (clear explicit marks) via the bulk actions bar; can change past days.  
- **Day-level** logging for v1.  
- Optional later: **last updated** timestamp per day.

---

## 8. User interface

### 8.1 Month calendar (primary view)

- One **calendar month** per view; **previous / next** month navigation clears multi-selection.  
- **Day cell** shows state: **office**, **WFH** (explicit only), **leave**, **unassigned** (working weekday with no label yet), **bank holiday**, **weekend**. Leave uses a **bright yellow** accent on dark backgrounds; **unassigned** uses a muted dashed style.  
- **Month header**: month name and **calendar year** only (no FY label).  
- **Selection:** **click** toggles a day in/out of the selection (one or many). **Shift+click** selects every **in-month** date between the anchor and the clicked day.  
- **Applying labels:** bulk bar — **In office**, **WFH**, **Annual leave**, **Unassigned**, and **Clear selection** (clears selection highlight only). **Best-effort** per day when applying; summary feedback if some days fail.

### 8.2 Dashboard (per user)

Two **summary cards** (plus context line explaining date caps):

**A. Viewed month**  
- **Tracked**, **office**, **WFH** (explicit), **unassigned** count, **leave**, **office attendance %**, **target**, **status** (ahead / on track / behind), over the **full** calendar month on screen.

**B. Current calendar year (YTD)**  
- **Office / WFH / tracked / %** from **1 Jan through today** (always the live calendar year, not the year of the month you are viewing).  
- **Leave** count and **allowance / remaining** for the **full** Jan–Dec of that same calendar year.  
- **Status** vs same target %.

**KPI strip**  
Two panels in a **responsive grid** (side by side from ~768px): shared **donut column width** and matching **footer** height under the Office donut (spacer) vs the leave allowance line so stat columns line up. **Narrow view:** segmented **tabs** (Office / WFH · Annual leave) show one panel at a time; `resize` restores two-up layout. **Office vs WFH (YTD)** — donut, subtitle **Jan 1–today**, centre **office share · YTD**; empty when **tracked** is zero. **Annual leave** — allowance donut, **Number of days allowance** under the chart, stat rows; over-allowance and zero-allowance states unchanged. Updates on `renderAll`.

**Banner**  
**Calendar year** {year}: leave booked vs allowance, office/WFH YTD, **leave days YTD**, office attendance %.

### 8.3 Settings

- Profile name (add profile via prompt).  
- Leave **allowance** for the **current** calendar year.  
- Working week (default Mon–Fri).  
- Target % (default 40%).

### 8.4 Profiles

- **Multi-user**: **profile switcher** with **created** date to the **left** of the picker (London calendar date).  
- **Data isolated per profile** in storage.  
- **Signed-in users**: full app state is synced to **PostgreSQL** (`public.app_state` via the deployed **REST API**); the browser also keeps a **localStorage** copy for fast load and resilience. **Without** `config.js` pointing at the API, the auth gate explains setup.

---

## 9. Ahead / on track / behind

Uses the **same target %** for month and year cards.

Implementation bands:

- **Behind**: actual % **< target**  
- **On track**: actual % within **±0.5** percentage points of target  
- **Ahead**: actual % **> target**

---

## 10. Data (high level)

All profiles and marks for a signed-in user are stored as **one JSON document** in Postgres (`app_state.payload`); the app normalizes that into per-profile structures in memory. Access is enforced in the **API** (JWT identifies `user_id` for reads/writes).

Per profile:

- **Settings**: working week, target %, yearly leave allowances by calendar year.  
- **`createdAtISO`**: calendar date the profile was created (London); legacy profiles without it infer from profile **id** timestamp when possible.  
- **Office marks**, **leave marks**, **WFH marks** (dates, unique per day where applicable).  
- **Bank holidays**: cached list by year (England & Wales).

Legacy **`fyStartMonth`** in saved JSON is **stripped on load/save**; it is not part of the product model.

---

## 11. Non-goals (v1)

- SSO, manager dashboards, HR system integration, GPS proof.  
- **Financial year** labels, boundaries, or metrics.  
- Half-day office / half-day leave (unless added in a later version).

---

## 12. Technical notes (v1)

- **Storage**: browser **localStorage** (key `attendanceTracker.v1`) as cache; **PostgreSQL** table **`public.app_state`** (`user_id`, **`payload` JSONB**, `updated_at`) for the canonical copy per signed-in user. **`public.users`** holds email + password hash for the API. The **Node server** (`server/`) issues **JWTs** and only reads/writes `app_state` for the authenticated user. **Railway** (or any host) can run Postgres + the API.  
- **Timezone**: **Europe/London** for “today” and month boundaries.  
- **Export** (optional v1.1): CSV for appraisal backup.

---

## 13. Summary table

| Topic | Decision |
|--------|----------|
| Year for leave & metrics | **1 Jan – 31 Dec** (calendar year only) |
| Financial year | **Not used** |
| Office attendance % | **In office ÷ (in office + explicit WFH)** over the summary range |
| Summary ranges | **Month:** full viewed month. **Year card & KPI:** office/explicit WFH/tracked **YTD through today**; leave vs allowance **full current calendar year** |
| Unassigned weekday | No default WFH; counts as **Unassigned** until labeled |
| Target | **40%** default; per profile in settings |
| Leave | Allowance per calendar year; logged days update views |
| Users | Multiple local profiles |
| Hosting / DB | Static front-end; **Railway PostgreSQL** + **Node REST API** for signed-in sync |

This is the **single master spec** for implementation.
