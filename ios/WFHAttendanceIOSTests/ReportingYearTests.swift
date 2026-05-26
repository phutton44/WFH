import XCTest

final class ReportingYearTests: XCTestCase {
    func testCalendarYearDefaultsToJanuary() {
        let profile = AttendanceProfile.defaultProfile()

        XCTAssertEqual(profile.yearStartMonth, 1)
        XCTAssertEqual(profile.reportingYear(for: "2026-01-01"), 2026)
        XCTAssertEqual(profile.reportingYear(for: "2026-12-31"), 2026)

        let bounds = profile.reportingYearBounds(for: 2026)
        XCTAssertEqual(bounds.startISO, "2026-01-01")
        XCTAssertEqual(bounds.endISO, "2026-12-31")

        let months = profile.reportingYearMonths(for: 2026).map(\.key)
        XCTAssertEqual(months.first, "2026-01")
        XCTAssertEqual(months.last, "2026-12")
    }

    func testJulyReportingYearBoundariesAndTotals() throws {
        var state = julyReportingYearState()

        XCTAssertEqual(state.activeProfile.reportingYear(for: "2026-06-30"), 2025)
        XCTAssertEqual(state.activeProfile.reportingYear(for: "2026-07-01"), 2026)

        let bounds2026 = state.activeProfile.reportingYearBounds(for: 2026)
        XCTAssertEqual(bounds2026.startISO, "2026-07-01")
        XCTAssertEqual(bounds2026.endISO, "2027-06-30")

        let months2026 = state.activeProfile.reportingYearMonths(for: 2026).map(\.key)
        XCTAssertEqual(months2026.first, "2026-07")
        XCTAssertEqual(months2026.last, "2027-06")

        try state.set(date: "2026-06-29", to: .leave)
        try state.set(date: "2026-07-01", to: .leave)
        try state.set(date: "2027-06-30", to: .leave)

        let leave2025 = state.leaveBreakdown(year: 2025, today: "2026-07-15")
        XCTAssertEqual(leave2025.taken, 1)
        XCTAssertEqual(leave2025.booked, 0)
        XCTAssertEqual(leave2025.allowance, 1)
        XCTAssertEqual(leave2025.remaining, 0)

        let leave2026 = state.leaveBreakdown(year: 2026, today: "2026-07-15")
        XCTAssertEqual(leave2026.taken, 1)
        XCTAssertEqual(leave2026.booked, 1)
        XCTAssertEqual(leave2026.allowance, 2)
        XCTAssertEqual(leave2026.remaining, 0)

        XCTAssertThrowsError(try state.set(date: "2027-06-29", to: .leave)) { error in
            XCTAssertTrue(error.localizedDescription.contains("2026"))
        }

        try state.set(date: "2026-07-02", to: .office)
        try state.set(date: "2026-07-03", to: .wfh)
        try state.set(date: "2027-06-29", to: .office)

        let metrics2026 = state.metrics(from: bounds2026.startISO, through: bounds2026.endISO, respectingRecordingStart: true)
        XCTAssertEqual(metrics2026.office, 2)
        XCTAssertEqual(metrics2026.wfh, 1)
        XCTAssertEqual(metrics2026.leave, 2)
    }

    func testUpdateSettingsPersistsReportingYearStartAndAllowance() {
        var state = AttendanceState.defaultState()

        state.updateSettings(
            name: "Test User",
            targetPct: 60,
            leaveAllowance: 30,
            year: 2026,
            recordingStartMonth: "2026-04",
            yearStartMonth: 7
        )

        XCTAssertEqual(state.activeProfile.name, "Test User")
        XCTAssertEqual(state.activeProfile.settings.targetPct, 60)
        XCTAssertEqual(state.activeProfile.allowance(for: 2026), 30)
        XCTAssertEqual(state.activeProfile.recordingStartMonthKey, "2026-04")
        XCTAssertEqual(state.activeProfile.yearStartMonth, 7)
    }

    func testRecordingStartExcludesEarlierMonthsFromMetrics() {
        var profile = AttendanceProfile.defaultProfile()
        profile.settings = ProfileSettings(
            targetPct: 50,
            leaveAllowances: ["2026": 25],
            recordingStartMonth: "2026-03",
            yearStartMonth: 1
        )
        profile.officeMarks = ["2026-02-02", "2026-03-02"]

        let respectingStart = profile.metrics(from: "2026-01-01", through: "2026-12-31", respectingRecordingStart: true)
        let ignoringStart = profile.metrics(from: "2026-01-01", through: "2026-12-31", respectingRecordingStart: false)

        XCTAssertEqual(respectingStart.office, 1)
        XCTAssertEqual(ignoringStart.office, 2)
    }

    func testLockedMonthBlocksEdits() async {
        var state = julyReportingYearState()
        state.setMonth("2026-07", locked: true)

        XCTAssertThrowsError(try state.set(date: "2026-07-02", to: .office)) { error in
            XCTAssertTrue(error.localizedDescription.contains("locked"))
        }
    }

    func testLeaveShortfallUsesConfiguredReportingYear() throws {
        var state = julyReportingYearState()
        try state.set(date: "2026-07-01", to: .leave)
        try state.set(date: "2027-06-30", to: .leave)

        let warning = state.leaveShortfall(for: ["2027-06-29"])

        XCTAssertEqual(warning?.year, 2026)
        XCTAssertEqual(warning?.remaining, 0)
        XCTAssertEqual(warning?.requested, 1)
        XCTAssertEqual(warning?.deficit, 1)
    }

    func testMetricsExcludeWeekendsBankHolidaysAndNonWorkingDays() {
        var profile = AttendanceProfile.defaultProfile()
        profile.settings = ProfileSettings(
            targetPct: 50,
            leaveAllowances: ["2026": 25],
            recordingStartMonth: "2026-07",
            yearStartMonth: 7
        )
        profile.officeMarks = [
            "2026-07-04", // Saturday
            "2026-07-06", // counted weekday
            "2026-08-31"  // bank holiday
        ]
        profile.nwdMarks = ["2026-07-07"]

        let metrics = profile.metrics(from: "2026-07-01", through: "2026-08-31", respectingRecordingStart: true)

        XCTAssertEqual(metrics.office, 1)
        XCTAssertEqual(metrics.nwd, 1)
        XCTAssertGreaterThan(metrics.workingDays, metrics.office)
    }

    private func julyReportingYearState() -> AttendanceState {
        var state = AttendanceState.defaultState()
        state.profiles[0].settings = ProfileSettings(
            targetPct: 50,
            leaveAllowances: ["2025": 1, "2026": 2],
            recordingStartMonth: "2026-01",
            yearStartMonth: 7
        )
        return state
    }
}
