import SwiftUI

@main
struct WFHAttendanceApp: App {
    @UIApplicationDelegateAdaptor(NotificationDelegate.self) private var notificationDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
