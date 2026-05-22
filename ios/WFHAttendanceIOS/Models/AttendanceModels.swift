import Foundation
import SwiftUI

struct SocialAuthRequest: Encodable {
    let idToken: String
}

struct GoogleTokenResponse: Decodable {
    let idToken: String

    enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
    }
}

struct GoogleTokenError: Decodable {
    let error: String
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

struct AuthResponse: Decodable {
    let token: String
    let user: AuthUser
}

struct AuthUser: Codable {
    let id: String
    let email: String

    var displayName: String {
        let localPart = email.split(separator: "@").first.map(String.init) ?? ""
        let cleaned = localPart
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        let words = cleaned
            .split(separator: " ")
            .map { word in
                word.prefix(1).uppercased() + word.dropFirst().lowercased()
            }
        return words.isEmpty ? email : words.joined(separator: " ")
    }
}

struct StateResponse: Decodable {
    let payload: AttendanceState?
}

struct SaveStateRequest: Encodable {
    let payload: AttendanceState
}

struct SaveStateResponse: Decodable {
    let ok: Bool
}

struct AttendanceState: Codable {
    var activeProfileId: String
    var profiles: [AttendanceProfile]

    var activeProfile: AttendanceProfile {
        profiles.first(where: { $0.id == activeProfileId }) ?? profiles[0]
    }

    static func defaultState() -> AttendanceState {
        let profile = AttendanceProfile.defaultProfile()
        return AttendanceState(activeProfileId: profile.id, profiles: [profile])
    }

    func normalized() -> AttendanceState {
        var copy = self
        copy.profiles = copy.profiles.map { $0.normalized() }
        if !copy.profiles.contains(where: { $0.id == copy.activeProfileId }), let first = copy.profiles.first {
            copy.activeProfileId = first.id
        }
        if copy.profiles.isEmpty {
            return AttendanceState.defaultState()
        }
        return copy
    }

    mutating func set(date: String, to kind: DayKind, normalizing: Bool = true) throws {
        guard let index = profiles.firstIndex(where: { $0.id == activeProfileId }) else { return }
        try profiles[index].set(date: date, to: kind, normalizing: normalizing)
    }

    mutating func normalizeActiveProfile() {
        guard let index = profiles.firstIndex(where: { $0.id == activeProfileId }) else { return }
        profiles[index] = profiles[index].normalized()
    }

    func leaveShortfall(for dates: Set<String>) -> LeaveShortfallWarning? {
        activeProfile.leaveShortfall(for: dates)
    }

    func hasAssignedDays(in dates: Set<String>) -> Bool {
        activeProfile.hasAssignedDays(in: dates)
    }

    mutating func updateSettings(name: String, targetPct: Double, leaveAllowance: Int, year: Int, recordingStartMonth: String) {
        guard let index = profiles.firstIndex(where: { $0.id == activeProfileId }) else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            profiles[index].name = trimmedName
        }
        profiles[index].settings.targetPct = targetPct
        profiles[index].settings.leaveAllowances[String(year)] = leaveAllowance
        profiles[index].settings.recordingStartMonth = DateHelpers.validMonthKey(recordingStartMonth) ?? DateHelpers.currentMonthKey
    }

    mutating func setMonth(_ monthKey: String, locked: Bool) {
        guard let index = profiles.firstIndex(where: { $0.id == activeProfileId }) else { return }
        profiles[index].setMonth(monthKey, locked: locked)
    }

    mutating func repairDefaultProfileName(using name: String) {
        guard let index = profiles.firstIndex(where: { $0.id == activeProfileId }) else { return }
        let current = profiles[index].name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard current.isEmpty || current == "Default profile" else { return }
        let replacement = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !replacement.isEmpty else { return }
        profiles[index].name = replacement
    }

    func metrics(from start: String, through end: String) -> Metrics {
        activeProfile.metrics(from: start, through: end, respectingRecordingStart: true)
    }

