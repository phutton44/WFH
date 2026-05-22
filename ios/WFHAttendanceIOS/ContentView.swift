import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearanceMode") private var appearanceModeRaw = AppAppearanceMode.dark.rawValue
    @StateObject private var store = AttendanceStore()

    var body: some View {
        Group {
            if store.isSignedIn {
                AttendanceHomeView()
                    .environmentObject(store)
            } else {
                AuthView()
                    .environmentObject(store)
            }
        }
        .task {
            UIApplication.shared.isIdleTimerDisabled = false
            await store.resumeSession()
        }
        .task(id: store.isSignedIn && scenePhase == .active) {
            guard store.isSignedIn, scenePhase == .active else { return }
            await store.startTimelySyncLoop()
        }
        .task(id: notificationScheduleKey) {
            guard store.isSignedIn, scenePhase == .active else { return }
            await WorkingDayNotificationScheduler.scheduleUpcomingWorkingDayReminders(profile: store.profile)
        }
        .alert("Something went wrong", isPresented: $store.showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage)
        }
        .overlay {
            if store.bulkUndo != nil {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .top) {
            if let undo = store.bulkUndo {
                BulkUndoBar(
                    message: undo.message,
                    undo: {
                        Task { await store.restoreBulkUndo() }
                    },
                    keep: {
                        store.keepBulkChange()
                    }
                )
                .padding(.horizontal, 14)
                .padding(.top, 48)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay {
            if let warning = store.leaveShortfallWarning {
                LeaveShortfallCard(
                    warning: warning,
                    dismiss: { store.dismissLeaveShortfallWarning() }
                )
                .transition(.scale(scale: 0.94).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: store.bulkUndo?.id)
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: store.leaveShortfallWarning?.id)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            UIApplication.shared.isIdleTimerDisabled = false
            Task { await store.loadState() }
        }
        .preferredColorScheme(appearanceMode.colorScheme)
    }

    private var appearanceMode: AppAppearanceMode {
        AppAppearanceMode.resolved(from: appearanceModeRaw)
    }

    private var notificationScheduleKey: String {
        let profile = store.profile
        return [
            store.isSignedIn ? "signed-in" : "signed-out",
            scenePhase == .active ? "active" : "inactive",
            DateHelpers.todayISO(),
            profile.recordingStartMonthKey,
            profile.nwdMarks.sorted().joined(separator: ",")
        ].joined(separator: "|")
    }
}
