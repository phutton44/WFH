const STORAGE_KEY = "attendanceTracker.v1";
const HOLIDAY_FILE = "./bank-holidays-england-wales.json";
const LONDON_TZ = "Europe/London";
const WEEKDAY_LABELS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
const MONTH_NAMES = [
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

const CALENDAR_YEAR_PICKER_MIN = 2027;
const CALENDAR_YEAR_PICKER_MAX = 2035;

const monthTitle = document.getElementById("month-title");
const calendarGrid = document.getElementById("calendar-grid");
const weekdayRow = document.getElementById("weekday-row");
const dashboardCards = document.getElementById("dashboard-cards");
const kpiStrip = document.getElementById("kpi-strip");
const profileSelect = document.getElementById("profile-select");
const addProfileButton = document.getElementById("add-profile-button");
const prevMonthButton = document.getElementById("prev-month");
const nextMonthButton = document.getElementById("next-month");
const settingsForm = document.getElementById("settings-form");
const targetInput = document.getElementById("target-input");
const leaveAllowanceInput = document.getElementById("leave-allowance-input");
const settingsMessage = document.getElementById("settings-message");
const calendarBulkBar = document.getElementById("calendar-bulk-bar");
const profileCreatedEl = document.getElementById("profile-created");
const calendarYearSelect = document.getElementById("calendar-year-select");

let holidaysByYear = {};
let state = null;
let currentView = getTodayYearMonth();
let selectedDate = getLondonTodayISO();
let selectedDays = new Set();
let selectionAnchorISO = null;
/** Sorted ISO dates from last "Clear selection", for restore toggle. */
let selectionUndoBuffer = null;
let bulkFeedbackMessage = "";
let kpiPanelsPageIndex = 0;

let appBootstrapped = false;
let staticEventsBound = false;
let cloudSaveTimer = null;

async function bootstrap() {
  holidaysByYear = await loadBankHolidays();
  setupStaticInputs();
  attachEvents();
  renderAll();
}

function setupStaticInputs() {
  if (weekdayRow.children.length > 0) {
    return;
  }
  WEEKDAY_LABELS.forEach((label) => {
    const el = document.createElement("div");
    el.className = "weekday";
    el.textContent = label;
    weekdayRow.append(el);
  });
}

function attachEvents() {
  if (staticEventsBound) {
    return;
  }
  staticEventsBound = true;

  prevMonthButton.addEventListener("click", () => {
    currentView = shiftMonth(currentView.year, currentView.month, -1);
    clearCalendarSelection();
    renderAll();
  });

  nextMonthButton.addEventListener("click", () => {
    currentView = shiftMonth(currentView.year, currentView.month, 1);
    clearCalendarSelection();
    renderAll();
  });

  if (calendarYearSelect) {
    calendarYearSelect.addEventListener("change", () => {
      const nextYear = Number(calendarYearSelect.value);
      if (!Number.isFinite(nextYear)) {
        return;
      }
      currentView = { year: nextYear, month: currentView.month };
      clearCalendarSelection();
      bulkFeedbackMessage = "";
      renderAll();
    });
  }

  const calendarPanel = document.querySelector(".calendar-panel");
  if (kpiStrip) {
    kpiStrip.addEventListener("click", (event) => {
      const tab = event.target.closest(".kpi-panels-tab");
      if (!tab) {
        return;
      }
      const page = Number(tab.dataset.kpiPage);
      if (page !== 0 && page !== 1 && page !== 2) {
        return;
      }
      kpiPanelsPageIndex = page;
      syncKpiPanelsNav();
    });
    window.addEventListener("resize", () => {
      syncKpiPanelsNav();
    });
  }

  if (calendarPanel) {
    calendarPanel.addEventListener("click", (event) => {
      const applyBtn = event.target.closest("[data-bulk-apply]");
      if (applyBtn) {
        event.preventDefault();
        const nextType = applyBtn.getAttribute("data-bulk-apply");
        bulkApplySelectedDays(nextType);
        return;
      }
      const restoreBtn = event.target.closest("[data-bulk-restore-selection]");
      if (restoreBtn) {
        event.preventDefault();
        if (selectionUndoBuffer?.length) {
          selectedDays = new Set(selectionUndoBuffer);
          selectionUndoBuffer = null;
          const sorted = [...selectedDays].sort();
          selectionAnchorISO = sorted.length ? sorted[sorted.length - 1] : null;
          bulkFeedbackMessage = "";
          renderAll();
        }
        return;
      }
      const clearSelBtn = event.target.closest("[data-bulk-clear-selection]");
      if (clearSelBtn) {
        event.preventDefault();
        bulkFeedbackMessage = "";
        if (selectedDays.size > 0) {
          selectionUndoBuffer = [...selectedDays].sort();
          clearCalendarSelection({ discardUndo: false });
          renderAll();
        }
        return;
      }
    });
  }

  addProfileButton.addEventListener("click", () => {
    const name = window.prompt("Profile name:");
    if (!name || !name.trim()) {
      return;
    }
    const profile = createDefaultProfile(name.trim());
    state.profiles.push(profile);
    state.activeProfileId = profile.id;
    clearCalendarSelection();
    bulkFeedbackMessage = "";
    saveState();
    renderAll();
  });

  profileSelect.addEventListener("change", (event) => {
    state.activeProfileId = event.target.value;
    clearCalendarSelection();
    bulkFeedbackMessage = "";
    saveState();
    renderAll();
  });

  settingsForm.addEventListener("submit", (event) => {
    event.preventDefault();
    const profile = getActiveProfile();
    const target = Number(targetInput.value);
    const allowance = Number(leaveAllowanceInput.value);

    profile.settings.targetPct = Number.isFinite(target) ? target : 40;
    profile.settings.leaveAllowances[String(currentView.year)] = Number.isFinite(allowance)
      ? Math.max(0, Math.floor(allowance))
      : 0;

    saveState();
    settingsMessage.textContent = "Settings saved.";
    renderAll();
  });
}

function renderAll() {
  renderProfileSelect();
  renderProfileCreated();
  renderKpiStrip();
  renderDashboard();
  renderCalendar();
  renderCalendarBulkBar();
  renderSettings();
}

function clearCalendarSelection({ discardUndo = true } = {}) {
  selectedDays.clear();
  selectionAnchorISO = null;
  if (discardUndo) {
    selectionUndoBuffer = null;
  }
}

function bulkApplySelectedDays(nextType) {
  const profile = getActiveProfile();
  const dates = [...selectedDays].sort();
  if (!dates.length || !nextType) {
    return;
  }
  let okCount = 0;
  const errors = [];
  for (const iso of dates) {
    const result = applyDayType(profile, iso, nextType);
    if (result.ok) {
      okCount += 1;
    } else if (result.message) {
      errors.push(result.message);
    }
  }
  if (okCount > 0) {
    saveState();
  }
  const uniqErr = [...new Set(errors)];
  bulkFeedbackMessage =
    uniqErr.length > 0
      ? `${okCount} updated — ${uniqErr.slice(0, 2).join("; ")}${uniqErr.length > 2 ? "…" : ""}`
      : `${okCount} day(s) updated.`;
  clearCalendarSelection();
  renderAll();
}

function renderCalendarBulkBar() {
  if (!calendarBulkBar) {
    return;
  }
  const n = selectedDays.size;
  const hasUndo = Array.isArray(selectionUndoBuffer) && selectionUndoBuffer.length > 0;
  const showBar = n > 0 || Boolean(bulkFeedbackMessage) || hasUndo;
  calendarBulkBar.hidden = !showBar;

  const feedbackHtml = bulkFeedbackMessage
    ? `<p class="calendar-bulk-feedback muted">${bulkFeedbackMessage}</p>`
    : "";

  if (n === 0 && !hasUndo) {
    calendarBulkBar.innerHTML = feedbackHtml;
    return;
  }

  if (n === 0 && hasUndo) {
    calendarBulkBar.innerHTML = `
    <div class="calendar-bulk-inner">
      <span class="calendar-bulk-count muted">Selection cleared</span>
      <div class="calendar-bulk-actions">
        <button type="button" class="btn-bulk btn-bulk-restore" data-bulk-restore-selection>Restore selection</button>
      </div>
    </div>
    ${feedbackHtml}`;
    return;
  }

  calendarBulkBar.innerHTML = `
    <div class="calendar-bulk-inner">
      <span class="calendar-bulk-count">${n} day${n === 1 ? "" : "s"} selected</span>
      <div class="calendar-bulk-actions">
        <button type="button" class="btn-bulk btn-bulk-office" data-bulk-apply="office">In office</button>
        <button type="button" class="btn-bulk btn-bulk-wfh" data-bulk-apply="wfh">WFH</button>
        <button type="button" class="btn-bulk btn-bulk-leave" data-bulk-apply="leave">Annual leave</button>
        <button type="button" class="btn-bulk btn-bulk-sickness" data-bulk-apply="sickness">Sickness</button>
        <button type="button" class="btn-bulk btn-bulk-nwd" data-bulk-apply="nwd">NWD</button>
        <button type="button" class="btn-bulk btn-bulk-clear" data-bulk-clear-selection>Clear selection</button>
      </div>
    </div>
    ${feedbackHtml}`;
}

function renderProfileSelect() {
  profileSelect.innerHTML = "";
  state.profiles.forEach((profile) => {
    const option = document.createElement("option");
    option.value = profile.id;
    option.textContent = profile.name;
    option.selected = profile.id === state.activeProfileId;
    profileSelect.append(option);
  });
}

function renderProfileCreated() {
  if (!profileCreatedEl) {
    return;
  }
  const profile = getActiveProfile();
  ensureProfileCreatedAt(profile);
  profileCreatedEl.textContent = `Created ${formatFriendlyDate(profile.createdAtISO)}`;
}

/**
 * KPI + year-card metrics follow the calendar navigation year (currentView),
 * not only the live clock year. periodEnd caps office/WFH/leave-taken windows.
 */
function getCalendarYearMetricsContext() {
  const today = getLondonToday();
  const todayISO = toISO(today.year, today.month, today.day);
  const year = currentView.year;
  const month = currentView.month;
  const yearStart = toISO(year, 1, 1);
  const yearEnd = toISO(year, 12, 31);
  let periodEnd;
  if (year < today.year) {
    periodEnd = yearEnd;
  } else if (year > today.year) {
    periodEnd = minISO(toISO(year, month, daysInMonth(year, month)), yearEnd);
  } else {
    periodEnd = minISO(todayISO, yearEnd);
  }

  let mixPeriodCaption;
  if (year < today.year) {
    mixPeriodCaption = `Jan 1–Dec 31 ${year}`;
  } else if (year > today.year) {
    const [yy, mm, dd] = periodEnd.split("-").map(Number);
    mixPeriodCaption = `Jan 1–${dd} ${MONTH_NAMES[mm - 1]} ${yy}`;
  } else {
    mixPeriodCaption = "Jan 1–today";
  }

  return { year, yearStart, yearEnd, periodEnd, mixPeriodCaption, today, todayISO };
}

function renderDashboard() {
  const profile = getActiveProfile();
  const target = profile.settings.targetPct;
  const today = getLondonToday();
  const viewYear = currentView.year;
  const viewMonth = currentView.month;
  const viewedMonthRange = {
    start: toISO(viewYear, viewMonth, 1),
    end: toISO(viewYear, viewMonth, daysInMonth(viewYear, viewMonth)),
  };

  const yctx = getCalendarYearMetricsContext();
  const yearStart = yctx.yearStart;
  const periodEnd = yctx.periodEnd;
  const metricsYear = yctx.year;

  const monthTracked = countTrackedWorkingDays(profile, viewedMonthRange.start, viewedMonthRange.end);
  const monthOffice = countOfficeDays(profile, viewedMonthRange.start, viewedMonthRange.end);
  const monthWfh = countWfhDays(profile, viewedMonthRange.start, viewedMonthRange.end);
  const monthLeave = countLeaveDays(profile, viewedMonthRange.start, viewedMonthRange.end);
  const monthSickness = countSicknessDays(profile, viewedMonthRange.start, viewedMonthRange.end);
  const monthUnassigned = countUnassignedWorkingDays(profile, viewedMonthRange.start, viewedMonthRange.end);
  const monthNwd = countNwdDaysInRange(profile, viewedMonthRange.start, viewedMonthRange.end);
  const monthActual = toPercent(monthOffice, monthTracked);

  const monthTitleLabel = `${MONTH_NAMES[viewMonth - 1]} ${viewYear}`;

  const yearTracked = countTrackedWorkingDays(profile, yearStart, periodEnd);
  const yearOffice = countOfficeDays(profile, yearStart, periodEnd);
  const yearWfh = countWfhDays(profile, yearStart, periodEnd);
  const yearLeaveInWindow = countLeaveDays(profile, yearStart, periodEnd);
  const yearSickness = countSicknessDays(profile, yearStart, periodEnd);
  const yearNwd = countNwdDaysInRange(profile, yearStart, periodEnd);

  const yearCardTitle =
    metricsYear < today.year
      ? `${metricsYear} · Full calendar year`
      : metricsYear > today.year
        ? `${metricsYear} · Through ${MONTH_NAMES[viewMonth - 1]}`
        : `${metricsYear} · Year to date`;

  dashboardCards.innerHTML = "";
  dashboardCards.append(
    buildDataCard({
      title: monthTitleLabel,
      office: monthOffice,
      wfh: monthWfh,
      tracked: monthTracked,
      unassigned: monthUnassigned,
      leave: monthLeave,
      sickness: monthSickness,
      nwd: monthNwd,
      pct: monthActual,
      target,
      variant: "month",
    }),
  );
  dashboardCards.append(
    buildDataCard({
      title: yearCardTitle,
      office: yearOffice,
      wfh: yearWfh,
      tracked: yearTracked,
      leave: yearLeaveInWindow,
      sickness: yearSickness,
      nwd: yearNwd,
      variant: "year",
    }),
  );
}

function buildMonthDayListHtml(
  { tracked, office, wfh, unassigned, leave, sickness, nwd = 0 },
  rootClass = "card-month-summary",
  rowClass = "card-metric-row",
) {
  const rows = [
    ["Total working days", String(tracked)],
    ["In office", String(office)],
    ["WFH", String(wfh)],
    ["Annual leave", String(leave)],
    ["Sickness", String(sickness)],
    ["NWD", String(nwd)],
    ["Unassigned", String(unassigned)],
  ];
  return `<div class="${rootClass}">${rows
    .map(
      ([k, v]) =>
        `<div class="${rowClass}"><strong>${k}</strong><span>${v}</span></div>`,
    )
    .join("")}</div>`;
}

function buildKpiMonthPanelHtml(profile, viewYear, viewMonth) {
  const target = profile.settings.targetPct;
  const start = toISO(viewYear, viewMonth, 1);
  const end = toISO(viewYear, viewMonth, daysInMonth(viewYear, viewMonth));
  const monthTracked = countTrackedWorkingDays(profile, start, end);
  const monthOffice = countOfficeDays(profile, start, end);
  const monthWfh = countWfhDays(profile, start, end);
  const share = toPercent(monthOffice, monthTracked);
  const shareLabel = share.label;
  const monthStripStatus = getStatus(share.value, target);
  const officeBarPct =
    monthTracked > 0 ? (monthOffice / monthTracked) * 100 : 0;
  const wfhBarPct = monthTracked > 0 ? (monthWfh / monthTracked) * 100 : 0;

  const monthFooterHtml =
    monthTracked > 0
      ? `<div class="kpi-mix-footer">
      <div class="chart-row kpi-mix-chart-row">
        <div class="chart-label"><span>Office vs WFH (tracked)</span><span>${monthTracked} days</span></div>
        <div class="chart-bar" title="Green = office, teal = WFH">
          <div class="chart-seg-office" style="width:${officeBarPct}%"></div>
          <div class="chart-seg-wfh" style="width:${wfhBarPct}%"></div>
        </div>
      </div>
      <span class="status ${monthStripStatus.className} kpi-mix-status">${monthStripStatus.label}</span>
    </div>`
      : `<div class="kpi-mix-footer">
      <span class="status ${monthStripStatus.className} kpi-mix-status">${monthStripStatus.label}</span>
    </div>`;

  const officeMixPct =
    monthTracked > 0 ? (monthOffice / monthTracked) * 100 : 0;
  const wfhMixPct = monthTracked > 0 ? (monthWfh / monthTracked) * 100 : 0;
  const markSum = monthOffice + monthWfh;
  const officeTurn = markSum > 0 ? monthOffice / markSum : 0;
  const wfhTurn = markSum > 0 ? monthWfh / markSum : 0;

  const titleLabel = `${MONTH_NAMES[viewMonth - 1]} ${viewYear}`;
  const monthWorkingDays = countWorkingWeekdays(profile, start, end);

  if (monthTracked > 0) {
    return `<aside id="kpi-panel-month" class="kpi-mix-panel" aria-label="Office and WFH mix for ${titleLabel}">
      <div class="kpi-mix-head">
        <span class="kpi-mix-title">${titleLabel}</span>
        <span class="kpi-mix-sub muted">${viewYear} · calendar month · ${monthTracked} tracked · vs ${target.toFixed(1)}% target</span>
      </div>
      <div class="kpi-mix-body">
        <div class="kpi-mix-donut-wrap">
          <div class="kpi-mix-donut" style="--o-turn:${officeTurn};--w-turn:${wfhTurn}">
            <div class="kpi-mix-donut-hole">
              <span class="kpi-mix-donut-pct">${shareLabel}</span>
              <span class="kpi-mix-donut-cap muted">office share · month</span>
            </div>
          </div>
          <p class="kpi-chart-donut-foot" aria-hidden="true"></p>
        </div>
        <div class="kpi-mix-stats">
          <div class="kpi-mix-stat kpi-mix-stat--office">
            <span class="kpi-mix-stat-dot" aria-hidden="true"></span>
            <div class="kpi-mix-stat-text">
              <span class="kpi-mix-stat-val">${monthOffice}</span>
              <span class="kpi-mix-stat-lbl">Office days</span>
            </div>
            <span class="kpi-mix-stat-pct">${officeMixPct.toFixed(1)}%</span>
          </div>
          <div class="kpi-mix-stat kpi-mix-stat--wfh">
            <span class="kpi-mix-stat-dot" aria-hidden="true"></span>
            <div class="kpi-mix-stat-text">
              <span class="kpi-mix-stat-val">${monthWfh}</span>
              <span class="kpi-mix-stat-lbl">WFH days</span>
            </div>
            <span class="kpi-mix-stat-pct">${wfhMixPct.toFixed(1)}%</span>
          </div>
          <div class="kpi-mix-stat kpi-mix-stat--tracked-total">
            <span class="kpi-mix-stat-dot" aria-hidden="true"></span>
            <div class="kpi-mix-stat-text">
              <span class="kpi-mix-stat-val">${markSum}</span>
              <span class="kpi-mix-stat-lbl">Total working days</span>
            </div>
          </div>
        </div>
      </div>
      ${monthFooterHtml}
    </aside>`;
  }

  return `<aside id="kpi-panel-month" class="kpi-mix-panel kpi-mix-panel--empty" aria-label="Office and WFH mix for ${titleLabel}">
      <div class="kpi-mix-head">
        <span class="kpi-mix-title">${titleLabel}</span>
        <span class="kpi-mix-sub muted">${viewYear} · calendar month</span>
      </div>
      <p class="kpi-mix-empty muted">No tracked office or explicit WFH days in this month yet — assign days on the calendar to see the split.</p>
      <p class="kpi-month-total-working muted" aria-live="polite"><strong>${monthWorkingDays}</strong> total working days</p>
      ${monthFooterHtml}
    </aside>`;
}

function buildDataCard({
  title,
  subtitle = "",
  office,
  wfh,
  tracked,
  unassigned = 0,
  leave,
  sickness = 0,
  nwd = 0,
  pct = { value: null, label: "N/A" },
  target = 0,
  extraRows = [],
  variant = "year",
}) {
  const card = document.createElement("article");
  card.className = "card";

  const subtitleBlock = subtitle
    ? `<p class="muted" style="font-size:0.78rem;margin:0 0 0.6rem">${subtitle}</p>`
    : "";

  if (variant === "month") {
    const listHtml = buildMonthDayListHtml({
      tracked,
      office,
      wfh,
      unassigned,
      leave,
      sickness,
      nwd,
    });

    card.innerHTML = `
    <h3>${title}</h3>
    ${subtitleBlock}
    ${listHtml}
  `;
    return card;
  }

  const rowsHtml = [
    ["Total working days", String(tracked)],
    ["In office", String(office)],
    ["WFH", String(wfh)],
    ["Annual leave", String(leave)],
    ["Sickness", String(sickness)],
    ["NWD", String(nwd)],
    ...extraRows,
  ]
    .map(
      ([k, v]) =>
        `<div class="card-metric-row"><strong>${k}</strong><span>${v}</span></div>`,
    )
    .join("");

  card.innerHTML = `
    <h3>${title}</h3>
    ${subtitleBlock}
    ${rowsHtml}
  `;
  return card;
}

function syncKpiPanelsNav() {
  if (!kpiStrip) {
    return;
  }
  const panels = kpiStrip.querySelector(".kpi-panels");
  const tabs = kpiStrip.querySelectorAll(".kpi-panels-tab");
  const nav = kpiStrip.querySelector(".kpi-panels-nav");
  if (!panels || !tabs.length) {
    return;
  }
  const narrow = window.matchMedia("(max-width: 1100px)").matches;
  const idx = Math.min(2, Math.max(0, kpiPanelsPageIndex));
  kpiPanelsPageIndex = idx;
  panels.setAttribute("data-kpi-page", String(idx));
  if (nav) {
    nav.setAttribute("aria-hidden", narrow ? "false" : "true");
  }
  tabs.forEach((btn) => {
    const on = Number(btn.dataset.kpiPage) === idx;
    btn.setAttribute("aria-selected", String(on));
    btn.tabIndex = narrow ? (on ? 0 : -1) : 0;
  });
  const mix = document.getElementById("kpi-panel-mix");
  const leave = document.getElementById("kpi-panel-leave");
  const month = document.getElementById("kpi-panel-month");
  if (narrow) {
    if (month) {
      month.hidden = idx !== 0;
    }
    if (mix) {
      mix.hidden = idx !== 1;
    }
    if (leave) {
      leave.hidden = idx !== 2;
    }
  } else {
    if (mix) {
      mix.hidden = false;
    }
    if (leave) {
      leave.hidden = false;
    }
    if (month) {
      month.hidden = false;
    }
  }
}

function renderKpiStrip() {
  if (!kpiStrip) {
    return;
  }
  const profile = getActiveProfile();
  ensureProfileCreatedAt(profile);
  const yctx = getCalendarYearMetricsContext();
  const year = yctx.year;
  const yearStart = yctx.yearStart;
  const yearEnd = yctx.yearEnd;
  const periodEnd = yctx.periodEnd;
  const mixPeriodCaption = yctx.mixPeriodCaption;

  const office = countOfficeDays(profile, yearStart, periodEnd);
  const wfh = countWfhDays(profile, yearStart, periodEnd);
  const tracked = countTrackedWorkingDays(profile, yearStart, periodEnd);
  const leaveTakenThrough = countLeaveDays(profile, yearStart, periodEnd);
  const leaveBookedYear = countLeaveDays(profile, yearStart, yearEnd);
  const allowance = getAllowance(profile, year);
  const remaining = allowance - leaveBookedYear;
  const leaveFutureBooked = Math.max(0, leaveBookedYear - leaveTakenThrough);
  const leaveOverBy = leaveBookedYear > allowance ? leaveBookedYear - allowance : 0;

  const share = toPercent(office, tracked);
  const shareLabel = share.label;
  const mixStripStatus = getStatus(share.value, profile.settings.targetPct);
  const officeBarPct = tracked > 0 ? (office / tracked) * 100 : 0;
  const wfhBarPct = tracked > 0 ? (wfh / tracked) * 100 : 0;

  const mixFooterHtml =
    tracked > 0
      ? `<div class="kpi-mix-footer">
      <div class="chart-row kpi-mix-chart-row">
        <div class="chart-label"><span>Office vs WFH (tracked)</span><span>${tracked} days</span></div>
        <div class="chart-bar" title="Green = office, teal = WFH">
          <div class="chart-seg-office" style="width:${officeBarPct}%"></div>
          <div class="chart-seg-wfh" style="width:${wfhBarPct}%"></div>
        </div>
      </div>
      <span class="status ${mixStripStatus.className} kpi-mix-status">${mixStripStatus.label}</span>
    </div>`
      : `<div class="kpi-mix-footer">
      <span class="status ${mixStripStatus.className} kpi-mix-status">${mixStripStatus.label}</span>
    </div>`;

  const officeMixPct = tracked > 0 ? (office / tracked) * 100 : 0;
  const wfhMixPct = tracked > 0 ? (wfh / tracked) * 100 : 0;
  const markSum = office + wfh;
  const officeTurn = markSum > 0 ? office / markSum : 0;
  const wfhTurn = markSum > 0 ? wfh / markSum : 0;

  const mixPanelHtml =
    tracked > 0
      ? `<aside id="kpi-panel-mix" class="kpi-mix-panel" aria-label="Office and WFH mix year to date">
      <div class="kpi-mix-head">
        <span class="kpi-mix-title">Office vs WFH (YTD)</span>
        <span class="kpi-mix-sub muted">${year} · ${mixPeriodCaption} · ${tracked} tracked days</span>
      </div>
      <div class="kpi-mix-body">
        <div class="kpi-mix-donut-wrap">
          <div class="kpi-mix-donut" style="--o-turn:${officeTurn};--w-turn:${wfhTurn}">
            <div class="kpi-mix-donut-hole">
              <span class="kpi-mix-donut-pct">${shareLabel}</span>
              <span class="kpi-mix-donut-cap muted">office share · YTD</span>
            </div>
          </div>
          <p class="kpi-chart-donut-foot" aria-hidden="true"></p>
        </div>
        <div class="kpi-mix-stats">
          <div class="kpi-mix-stat kpi-mix-stat--office">
            <span class="kpi-mix-stat-dot" aria-hidden="true"></span>
            <div class="kpi-mix-stat-text">
              <span class="kpi-mix-stat-val">${office}</span>
              <span class="kpi-mix-stat-lbl">Office days</span>
            </div>
            <span class="kpi-mix-stat-pct">${officeMixPct.toFixed(1)}%</span>
          </div>
          <div class="kpi-mix-stat kpi-mix-stat--wfh">
            <span class="kpi-mix-stat-dot" aria-hidden="true"></span>
            <div class="kpi-mix-stat-text">
              <span class="kpi-mix-stat-val">${wfh}</span>
              <span class="kpi-mix-stat-lbl">WFH days</span>
            </div>
            <span class="kpi-mix-stat-pct">${wfhMixPct.toFixed(1)}%</span>
          </div>
        </div>
      </div>
      ${mixFooterHtml}
    </aside>`
      : `<aside id="kpi-panel-mix" class="kpi-mix-panel kpi-mix-panel--empty" aria-label="Office and WFH mix year to date">
      <div class="kpi-mix-head">
        <span class="kpi-mix-title">Office vs WFH (YTD)</span>
        <span class="kpi-mix-sub muted">${year} · ${mixPeriodCaption}</span>
      </div>
      <p class="kpi-mix-empty muted">No tracked office or explicit WFH days yet — assign days on the calendar to see the split.</p>
      ${mixFooterHtml}
    </aside>`;

  let leavePanelHtml;
  if (allowance <= 0) {
    leavePanelHtml = `<aside id="kpi-panel-leave" class="kpi-leave-panel kpi-leave-panel--empty" aria-label="Annual leave allowance">
      <div class="kpi-leave-head">
        <span class="kpi-leave-title">Annual leave</span>
        <span class="kpi-leave-sub muted">${year} allowance</span>
      </div>
      <p class="kpi-leave-empty muted">Set a <span class="kpi-leave-empty-hl">days allowance</span> for ${year} in settings to see how taken, booked-ahead, and remaining pool days add up.</p>
    </aside>`;
  } else if (leaveOverBy > 0) {
    const booked = leaveBookedYear;
    const tTurn = booked > 0 ? leaveTakenThrough / booked : 0;
    const fTurn = booked > 0 ? leaveFutureBooked / booked : 0;
    leavePanelHtml = `<aside id="kpi-panel-leave" class="kpi-leave-panel kpi-leave-panel--over" aria-label="Annual leave allowance breakdown">
      <div class="kpi-leave-head">
        <span class="kpi-leave-title">Annual leave</span>
        <span class="kpi-leave-sub muted">${year} · ${allowance} day allowance · ${booked} booked</span>
      </div>
      <div class="kpi-leave-body">
        <div class="kpi-leave-donut-wrap">
          <div class="kpi-leave-donut kpi-leave-donut--over" style="--t-turn:${tTurn};--f-turn:${fTurn}">
            <div class="kpi-leave-donut-hole">
              <span class="kpi-leave-donut-pct kpi-leave-donut-pct--warn">${leaveOverBy}</span>
              <span class="kpi-leave-donut-cap muted">days over</span>
            </div>
          </div>
          <p class="kpi-leave-allowance-cap muted">Number of days allowance: ${allowance}</p>
        </div>
        <div class="kpi-leave-stats">
          <p class="kpi-leave-over-note">Booked leave exceeds this year’s allowance. Ring shows <span class="kpi-leave-over-note-em">taken</span> vs <span class="kpi-leave-over-note-em">booked ahead</span> among all booked days.</p>
          <div class="kpi-leave-stat kpi-leave-stat--taken">
            <span class="kpi-leave-stat-dot" aria-hidden="true"></span>
            <div class="kpi-leave-stat-text">
              <span class="kpi-leave-stat-val">${leaveTakenThrough}</span>
              <span class="kpi-leave-stat-lbl">Taken (YTD)</span>
              <span class="kpi-leave-stat-tag">Annual leave</span>
            </div>
          </div>
          <div class="kpi-leave-stat kpi-leave-stat--ahead">
            <span class="kpi-leave-stat-dot" aria-hidden="true"></span>
            <div class="kpi-leave-stat-text">
              <span class="kpi-leave-stat-val">${leaveFutureBooked}</span>
              <span class="kpi-leave-stat-lbl">Booked ahead</span>
              <span class="kpi-leave-stat-tag">Rest of year</span>
            </div>
          </div>
        </div>
      </div>
    </aside>`;
  } else {
    const tTurn = leaveTakenThrough / allowance;
    const fTurn = leaveFutureBooked / allowance;
    const vTurn = Math.max(0, remaining) / allowance;
    const centerVal = remaining;
    const centerCap = remaining === 1 ? "day left" : "days left";
    leavePanelHtml = `<aside id="kpi-panel-leave" class="kpi-leave-panel" aria-label="Annual leave allowance breakdown">
      <div class="kpi-leave-head">
        <span class="kpi-leave-title">Annual leave</span>
        <span class="kpi-leave-sub muted">${year} · ${allowance} day allowance · ${leaveBookedYear} booked</span>
      </div>
      <div class="kpi-leave-body">
        <div class="kpi-leave-donut-wrap">
          <div class="kpi-leave-donut kpi-leave-donut--split" style="--t-turn:${tTurn};--f-turn:${fTurn};--v-turn:${vTurn}">
            <div class="kpi-leave-donut-hole">
              <span class="kpi-leave-donut-pct">${centerVal}</span>
              <span class="kpi-leave-donut-cap muted">${centerCap}</span>
            </div>
          </div>
          <p class="kpi-leave-allowance-cap muted">Number of days allowance: ${allowance}</p>
        </div>
        <div class="kpi-leave-stats">
          <div class="kpi-leave-stat kpi-leave-stat--taken">
            <span class="kpi-leave-stat-dot" aria-hidden="true"></span>
            <div class="kpi-leave-stat-text">
              <span class="kpi-leave-stat-val">${leaveTakenThrough}</span>
              <span class="kpi-leave-stat-lbl">Taken (YTD)</span>
              <span class="kpi-leave-stat-tag">Annual leave</span>
            </div>
          </div>
          <div class="kpi-leave-stat kpi-leave-stat--ahead">
            <span class="kpi-leave-stat-dot" aria-hidden="true"></span>
            <div class="kpi-leave-stat-text">
              <span class="kpi-leave-stat-val">${leaveFutureBooked}</span>
              <span class="kpi-leave-stat-lbl">Booked ahead</span>
              <span class="kpi-leave-stat-tag">Still to take</span>
            </div>
          </div>
          <div class="kpi-leave-stat kpi-leave-stat--pool">
            <span class="kpi-leave-stat-dot" aria-hidden="true"></span>
            <div class="kpi-leave-stat-text">
              <span class="kpi-leave-stat-val">${remaining}</span>
              <span class="kpi-leave-stat-lbl">Unbooked pool</span>
              <span class="kpi-leave-stat-tag">In allowance</span>
            </div>
          </div>
        </div>
      </div>
    </aside>`;
  }

  const viewMonth = currentView.month;
  const monthPanelHtml = buildKpiMonthPanelHtml(profile, year, viewMonth);
  const monthTabLabel = `${MONTH_NAMES[viewMonth - 1].slice(0, 3)} ${year}`;

  kpiStrip.innerHTML = `
    <div class="kpi-panels-wrap">
      <div class="kpi-panels-nav" role="tablist" aria-label="Summary charts">
        <button type="button" class="kpi-panels-tab" role="tab" data-kpi-page="0" id="kpi-tab-month" aria-controls="kpi-panel-month" aria-selected="true">${monthTabLabel}</button>
        <button type="button" class="kpi-panels-tab" role="tab" data-kpi-page="1" id="kpi-tab-mix" aria-controls="kpi-panel-mix" aria-selected="false">Office / WFH</button>
        <button type="button" class="kpi-panels-tab" role="tab" data-kpi-page="2" id="kpi-tab-leave" aria-controls="kpi-panel-leave" aria-selected="false">Annual leave</button>
      </div>
      <div class="kpi-panels" data-kpi-page="0">
        ${monthPanelHtml}
        ${mixPanelHtml}
        ${leavePanelHtml}
      </div>
    </div>`;
  syncKpiPanelsNav();
}

function syncCalendarYearSelect() {
  if (!calendarYearSelect) {
    return;
  }
  const y = currentView.year;
  const yearSet = new Set();
  for (let yy = CALENDAR_YEAR_PICKER_MIN; yy <= CALENDAR_YEAR_PICKER_MAX; yy += 1) {
    yearSet.add(yy);
  }
  if (y < CALENDAR_YEAR_PICKER_MIN || y > CALENDAR_YEAR_PICKER_MAX) {
    yearSet.add(y);
  }
  const years = [...yearSet].sort((a, b) => a - b);
  calendarYearSelect.innerHTML = years
    .map(
      (yy) =>
        `<option value="${yy}"${yy === y ? " selected" : ""}>${yy}</option>`,
    )
    .join("");
}

function renderCalendar() {
  const profile = getActiveProfile();
  const { year, month } = currentView;
  monthTitle.textContent = `${MONTH_NAMES[month - 1]} ${year}`;

  const monthStartDay = dayOfWeek(year, month, 1);
  const totalDays = daysInMonth(year, month);
  const leadSlots = (monthStartDay + 6) % 7;
  const totalCells = Math.ceil((leadSlots + totalDays) / 7) * 7;
  const todayISO = getLondonTodayISO();

  calendarGrid.innerHTML = "";
  for (let slot = 0; slot < totalCells; slot += 1) {
    const dayNum = slot - leadSlots + 1;
    const inMonth = dayNum >= 1 && dayNum <= totalDays;
    const dayDate = inMonth ? toISO(year, month, dayNum) : null;
    const button = document.createElement("button");
    button.type = "button";
    button.className = "day";

    if (!inMonth) {
      button.classList.add("outside-month");
      button.disabled = true;
      calendarGrid.append(button);
      continue;
    }

    const stateForDay = describeDay(profile, dayDate);
    button.classList.add(stateForDay.cssClass);
    if (dayDate === selectedDate) {
      button.classList.add("active");
    }
    if (selectedDays.has(dayDate)) {
      button.classList.add("day--bulk-selected");
    }

    button.innerHTML = `
      <div class="day-number">${dayNum}${dayDate === todayISO ? " • today" : ""}</div>
      <div class="day-state">${stateForDay.label}</div>
    `;
    button.addEventListener("click", (event) => {
      const vy = currentView.year;
      const vm = currentView.month;
      bulkFeedbackMessage = "";
      selectionUndoBuffer = null;
      if (event.shiftKey) {
        const anchor = selectionAnchorISO || selectedDate || dayDate;
        clampDatesToMonth(vy, vm, anchor, dayDate).forEach((iso) => {
          selectedDays.add(iso);
        });
        selectionAnchorISO = anchor;
      } else {
        if (selectedDays.has(dayDate)) {
          selectedDays.delete(dayDate);
        } else {
          selectedDays.add(dayDate);
        }
        selectionAnchorISO = dayDate;
      }
      selectedDate = dayDate;
      renderAll();
    });
    calendarGrid.append(button);
  }
  syncCalendarYearSelect();
}

function renderSettings() {
  const profile = getActiveProfile();
  targetInput.value = String(profile.settings.targetPct);
  leaveAllowanceInput.value = String(getAllowance(profile, currentView.year));
}

function isPermanentWeekendIso(isoDate) {
  const w = isoToWeekday(isoDate);
  return w === 6 || w === 7;
}

function describeDay(profile, isoDate) {
  if (profile.officeMarks.includes(isoDate)) {
    return { label: "Office", cssClass: "office" };
  }
  if (profile.leaveMarks.includes(isoDate)) {
    return { label: "Leave", cssClass: "leave" };
  }
  if (profile.sicknessMarks.includes(isoDate)) {
    return { label: "Sickness", cssClass: "sickness" };
  }
  if (profile.wfhMarks.includes(isoDate)) {
    return { label: "WFH", cssClass: "wfh" };
  }
  if (isWeekdayBankHoliday(profile, isoDate)) {
    return { label: "Bank holiday", cssClass: "bank-holiday" };
  }
  if (isPermanentWeekendIso(isoDate)) {
    return { label: "Weekend", cssClass: "weekend" };
  }
  if (profile.nwdMarks.includes(isoDate)) {
    return { label: "NWD", cssClass: "nwd" };
  }
  return { label: "Unassigned", cssClass: "unassigned" };
}

function countTrackedWorkingDays(profile, startISO, endISO) {
  const tracked = new Set();
  for (const isoDate of listDates(startISO, endISO)) {
    if (!countsAsMetricsWorkingDay(profile, isoDate)) {
      continue;
    }
    if (profile.officeMarks.includes(isoDate) || isWfhDay(profile, isoDate)) {
      tracked.add(isoDate);
    }
  }
  return tracked.size;
}

function countOfficeDays(profile, startISO, endISO) {
  return profile.officeMarks.filter(
    (d) => d >= startISO && d <= endISO && countsAsMetricsWorkingDay(profile, d),
  ).length;
}

function countLeaveDays(profile, startISO, endISO) {
  return profile.leaveMarks.filter(
    (d) => d >= startISO && d <= endISO && countsAsMetricsWorkingDay(profile, d),
  ).length;
}

function countSicknessDays(profile, startISO, endISO) {
  return profile.sicknessMarks.filter(
    (d) => d >= startISO && d <= endISO && countsAsMetricsWorkingDay(profile, d),
  ).length;
}

function countWfhDays(profile, startISO, endISO) {
  return profile.wfhMarks.filter(
    (d) => d >= startISO && d <= endISO && countsAsMetricsWorkingDay(profile, d),
  ).length;
}

function countNwdDaysInRange(profile, startISO, endISO) {
  return profile.nwdMarks.filter((d) => d >= startISO && d <= endISO).length;
}

function isWeekdayBankHoliday(profile, isoDate) {
  const year = isoDate.slice(0, 4);
  const list = holidaysByYear[year] || [];
  if (!list.includes(isoDate)) {
    return false;
  }
  if (isPermanentWeekendIso(isoDate)) {
    return false;
  }
  return true;
}

/** Mon–Fri (ISO weekday 1–5). Sat/Sun are never metric days. */
function isWeekdayMonFriIso(isoDate) {
  const weekday = isoToWeekday(isoDate);
  return weekday >= 1 && weekday <= 5;
}

function countsAsMetricsWorkingDay(profile, isoDate) {
  if (isPermanentWeekendIso(isoDate) || !isWeekdayMonFriIso(isoDate)) {
    return false;
  }
  if (profile.nwdMarks.includes(isoDate)) {
    return false;
  }
  if (isWeekdayBankHoliday(profile, isoDate)) {
    return false;
  }
  return true;
}

/** Mon–Fri slot where office / WFH / leave / sickness may be set. Ignores NWD so a marked NWD can be changed to another type. Weekends and bank holidays still block. */
function isCalendarWeekdayAssignable(profile, isoDate) {
  if (isPermanentWeekendIso(isoDate) || !isWeekdayMonFriIso(isoDate)) {
    return false;
  }
  if (isWeekdayBankHoliday(profile, isoDate)) {
    return false;
  }
  return true;
}

function isWfhDay(profile, isoDate) {
  return profile.wfhMarks.includes(isoDate);
}

function getStatus(actual, target) {
  if (actual === null) {
    return { label: "Status: N/A", className: "status-on-track" };
  }
  const diff = actual - target;
  if (Math.abs(diff) <= 0.5) {
    return { label: "On track", className: "status-on-track" };
  }
  if (diff > 0) {
    return { label: "Ahead", className: "status-ahead" };
  }
  return { label: "Behind", className: "status-behind" };
}

function toPercent(numerator, denominator) {
  if (denominator === 0) {
    return { value: null, label: "N/A" };
  }
  const value = (numerator / denominator) * 100;
  return { value, label: `${value.toFixed(1)}%` };
}

function loadStateFromLocalStorage() {
  const raw = localStorage.getItem(STORAGE_KEY);
  if (!raw) {
    return getDefaultState();
  }
  try {
    const parsed = JSON.parse(raw);
    const normalized = parseStateFromJSON(parsed);
    return normalized || getDefaultState();
  } catch {
    return getDefaultState();
  }
}

function parseStateFromJSON(parsed) {
  if (!parsed?.profiles?.length) {
    return null;
  }
  return {
    activeProfileId: parsed.activeProfileId,
    profiles: parsed.profiles.map((profile) => {
      const merged = {
        ...profile,
        wfhMarks: Array.isArray(profile.wfhMarks) ? profile.wfhMarks : [],
        sicknessMarks: Array.isArray(profile.sicknessMarks) ? profile.sicknessMarks : [],
        nwdMarks: Array.isArray(profile.nwdMarks) ? profile.nwdMarks : [],
      };
      delete merged.clearedDefaultWfh;
      normalizeProfileMarks(merged);
      return merged;
    }),
  };
}

function getDefaultState() {
  const defaultProfile = createDefaultProfile("Default profile");
  return {
    activeProfileId: defaultProfile.id,
    profiles: [defaultProfile],
  };
}

async function hydrateStateFromCloud() {
  const base = window.__attendanceApiBase;
  const token = window.__attendanceToken;
  const userId = window.__attendanceUser?.id;
  if (!base || !token || !userId) {
    state = loadStateFromLocalStorage();
    return;
  }
  try {
    const response = await fetch(`${base}/api/state`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (response.status === 401) {
      state = loadStateFromLocalStorage();
      if (typeof window.wfhInvalidateSession === "function") {
        window.wfhInvalidateSession(
          "Could not load your data from the server (session not accepted). If you recently changed JWT_SECRET on Railway, sign in again.",
        );
      }
      const authErr = new Error("SESSION_EXPIRED");
      authErr.skipAuthMessage = true;
      throw authErr;
    }
    if (!response.ok) {
      console.error("Cloud load failed:", response.status);
      state = loadStateFromLocalStorage();
      return;
    }
    const data = await response.json();
    if (data?.payload != null) {
      const rawPayload = data.payload;
      const asObj = typeof rawPayload === "string" ? JSON.parse(rawPayload) : rawPayload;
      const normalized = parseStateFromJSON(asObj);
      if (normalized) {
        state = normalized;
        localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
        return;
      }
    }
    state = loadStateFromLocalStorage();
    await flushCloudSaveInternal();
  } catch (err) {
    console.error(err);
    state = loadStateFromLocalStorage();
  }
}

async function flushCloudSaveInternal() {
  const base = window.__attendanceApiBase;
  const token = window.__attendanceToken;
  const userId = window.__attendanceUser?.id;
  if (!state || !base || !token || !userId) {
    return;
  }
  state.profiles.forEach(normalizeProfileMarks);
  try {
    const response = await fetch(`${base}/api/state`, {
      method: "PUT",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ payload: state }),
    });
    if (response.status === 401) {
      if (typeof window.wfhInvalidateSession === "function") {
        window.wfhInvalidateSession(
          "Save failed: the server rejected your session. Sign in again (often fixed by a stable JWT_SECRET on Railway).",
        );
      }
      return;
    }
    if (!response.ok) {
      const text = await response.text();
      console.error("Cloud save failed:", response.status, text);
    }
  } catch (err) {
    console.error("Cloud save failed:", err);
  }
}