    func metrics(from start: String, through end: String, respectingRecordingStart: Bool) -> Metrics {
        activeProfile.metrics(from: start, through: end, respectingRecordingStart: respectingRecordingStart)
    }

    func leaveBreakdown(year: Int, today: String) -> LeaveBreakdown {
        activeProfile.leaveBreakdown(year: year, today: today)
    }
}

struct AttendanceProfile: Codable {
    var id: String
    var name: String
    var createdAtISO: String?
    var settings: ProfileSettings
    var officeMarks: [String]
    var leaveMarks: [String]
    var wfhMarks: [String]
    var sicknessMarks: [String]
    var nwdMarks: [String]
    var lockedMonths: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case createdAtISO
        case settings
        case officeMarks
        case leaveMarks
        case wfhMarks
        case sicknessMarks
        case nwdMarks
        case lockedMonths
    }

    init(
        id: String,
        name: String,
        createdAtISO: String?,
        settings: ProfileSettings,
        officeMarks: [String],
        leaveMarks: [String],
        wfhMarks: [String],
        sicknessMarks: [String],
        nwdMarks: [String],
        lockedMonths: [String]
    ) {
        self.id = id
        self.name = name
        self.createdAtISO = createdAtISO
        self.settings = settings
        self.officeMarks = officeMarks
        self.leaveMarks = leaveMarks
        self.wfhMarks = wfhMarks
        self.sicknessMarks = sicknessMarks
        self.nwdMarks = nwdMarks
        self.lockedMonths = lockedMonths
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? "p-\(Int(Date().timeIntervalSince1970))"
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Default profile"
        createdAtISO = try container.decodeIfPresent(String.self, forKey: .createdAtISO)
        settings = try container.decodeIfPresent(ProfileSettings.self, forKey: .settings) ?? ProfileSettings.defaultSettings()
        officeMarks = try container.decodeIfPresent([String].self, forKey: .officeMarks) ?? []
        leaveMarks = try container.decodeIfPresent([String].self, forKey: .leaveMarks) ?? []
        wfhMarks = try container.decodeIfPresent([String].self, forKey: .wfhMarks) ?? []
        sicknessMarks = try container.decodeIfPresent([String].self, forKey: .sicknessMarks) ?? []
        nwdMarks = try container.decodeIfPresent([String].self, forKey: .nwdMarks) ?? []
        lockedMonths = try container.decodeIfPresent([String].self, forKey: .lockedMonths) ?? []
    }

    static func defaultProfile() -> AttendanceProfile {
        AttendanceProfile(
            id: "p-\(Int(Date().timeIntervalSince1970))",
            name: "Default profile",
            createdAtISO: DateHelpers.todayISO(),
            settings: ProfileSettings(
                targetPct: 40,
                leaveAllowances: [String(DateHelpers.currentYear): 25],
                recordingStartMonth: DateHelpers.currentMonthKey
            ),
            officeMarks: [],
            leaveMarks: [],
            wfhMarks: [],
            sicknessMarks: [],
            nwdMarks: [],
            lockedMonths: []
        )
    }

    func normalized() -> AttendanceProfile {
        var copy = self
        copy.officeMarks = Array(Set(copy.officeMarks)).sorted()
        copy.leaveMarks = Array(Set(copy.leaveMarks)).sorted()
        copy.wfhMarks = Array(Set(copy.wfhMarks)).sorted()
        copy.sicknessMarks = Array(Set(copy.sicknessMarks)).sorted()
        copy.nwdMarks = Array(Set(copy.nwdMarks)).sorted()
        copy.lockedMonths = Array(Set(copy.lockedMonths)).sorted()
        if copy.createdAtISO == nil {
            copy.createdAtISO = DateHelpers.todayISO()
        }
        return copy
    }

    func allowance(for year: Int) -> Int {
        settings.leaveAllowances[String(year)]
            ?? settings.leaveAllowances[String(DateHelpers.currentYear)]
            ?? 25
    }

    var recordingStartMonthKey: String {
        DateHelpers.validMonthKey(settings.recordingStartMonth)
            ?? earliestMarkedMonthKey
            ?? createdAtISO.flatMap { DateHelpers.monthKey(fromISO: $0) }
            ?? DateHelpers.currentMonthKey
    }

    var recordingStartMonthParts: (year: Int, month: Int) {
        DateHelpers.monthParts(fromKey: recordingStartMonthKey)
            ?? (DateHelpers.currentYear, DateHelpers.currentMonth)
    }

    private var earliestMarkedMonthKey: String? {
        (officeMarks + leaveMarks + wfhMarks + sicknessMarks + nwdMarks)
            .compactMap(DateHelpers.monthKey(fromISO:))
            .min()
    }

    func isMonthLocked(_ monthKey: String) -> Bool {
        lockedMonths.contains(monthKey)
    }

    func isBeforeRecordingStart(_ monthKey: String) -> Bool {
        monthKey < recordingStartMonthKey
    }

    mutating func setMonth(_ monthKey: String, locked: Bool) {
        if locked {
            lockedMonths.append(monthKey)
        } else {
            lockedMonths.removeAll { $0 == monthKey }
        }
        self = normalized()
    }

    func leaveShortfall(for dates: Set<String>) -> LeaveShortfallWarning? {
        let marks = AttendanceMarkIndex(profile: self)
        let effectiveNWDMarks = marks.nwd.subtracting(dates)
        var requestedByYear: [Int: Int] = [:]

        for date in dates {
            guard DateHelpers.isAssignableWorkday(date, excludingNWD: effectiveNWDMarks) else { continue }
            guard marks.kind(for: date) != .leave else { continue }
            let year = Int(date.prefix(4)) ?? DateHelpers.currentYear
            requestedByYear[year, default: 0] += 1
        }

        for year in requestedByYear.keys.sorted() {
            let requested = requestedByYear[year] ?? 0
            let used = leaveMarks.filter { $0.hasPrefix("\(year)-") }.count
            let remaining = max(allowance(for: year) - used, 0)
            guard requested > remaining else { continue }
            return LeaveShortfallWarning(
                year: year,
                remaining: remaining,
                requested: requested,
                deficit: requested - remaining
            )
        }

        return nil
    }

    func kind(for date: String) -> DayKind {
        AttendanceMarkIndex(profile: self).kind(for: date)
    }

    func kinds(for dates: [String]) -> [String: DayKind] {
        let marks = AttendanceMarkIndex(profile: self)
        return Dictionary(uniqueKeysWithValues: dates.map { ($0, marks.kind(for: $0)) })
    }

    func hasAssignedDays(in dates: Set<String>) -> Bool {
        let marks = AttendanceMarkIndex(profile: self)
        return dates.contains { date in
            switch marks.kind(for: date) {
            case .office, .wfh, .leave, .sickness, .nwd:
                return true
            case .unassigned, .weekend, .bankHoliday:
                return false
            }
        }
    }

    mutating func set(date: String, to kind: DayKind, normalizing: Bool = true) throws {
        let monthKey = String(date.prefix(7))
        guard !isBeforeRecordingStart(monthKey) else {
            throw AppError.message("This month is before your recording start date.")
        }
        guard !isMonthLocked(monthKey) else {
            throw AppError.message("This month is locked. Unlock it before editing.")
        }
        clear(date)
        switch kind {
        case .unassigned:
            break
        case .nwd:
            guard !DateHelpers.isWeekend(date), !DateHelpers.isBankHoliday(date) else {
                throw AppError.message("NWD can only be set on a weekday.")
            }
            nwdMarks.append(date)
        case .office, .wfh, .leave, .sickness:
            guard DateHelpers.isAssignableWorkday(date, excludingNWD: nwdMarks) else {
                throw AppError.message("That day is not an assignable working day.")
            }
            if kind == .leave {
                let year = Int(date.prefix(4)) ?? DateHelpers.currentYear
                let used = leaveMarks.filter { $0.hasPrefix("\(year)-") }.count
                guard used < allowance(for: year) else {
                    throw AppError.message("Leave allowance reached for \(year).")
                }
            }
            switch kind {
            case .office: officeMarks.append(date)
            case .wfh: wfhMarks.append(date)
            case .leave: leaveMarks.append(date)
            case .sickness: sicknessMarks.append(date)
            default: break
            }
        case .weekend, .bankHoliday:
            break
        }
        if normalizing {
            self = normalized()
        }
    }

    private mutating func clear(_ date: String) {
        officeMarks.removeAll { $0 == date }
        leaveMarks.removeAll { $0 == date }
        wfhMarks.removeAll { $0 == date }
        sicknessMarks.removeAll { $0 == date }
        nwdMarks.removeAll { $0 == date }
    }

    func metrics(from start: String, through end: String) -> Metrics {
        metrics(from: start, through: end, respectingRecordingStart: true)
    }

    func metrics(from start: String, through end: String, respectingRecordingStart: Bool) -> Metrics {
        let marks = AttendanceMarkIndex(profile: self)
        var metrics = Metrics()
        let effectiveStart = respectingRecordingStart ? max(start, DateHelpers.monthStartISO(recordingStartMonthKey)) : start
        guard effectiveStart <= end else { return metrics }
        DateHelpers.forEachDate(from: effectiveStart, through: end) { date in
            let working = DateHelpers.isMetricsWorkingDay(date, excludingNWD: marks.nwd)
            switch marks.kind(for: date) {
            case .office where working:
                metrics.workingDays += 1
                metrics.office += 1
                metrics.tracked += 1
            case .wfh where working:
                metrics.workingDays += 1
                metrics.wfh += 1
                metrics.tracked += 1
            case .leave where working:
                metrics.leave += 1
            case .sickness where working:
                metrics.workingDays += 1
                metrics.sickness += 1
            case .nwd:
                metrics.nwd += 1
            case .unassigned where working:
                metrics.workingDays += 1
                metrics.unassigned += 1
            default:
                break
            }
        }
        return metrics
    }

    func leaveBreakdown(year: Int, today: String) -> LeaveBreakdown {
        var taken = 0
        var booked = 0
        for date in leaveMarks where date.hasPrefix("\(year)-") {
            if date <= today {
                taken += 1
            } else {
                booked += 1
            }
        }
        let allowance = allowance(for: year)
        return LeaveBreakdown(
            taken: taken,
            booked: booked,
            allowance: allowance,
            remaining: allowance - taken - booked
        )
    }
}

