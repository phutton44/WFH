import Foundation

struct Month {
    let year: Int
    let month: Int

    init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    static func current() -> Month {
        let parts = DateHelpers.todayParts()
        return Month(year: parts.year, month: parts.month)
    }

    var title: String {
        "\(DateHelpers.monthNames[month - 1]) \(year)"
    }

    var startISO: String {
        DateHelpers.iso(year: year, month: month, day: 1)
    }

    var endISO: String {
        DateHelpers.iso(year: year, month: month, day: DateHelpers.daysInMonth(year: year, month: month))
    }

    var key: String {
        String(format: "%04d-%02d", year, month)
    }

    var quarter: Int {
        ((month - 1) / 3) + 1
    }

    init?(key: String) {
        guard let parts = DateHelpers.monthParts(fromKey: key) else { return nil }
        self.year = parts.year
        self.month = parts.month
    }

    var gridDays: [CalendarDay] {
        let lead = DateHelpers.mondayLeadSlots(year: year, month: month)
        let days = DateHelpers.daysInMonth(year: year, month: month)
        return (0..<lead).map { CalendarDay.empty(slot: $0) } +
            (1...days).map { day in
                let iso = DateHelpers.iso(year: year, month: month, day: day)
                return CalendarDay(id: iso, day: day, iso: iso)
            }
    }

    var assignableDates: [String] {
        (1...DateHelpers.daysInMonth(year: year, month: month))
            .map { DateHelpers.iso(year: year, month: month, day: $0) }
            .filter {
                !DateHelpers.isWeekend($0) && !DateHelpers.isBankHoliday($0)
            }
    }

    func shifted(by offset: Int) -> Month {
        var y = year
        var m = month + offset
        while m < 1 {
            y -= 1
            m += 12
        }
        while m > 12 {
            y += 1
            m -= 12
        }
        return Month(year: y, month: m)
    }

}

struct CalendarDay: Identifiable {
    let id: String
    let day: Int
    let iso: String?

    static func empty(slot: Int) -> CalendarDay {
        CalendarDay(id: "empty-\(slot)", day: 0, iso: nil)
    }
}