function saveState() {
  if (!state) {
    return;
  }
  state.profiles.forEach(normalizeProfileMarks);
  localStorage.setItem(STORAGE_KEY, JSON.stringify(state));

  const base = window.__attendanceApiBase;
  const token = window.__attendanceToken;
  const user = window.__attendanceUser;
  if (!base || !token || !user?.id) {
    return;
  }
  clearTimeout(cloudSaveTimer);
  cloudSaveTimer = setTimeout(() => {
    flushCloudSaveInternal();
  }, 700);
}

window.flushAttendanceCloudNow = async function flushAttendanceCloudNow() {
  clearTimeout(cloudSaveTimer);
  const base = window.__attendanceApiBase;
  const token = window.__attendanceToken;
  const user = window.__attendanceUser;
  if (base && token && user?.id && state) {
    await flushCloudSaveInternal();
  }
};

function dedupeSortedDates(arr) {
  return [...new Set(arr)].sort();
}

function normalizeProfileMarks(profile) {
  profile.officeMarks = dedupeSortedDates(profile.officeMarks || []);
  profile.leaveMarks = dedupeSortedDates(profile.leaveMarks || []);
  profile.wfhMarks = dedupeSortedDates(profile.wfhMarks || []);
  profile.sicknessMarks = dedupeSortedDates(profile.sicknessMarks || []);
  profile.nwdMarks = dedupeSortedDates(profile.nwdMarks || []);
  if (profile.settings && "workingWeek" in profile.settings) {
    delete profile.settings.workingWeek;
  }
  delete profile.clearedDefaultWfh;
  if (profile.settings && "fyStartMonth" in profile.settings) {
    delete profile.settings.fyStartMonth;
  }
  ensureProfileCreatedAt(profile);
}