struct AttendanceMarkIndex {
    let office: Set<String>
    let leave: Set<String>
    let wfh: Set<String>
    let sickness: Set<String>
    let nwd: Set<String>

    init(profile: AttendanceProfile) {
        office = Set(profile.officeMarks)
        leave = Set(profile.leaveMarks)
        wfh = Set(profile.wfhMarks)
        sickness = Set(profile.sicknessMarks)
        nwd = Set(profile.nwdMarks)
    }

    func kind(for date: String) -> DayKind {
        if office.contains(date) { return .office }
        if leave.contains(date) { return .leave }
        if sickness.contains(date) { return .sickness }
        if wfh.contains(date) { return .wfh }
        if DateHelpers.isBankHoliday(date) { return .bankHoliday }
        if DateHelpers.isWeekend(date) { return .weekend }
        if nwd.contains(date) { return .nwd }
        return .unassigned
    }
}

struct ProfileSettings: Codable {
    var targetPct: Double
    var leaveAllowances: [String: Int]
    var recordingStartMonth: String?

    init(targetPct: Double, leaveAllowances: [String: Int], recordingStartMonth: String? = nil) {
        self.targetPct = targetPct
        self.leaveAllowances = leaveAllowances
        self.recordingStartMonth = recordingStartMonth
    }

