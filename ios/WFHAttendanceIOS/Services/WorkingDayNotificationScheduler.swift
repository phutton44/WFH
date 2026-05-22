import UIKit
import UserNotifications

final class NotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}

enum WorkingDayNotificationScheduler {
    private static let identifierPrefix = "working-day-reminder-"
    private static let simulatorPreviewIdentifier = "working-day-reminder-simulator-preview"
    private static let reminderHour = 17
    private static let reminderMinute = 0
    private static let scheduleDaysAhead = 45

    static func scheduleUpcomingWorkingDayReminders(profile: AttendanceProfile) async {
        let center = UNUserNotificationCenter.current()
        let granted = await requestAuthorizationIfNeeded(center: center)
        guard granted else { return }

#if DEBUG
        scheduleSimulatorPreview(center: center, profile: profile)
#endif

        let pendingRequests = await center.pendingNotificationRequests()
        let oldReminderIds = pendingRequests
            .map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix) && $0 != simulatorPreviewIdentifier }
        center.removePendingNotificationRequests(withIdentifiers: oldReminderIds)

        let today = DateHelpers.todayISO()
        let nwd = Set(profile.nwdMarks)
        DateHelpers.forEachDate(from: today, through: endDateISO(from: today)) { iso in
            guard shouldScheduleReminder(for: iso, profile: profile, nwd: nwd) else { return }
            guard let trigger = reminderTrigger(for: iso) else { return }

            let content = UNMutableNotificationContent()
            content.title = "Please record your working day"
            content.body = readableDate(from: iso)
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "\(identifierPrefix)\(iso)",
                content: content,
                trigger: trigger
            )
            center.add(request)
        }
    }

#if DEBUG
    private static func scheduleSimulatorPreview(center: UNUserNotificationCenter, profile: AttendanceProfile) {
#if targetEnvironment(simulator)
        let today = DateHelpers.todayISO()
        guard shouldScheduleReminder(for: today, profile: profile, nwd: Set(profile.nwdMarks)) else { return }

        center.removePendingNotificationRequests(withIdentifiers: [simulatorPreviewIdentifier])

        let content = UNMutableNotificationContent()
        content.title = "Please record your working day"
        content.body = readableDate(from: today)
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 8, repeats: false)
        let request = UNNotificationRequest(identifier: simulatorPreviewIdentifier, content: content, trigger: trigger)
        center.add(request)
#endif
    }
#endif

    private static func requestAuthorizationIfNeeded(center: UNUserNotificationCenter) async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                return false
            }
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    private static func shouldScheduleReminder(for iso: String, profile: AttendanceProfile, nwd: Set<String>) -> Bool {
        guard iso >= DateHelpers.monthStartISO(profile.recordingStartMonthKey) else { return false }
        return DateHelpers.isAssignableWorkday(iso, excludingNWD: nwd)
    }

    private static func reminderTrigger(for iso: String) -> UNCalendarNotificationTrigger? {
        guard let date = DateHelpers.date(from: iso) else { return nil }
        var components = DateHelpers.gregorianCalendar.dateComponents([.year, .month, .day], from: date)
        components.hour = reminderHour
        components.minute = reminderMinute

        guard let reminderDate = DateHelpers.gregorianCalendar.date(from: components),
              reminderDate > Date() else { return nil }
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    }

    private static func endDateISO(from today: String) -> String {
        guard let start = DateHelpers.date(from: today),
              let end = DateHelpers.gregorianCalendar.date(byAdding: .day, value: scheduleDaysAhead, to: start) else {
            return today
        }
        let parts = DateHelpers.gregorianCalendar.dateComponents([.year, .month, .day], from: end)
        return DateHelpers.iso(year: parts.year ?? DateHelpers.currentYear, month: parts.month ?? DateHelpers.currentMonth, day: parts.day ?? 1)
    }

    private static func readableDate(from iso: String) -> String {
        guard let parts = isoParts(from: iso), (1...12).contains(parts.month) else { return iso }
        return "\(parts.day) \(DateHelpers.monthNames[parts.month - 1]) \(parts.year)"
    }

    private static func isoParts(from iso: String) -> (year: Int, month: Int, day: Int)? {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return (parts[0], parts[1], parts[2])
    }
}