function createDefaultProfile(name) {
  return {
    id: `p-${Date.now()}-${Math.random().toString(16).slice(2, 8)}`,
    name,
    createdAtISO: getLondonTodayISO(),
    settings: {
      targetPct: 40,
      leaveAllowances: { [String(getLondonToday().year)]: 25 },
    },
    officeMarks: [],
    leaveMarks: [],
    wfhMarks: [],
    sicknessMarks: [],
    nwdMarks: [],
  };
}

function getActiveProfile() {
  return (
    state.profiles.find((p) => p.id === state.activeProfileId) ||
    state.profiles[0]
  );
}

function getAllowance(profile, year) {
  return Number(profile.settings.leaveAllowances[String(year)] || 0);
}

function toggleDate(arr, value) {
  const idx = arr.indexOf(value);
  if (idx >= 0) {
    arr.splice(idx, 1);
  } else {
    arr.push(value);
  }
}

function removeDate(arr, value) {
  return arr.filter((item) => item !== value);
}

function clearAttendanceMarks(profile, isoDate) {
  profile.officeMarks = removeDate(profile.officeMarks, isoDate);
  profile.leaveMarks = removeDate(profile.leaveMarks, isoDate);
  profile.wfhMarks = removeDate(profile.wfhMarks, isoDate);
  profile.sicknessMarks = removeDate(profile.sicknessMarks, isoDate);
}