    static func defaultSettings() -> ProfileSettings {
        ProfileSettings(
            targetPct: 40,
            leaveAllowances: [String(DateHelpers.currentYear): 25],
            recordingStartMonth: DateHelpers.currentMonthKey
        )
    }
}

struct Metrics {
    var workingDays = 0
    var office = 0
    var wfh = 0
    var leave = 0
    var sickness = 0
    var nwd = 0
    var unassigned = 0
    var tracked = 0

    var officeShare: Double? {
        guard tracked > 0 else { return nil }
        return Double(office) / Double(tracked) * 100
    }

    var monthOfficeShare: Double {
        guard workingDays > 0 else { return 0 }
        return Double(office) / Double(workingDays) * 100
    }

    var assignedWorkingDays: Int {
        office + wfh + sickness
    }

    func officeDaysNeededForMonthTarget(_ target: Double) -> Int {
        guard target > 0, target < 100, workingDays > 0 else { return 0 }
        let required = (target / 100) * Double(workingDays) - Double(office)
        return max(0, Int(ceil(required)))
    }
}

struct LeaveBreakdown {
    let taken: Int
    let booked: Int
    let allowance: Int
    let remaining: Int
}

enum DayKind: String, Codable, Identifiable {
    case office
    case wfh
    case leave
    case sickness
    case nwd
    case unassigned
    case weekend
    case bankHoliday

