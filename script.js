const STORAGE_KEY = "attendanceTracker.v1";
/** Must match `JWT_STORAGE` in `auth.js` (sessionStorage key for API bearer token). */
const WFH_JWT_SESSION_KEY = "WFH_JWT";
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
const prevMonthButton = document.getElementById("prev-month");
const nextMonthButton = document.getElementById("next-month");
const settingsForm = document.getElementById("settings-form");
const targetInput = document.getElementById("target-input");
const leaveAllowanceInput = document.getElementById("leave-allowance-input");
const settingsMessage = document.getElementById("settings-message");
const calendarBulkBar = document.getElementById("calendar-bulk-bar");
const profileCreatedEl = document.getElementById("profile-created");
const calendarYearSelect = document.getElementById("calendar-year-select");
const profileGreeting = document.getElementById("profile-greeting");
const monthSubtitle = document.getElementById("month-subtitle");
const calendarEyebrow = document.getElementById("calendar-eyebrow");
const lockMonthButton = document.getElementById("lock-month");
const appTabs = document.querySelectorAll("[data-app-tab]");
const tabPanels = document.querySelectorAll("[data-tab-panel]");
const monthInsightsEl = document.getElementById("month-insights");
const yearInsightsEl = document.getElementById("year-insights");
const rangeModeButtons = document.querySelectorAll("[data-range-mode]");
const profileNameInput = document.getElementById("profile-name-input");
const recordingStartMonthSelect = document.getElementById("recording-start-month");
const recordingStartYearSelect = document.getElementById("recording-start-year");
const leaveYearSelect = document.getElementById("leave-year-select");
const settingsAccountEmail = document.getElementById("settings-account-email");
const settingsSignOutButton = document.getElementById("settings-sign-out-button");

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
let activeTab = "record";
let monthInsightRangeMode = "recorded";

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

  appTabs.forEach((tab) => {
    tab.addEventListener("click", () => {
      activeTab = tab.dataset.appTab || "record";
      syncActiveTab();
    });
  });

  rangeModeButtons.forEach((button) => {
    button.addEventListener("click", () => {
      monthInsightRangeMode = button.dataset.rangeMode === "mtd" ? "mtd" : "recorded";
      syncRangeToggle();
      renderInsights();
    });
  });

  if (lockMonthButton) {
    lockMonthButton.addEventListener("click", () => {
      const profile = getActiveProfile();
      const key = monthKey(currentView.year, currentView.month);
      if (isBeforeRecordingStart(profile, key)) {
        return;
      }
      setMonthLocked(profile, key, !isMonthLocked(profile, key));
      clearCalendarSelection();
      saveState();
      renderAll();
    });
  }

  if (leaveYearSelect) {
    leaveYearSelect.addEventListener("change", () => {
      renderSettings();
    });
  }

  if (settingsSignOutButton) {
    settingsSignOutButton.addEventListener("click", () => {
      document.getElementById("sign-out-button")?.click();
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

  settingsForm.addEventListener("submit", (event) => {
    event.preventDefault();
    const profile = getActiveProfile();
    const target = Number(targetInput.value);
    const allowance = Number(leaveAllowanceInput.value);

    const leaveYear = Number(leaveYearSelect?.value || currentView.year);
    const startYear = Number(recordingStartYearSelect?.value || getLondonToday().year);
    const startMonth = Number(recordingStartMonthSelect?.value || getLondonToday().month);
    const trimmedName = String(profileNameInput?.value || "").trim();

    if (trimmedName) {
      profile.name = trimmedName;
    }
    profile.settings.targetPct = Number.isFinite(target) ? target : 40;
    profile.settings.recordingStartMonth = monthKey(startYear, startMonth);
    profile.settings.leaveAllowances[String(leaveYear)] = Number.isFinite(allowance)
      ? Math.max(0, Math.floor(allowance))
      : 0;

    saveState();
    settingsMessage.textContent = "Settings saved.";
    renderAll();
  });
}

function renderAll() {
  if (!state || !state.profiles?.length) {
    state = loadStateFromLocalStorage();
  }
  syncActiveTab();
  renderProfileHeader();
  renderProfileCreated();
  renderKpiStrip();
  renderDashboard();
  renderCalendar();
  renderCalendarBulkBar();
  renderInsights();
  renderSettings();
}

function syncActiveTab() {
  appTabs.forEach((tab) => {
    const on = tab.dataset.appTab === activeTab;
    tab.classList.toggle("active", on);
    if (on) {
      tab.setAttribute("aria-current", "page");
    } else {
      tab.removeAttribute("aria-current");
    }
  });
  tabPanels.forEach((panel) => {
    panel.hidden = panel.dataset.tabPanel !== activeTab;
  });
}

function syncRangeToggle() {
  rangeModeButtons.forEach((button) => {
    const on = button.dataset.rangeMode === monthInsightRangeMode;
    button.classList.toggle("active", on);
    button.setAttribute("aria-selected", String(on));
  });
}

function renderProfileHeader() {
  const profile = getActiveProfile();
  if (profileGreeting) {
    profileGreeting.textContent = profile.name || "Record";
  }
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
  const profile = getActiveProfile();
  const key = monthKey(currentView.year, currentView.month);
  if (isMonthLocked(profile, key) || isBeforeRecordingStart(profile, key)) {
    calendarBulkBar.hidden = true;
    calendarBulkBar.innerHTML = "";
    return;
  }
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
  const monthWorkingDays = countWorkingWeekdays(profile, viewedMonthRange.start, viewedMonthRange.end);
  const monthOffice = countOfficeDays(profile, viewedMonthRange.start, viewedMonthRange.end);
  const monthWfh = countWfhDays(profile, viewedMonthRange.start, viewedMonthRange.end);
  const monthLeave = countLeaveDays(profile, viewedMonthRange.start, viewedMonthRange.end);
  const monthSickness = countSicknessDays(profile, viewedMonthRange.start, viewedMonthRange.end);
  const monthUnassigned = countUnassignedWorkingDays(profile, viewedMonthRange.start, viewedMonthRange.end);
  const monthNwd = countNwdDaysInRange(profile, viewedMonthRange.start, viewedMonthRange.end);
  const monthActual = toPercent(monthOffice, monthTracked);

  const monthTitleLabel = `${MONTH_NAMES[viewMonth - 1]} ${viewYear}`;

  const yearTracked = countTrackedWorkingDays(profile, yearStart, periodEnd);
  const yearWorkingDays = countWorkingWeekdays(profile, yearStart, periodEnd);
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
      workingDays: monthWorkingDays,
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
      workingDays: yearWorkingDays,
      leave: yearLeaveInWindow,
      sickness: yearSickness,
      nwd: yearNwd,
      variant: "year",
    }),
  );
}