function clearExplicitDayMarks(profile, isoDate) {
  clearAttendanceMarks(profile, isoDate);
  profile.nwdMarks = removeDate(profile.nwdMarks, isoDate);
}

function applyDayType(profile, isoDate, nextType) {
  if (!nextType) {
    return { ok: false, message: "" };
  }

  const backup = {
    officeMarks: [...profile.officeMarks],
    leaveMarks: [...profile.leaveMarks],
    wfhMarks: [...profile.wfhMarks],
    sicknessMarks: [...profile.sicknessMarks],
    nwdMarks: [...profile.nwdMarks],
  };
  const restore = () => {
    profile.officeMarks = backup.officeMarks;
    profile.leaveMarks = backup.leaveMarks;
    profile.wfhMarks = backup.wfhMarks;
    profile.sicknessMarks = backup.sicknessMarks;
    profile.nwdMarks = backup.nwdMarks;
  };

  const assignableSlot = isCalendarWeekdayAssignable(profile, isoDate);
  const year = Number(isoDate.slice(0, 4));

  if (nextType === "unassigned") {
    clearExplicitDayMarks(profile, isoDate);
    normalizeProfileMarks(profile);
    return { ok: true, message: "" };
  }

  if (nextType === "nwd") {
    if (isPermanentWeekendIso(isoDate)) {
      return { ok: false, message: "Cannot mark NWD on Saturday or Sunday." };
    }
    clearAttendanceMarks(profile, isoDate);
    if (!profile.nwdMarks.includes(isoDate)) {
      profile.nwdMarks.push(isoDate);
    }
    normalizeProfileMarks(profile);
    return { ok: true, message: "Marked as non-working day (NWD)." };
  }

  if (nextType === "wfh") {
    if (!assignableSlot) {
      return { ok: false, message: "Cannot set WFH on a non-working day." };
    }
    clearExplicitDayMarks(profile, isoDate);
    if (!profile.wfhMarks.includes(isoDate)) {
      profile.wfhMarks.push(isoDate);
    }
    normalizeProfileMarks(profile);
    return { ok: true, message: "WFH set." };
  }

  if (nextType === "office") {
    if (!assignableSlot) {
      return { ok: false, message: "Cannot mark in-office on a non-working day." };
    }
    clearExplicitDayMarks(profile, isoDate);
    profile.officeMarks.push(isoDate);
    normalizeProfileMarks(profile);
    return { ok: true, message: "Day marked as in office." };
  }

  if (nextType === "leave") {
    clearExplicitDayMarks(profile, isoDate);
    if (!assignableSlot) {
      restore();
      return { ok: false, message: "Cannot set annual leave on a non-working day." };
    }
    const allowance = getAllowance(profile, year);
    const used = countLeaveDays(profile, toISO(year, 1, 1), toISO(year, 12, 31));
    if (used >= allowance) {
      restore();
      return { ok: false, message: "Leave allowance reached for this calendar year." };
    }
    profile.leaveMarks.push(isoDate);
    normalizeProfileMarks(profile);
    return { ok: true, message: "Day marked as annual leave." };
  }

  if (nextType === "sickness") {
    clearExplicitDayMarks(profile, isoDate);
    if (!assignableSlot) {
      restore();
      return { ok: false, message: "Cannot set sickness on a non-working day." };
    }
    profile.sicknessMarks.push(isoDate);
    normalizeProfileMarks(profile);
    return { ok: true, message: "Day marked as sickness." };
  }

  restore();
  return { ok: false, message: "Unknown day type." };
}