    var id: String { rawValue }

    var title: String {
        switch self {
        case .office: "Office"
        case .wfh: "Work from home"
        case .leave: "Annual leave"
        case .sickness: "Sickness"
        case .nwd: "Non-working day"
        case .unassigned: "Unassigned"
        case .weekend: "Weekend"
        case .bankHoliday: "Bank holiday"
        }
    }

    var actionTitle: String {
        self == .unassigned ? "Clear" : title
    }

    var tileLabel: String {
        switch self {
        case .office: "OFFICE"
        case .wfh: "WFH"
        case .leave: "LEAVE"
        case .sickness: "SICK"
        case .nwd: "NWD"
        case .bankHoliday: "BH"
        case .unassigned: ""
        case .weekend: ""
        }
    }

    var shortTitle: String {
        switch self {
        case .office: "Office"
        case .wfh: "WFH"
        case .leave: "Annual leave"
        case .sickness: "Sickness"
        case .nwd: "Non-working"
        case .unassigned: "Clear"
        case .weekend: "Weekend"
        case .bankHoliday: "Bank holiday"
        }
    }

    var icon: String {
        switch self {
        case .office: "building.2.fill"
        case .wfh: "house.fill"
        case .leave: "sun.max.fill"
        case .sickness: "cross.case.fill"
        case .nwd: "moon.zzz.fill"
        case .unassigned: "xmark.circle"
        case .weekend: "calendar.badge.clock"
        case .bankHoliday: "flag.fill"
        }
    }

    var sheetIcon: String {
        switch self {
        case .office: "building.columns"
        case .wfh: "house"
        case .leave: "tree"
        case .sickness: "thermometer.medium"
        case .nwd: "minus"
        case .unassigned: "xmark"
        case .weekend: "calendar.badge.clock"
        case .bankHoliday: "star"
        }
    }

    var color: Color {
        switch self {
        case .office: .officeBlue
        case .wfh: .wfhPurple
        case .leave: .leaveOrange
        case .sickness: .holidayGreen
        case .nwd: .nwdGray
        case .unassigned: .blue
        case .weekend: .gray
        case .bankHoliday: .sickRed
        }
    }

    var insightColor: Color {
        switch self {
        case .office: .officeBlue
        case .wfh: .wfhPurple
        case .leave: .leaveOrange
        case .sickness: .holidayGreen
        case .nwd: .nwdGray
        case .bankHoliday: .sickRed
        case .unassigned, .weekend: Color.cardBackgroundElevated
        }
    }
}
