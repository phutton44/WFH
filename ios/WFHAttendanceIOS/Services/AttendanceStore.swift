import AuthenticationServices
import Foundation
import SwiftUI

struct BulkUndoState: Identifiable {
    let id = UUID()
    let previousState: AttendanceState
    let message: String
}

struct LeaveShortfallWarning: Identifiable, Equatable {
    let id = UUID()
    let year: Int
    let remaining: Int
    let requested: Int
    let deficit: Int
}

// MARK: - Store

@MainActor
final class AttendanceStore: ObservableObject {
    @Published var state = AttendanceState.defaultState()
    @Published var user: AuthUser?
    @Published var isBusy = false
    @Published var isSyncing = false
    @Published var showingError = false
    @Published var errorMessage = ""
    @Published var leaveShortfallWarning: LeaveShortfallWarning?
    @Published private(set) var bulkUndo: BulkUndoState?

    private let client = APIClient()
    private let tokenKey = "WFH_IOS_JWT"
    private let userKey = "WFH_IOS_USER"
    private let stateKey = "WFH_IOS_STATE"
    private static let activeSyncInterval: Duration = .seconds(120)

    var isSignedIn: Bool {
        user != nil && client.token != nil
    }

    var profile: AttendanceProfile {
        state.activeProfile
    }

    func resumeSession() async {
        if let token = UserDefaults.standard.string(forKey: tokenKey) {
            client.token = token
        }
        if let data = UserDefaults.standard.data(forKey: userKey),
           let decoded = try? JSONDecoder().decode(AuthUser.self, from: data) {
            user = decoded
        }
        if let data = UserDefaults.standard.data(forKey: stateKey),
           let decoded = try? JSONDecoder().decode(AttendanceState.self, from: data) {
            state = decoded.normalized()
        }
        if isSignedIn {
            await loadState()
        }
    }