function getLondonToday() {
  const now = new Date();
  const formatter = new Intl.DateTimeFormat("en-GB", {
    timeZone: LONDON_TZ,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  });
  const parts = formatter.formatToParts(now);
  const day = Number(parts.find((p) => p.type === "day").value);
  const month = Number(parts.find((p) => p.type === "month").value);
  const year = Number(parts.find((p) => p.type === "year").value);
  return { year, month, day };
}

function getLondonTodayISO() {
  const { year, month, day } = getLondonToday();
  return toISO(year, month, day);
}

function getTodayYearMonth() {
  const { year, month } = getLondonToday();
  return { year, month };
}

function daysInMonth(year, month) {
  return new Date(Date.UTC(year, month, 0)).getUTCDate();
}

function dayOfWeek(year, month, day) {
  return new Date(Date.UTC(year, month - 1, day)).getUTCDay();
}

function toISO(year, month, day) {
  const m = String(month).padStart(2, "0");
  const d = String(day).padStart(2, "0");
  return `${year}-${m}-${d}`;
}

function minISO(a, b) {
  return a <= b ? a : b;
}

function maxISO(a, b) {
  return a >= b ? a : b;
}

function utcMsToLondonISO(ms) {
  const formatter = new Intl.DateTimeFormat("en-GB", {
    timeZone: LONDON_TZ,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  });
  const parts = formatter.formatToParts(new Date(ms));
  const day = Number(parts.find((p) => p.type === "day").value);
  const month = Number(parts.find((p) => p.type === "month").value);
  const year = Number(parts.find((p) => p.type === "year").value);
  return toISO(year, month, day);
}