enum DateHelpers {
    static let weekdayLetters = ["M", "T", "W", "T", "F", "S", "S"]
    static let monthNames = Calendar.current.monthSymbols
    static let london = TimeZone(identifier: "Europe/London") ?? .current
    static let gregorianCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = london
        return calendar
    }()
    static let isoCalendar: Calendar = {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = london
        return calendar
    }()
    static let bankHolidays: Set<String> = [
        "2025-01-01", "2025-04-18", "2025-04-21", "2025-05-05", "2025-05-26", "2025-08-25", "2025-12-25", "2025-12-26",
        "2026-01-01", "2026-04-03", "2026-04-06", "2026-05-04", "2026-05-25", "2026-08-31", "2026-12-25", "2026-12-28",
        "2027-01-01", "2027-03-26", "2027-03-29", "2027-05-03", "2027-05-31", "2027-08-30", "2027-12-27", "2027-12-28"
    ]

    static var currentYear: Int {
        todayParts().year
    }

    static var currentMonth: Int {
        todayParts().month
    }

    static var currentMonthKey: String {
        let parts = todayParts()
        return monthKey(year: parts.year, month: parts.month)
    }

    static func todayParts() -> (year: Int, month: Int, day: Int) {
        let parts = gregorianCalendar.dateComponents([.year, .month, .day], from: Date())
        return (parts.year ?? 2026, parts.month ?? 1, parts.day ?? 1)
    }

    static func todayISO() -> String {
        let parts = todayParts()
        return iso(year: parts.year, month: parts.month, day: parts.day)
    }

    static var readableToday: String {
        let parts = todayParts()
        return "\(parts.day) \(monthNames[parts.month - 1]) \(parts.year)"
    }

    static func iso(year: Int, month: Int, day: Int) -> String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    static func monthKey(year: Int, month: Int) -> String {
        String(format: "%04d-%02d", year, min(max(month, 1), 12))
    }

    static func normalizedMonth(_ month: Int) -> Int {
        min(max(month, 1), 12)
    }

    static func monthStartISO(_ key: String) -> String {
        "\(validMonthKey(key) ?? currentMonthKey)-01"
    }

    static func validMonthKey(_ key: String?) -> String? {
        guard let key, let parts = monthParts(fromKey: key) else { return nil }
        return monthKey(year: parts.year, month: parts.month)
    }

    static func monthKey(fromISO iso: String) -> String? {
        validMonthKey(String(iso.prefix(7)))
    }

    static func monthParts(fromKey key: String) -> (year: Int, month: Int)? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2, (1...12).contains(parts[1]) else { return nil }
        return (parts[0], parts[1])
    }

    static func reportingYear(for iso: String, startMonth: Int) -> Int {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count >= 2 else { return currentYear }
        let month = normalizedMonth(startMonth)
        return parts[1] < month ? parts[0] - 1 : parts[0]
    }

    static func reportingYearBounds(year: Int, startMonth: Int) -> (startISO: String, endISO: String) {
        let month = normalizedMonth(startMonth)
        let start = iso(year: year, month: month, day: 1)
        let endYear = month == 1 ? year : year + 1
        let endMonth = month == 1 ? 12 : month - 1
        let end = iso(year: endYear, month: endMonth, day: daysInMonth(year: endYear, month: endMonth))
        return (start, end)
    }

    static func reportingYearMonths(year: Int, startMonth: Int) -> [Month] {
        let month = normalizedMonth(startMonth)
        return (0..<12).map { offset in
            let rawMonth = month + offset
            let displayYear = year + ((rawMonth - 1) / 12)
            let displayMonth = ((rawMonth - 1) % 12) + 1
            return Month(year: displayYear, month: displayMonth)
        }
    }

    static func reportingQuarter(for iso: String, startMonth: Int) -> Int {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count >= 2 else { return 1 }
        let month = normalizedMonth(startMonth)
        let offset = (parts[1] - month + 12) % 12
        return (offset / 3) + 1
    }

    static func date(from iso: String) -> Date? {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return gregorianCalendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static func daysInMonth(year: Int, month: Int) -> Int {
        let date = gregorianCalendar.date(from: DateComponents(year: year, month: month, day: 1))!
        return gregorianCalendar.range(of: .day, in: .month, for: date)?.count ?? 30
    }

    static func mondayLeadSlots(year: Int, month: Int) -> Int {
        let date = gregorianCalendar.date(from: DateComponents(year: year, month: month, day: 1))!
        let weekday = gregorianCalendar.component(.weekday, from: date)
        return (weekday + 5) % 7
    }

    static func isWeekend(_ iso: String) -> Bool {
        guard let date = date(from: iso) else { return false }
        let weekday = gregorianCalendar.component(.weekday, from: date)
        return weekday == 1 || weekday == 7
    }

    static func isoWeekNumber(_ iso: String) -> Int {
        guard let date = date(from: iso) else { return 0 }
        return isoCalendar.component(.weekOfYear, from: date)
    }

    static func isBankHoliday(_ iso: String) -> Bool {
        bankHolidays.contains(iso) && !isWeekend(iso)
    }

    static func isAssignableWorkday(_ iso: String, excludingNWD nwd: [String]) -> Bool {
        isAssignableWorkday(iso, excludingNWD: Set(nwd))
    }

    static func isAssignableWorkday(_ iso: String, excludingNWD nwd: Set<String>) -> Bool {
        !isWeekend(iso) && !isBankHoliday(iso) && !nwd.contains(iso)
    }

    static func isMetricsWorkingDay(_ iso: String, excludingNWD nwd: Set<String>) -> Bool {
        !isWeekend(iso) && !isBankHoliday(iso) && !nwd.contains(iso)
    }

    static func forEachDate(from start: String, through end: String, _ body: (String) -> Void) {
        guard var cursor = date(from: start), let endDate = date(from: end) else { return }
        while cursor <= endDate {
            let parts = gregorianCalendar.dateComponents([.year, .month, .day], from: cursor)
            body(iso(year: parts.year ?? 0, month: parts.month ?? 1, day: parts.day ?? 1))
            cursor = gregorianCalendar.date(byAdding: .day, value: 1, to: cursor) ?? endDate.addingTimeInterval(1)
        }
    }
}