    func startTimelySyncLoop() async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: Self.activeSyncInterval)
            } catch {
                break
            }
            guard !Task.isCancelled else { break }
            await refreshState(showIndicator: false, reportErrors: false, createIfMissing: false)
        }
    }

    func signInWithGoogle(idToken: String) async {
        await authenticateSocial(path: "/api/auth/google", idToken: idToken)
    }

    func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let data = credential.identityToken,
                  let idToken = String(data: data, encoding: .utf8) else {
                presentError("Apple did not return a sign-in credential. Try again.")
                return
            }
            await authenticateSocial(path: "/api/auth/apple", idToken: idToken)
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled {
                return
            }
            presentError(error.localizedDescription)
        }
    }

    func loadState() async {
        await refreshState(showIndicator: true, reportErrors: true, createIfMissing: true)
    }

    private func refreshState(showIndicator: Bool, reportErrors: Bool, createIfMissing: Bool) async {
        guard isSignedIn else { return }
        if showIndicator {
            isSyncing = true
        }
        defer {
            if showIndicator {
                isSyncing = false
            }
        }
        do {
            let response: StateResponse = try await client.request(path: "/api/state", method: "GET")
            if let payload = response.payload {
                state = payload.normalized()
            } else if createIfMissing {
                state = AttendanceState.defaultState()
                await saveState()
            }
            repairDefaultProfileNameIfNeeded()
            persistState()
        } catch {
            if reportErrors, !Self.isCancellation(error) {
                presentError(error.localizedDescription)
            }
        }
    }

    func set(dates: Set<String>, to kind: DayKind, allowBulkUndo: Bool = false) async {
        guard !dates.isEmpty else { return }
        await refreshState(showIndicator: false, reportErrors: false, createIfMissing: false)
        if kind == .leave, let warning = state.leaveShortfall(for: dates) {
            presentLeaveShortfall(warning)
            return
        }
        let previousState = state
        let shouldShowBulkUndo = allowBulkUndo && previousState.hasAssignedDays(in: dates)
        var failures: [String] = []
        var changed = false
        for date in dates.sorted() {
            do {
                try state.set(date: date, to: kind, normalizing: false)
                changed = true
            } catch {
                failures.append(error.localizedDescription)
            }
        }
        if changed {
            state.normalizeActiveProfile()
            if shouldShowBulkUndo {
                showBulkUndo(previousState: previousState, count: dates.count)
            }
            persistState()
            await saveState()
        }
        if let first = failures.first {
            presentError(first)
        }
    }

    func restoreBulkUndo() async {
        guard let undo = bulkUndo else { return }
        bulkUndo = nil
        state = undo.previousState.normalized()
        persistState()
        await saveState()
    }

    func keepBulkChange() {
        bulkUndo = nil
    }

    func updateSettings(name: String, targetPct: Double, leaveAllowance: Int, year: Int, recordingStartMonth: String, yearStartMonth: Int) async {
        await refreshState(showIndicator: false, reportErrors: false, createIfMissing: false)
        state.updateSettings(
            name: name,
            targetPct: targetPct,
            leaveAllowance: leaveAllowance,
            year: year,
            recordingStartMonth: recordingStartMonth,
            yearStartMonth: yearStartMonth
        )
        persistState()
        await saveState()
    }

    func isMonthLocked(_ month: Month) -> Bool {
        profile.isMonthLocked(month.key)
    }

    func isBeforeRecordingStart(_ month: Month) -> Bool {
        profile.isBeforeRecordingStart(month.key)
    }

    func setMonth(_ month: Month, locked: Bool) async {
        await refreshState(showIndicator: false, reportErrors: false, createIfMissing: false)
        state.setMonth(month.key, locked: locked)
        persistState()
        await saveState()
    }

    func signOut() {
        client.token = nil
        user = nil
        bulkUndo = nil
        UserDefaults.standard.removeObject(forKey: tokenKey)
        UserDefaults.standard.removeObject(forKey: userKey)
    }

    func presentError(_ message: String) {
        errorMessage = message
        showingError = true
    }

    func dismissLeaveShortfallWarning() {
        leaveShortfallWarning = nil
    }

    private func presentLeaveShortfall(_ warning: LeaveShortfallWarning) {
        showingError = false
        leaveShortfallWarning = warning
    }

    func kind(for date: String) -> DayKind {
        profile.kind(for: date)
    }

    func kinds(for dates: [String]) -> [String: DayKind] {
        profile.kinds(for: dates)
    }

    func metrics(for month: Month) -> Metrics {
        state.metrics(from: month.startISO, through: month.endISO)
    }

    func metrics(from start: String, through end: String) -> Metrics {
        state.metrics(from: start, through: end, respectingRecordingStart: true)
    }

    func metrics(from start: String, through end: String, respectingRecordingStart: Bool) -> Metrics {
        state.metrics(from: start, through: end, respectingRecordingStart: respectingRecordingStart)
    }

    func leaveBreakdown(year: Int) -> LeaveBreakdown {
        state.leaveBreakdown(year: year, today: DateHelpers.todayISO())
    }

    private func authenticateSocial(path: String, idToken: String) async {
        isBusy = true
        defer { isBusy = false }
        do {
            let body = SocialAuthRequest(idToken: idToken)
            let response: AuthResponse = try await client.request(path: path, method: "POST", body: body)
            await finishAuthentication(response)
        } catch {
            if !Self.isCancellation(error) {
                presentError(error.localizedDescription)
            }
        }
    }

    private func finishAuthentication(_ response: AuthResponse) async {
        client.token = response.token
        user = response.user
        repairDefaultProfileNameIfNeeded()
        UserDefaults.standard.set(response.token, forKey: tokenKey)
        if let userData = try? JSONEncoder().encode(response.user) {
            UserDefaults.standard.set(userData, forKey: userKey)
        }
        await loadState()
    }

    private func repairDefaultProfileNameIfNeeded() {
        guard let user else { return }
        state.repairDefaultProfileName(using: user.displayName)
    }

    private func saveState() async {
        guard isSignedIn else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let body = SaveStateRequest(payload: state.normalized())
            let _: SaveStateResponse = try await client.request(path: "/api/state", method: "PUT", body: body)
        } catch {
            if !Self.isCancellation(error) {
                presentError(error.localizedDescription)
            }
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if (error as? URLError)?.code == .cancelled {
            return true
        }
        return (error as NSError).code == NSURLErrorCancelled
    }

    private func showBulkUndo(previousState: AttendanceState, count: Int) {
        let undo = BulkUndoState(
            previousState: previousState,
            message: "\(count) day\(count == 1 ? "" : "s") changed"
        )
        bulkUndo = undo
    }

    private func persistState() {
        if let data = try? JSONEncoder().encode(state.normalized()) {
            UserDefaults.standard.set(data, forKey: stateKey)
        }
    }
}