function ensureProfileCreatedAt(profile) {
  if (profile.createdAtISO && /^\d{4}-\d{2}-\d{2}$/.test(profile.createdAtISO)) {
    return;
  }
  const m = /^p-(\d+)-/.exec(profile.id || "");
  profile.createdAtISO = m ? utcMsToLondonISO(Number(m[1])) : getLondonTodayISO();
}

function countWorkingWeekdays(profile, startISO, endISO) {
  let n = 0;
  for (const iso of listDates(startISO, endISO)) {
    if (countsAsMetricsWorkingDay(profile, iso)) {
      n += 1;
    }
  }
  return n;
}

function countUnassignedWorkingDays(profile, startISO, endISO) {
  let n = 0;
  for (const iso of listDates(startISO, endISO)) {
    if (!countsAsMetricsWorkingDay(profile, iso)) {
      continue;
    }
    if (
      profile.officeMarks.includes(iso) ||
      profile.leaveMarks.includes(iso) ||
      profile.sicknessMarks.includes(iso) ||
      profile.wfhMarks.includes(iso)
    ) {
      continue;
    }
    n += 1;
  }
  return n;
}

function isoToWeekday(isoDate) {
  const [year, month, day] = isoDate.split("-").map(Number);
  const jsDay = dayOfWeek(year, month, day);
  return jsDay === 0 ? 7 : jsDay;
}

