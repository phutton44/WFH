import SwiftUI

struct KPIScreen: View {
    @EnvironmentObject private var store: AttendanceStore
    let scope: InsightScope
    @Binding var month: Month
    @State private var rangeMode: InsightRangeMode = .userRecorded
    @State private var generatedReport: GeneratedYearReport?
    @State private var pdfErrorMessage = ""
    @State private var showingPDFError = false

    var body: some View {
        let activeMetrics = metricsForActiveSelection()
        let monthOutlookMetrics = metricsForFullMonthOutlook()
        let monthToDateEnd = monthToDateEndISO()
        let bankHolidayCount = bankHolidayCountForActiveSelection()
        let reportYear = scope == .year ? month.year : store.profile.reportingYear(for: month.startISO)
        let leave = store.leaveBreakdown(year: reportYear)
        let activeShare = activeMetrics.monthOfficeShare
        let target = store.profile.settings.targetPct
        let rangeTitle = scope == .month
            ? (rangeMode == .yearToDate ? "Month-to-Date" : "User Recorded")
            : "Year"
        let canGoPrevious = canMoveToPreviousPeriod

        ScrollView(showsIndicators: false) {
            VStack(spacing: scope == .month ? 6 : 9) {
                InsightsMonthHeader(
                    month: month,
                    scope: scope,
                    previous: { moveInsightsPeriod(-1) },
                    next: { moveInsightsPeriod(1) },
                    today: { month = defaultVisibleMonth },
                    canGoPrevious: canGoPrevious,
                    printReport: {
                        printReport()
                    }
                )

                if scope == .month {
                    Picker("Range", selection: $rangeMode) {
                        Text("User Recorded").tag(InsightRangeMode.userRecorded)
                        Text("Month-to-Date").tag(InsightRangeMode.yearToDate)
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                }

                InsightDonutHero(
                    month: month,
                    title: "\(rangeTitle) insight",
                    metrics: activeMetrics,
                    outlookMetrics: scope == .month && rangeMode == .yearToDate ? monthOutlookMetrics : nil,
                    percent: activeShare,
                    target: target,
                    compact: false,
                    dense: false
                )

                if scope == .month {
                    WeekByWeekCard(
                        month: month,
                        compact: true,
                        dense: false,
                        cutoffISO: rangeMode == .yearToDate ? monthToDateEnd : nil
                    )
                    QuarterScoreboardCard(
                        year: reportYear,
                        mode: .recordedInformation,
                        compact: true,
                        dense: false,
                        highlightedQuarter: DateHelpers.reportingQuarter(for: month.startISO, startMonth: store.profile.yearStartMonth),
                        cutoffISO: rangeMode == .yearToDate ? monthToDateEnd : nil
                    )
                    MonthDetailsCard(
                        month: month,
                        metrics: activeMetrics,
                        leave: leave,
                        bankHolidayCount: bankHolidayCount,
                        compact: true,
                        dense: false,
                        rangeLabel: rangeMode == .yearToDate ? "Month-to-Date" : nil
                    )
                } else {
                    QuarterScoreboardCard(
                        year: month.year,
                        mode: .recordedInformation,
                        compact: true,
                        dense: false
                    )
                    YearCompositionLeaveCard(
                        year: month.year,
                        metrics: activeMetrics,
                        leave: leave,
                        bankHolidayCount: bankHolidayCount,
                        rangeLabel: nil
                    )
                }
            }
            .padding(.horizontal, scope == .month ? 10 : 12)
            .padding(.top, scope == .month ? 3 : 6)
            .padding(.bottom, scope == .month ? 10 : 90)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $generatedReport) { report in
            YearReportPreviewSheet(url: report.url, title: report.title)
        }
        .alert("Could not create PDF", isPresented: $showingPDFError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(pdfErrorMessage)
        }
        .onAppear {
            snapToRecordingStartIfNeeded()
        }
        .onChange(of: store.profile.recordingStartMonthKey) { _, _ in
            snapToRecordingStartIfNeeded()
        }
        .refreshable {
            await store.loadState()
        }
        .horizontalSwipe { direction in
            guard direction > 0 || canMoveToPreviousPeriod else { return }
            moveInsightsPeriod(direction)
        }
    }

    private func moveInsightsPeriod(_ direction: Int) {
        guard direction > 0 || canMoveToPreviousPeriod else { return }
        if scope == .year {
            month = Month(year: month.year + direction, month: month.month)
        } else {
            month = month.shifted(by: direction)
        }
        snapToRecordingStartIfNeeded()
    }

    private func printReport() {
        do {
            switch scope {
            case .month:
                let url = try MonthReportPDFRenderer.render(
                    month: month,
                    profile: store.profile,
                    userEmail: store.user?.email,
                    rangeMode: rangeMode,
                    cutoffISO: rangeMode == .yearToDate ? monthToDateEndISO() : nil
                )
                generatedReport = GeneratedYearReport(url: url, title: "Month Report")
            case .year:
                let url = try YearReportPDFRenderer.render(
                    year: month.year,
                    profile: store.profile,
                    userEmail: store.user?.email
                )
                generatedReport = GeneratedYearReport(url: url, title: "Year Report")
            }
        } catch {
            pdfErrorMessage = error.localizedDescription
            showingPDFError = true
        }
    }

    private var canMoveToPreviousPeriod: Bool {
        switch scope {
        case .month:
            return month.key > store.profile.recordingStartMonthKey
        case .year:
            let previousBounds = store.profile.reportingYearBounds(for: month.year - 1)
            return previousBounds.endISO >= DateHelpers.monthStartISO(store.profile.recordingStartMonthKey)
        }
    }

    private var defaultVisibleMonth: Month {
        let current = Month.current()
        if scope == .year {
            let reportYear = store.profile.reportingYear(for: DateHelpers.todayISO())
            return Month(year: reportYear, month: current.month)
        }
        guard current.key < store.profile.recordingStartMonthKey,
              let startMonth = Month(key: store.profile.recordingStartMonthKey) else { return current }
        return startMonth
    }

    private func snapToRecordingStartIfNeeded() {
        let startParts = store.profile.recordingStartMonthParts
        switch scope {
        case .month:
            guard month.key < store.profile.recordingStartMonthKey,
                  let startMonth = Month(key: store.profile.recordingStartMonthKey) else { return }
            month = startMonth
        case .year:
            let bounds = store.profile.reportingYearBounds(for: month.year)
            if bounds.endISO < DateHelpers.monthStartISO(store.profile.recordingStartMonthKey) {
                let firstYear = store.profile.reportingYear(for: DateHelpers.monthStartISO(store.profile.recordingStartMonthKey))
                month = Month(year: firstYear, month: startParts.month)
            }
        }
    }

    private func metricsForActiveSelection() -> Metrics {
        switch scope {
        case .month:
            return metricsForMonth()
        case .year:
            return metricsForYear()
        }
    }

    private func bankHolidayCountForActiveSelection() -> Int {
        switch scope {
        case .month:
            let end = rangeMode == .yearToDate ? (monthToDateEndISO() ?? month.endISO) : month.endISO
            return countBankHolidays(from: month.startISO, through: end)
        case .year:
            let bounds = yearMetricsBounds()
            return countBankHolidays(from: bounds.startISO, through: bounds.endISO)
        }
    }

    private func metricsForMonth() -> Metrics {
        if rangeMode == .userRecorded {
            return store.metrics(from: month.startISO, through: month.endISO, respectingRecordingStart: true)
        }
        guard let end = monthToDateEndISO() else { return Metrics() }
        return store.metrics(from: month.startISO, through: end, respectingRecordingStart: true)
    }

    private func monthToDateEndISO() -> String? {
        let end = min(DateHelpers.todayISO(), month.endISO)
        return end >= month.startISO ? end : nil
    }

    private func metricsForFullMonthOutlook() -> Metrics {
        store.metrics(from: month.startISO, through: month.endISO, respectingRecordingStart: true)
    }

    private func metricsForYear() -> Metrics {
        let bounds = yearMetricsBounds()
        return store.metrics(from: bounds.startISO, through: bounds.endISO, respectingRecordingStart: true)
    }

    private func yearMetricsBounds() -> (startISO: String, endISO: String) {
        let bounds = store.profile.reportingYearBounds(for: month.year)
        let recordingStart = DateHelpers.monthStartISO(store.profile.recordingStartMonthKey)
        return (max(bounds.startISO, recordingStart), bounds.endISO)
    }

    private func countBankHolidays(from start: String, through end: String) -> Int {
        guard end >= start else { return 0 }
        var count = 0
        DateHelpers.forEachDate(from: start, through: end) { iso in
            if DateHelpers.isBankHoliday(iso) {
                count += 1
            }
        }
        return count
    }
}

enum InsightScope {
    case month
    case year
}

enum InsightRangeMode {
    case userRecorded
    case yearToDate
}
