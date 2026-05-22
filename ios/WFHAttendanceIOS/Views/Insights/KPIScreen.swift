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
        let leave = store.leaveBreakdown(year: month.year)
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
                        year: month.year,
                        mode: .recordedInformation,
                        compact: true,
                        dense: false,
                        highlightedQuarter: month.quarter,
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
            return month.year > store.profile.recordingStartMonthParts.year
        }
    }

    private var defaultVisibleMonth: Month {
        let current = Month.current()
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
            if month.year < startParts.year {
                month = Month(year: startParts.year, month: startParts.month)
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
            return countBankHolidays(from: yearMetricsStartISO(), through: "\(month.year)-12-31")
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
        let start = yearMetricsStartISO()
        let endOfYear = "\(month.year)-12-31"
        return store.metrics(from: start, through: endOfYear, respectingRecordingStart: true)
    }

    private func yearMetricsStartISO() -> String {
        let startParts = store.profile.recordingStartMonthParts
        guard month.year == startParts.year else {
            return "\(month.year)-01-01"
        }
        return DateHelpers.monthStartISO(store.profile.recordingStartMonthKey)
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