function shiftMonth(year, month, delta) {
  const idx = year * 12 + (month - 1) + delta;
  return {
    year: Math.floor(idx / 12),
    month: (idx % 12) + 1,
  };
}

function addOneDayISO(iso) {
  const [y, m, d] = iso.split("-").map(Number);
  const dim = daysInMonth(y, m);
  let nextDay = d + 1;
  let nextMonth = m;
  let nextYear = y;
  if (nextDay > dim) {
    nextDay = 1;
    nextMonth += 1;
    if (nextMonth > 12) {
      nextMonth = 1;
      nextYear += 1;
    }
  }
  return toISO(nextYear, nextMonth, nextDay);
}

function listDates(startISO, endISO) {
  if (!startISO || !endISO || startISO > endISO) {
    return [];
  }
  const dates = [];
  let cur = startISO;
  while (cur <= endISO) {
    dates.push(cur);
    cur = addOneDayISO(cur);
  }
  return dates;
}

function clampDatesToMonth(year, month, startISO, endISO) {
  const monthStart = toISO(year, month, 1);
  const monthEnd = toISO(year, month, daysInMonth(year, month));
  const lo = maxISO(minISO(startISO, endISO), monthStart);
  const hi = minISO(maxISO(startISO, endISO), monthEnd);
  if (lo > hi) {
    return [];
  }
  return listDates(lo, hi);
}