function buildMonthDayListHtml(
  { tracked, workingDays = tracked, office, wfh, unassigned, leave, sickness, nwd = 0 },
  rootClass = "card-month-summary",
  rowClass = "card-metric-row",
) {
  const rows = [
    ["Total working days", String(workingDays)],
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
  workingDays = tracked,
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
      workingDays,
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
    ["Total working days", String(workingDays)],
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
  const profile = getActiveProfile();
  const startParts = getRecordingStartParts(profile);
  const yearSet = new Set();
  const minYear = Math.min(startParts.year, CALENDAR_YEAR_PICKER_MIN);
  for (let yy = minYear; yy <= CALENDAR_YEAR_PICKER_MAX; yy += 1) {
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

function populateSettingsSelects(profile) {
  const startParts = getRecordingStartParts(profile);
  if (recordingStartMonthSelect && recordingStartMonthSelect.children.length === 0) {
    recordingStartMonthSelect.innerHTML = MONTH_NAMES.map(
      (name, idx) => `<option value="${idx + 1}">${name}</option>`,
    ).join("");
  }
  if (recordingStartYearSelect) {
    const todayYear = getLondonToday().year;
    const years = new Set([startParts.year]);
    for (let y = Math.min(startParts.year, todayYear); y <= todayYear + 3; y += 1) {
      years.add(y);
    }
    recordingStartYearSelect.innerHTML = [...years]
      .sort((a, b) => a - b)
      .map((y) => `<option value="${y}"${y === startParts.year ? " selected" : ""}>${y}</option>`)
      .join("");
  }
  if (recordingStartMonthSelect) {
    recordingStartMonthSelect.value = String(startParts.month);
  }
  if (leaveYearSelect) {
    const currentSelected = Number(leaveYearSelect.value || currentView.year);
    const todayYear = getLondonToday().year;
    const configured = Object.keys(profile.settings.leaveAllowances || {})
      .map(Number)
      .filter(Number.isFinite);
    const years = new Set([currentSelected, currentView.year, startParts.year, ...configured]);
    for (let y = startParts.year; y <= todayYear + 3; y += 1) {
      years.add(y);
    }
    const selected = Math.max(startParts.year, currentSelected || currentView.year);
    leaveYearSelect.innerHTML = [...years]
      .filter((y) => y >= startParts.year)
      .sort((a, b) => a - b)
      .map((y) => `<option value="${y}"${y === selected ? " selected" : ""}>${y}</option>`)
      .join("");
  }
}

function renderCalendar() {
  const profile = getActiveProfile();
  const { year, month } = currentView;
  const key = monthKey(year, month);
  const isLocked = isMonthLocked(profile, key);
  const beforeStart = isBeforeRecordingStart(profile, key);
  const isEditable = !isLocked && !beforeStart;
  monthTitle.textContent = `${MONTH_NAMES[month - 1]}`;
  if (calendarEyebrow) {
    calendarEyebrow.textContent = String(year);
  }
  if (monthSubtitle) {
    const start = toISO(year, month, 1);
    const end = toISO(year, month, daysInMonth(year, month));
    const working = countWorkingWeekdays(profile, start, end);
    const unassigned = countUnassignedWorkingDays(profile, start, end);
    monthSubtitle.textContent = beforeStart
      ? "Before recording start"
      : `${working} working days · ${unassigned} unassigned`;
  }
  if (lockMonthButton) {
    lockMonthButton.textContent = beforeStart ? "Locked" : isLocked ? "Unlock" : "Lock";
    lockMonthButton.disabled = beforeStart;
    lockMonthButton.setAttribute("aria-pressed", String(isLocked || beforeStart));
    lockMonthButton.classList.toggle("lock-month--locked", isLocked || beforeStart);
  }

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
    if (!isEditable || stateForDay.cssClass === "weekend" || stateForDay.cssClass === "bank-holiday") {
      button.classList.add("day--disabled");
    }
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
      if (!isEditable || stateForDay.cssClass === "weekend" || stateForDay.cssClass === "bank-holiday") {
        return;
      }
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
  populateSettingsSelects(profile);
  if (profileNameInput) {
    profileNameInput.value = profile.name || "";
  }
  targetInput.value = String(profile.settings.targetPct);
  const leaveYear = Number(leaveYearSelect?.value || currentView.year);
  leaveAllowanceInput.value = String(getAllowance(profile, leaveYear));
  if (settingsAccountEmail) {
    settingsAccountEmail.textContent = window.__attendanceUser?.email || "";
  }
}

function renderInsights() {
  const profile = getActiveProfile();
  syncRangeToggle();
  if (monthInsightsEl) {
    monthInsightsEl.innerHTML = buildMonthInsightsHtml(profile);
  }
  if (yearInsightsEl) {
    yearInsightsEl.innerHTML = buildYearInsightsHtml(profile);
  }
}

function buildMonthInsightsHtml(profile) {
  const { year, month } = currentView;
  const start = toISO(year, month, 1);
  const monthEnd = toISO(year, month, daysInMonth(year, month));
  const end = monthInsightRangeMode === "mtd" ? minISO(getLondonTodayISO(), monthEnd) : monthEnd;
  const metrics = getMetrics(profile, start, end);
  const fullMonthMetrics = getMetrics(profile, start, monthEnd);
  const officeShare = toPercent(metrics.office, metrics.workingDays);
  const target = profile.settings.targetPct;
  const needed = officeDaysNeeded(metrics, target);
  const title = `${MONTH_NAMES[month - 1]} ${year}`;
  const rangeLabel = monthInsightRangeMode === "mtd" ? "Month-to-Date" : "User Recorded";
  const status = getStatus(officeShare.value, target);
  return `
    ${buildInsightHeroHtml({
      title,
      eyebrow: rangeLabel,
      pct: officeShare,
      target,
      status,
      metrics,
      caption: `${metrics.tracked} tracked · ${metrics.workingDays} working days`,
    })}
    <div class="insight-grid">
      ${buildCompositionCardHtml("Month composition", metrics)}
      ${buildMonthOutlookCardHtml(fullMonthMetrics, needed, target)}
    </div>
    ${buildWeekCardHtml(profile, year, month, end)}
  `;
}

function buildYearInsightsHtml(profile) {
  const { year } = currentView;
  const startParts = getRecordingStartParts(profile);
  const start = year === startParts.year ? toISO(startParts.year, startParts.month, 1) : toISO(year, 1, 1);
  const end = toISO(year, 12, 31);
  const metrics = getMetrics(profile, start, end);
  const leave = getLeaveBreakdown(profile, year);
  const officeShare = toPercent(metrics.office, metrics.workingDays);
  const status = getStatus(officeShare.value, profile.settings.targetPct);
  return `
    ${buildInsightHeroHtml({
      title: String(year),
      eyebrow: "Year insight",
      pct: officeShare,
      target: profile.settings.targetPct,
      status,
      metrics,
      caption: `${metrics.tracked} tracked · ${metrics.workingDays} working days`,
    })}
    <div class="insight-grid">
      ${buildCompositionCardHtml("Year composition", metrics)}
      ${buildLeaveInsightCardHtml(leave)}
    </div>
    ${buildQuarterCardHtml(profile, year)}
  `;
}

function buildInsightHeroHtml({ title, eyebrow, pct, target, status, metrics, caption }) {
  const share = pct.value == null ? 0 : Math.max(0, Math.min(100, pct.value));
  return `<article class="insight-hero">
    <div class="insight-hero-copy">
      <span class="insight-eyebrow">${eyebrow}</span>
      <h3>${title}</h3>
      <p class="muted">${caption}</p>
      <span class="status ${status.className}">${status.label}</span>
    </div>
    <div class="insight-ring" style="--share:${share * 3.6}deg">
      <div class="insight-ring-hole">
        <strong>${pct.label}</strong>
        <span>office · target ${target.toFixed(1)}%</span>
      </div>
    </div>
    <div class="insight-quickstats">
      ${buildMiniStat("Office", metrics.office, "office")}
      ${buildMiniStat("WFH", metrics.wfh, "wfh")}
      ${buildMiniStat("Leave", metrics.leave, "leave")}
      ${buildMiniStat("Sick", metrics.sickness, "sickness")}
    </div>
  </article>`;
}

function buildMiniStat(label, value, kind) {
  return `<div class="mini-stat mini-stat--${kind}"><span>${value}</span><strong>${label}</strong></div>`;
}

function buildCompositionCardHtml(title, metrics) {
  const total = Math.max(metrics.workingDays, 1);
  const barSegments = [
    ["office", metrics.office],
    ["wfh", metrics.wfh],
    ["sickness", metrics.sickness],
    ["unassigned", metrics.unassigned],
  ];
  const statSegments = [
    ["office", metrics.office],
    ["wfh", metrics.wfh],
    ["leave", metrics.leave],
    ["sickness", metrics.sickness],
    ["nwd", metrics.nwd],
    ["unassigned", metrics.unassigned],
  ];
  return `<article class="insight-card">
    <h3>${title}</h3>
    <div class="composition-track">
      ${barSegments.map(([kind, value]) => `<span class="composition-seg composition-seg--${kind}" style="width:${(value / total) * 100}%"></span>`).join("")}
    </div>
    <div class="insight-stat-grid">
      ${statSegments.map(([kind, value]) => `<div><strong>${value}</strong><span>${kind === "nwd" ? "NWD" : kind}</span></div>`).join("")}
    </div>
  </article>`;
}

function buildMonthOutlookCardHtml(metrics, needed, target) {
  return `<article class="insight-card">
    <h3>Month target</h3>
    <p class="insight-large">${needed}</p>
    <p class="muted">${needed === 1 ? "more office day" : "more office days"} needed to reach ${target.toFixed(1)}% for the full month.</p>
    <div class="card-metric-row"><strong>Working days</strong><span>${metrics.workingDays}</span></div>
    <div class="card-metric-row"><strong>Unassigned</strong><span>${metrics.unassigned}</span></div>
  </article>`;
}

function buildLeaveInsightCardHtml(leave) {
  return `<article class="insight-card">
    <h3>Annual leave</h3>
    <p class="insight-large">${leave.remaining}</p>
    <p class="muted">days remaining from a ${leave.allowance} day allowance.</p>
    <div class="card-metric-row"><strong>Taken</strong><span>${leave.taken}</span></div>
    <div class="card-metric-row"><strong>Booked ahead</strong><span>${leave.booked}</span></div>
  </article>`;
}

function buildWeekCardHtml(profile, year, month, cutoffISO) {
  const rows = [];
  let week = [];
  for (const iso of listDates(toISO(year, month, 1), toISO(year, month, daysInMonth(year, month)))) {
    if (cutoffISO && iso > cutoffISO) {
      continue;
    }
    week.push(iso);
    if (isoToWeekday(iso) === 7 || iso.endsWith(`-${String(daysInMonth(year, month)).padStart(2, "0")}`)) {
      rows.push(week);
      week = [];
    }
  }
  return `<article class="insight-card insight-card--wide">
    <h3>Week by week</h3>
    <div class="week-list">
      ${rows.map((dates, idx) => {
        const metrics = getMetrics(profile, dates[0], dates[dates.length - 1]);
        const share = toPercent(metrics.office, metrics.workingDays);
        return `<div class="week-row"><strong>Week ${idx + 1}</strong><span>${share.label}</span><small>${metrics.office} office · ${metrics.wfh} WFH · ${metrics.unassigned} open</small></div>`;
      }).join("")}
    </div>
  </article>`;
}

function buildQuarterCardHtml(profile, year) {
  return `<article class="insight-card insight-card--wide">
    <h3>Quarter scoreboard</h3>
    <div class="quarter-grid">
      ${[1, 2, 3, 4].map((q) => {
        const startMonth = (q - 1) * 3 + 1;
        const metrics = getMetrics(profile, toISO(year, startMonth, 1), toISO(year, startMonth + 2, daysInMonth(year, startMonth + 2)));
        const share = toPercent(metrics.office, metrics.workingDays);
        return `<div class="quarter-tile"><span>Q${q}</span><strong>${share.label}</strong><small>${metrics.tracked} tracked</small></div>`;
      }).join("")}
    </div>
  </article>`;
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
  if (isoDate < recordingStartISO(profile)) {
    return false;
  }
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
  const key = isoDate.slice(0, 7);
  if (isBeforeRecordingStart(profile, key) || isMonthLocked(profile, key)) {
    return false;
  }
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
        lockedMonths: Array.isArray(profile.lockedMonths) ? profile.lockedMonths : [],
        settings: {
          ...(profile.settings || {}),
          targetPct: Number(profile.settings?.targetPct ?? 40),
          leaveAllowances: profile.settings?.leaveAllowances || {},
          recordingStartMonth:
            validMonthKey(profile.settings?.recordingStartMonth) ||
            earliestMarkedMonthKey(profile) ||
            monthKeyFromISO(profile.createdAtISO) ||
            monthKey(getLondonToday().year, getLondonToday().month),
        },
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

function cloudApiUrl(path) {
  const base = String(window.WFH_API?.apiBase ?? "")
    .trim()
    .replace(/\/$/, "");
  const p = path.startsWith("/") ? path : `/${path}`;
  return `${base}${p}`;
}

/** Avoid hanging forever on stalled serverless/network (stuck “Loading your calendar…”). */
async function fetchWithTimeout(url, init = {}, timeoutMs = 28000) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    return await fetch(url, { ...init, signal: ctrl.signal });
  } catch (err) {
    if (err?.name === "AbortError") {
      const timeoutErr = new Error("Request timed out. Check your connection and try again.");
      timeoutErr.name = "TimeoutError";
      throw timeoutErr;
    }
    throw err;
  } finally {
    clearTimeout(t);
  }
}

async function cloudApiFetch(path, options = {}) {
  const headers = { ...(options.headers || {}) };
  let body = options.body;
  if (body != null && typeof body === "object" && !(body instanceof FormData)) {
    headers["Content-Type"] = "application/json";
    body = JSON.stringify(body);
  }
  const token = window.__attendanceToken;
  if (token) {
    headers.Authorization = `Bearer ${token}`;
  }
  const res = await fetchWithTimeout(cloudApiUrl(path), { ...options, headers, body });
  const text = await res.text();
  let data = null;
  try {
    data = text ? JSON.parse(text) : null;
  } catch {
    data = { error: text || "Invalid response" };
  }
  return { ok: res.ok, status: res.status, data };
}

function isCloudSessionAuthFailure(status) {
  return status === 401 || status === 403;
}

async function hydrateStateFromCloud(user) {
  const token = window.__attendanceToken;
  if (!token || !user?.id) {
    state = loadStateFromLocalStorage();
    return;
  }
  try {
    const { ok, status, data } = await cloudApiFetch("/api/state", { method: "GET" });
    if (!ok) {
      console.error(data);
      state = loadStateFromLocalStorage();
      if (isCloudSessionAuthFailure(status) && typeof window.wfhInvalidateSession === "function") {
        await window.wfhInvalidateSession(
          "Could not load your data (session expired or not allowed). Please sign in again.",
        );
        const authErr = new Error("SESSION_EXPIRED");
        authErr.skipAuthMessage = true;
        throw authErr;
      }
      return;
    }

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
    await flushCloudSaveInternal(user.id);
  } catch (err) {
    if (err?.skipAuthMessage) {
      throw err;
    }
    console.error(err);
    state = loadStateFromLocalStorage();
  }
}

async function flushCloudSaveInternal(userId) {
  if (!state || !userId) {
    return;
  }
  const token = window.__attendanceToken;
  if (!token) {
    return;
  }
  state.profiles.forEach(normalizeProfileMarks);
  const { ok, status, data } = await cloudApiFetch("/api/state", {
    method: "PUT",
    body: { payload: state },
  });
  if (!ok) {
    console.error("Cloud save failed:", data);
    if (isCloudSessionAuthFailure(status) && typeof window.wfhInvalidateSession === "function") {
      await window.wfhInvalidateSession(
        "Save failed: the server rejected your session. Please sign in again.",
      );
    }
  }
}

function saveState() {
  if (!state) {
    return;
  }
  state.profiles.forEach(normalizeProfileMarks);
  localStorage.setItem(STORAGE_KEY, JSON.stringify(state));

  const user = window.__attendanceUser;
  const token = window.__attendanceToken;
  if (!token || !user?.id) {
    return;
  }
  clearTimeout(cloudSaveTimer);
  cloudSaveTimer = setTimeout(() => {
    flushCloudSaveInternal(user.id);
  }, 700);
}

window.flushAttendanceCloudNow = async function flushAttendanceCloudNow() {
  clearTimeout(cloudSaveTimer);
  const user = window.__attendanceUser;
  const token = window.__attendanceToken;
  if (token && user?.id && state) {
    await flushCloudSaveInternal(user.id);
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
  profile.lockedMonths = dedupeSortedDates(profile.lockedMonths || []);
  profile.settings = profile.settings || {};
  profile.settings.leaveAllowances = profile.settings.leaveAllowances || {};
  profile.settings.targetPct = Number(profile.settings.targetPct ?? 40);
  profile.settings.recordingStartMonth =
    validMonthKey(profile.settings.recordingStartMonth) ||
    earliestMarkedMonthKey(profile) ||
    monthKeyFromISO(profile.createdAtISO) ||
    monthKey(getLondonToday().year, getLondonToday().month);
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
      recordingStartMonth: monthKey(getLondonToday().year, getLondonToday().month),
    },
    officeMarks: [],
    leaveMarks: [],
    wfhMarks: [],
    sicknessMarks: [],
    nwdMarks: [],
    lockedMonths: [],
  };
}

function getActiveProfile() {
  return (
    state.profiles.find((p) => p.id === state.activeProfileId) ||
    state.profiles[0]
  );
}

function getAllowance(profile, year) {
  return Number(
    profile.settings.leaveAllowances[String(year)] ??
      profile.settings.leaveAllowances[String(getLondonToday().year)] ??
      25,
  );
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
  const key = isoDate.slice(0, 7);
  if (isBeforeRecordingStart(profile, key)) {
    return { ok: false, message: "This month is before your recording start date." };
  }
  if (isMonthLocked(profile, key)) {
    return { ok: false, message: "This month is locked. Unlock it before editing." };
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
    if (isPermanentWeekendIso(isoDate) || isWeekdayBankHoliday(profile, isoDate)) {
      return { ok: false, message: "NWD can only be set on a weekday." };
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

function monthKey(year, month) {
  return `${year}-${String(month).padStart(2, "0")}`;
}

function validMonthKey(value) {
  const raw = String(value || "");
  const match = /^(\d{4})-(\d{2})$/.exec(raw);
  if (!match) {
    return "";
  }
  const month = Number(match[2]);
  return month >= 1 && month <= 12 ? raw : "";
}

function monthKeyFromISO(isoDate) {
  return /^\d{4}-\d{2}-\d{2}$/.test(String(isoDate || "")) ? isoDate.slice(0, 7) : "";
}

function earliestMarkedMonthKey(profile) {
  return [
    ...(profile.officeMarks || []),
    ...(profile.leaveMarks || []),
    ...(profile.wfhMarks || []),
    ...(profile.sicknessMarks || []),
    ...(profile.nwdMarks || []),
  ]
    .map(monthKeyFromISO)
    .filter(Boolean)
    .sort()[0] || "";
}

function getRecordingStartMonthKey(profile) {
  return (
    validMonthKey(profile?.settings?.recordingStartMonth) ||
    earliestMarkedMonthKey(profile || {}) ||
    monthKeyFromISO(profile?.createdAtISO) ||
    monthKey(getLondonToday().year, getLondonToday().month)
  );
}

function getRecordingStartParts(profile) {
  const [year, month] = getRecordingStartMonthKey(profile).split("-").map(Number);
  return { year, month };
}

function recordingStartISO(profile) {
  const parts = getRecordingStartParts(profile);
  return toISO(parts.year, parts.month, 1);
}

function isBeforeRecordingStart(profile, key) {
  return key < getRecordingStartMonthKey(profile);
}

function isMonthLocked(profile, key) {
  return (profile.lockedMonths || []).includes(key);
}

function setMonthLocked(profile, key, locked) {
  const months = new Set(profile.lockedMonths || []);
  if (locked) {
    months.add(key);
  } else {
    months.delete(key);
  }
  profile.lockedMonths = [...months].sort();
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
    if (countsAsMetricsWorkingDay(profile, iso) && !profile.leaveMarks.includes(iso)) {
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

function getMetrics(profile, startISO, endISO) {
  const metrics = {
    workingDays: 0,
    office: 0,
    wfh: 0,
    leave: 0,
    sickness: 0,
    nwd: 0,
    unassigned: 0,
    tracked: 0,
  };
  for (const iso of listDates(maxISO(startISO, recordingStartISO(profile)), endISO)) {
    const working = countsAsMetricsWorkingDay(profile, iso);
    if (profile.officeMarks.includes(iso) && working) {
      metrics.workingDays += 1;
      metrics.office += 1;
      metrics.tracked += 1;
    } else if (profile.wfhMarks.includes(iso) && working) {
      metrics.workingDays += 1;
      metrics.wfh += 1;
      metrics.tracked += 1;
    } else if (profile.leaveMarks.includes(iso) && working) {
      metrics.leave += 1;
    } else if (profile.sicknessMarks.includes(iso) && working) {
      metrics.sickness += 1;
    } else if (profile.nwdMarks.includes(iso)) {
      metrics.nwd += 1;
    } else if (working) {
      metrics.workingDays += 1;
      metrics.unassigned += 1;
    }
  }
  return metrics;
}

function officeDaysNeeded(metrics, target) {
  if (!Number.isFinite(target) || target <= 0 || target >= 100 || metrics.workingDays <= 0) {
    return 0;
  }
  return Math.max(0, Math.ceil((target / 100) * metrics.workingDays - metrics.office));
}

function getLeaveBreakdown(profile, year) {
  const today = getLondonTodayISO();
  const marks = (profile.leaveMarks || []).filter((d) => d.startsWith(`${year}-`));
  const taken = marks.filter((d) => d <= today).length;
  const booked = marks.length - taken;
  const allowance = getAllowance(profile, year);
  return {
    taken,
    booked,
    allowance,
    remaining: allowance - taken - booked,
  };
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
    const response = await fetchWithTimeout(HOLIDAY_FILE, {}, 15000);
    if (!response.ok) {
      throw new Error("Holiday file load failed");
    }
    return response.json();
  } catch {
    return {};
  }
}

window.startAttendanceApp = async function startAttendanceApp({ user }) {
  if (typeof window.wfhDebugLog === "function") {
    window.wfhDebugLog("startAttendanceApp", { email: user?.email });
  }
  window.__attendanceUser = user;

  await hydrateStateFromCloud(user);
  if (typeof window.wfhDebugLog === "function") {
    window.wfhDebugLog("hydrateStateFromCloud:done");
  }

  const token =
    window.__attendanceToken ||
    (typeof sessionStorage !== "undefined" && sessionStorage.getItem(WFH_JWT_SESSION_KEY));
  const userId = window.__attendanceUser?.id || user?.id;
  if (!token || !userId) {
    throw new Error("Your sign-in could not be completed. Please sign in again.");
  }
  window.__attendanceToken = token;
  if (!window.__attendanceUser?.id && user?.id) {
    window.__attendanceUser = user;
  }

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
    try {
      await bootstrap();
    } catch (bootErr) {
      console.error("[WFH] bootstrap failed:", bootErr);
      appBootstrapped = false;
      throw new Error(
        bootErr?.message || "The calendar failed to start. Try refreshing the page.",
      );
    }
  } else {
    renderAll();
  }
};