function formatFriendlyDate(isoDate) {
  const [year, month, day] = isoDate.split("-").map(Number);
  return `${day} ${MONTH_NAMES[month - 1]} ${year}`;
}

function isSameMonth(y1, m1, y2, m2) {
  return y1 === y2 && m1 === m2;
}

async function loadBankHolidays() {
  try {
    const response = await fetch(HOLIDAY_FILE);
    if (!response.ok) {
      throw new Error("Holiday file load failed");
    }
    return response.json();
  } catch {
    return {};
  }
}

window.startAttendanceApp = async function startAttendanceApp({ user, token, apiBaseUrl }) {
  window.__attendanceApiBase = String(apiBaseUrl || "").replace(/\/$/, "");
  window.__attendanceToken = token;
  window.__attendanceUser = user;

  await hydrateStateFromCloud();

  const accountEmailEl = document.getElementById("account-email");
  const signOutBtn = document.getElementById("sign-out-button");
  if (accountEmailEl) {
    accountEmailEl.textContent = user.email || "";
  }
  if (signOutBtn) {
    signOutBtn.onclick = () => {
      if (typeof window.wfhSignOut === "function") {
        window.wfhSignOut();
      }
    };
  }

  if (!appBootstrapped) {
    appBootstrapped = true;
    await bootstrap();
  } else {
    renderAll();
  }
};
