import AuthenticationServices
import CryptoKit
import SwiftUI
import UIKit

private let apiBase = URL(string: "https://wfh-one.vercel.app")!

struct ContentView: View {
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
            await store.resumeSession()
        }
        .alert("Something went wrong", isPresented: $store.showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage)
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Auth

private struct AuthView: View {
    @EnvironmentObject private var store: AttendanceStore
    @StateObject private var googleAuth = GoogleOAuthCoordinator()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("WFH Attendance")
                                .font(.system(size: 40, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .minimumScaleFactor(0.75)
                            Text("Track office days, WFH, leave, sickness, and non-working days with a native calendar built for your phone.")
                                .font(.callout)
                                .foregroundStyle(.white.opacity(0.62))
                                .lineSpacing(3)
                        }
                        .padding(.top, 44)

                        VStack(spacing: 16) {
                            if store.isBusy {
                                ProgressView()
                                    .tint(.white)
                            }

                            VStack(spacing: 10) {
                                Text("Continue with your ID")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                HStack(spacing: 10) {
                                    if Bundle.main.appleSignInEnabled {
                                        SignInWithAppleButton(.continue) { request in
                                            request.requestedScopes = [.email]
                                        } onCompletion: { result in
                                            Task { await store.handleAppleSignIn(result) }
                                        }
                                        .signInWithAppleButtonStyle(.white)
                                        .frame(height: 48)
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    }

                                    Button {
                                        Task { await signInWithGoogle() }
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: "g.circle.fill")
                                                .font(.title3)
                                            Text("Google")
                                                .fontWeight(.semibold)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 48)
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.white)
                                    .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                                    )
                                }
                                .disabled(store.isBusy)
                            }
                        }
                        .padding(20)
                        .glassPanel(cornerRadius: 30)
                    }
                    .padding(22)
                }
            }
        }
    }

    private func signInWithGoogle() async {
        do {
            let idToken = try await googleAuth.signIn()
            await store.signInWithGoogle(idToken: idToken)
        } catch {
            store.presentError(error.localizedDescription)
        }
    }
}

private final class GoogleOAuthCoordinator: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func signIn() async throws -> String {
        let clientID = Bundle.main.googleIOSClientID
        guard !clientID.isEmpty else {
            throw AppError.message("Google sign-in is not configured yet. Add a Google iOS OAuth client ID to GOOGLE_IOS_CLIENT_ID in Xcode.")
        }
        guard let callbackScheme = Bundle.main.googleIOSCallbackScheme ?? clientID.googleCallbackScheme else {
            throw AppError.message("Google sign-in needs an iOS OAuth callback scheme configured.")
        }

        let redirectURI = "\(callbackScheme):/oauth2redirect"
        let codeVerifier = Self.makeCodeVerifier()
        let codeChallenge = Self.codeChallenge(for: codeVerifier)
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "prompt", value: "select_account")
        ]
        guard let url = components.url else {
            throw AppError.message("Could not start Google sign-in.")
        }

        let code = try await requestAuthorizationCode(url: url, callbackScheme: callbackScheme)
        return try await exchangeCodeForIDToken(
            code: code,
            clientID: clientID,
            redirectURI: redirectURI,
            codeVerifier: codeVerifier
        )
    }

    private func requestAuthorizationCode(url: URL, callbackScheme: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callbackURL, error in
                self.session = nil
                if let error {
                    if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                        continuation.resume(throwing: AppError.message("Google sign-in was cancelled."))
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                guard let callbackURL,
                      let code = callbackURL.queryParameters["code"],
                      !code.isEmpty else {
                    if let message = callbackURL?.queryParameters["error_description"] ?? callbackURL?.queryParameters["error"] {
                        continuation.resume(throwing: AppError.message(message))
                    } else {
                        continuation.resume(throwing: AppError.message("Google did not return an authorization code. Try again."))
                    }
                    return
                }
                continuation.resume(returning: code)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            self.session = session
            if !session.start() {
                self.session = nil
                continuation.resume(throwing: AppError.message("Could not start Google sign-in."))
            }
        }
    }

    private func exchangeCodeForIDToken(code: String, clientID: String, redirectURI: String, codeVerifier: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 28
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "code_verifier", value: codeVerifier),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI)
        ]
        request.httpBody = body.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            if let error = try? JSONDecoder().decode(GoogleTokenError.self, from: data) {
                throw AppError.message(error.errorDescription ?? error.error)
            }
            throw AppError.message("Google token exchange failed.")
        }

        let tokenResponse = try JSONDecoder().decode(GoogleTokenResponse.self, from: data)
        guard !tokenResponse.idToken.isEmpty else {
            throw AppError.message("Google did not return a sign-in credential. Try again.")
        }
        return tokenResponse.idToken
    }

    private static func makeCodeVerifier() -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return String((0..<64).compactMap { _ in alphabet.randomElement() })
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}

// MARK: - Home

private struct AttendanceHomeView: View {
    @EnvironmentObject private var store: AttendanceStore
    @State private var selectedTab: HomeTab = .calendar

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                CalendarScreen()
            }
            .tabItem { Label("Calendar", systemImage: "calendar") }
            .tag(HomeTab.calendar)

            NavigationStack {
                KPIScreen()
            }
            .tabItem { Label("Insights", systemImage: "chart.bar.xaxis") }
            .tag(HomeTab.kpis)

            NavigationStack {
                SettingsScreen()
            }
            .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
            .tag(HomeTab.settings)
        }
        .tint(.blue)
        .overlay(alignment: .top) {
            if store.isSyncing {
                SyncPill(text: "Syncing")
                    .padding(.top, 8)
            }
        }
    }
}

private enum HomeTab {
    case calendar
    case kpis
    case settings
}

private struct MonthHeader: View {
    let month: Month
    let metrics: Metrics
    let previous: () -> Void
    let next: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Menu {
                        ForEach((DateHelpers.currentYear - 2)...(DateHelpers.currentYear + 3), id: \.self) { year in
                            Button(String(year)) {}
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text(String(month.year))
                                .font(.title3.weight(.bold))
                            Image(systemName: "chevron.down")
                                .font(.headline.weight(.bold))
                        }
                        .foregroundStyle(Color.holidayGreen)
                    }

                    Text(DateHelpers.monthNames[month.month - 1])
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text("\(metrics.workingDays) working days · \(metrics.unassigned) unassigned")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    MonthNavButton(systemName: "chevron.left", action: previous)
                    MonthNavButton(systemName: "chevron.right", action: next)
                }
                .padding(.top, 2)
            }
        }
    }
}

private struct MonthNavButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.holidayGreen)
                .frame(width: 36, height: 36)
                .background(Color.cardBackgroundElevated, in: Circle())
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}

private struct MonthTargetCard: View {
    let metrics: Metrics
    let target: Double

    var body: some View {
        let share = metrics.officeShare ?? 0
        let onTarget = share >= target
        let targetOffset = CGFloat(min(max(target / 100, 0), 1))
        let officeOffset = CGFloat(min(max(share / 100, 0), 1))
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(share, specifier: "%.0f")")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("% in office")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(onTarget ? "ON TARGET" : "BELOW TARGET")
                    .font(.caption.weight(.heavy))
                    .tracking(1.4)
                    .foregroundStyle(onTarget ? Color.holidayGreen : Color.sickRed)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.wfhPurple, .officeBlue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    Rectangle()
                        .fill(Color.officeBlue)
                        .frame(width: 2, height: 24)
                        .offset(x: proxy.size.width * targetOffset)
                    Circle()
                        .fill(Color.officeBlue)
                        .frame(width: 28, height: 28)
                        .overlay(Circle().stroke(Color.appBackground, lineWidth: 3))
                        .shadow(color: Color.officeBlue.opacity(0.75), radius: 10)
                        .offset(x: max(0, min(proxy.size.width - 28, proxy.size.width * officeOffset - 14)))
                }
            }
            .frame(height: 28)

            HStack {
                Label("ALL WFH", systemImage: "circle.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(Color.wfhPurple)
                Spacer()
                Text("↑ \(target, specifier: "%.0f")% TARGET")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(Color.officeBlue)
                Spacer()
                Label("ALL OFFICE", systemImage: "circle.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(Color.officeBlue)
            }
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.secondary)

            Divider()
                .overlay(Color.white.opacity(0.08))

            HStack {
                Text(targetHelpText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                Spacer()
                HStack(spacing: 12) {
                    Label("\(metrics.office)", systemImage: "square.fill")
                        .foregroundStyle(Color.officeBlue)
                    Label("\(metrics.wfh)", systemImage: "square.fill")
                        .foregroundStyle(Color.wfhPurple)
                }
                .font(.caption.weight(.semibold))
            }
        }
        .padding(10)
        .cardStyle()
    }

    private var targetHelpText: String {
        let needed = metrics.officeDaysNeeded(for: target)
        if needed <= 0 {
            return String(format: "You are on target for %.0f%%", target)
        }
        return String(format: "\(needed) more office day\(needed == 1 ? "" : "s") to stay on %.0f%%", target)
    }
}

private struct CalendarScreen: View {
    @EnvironmentObject private var store: AttendanceStore
    @State private var visibleMonth = Month.current()
    @State private var selectedDates: Set<String> = []

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)

    var body: some View {
        let metrics = store.metrics(for: visibleMonth)
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    MonthHeader(
                        month: visibleMonth,
                        metrics: metrics,
                        previous: { moveMonth(-1) },
                        next: { moveMonth(1) }
                    )

                    MonthTargetCard(metrics: metrics, target: store.profile.settings.targetPct)

                    MonthCard(
                        month: visibleMonth,
                        selectedDates: $selectedDates,
                        columns: columns,
                        selectAllWorkingDays: {
                            selectedDates = Set(visibleMonth.assignableDates)
                        }
                    )

                    MonthGlanceCard(
                        month: visibleMonth,
                        metrics: metrics,
                        selectAllWorkingDays: {
                            selectedDates = Set(visibleMonth.assignableDates)
                        }
                    )
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, selectedDates.isEmpty ? 180 : 310)
            }
            .background(Color.appBackground.ignoresSafeArea())

            if !selectedDates.isEmpty {
                SelectionActionSheet(
                    dates: selectedDates,
                    apply: { kind in
                        Task {
                            await store.set(dates: selectedDates, to: kind)
                            selectedDates.removeAll()
                        }
                    },
                    clearEntries: {
                        Task {
                            await store.set(dates: selectedDates, to: .unassigned)
                            selectedDates.removeAll()
                        }
                    },
                    dismiss: { selectedDates.removeAll() }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: selectedDates.isEmpty)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(selectedDates.isEmpty ? .visible : .hidden, for: .tabBar)
        .refreshable {
            await store.loadState()
        }
    }

    private func moveMonth(_ delta: Int) {
        visibleMonth = visibleMonth.shifted(by: delta)
        selectedDates.removeAll()
    }
}

private struct MonthCard: View {
    @EnvironmentObject private var store: AttendanceStore
    let month: Month
    @Binding var selectedDates: Set<String>
    let columns: [GridItem]
    let selectAllWorkingDays: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LazyVGrid(columns: columns, spacing: 5) {
                ForEach(Array(DateHelpers.weekdayLetters.enumerated()), id: \.offset) { _, label in
                    Text(label)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(month.gridDays) { day in
                    if let iso = day.iso {
                        let kind = store.kind(for: iso)
                        DayCell(
                            day: day.day,
                            kind: kind,
                            isSelected: selectedDates.contains(iso),
                            isToday: iso == DateHelpers.todayISO()
                        )
                        .onTapGesture {
                            guard kind != .weekend, kind != .bankHoliday else { return }
                            if selectedDates.contains(iso) {
                                selectedDates.remove(iso)
                            } else {
                                selectedDates.insert(iso)
                            }
                        }
                    } else {
                        Color.clear
                            .frame(height: 42)
                    }
                }
            }

            CalendarLegend()
        }
    }
}

private struct CalendarLegend: View {
    var body: some View {
        HStack {
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                LegendItem("Office", color: .officeBlue)
                LegendItem("WFH", color: .wfhPurple)
                LegendItem("Leave", color: .leaveOrange)
                LegendItem("Sick", color: .holidayGreen)
                LegendItem("NWD", color: .nwdGray)
                LegendItem("Bank holiday", color: .sickRed)
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(.secondary)
        .minimumScaleFactor(0.72)
        .lineLimit(1)
        .padding(.top, 6)
    }
}

private struct LegendItem: View {
    let label: String
    let color: Color

    init(_ label: String, color: Color) {
        self.label = label
        self.color = color
    }

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
        }
    }
}

private struct DayCell: View {
    let day: Int
    let kind: DayKind
    let isSelected: Bool
    let isToday: Bool

    var body: some View {
        ZStack {
            dayNumber
                .offset(y: kind.tileLabel.isEmpty ? 0 : -6)

            if !kind.tileLabel.isEmpty {
                VStack {
                    Spacer()
                    Text(kind.tileLabel)
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(0.55)
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .foregroundStyle(tagColor)
                        .padding(.bottom, 5)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 42)
        .background(cellBackground, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(borderColor, lineWidth: isSelected ? 2.5 : (isToday ? 1.5 : 0))
                if isToday {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 5, height: 5)
                        .padding(5)
                }
            }
        }
        .opacity(kind == .weekend ? 0.58 : 1)
    }

    private var dayNumber: some View {
        Text("\(day)")
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
            .foregroundStyle(foregroundColor)
    }

    private var cellBackground: Color {
        if isSelected, kind == .unassigned { return Color.cardBackground.opacity(0.62) }
        switch kind {
        case .office:
            return Color.officeBlue.opacity(0.82)
        case .wfh:
            return Color.wfhPurple.opacity(0.82)
        case .leave:
            return Color.leaveOrange.opacity(0.82)
        case .sickness:
            return Color.holidayGreen.opacity(0.82)
        case .nwd:
            return Color.nwdGray.opacity(0.45)
        case .bankHoliday:
            return Color.sickRed.opacity(0.82)
        case .weekend:
            return Color.clear
        case .unassigned:
            return Color.clear
        }
    }

    private var borderColor: Color {
        if isSelected { return Color.holidayGreen }
        if isToday { return Color.white.opacity(0.20) }
        return .clear
    }

    private var foregroundColor: Color {
        if kind == .weekend { return Color.slate }
        if !kind.tileLabel.isEmpty { return Color.black.opacity(0.82) }
        if kind == .unassigned { return .secondary }
        return .white
    }

    private var tagColor: Color {
        switch kind {
        case .office, .wfh, .leave, .sickness, .nwd, .bankHoliday:
            return Color.black.opacity(0.82)
        case .weekend, .unassigned:
            return .secondary
        }
    }

}

private struct MonthGlanceCard: View {
    let month: Month
    let metrics: Metrics
    let selectAllWorkingDays: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(DateHelpers.monthNames[month.month - 1]) at a glance")
                    .font(.caption.weight(.heavy))
                    .tracking(2)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Text("\(metrics.tracked) of \(metrics.workingDays) working days tracked.")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)

                CompositionBar(metrics: metrics)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    GlanceStat(label: "Office", value: metrics.office, color: .officeBlue)
                    GlanceStat(label: "WFH", value: metrics.wfh, color: .wfhPurple)
                    GlanceStat(label: "Leave", value: metrics.leave, color: .leaveOrange)
                    GlanceStat(label: "Sick", value: metrics.sickness, color: .sickRed)
                    GlanceStat(label: "NWD", value: metrics.nwd, color: .nwdGray)
                    GlanceStat(label: "Unassigned", value: metrics.unassigned, color: .secondary)
                }
            }
            .padding(11)
            .cardStyle()

            Button(action: selectAllWorkingDays) {
                HStack {
                    Spacer()
                    Text("Select all working days")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.holidayGreen)
                    Spacer()
                    Image(systemName: "plus")
                        .font(.system(size: 38, weight: .regular))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(Color.holidayGreen, in: Circle())
                        .shadow(color: Color.holidayGreen.opacity(0.55), radius: 22)
                }
                .padding(.leading, 16)
                .padding(.trailing, 16)
                .padding(.vertical, 6)
                .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
    }
}

private struct CompositionBar: View {
    let metrics: Metrics

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 1) {
                Segment(count: metrics.office, total: metrics.workingDays, width: proxy.size.width, color: .officeBlue)
                Segment(count: metrics.wfh, total: metrics.workingDays, width: proxy.size.width, color: .wfhPurple)
                Segment(count: metrics.leave, total: metrics.workingDays, width: proxy.size.width, color: .leaveOrange)
                Segment(count: metrics.sickness, total: metrics.workingDays, width: proxy.size.width, color: .sickRed)
                Segment(count: metrics.nwd, total: metrics.workingDays, width: proxy.size.width, color: .nwdGray)
                Segment(count: metrics.unassigned, total: metrics.workingDays, width: proxy.size.width, color: Color.white.opacity(0.18))
            }
            .clipShape(Capsule())
            .background(Color.white.opacity(0.18), in: Capsule())
        }
        .frame(height: 8)
    }
}

private struct Segment: View {
    let count: Int
    let total: Int
    let width: CGFloat
    let color: Color

    var body: some View {
        color
            .frame(width: total > 0 ? max(count == 0 ? 0 : 2, width * CGFloat(count) / CGFloat(total)) : 0)
    }
}

private struct GlanceStat: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 3, height: 30)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(value)")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct SelectionActionSheet: View {
    let dates: Set<String>
    let apply: (DayKind) -> Void
    let clearEntries: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(dates.count) day\(dates.count == 1 ? "" : "s") selected")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                    Text("Tap a type to apply")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(Color.cardBackgroundElevated, in: Circle())
                }
                .buttonStyle(.plain)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                SheetTypeButton(kind: .office) { apply(.office) }
                SheetTypeButton(kind: .wfh) { apply(.wfh) }
                SheetTypeButton(kind: .leave) { apply(.leave) }
                SheetTypeButton(kind: .sickness) { apply(.sickness) }
                SheetTypeButton(kind: .nwd) { apply(.nwd) }
                SheetTypeButton(kind: .unassigned, title: "Clear") { clearEntries() }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 24)
        .background(.ultraThinMaterial, in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28))
        .overlay(alignment: .bottom) {
            Capsule()
                .fill(Color.white.opacity(0.75))
                .frame(width: 140, height: 5)
                .padding(.bottom, 10)
        }
        .overlay {
            UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct SheetTypeButton: View {
    let kind: DayKind
    var title: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: kind.sheetIcon)
                    .font(.title2)
                    .foregroundStyle(kind.color)
                Text(title ?? kind.shortTitle)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(kind == .unassigned ? Color.sickRed : .white)
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 82)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var backgroundColor: Color {
        if kind == .unassigned { return Color.sickRed.opacity(0.22) }
        return kind.color.opacity(0.25)
    }
}

private struct KPIScreen: View {
    @EnvironmentObject private var store: AttendanceStore
    @State private var month = Month.current()
    @State private var mode: InsightMode = .month

    var body: some View {
        let monthMetrics = store.metrics(for: month)
        let ytdMetrics = store.yearMetrics(year: month.year)
        let leave = store.leaveBreakdown(year: month.year)
        let activeMetrics = mode == .yearToDate ? ytdMetrics : monthMetrics
        let activeShare = activeMetrics.officeShare ?? 0
        let target = store.profile.settings.targetPct

        ScrollView {
            VStack(spacing: 9) {
                InsightsMonthHeader(
                    month: month,
                    mode: mode,
                    previous: { moveInsightsPeriod(-1) },
                    next: { moveInsightsPeriod(1) },
                    today: { month = Month.current() }
                )

                Picker("Range", selection: $mode) {
                    Text("Month").tag(InsightMode.month)
                    Text("Year-to-date").tag(InsightMode.yearToDate)
                }
                .pickerStyle(.segmented)

                InsightDonutHero(
                    month: month,
                    metrics: activeMetrics,
                    percent: activeShare,
                    target: target
                )

                if mode == .month {
                    WeekByWeekCard(month: month)
                    CompositionListCard(title: "\(DateHelpers.monthNames[month.month - 1]) composition", metrics: monthMetrics)
                } else {
                    QuarterScoreboardCard(year: month.year, target: target)
                    AnnualLeaveGaugeCard(leave: leave)
                    StreaksHabitsCard(year: month.year)
                    WellbeingCard(metrics: ytdMetrics, year: month.year)
                }

                if mode == .month {
                    LeaveSnapshotCard(leave: leave)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 90)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable {
            await store.loadState()
        }
    }

    private func moveInsightsPeriod(_ direction: Int) {
        if mode == .yearToDate {
            month = Month(year: month.year + direction, month: month.month)
        } else {
            month = month.shifted(by: direction)
        }
    }
}

private enum InsightMode {
    case yearToDate
    case month
}

private struct InsightsMonthHeader: View {
    let month: Month
    let mode: InsightMode
    let previous: () -> Void
    let next: () -> Void
    let today: () -> Void

    var body: some View {
        VStack(spacing: 7) {
            HStack {
                Text("Insights")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Today", action: today)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.holidayGreen.opacity(0.72))
            }

            HStack {
                MonthNavButton(systemName: "chevron.left", action: previous)
                Spacer()
                VStack(spacing: 2) {
                    Text(mode == .month ? month.title : String(month.year))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(mode == .month ? "This month" : "Year-to-date")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                MonthNavButton(systemName: "chevron.right", action: next)
            }
        }
    }
}

private struct InsightDonutHero: View {
    let month: Month
    let metrics: Metrics
    let percent: Double
    let target: Double

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                ZStack {
                    DonutRing(office: metrics.office, wfh: metrics.wfh)
                        .frame(width: 106, height: 106)
                    Text("\(percent, specifier: "%.0f")")
                        .font(.system(size: 31, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    + Text("%")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 6) {
                    HeroKeyRow(value: metrics.office, label: "Office", color: .officeBlue)
                    HeroKeyRow(value: metrics.wfh, label: "WFH", color: .wfhPurple)
                    HeroKeyRow(value: metrics.tracked, label: "Worked", color: Color.white.opacity(0.78))
                }
                .frame(width: 92, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            Text(percent >= target ? "On Target" : "Below Target")
                .font(.caption.weight(.bold))
                .foregroundStyle(percent >= target ? Color.holidayGreen : Color.sickRed)
                .padding(.top, 2)
        }
        .padding(11)
        .cardStyle()
    }
}

private struct HeroKeyRow: View {
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 7, height: 7)
            Text("\(value)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 18, alignment: .leading)
            Text(label.uppercased())
                .font(.system(size: 8, weight: .heavy))
                .tracking(0.5)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }
}

private struct DonutRing: View {
    let office: Int
    let wfh: Int

    var body: some View {
        let total = max(office + wfh, 1)
        let officeEnd = Double(office) / Double(total)
        ZStack {
            Circle()
                .stroke(Color.cardBackgroundElevated, lineWidth: 20)
            Circle()
                .trim(from: 0, to: 1)
                .stroke(Color.wfhPurple, style: StrokeStyle(lineWidth: 20, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Circle()
                .trim(from: 0, to: officeEnd)
                .stroke(Color.officeBlue, style: StrokeStyle(lineWidth: 20, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

private struct WeekByWeekCard: View {
    @EnvironmentObject private var store: AttendanceStore
    let month: Month

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Week by week")
                .sectionLabel()

            VStack(spacing: 4) {
                ForEach(weekRows, id: \.label) { row in
                    HStack(spacing: 4) {
                        Text(row.label)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, alignment: .leading)
                        ForEach(row.days, id: \.id) { cell in
                            WeekCell(cell: cell)
                        }
                    }
                }

                HStack {
                    Spacer().frame(width: 32)
                    ForEach(Array(["M", "T", "W", "T", "F"].enumerated()), id: \.offset) { _, day in
                        Text(day)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(8)
            .cardStyle()
        }
    }

    private var weekRows: [InsightWeekRow] {
        var rows: [InsightWeekRow] = []
        let dates = DateHelpers.dates(from: month.startISO, through: month.endISO)
        let grouped = Dictionary(grouping: dates.filter { !DateHelpers.isWeekend($0) }) { DateHelpers.isoWeekNumber($0) }
        for week in grouped.keys.sorted() {
            let weekDates = grouped[week] ?? []
            let cells = (1...5).map { weekday -> InsightWeekCell in
                if let iso = weekDates.first(where: { DateHelpers.weekdayNumber($0) == weekday }) {
                    return InsightWeekCell(iso: iso, day: Int(iso.suffix(2)) ?? 0, kind: store.kind(for: iso), inMonth: true)
                }
                return InsightWeekCell(iso: "\(week)-\(weekday)", day: nil, kind: .unassigned, inMonth: false)
            }
            rows.append(InsightWeekRow(label: "W\(week)", days: cells))
        }
        return rows
    }
}

private struct InsightWeekRow {
    let label: String
    let days: [InsightWeekCell]
}

private struct InsightWeekCell: Identifiable {
    let iso: String
    let day: Int?
    let kind: DayKind
    let inMonth: Bool
    var id: String { iso }
}

private struct WeekCell: View {
    let cell: InsightWeekCell

    var body: some View {
        Text(cell.day.map(String.init) ?? "")
            .font(.caption.weight(.bold))
            .foregroundStyle(cell.inMonth ? .white : .clear)
            .frame(maxWidth: .infinity)
            .frame(height: 23)
            .background(cell.inMonth ? cell.kind.insightColor : Color.clear, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

private struct CompositionListCard: View {
    let title: String
    let metrics: Metrics

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .sectionLabel()
            VStack(alignment: .leading, spacing: 9) {
                CompositionBar(metrics: metrics)
                Text("\(metrics.tracked + metrics.leave + metrics.sickness + metrics.nwd) of \(metrics.workingDays) working days logged")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                CompositionRow(label: "Office", value: metrics.office, color: .officeBlue)
                CompositionRow(label: "WFH", value: metrics.wfh, color: .wfhPurple)
                CompositionRow(label: "Leave", value: metrics.leave, color: .leaveOrange)
                CompositionRow(label: "Sick", value: metrics.sickness, color: .sickRed)
                CompositionRow(label: "Non-working", value: metrics.nwd, color: .nwdGray)
                CompositionRow(label: "Unassigned", value: metrics.unassigned, color: Color.white.opacity(0.20))
            }
            .padding(11)
            .cardStyle()
        }
    }
}

private struct CompositionRow: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 4)
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            Spacer()
            Text("\(value)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
        }
        .padding(.vertical, 2)
    }
}

private struct LeaveSnapshotCard: View {
    let leave: LeaveBreakdown

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Leave snapshot")
                .sectionLabel()
            VStack(spacing: 0) {
                CompositionRow(label: "Taken", value: leave.taken, color: .leaveTaken)
                Divider().overlay(Color.white.opacity(0.08))
                CompositionRow(label: "Booked ahead", value: leave.booked, color: .leaveBooked)
                Divider().overlay(Color.white.opacity(0.08))
                CompositionRow(label: "Remaining", value: leave.remaining, color: Color.white.opacity(0.20))
            }
            .padding(11)
            .cardStyle()
            Text("\(leave.allowance) day allowance · YTD")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
        }
    }
}

private struct QuarterScoreboardCard: View {
    @EnvironmentObject private var store: AttendanceStore
    let year: Int
    let target: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("By quarter")
                .sectionLabel()
            HStack(spacing: 10) {
                ForEach(1...4, id: \.self) { quarter in
                    QuarterTile(
                        title: "Q\(quarter)",
                        metrics: metrics(for: quarter),
                        isCurrent: quarter == currentQuarter
                    )
                }
            }
            .padding(16)
            .cardStyle()
        }
    }

    private var currentQuarter: Int {
        let current = DateHelpers.todayParts()
        guard current.year == year else { return 0 }
        return ((current.month - 1) / 3) + 1
    }

    private func metrics(for quarter: Int) -> Metrics? {
        if currentQuarter > 0, quarter > currentQuarter { return nil }
        let startMonth = (quarter - 1) * 3 + 1
        let endMonth = startMonth + 2
        let start = DateHelpers.iso(year: year, month: startMonth, day: 1)
        let endOfQuarter = DateHelpers.iso(year: year, month: endMonth, day: DateHelpers.daysInMonth(year: year, month: endMonth))
        let end = currentQuarter == quarter ? min(DateHelpers.todayISO(), endOfQuarter) : endOfQuarter
        return store.metrics(from: start, through: end)
    }
}

private struct QuarterTile: View {
    let title: String
    let metrics: Metrics?
    let isCurrent: Bool

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption.weight(.heavy))
                .foregroundStyle(.secondary)
            if let metrics {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(metrics.officeShare.map { String(format: "%.0f", $0) } ?? "-")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Color.officeBlue)
                    Text("%")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Label("\(metrics.office)", systemImage: "circle.fill")
                        .foregroundStyle(Color.officeBlue)
                    Label("\(metrics.wfh)", systemImage: "circle.fill")
                        .foregroundStyle(Color.wfhPurple)
                }
                .font(.caption2.weight(.semibold))
            } else {
                Text("-")
                    .font(.title.weight(.bold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Label("0", systemImage: "circle.fill")
                        .foregroundStyle(Color.officeBlue.opacity(0.45))
                    Label("0", systemImage: "circle.fill")
                        .foregroundStyle(Color.wfhPurple.opacity(0.45))
                }
                .font(.caption2.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.cardBackgroundElevated.opacity(isCurrent ? 1 : 0.35), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            if isCurrent {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1.5)
            }
        }
    }
}

private struct StreaksHabitsCard: View {
    @EnvironmentObject private var store: AttendanceStore
    let year: Int

    var body: some View {
        let streaks = computeStreaks()
        VStack(alignment: .leading, spacing: 10) {
            Text("Streaks & habits")
                .sectionLabel()
            VStack(spacing: 0) {
                HabitRow(label: "Longest office streak", value: streaks.longestOffice, color: .officeBlue)
                HabitRow(label: "Longest WFH streak", value: streaks.longestWfh, color: .wfhPurple)
                HabitRow(label: "Office days in a row now", value: streaks.currentOffice, color: .officeBlue.opacity(0.55), muted: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .cardStyle()
        }
    }

    private func computeStreaks() -> (longestOffice: Int, longestWfh: Int, currentOffice: Int) {
        let dates = DateHelpers.dates(from: "\(year)-01-01", through: min(DateHelpers.todayISO(), "\(year)-12-31"))
            .filter { DateHelpers.isMetricsWorkingDay($0, excludingNWD: []) }
        var longestOffice = 0
        var longestWfh = 0
        var officeRun = 0
        var wfhRun = 0

        for date in dates {
            switch store.kind(for: date) {
            case .office:
                officeRun += 1
                wfhRun = 0
            case .wfh:
                wfhRun += 1
                officeRun = 0
            default:
                officeRun = 0
                wfhRun = 0
            }
            longestOffice = max(longestOffice, officeRun)
            longestWfh = max(longestWfh, wfhRun)
        }

        var currentOffice = 0
        for date in dates.reversed() {
            if store.kind(for: date) == .office {
                currentOffice += 1
            } else {
                break
            }
        }

        return (longestOffice, longestWfh, currentOffice)
    }
}

private struct HabitRow: View {
    let label: String
    let value: Int
    let color: Color
    var muted = false

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 4, height: 26)
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(muted ? Color.secondary : Color.white)
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(value)")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .foregroundStyle(muted ? Color.secondary : Color.white)
                Text("days")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 7)
    }
}

private struct AnnualLeaveGaugeCard: View {
    let leave: LeaveBreakdown

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Annual leave")
                .sectionLabel()
            VStack(spacing: 8) {
                LeaveArc(progress: progress)
                    .frame(width: 148, height: 82)
                    .overlay(alignment: .bottom) {
                        VStack(spacing: 2) {
                            Text("\(leave.remaining)")
                                .font(.system(size: 25, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Text("DAYS LEFT")
                                .font(.system(size: 9, weight: .heavy))
                                .tracking(1.4)
                                .foregroundStyle(.secondary)
                        }
                    }
                Divider().overlay(Color.white.opacity(0.08))
                HStack {
                    GaugeStat(label: "Taken", value: leave.taken, color: .leaveTaken)
                    GaugeStat(label: "Booked", value: leave.booked, color: .leaveBooked)
                    GaugeStat(label: "Allowance", value: leave.allowance, color: .nwdGray)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .cardStyle()
            Text("Calendar year · \(leave.allowance) day allowance")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
        }
    }

    private var progress: Double {
        guard leave.allowance > 0 else { return 0 }
        return min(max(Double(leave.taken + leave.booked) / Double(leave.allowance), 0), 1)
    }
}

private struct LeaveArc: View {
    let progress: Double

    var body: some View {
        ZStack {
            ArcShape()
                .stroke(Color.leaveBooked.opacity(0.75), style: StrokeStyle(lineWidth: 18, lineCap: .round))
            ArcShape(end: progress)
                .stroke(Color.leaveTaken, style: StrokeStyle(lineWidth: 18, lineCap: .round))
        }
    }
}

private struct ArcShape: Shape {
    var end: Double = 1

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.maxY)
        let radius = min(rect.width / 2 - 18, rect.height - 18)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(200),
            endAngle: .degrees(200 + 140 * end),
            clockwise: false
        )
        return path
    }
}

private struct GaugeStat: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title3.bold())
                .foregroundStyle(.white)
            Label(label.uppercased(), systemImage: "circle.fill")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(color)
                .labelStyle(.titleAndIcon)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct WellbeingCard: View {
    let metrics: Metrics
    let year: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Wellbeing")
                .sectionLabel()
            VStack(spacing: 0) {
                WellbeingRow(label: "Days sick YTD", value: metrics.sickness, color: .sickRed)
                Divider().overlay(Color.white.opacity(0.08))
                WellbeingRow(label: "Non-working days", value: metrics.nwd, color: .nwdGray)
                Divider().overlay(Color.white.opacity(0.08))
                WellbeingRow(label: "Bank holidays", value: DateHelpers.bankHolidayCount(year: year, through: min(DateHelpers.todayISO(), "\(year)-12-31")), color: .holidayGreen)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .cardStyle()
        }
    }
}

private struct WellbeingRow: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 4)
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            Spacer()
            Text("\(value)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
        }
        .padding(.vertical, 9)
    }
}

private struct SettingsScreen: View {
    @EnvironmentObject private var store: AttendanceStore
    @State private var name = ""
    @State private var targetPct = 40.0
    @State private var leaveAllowance = 25.0

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("Somehow shipped by non-dev Paul Hutton · 17 May 2026")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)

                VStack(alignment: .leading, spacing: 11) {
                    Text("Profile")
                        .font(.subheadline.weight(.bold))

                    HStack(spacing: 10) {
                        Text(initials)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(
                                LinearGradient(colors: [.holidayGreen, .wfhPurple], startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: Circle()
                            )
                        VStack(alignment: .leading, spacing: 5) {
                            TextField("Your name", text: $name)
                                .font(.subheadline.weight(.semibold))
                                .textInputAutocapitalization(.words)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Color.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            Text(store.user?.email ?? "")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(13)
                .cardStyle()

                VStack(alignment: .leading, spacing: 11) {
                    Text("KPI settings")
                        .font(.subheadline.weight(.bold))

                    HStack {
                        Text("Office target")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(targetPct, specifier: "%.1f")%")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $targetPct, in: 0...100, step: 0.5)
                        .tint(.cyan)
                }
                .padding(13)
                .cardStyle()

                VStack(alignment: .leading, spacing: 11) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Annual leave")
                                .font(.subheadline.weight(.bold))
                            Text("\(String(DateHelpers.currentYear)) allowance")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(Int(leaveAllowance)) days")
                            .font(.headline.weight(.bold))
                    }

                    Stepper(value: $leaveAllowance, in: 0...60, step: 1) {
                        Text("Annual allowance")
                            .font(.subheadline.weight(.medium))
                    }
                    .tint(.cyan)
                }
                .padding(13)
                .cardStyle()

                Button {
                    Task {
                        await store.updateSettings(
                            name: name,
                            targetPct: targetPct,
                            leaveAllowance: Int(leaveAllowance),
                            year: DateHelpers.currentYear
                        )
                    }
                } label: {
                    Label("Save settings", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)

                VStack(alignment: .leading, spacing: 9) {
                    Text("Account")
                        .font(.subheadline.weight(.bold))
                    Text(store.user?.email ?? "")
                        .font(.subheadline)
                        .textSelection(.enabled)
                    Divider()
                        .overlay(Color.white.opacity(0.08))
                    Button("Sign out", role: .destructive) {
                        store.signOut()
                    }
                    .font(.subheadline.weight(.semibold))
                }
                .padding(13)
                .cardStyle()
            }
            .padding(12)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("Settings")
        .onAppear {
            name = store.profile.name
            targetPct = store.profile.settings.targetPct
            leaveAllowance = Double(store.profile.allowance(for: DateHelpers.currentYear))
        }
    }

    private var initials: String {
        let parts = name.split(separator: " ")
        let raw = parts.prefix(2).compactMap(\.first).map(String.init).joined()
        return raw.isEmpty ? "OA" : raw.uppercased()
    }
}

private struct SyncPill: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.75)
            Text(text)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
    }
}

// MARK: - Store

@MainActor
private final class AttendanceStore: ObservableObject {
    @Published var state = AttendanceState.defaultState()
    @Published var user: AuthUser?
    @Published var isBusy = false
    @Published var isSyncing = false
    @Published var showingError = false
    @Published var errorMessage = ""

    private let client = APIClient()
    private let tokenKey = "WFH_IOS_JWT"
    private let userKey = "WFH_IOS_USER"
    private let stateKey = "WFH_IOS_STATE"

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
        guard isSignedIn else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let response: StateResponse = try await client.request(path: "/api/state", method: "GET")
            if let payload = response.payload {
                state = payload.normalized()
            } else {
                state = AttendanceState.defaultState()
                await saveState()
            }
            repairDefaultProfileNameIfNeeded()
            persistState()
        } catch {
            presentError(error.localizedDescription)
        }
    }

    func set(date: String, to kind: DayKind) async {
        do {
            try state.set(date: date, to: kind)
            persistState()
            await saveState()
        } catch {
            presentError(error.localizedDescription)
        }
    }

    func set(dates: Set<String>, to kind: DayKind) async {
        guard !dates.isEmpty else { return }
        var failures: [String] = []
        var changed = false
        for date in dates.sorted() {
            do {
                try state.set(date: date, to: kind)
                changed = true
            } catch {
                failures.append(error.localizedDescription)
            }
        }
        if changed {
            persistState()
            await saveState()
        }
        if let first = failures.first {
            presentError(first)
        }
    }

    func updateSettings(name: String, targetPct: Double, leaveAllowance: Int, year: Int) async {
        state.updateSettings(name: name, targetPct: targetPct, leaveAllowance: leaveAllowance, year: year)
        persistState()
        await saveState()
    }

    func signOut() {
        client.token = nil
        user = nil
        UserDefaults.standard.removeObject(forKey: tokenKey)
        UserDefaults.standard.removeObject(forKey: userKey)
    }

    func presentError(_ message: String) {
        errorMessage = message
        showingError = true
    }

    func kind(for date: String) -> DayKind {
        profile.kind(for: date)
    }

    func metrics(for month: Month) -> Metrics {
        state.metrics(from: month.startISO, through: month.endISO)
    }

    func metrics(from start: String, through end: String) -> Metrics {
        state.metrics(from: start, through: end)
    }

    func yearMetrics(year: Int) -> Metrics {
        let start = "\(year)-01-01"
        let end = min(DateHelpers.todayISO(), "\(year)-12-31")
        return state.metrics(from: start, through: end)
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
            presentError(error.localizedDescription)
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
            presentError(error.localizedDescription)
        }
    }

    private func persistState() {
        if let data = try? JSONEncoder().encode(state.normalized()) {
            UserDefaults.standard.set(data, forKey: stateKey)
        }
    }
}

// MARK: - API

private final class APIClient {
    var token: String?

    func request<T: Decodable>(path: String, method: String) async throws -> T {
        try await request(path: path, method: method, body: Optional<String>.none)
    }

    func request<T: Decodable, Body: Encodable>(path: String, method: String, body: Body?) async throws -> T {
        var request = URLRequest(url: apiBase.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = 28
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            if let apiError = try? JSONDecoder().decode(APIError.self, from: data) {
                throw AppError.message(apiError.error)
            }
            throw AppError.message("Server returned \(status).")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

private struct APIError: Decodable {
    let error: String
}

private enum AppError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message): message
        }
    }
}

// MARK: - Models

private struct SocialAuthRequest: Encodable {
    let idToken: String
}

private struct GoogleTokenResponse: Decodable {
    let idToken: String

    private enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
    }
}

private struct GoogleTokenError: Decodable {
    let error: String
    let errorDescription: String?

    private enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

private struct AuthResponse: Decodable {
    let token: String
    let user: AuthUser
}

private struct AuthUser: Codable {
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

private struct StateResponse: Decodable {
    let payload: AttendanceState?
}

private struct SaveStateRequest: Encodable {
    let payload: AttendanceState
}

private struct SaveStateResponse: Decodable {
    let ok: Bool
}

private extension Bundle {
    var googleIOSClientID: String {
        String(object(forInfoDictionaryKey: "GOOGLE_IOS_CLIENT_ID") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var googleIOSCallbackScheme: String? {
        let value = String(object(forInfoDictionaryKey: "GOOGLE_IOS_CALLBACK_SCHEME") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var appleSignInEnabled: Bool {
        String(object(forInfoDictionaryKey: "ENABLE_APPLE_SIGN_IN") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased() == "YES"
    }
}

private extension String {
    var googleCallbackScheme: String? {
        let suffix = ".apps.googleusercontent.com"
        guard hasSuffix(suffix) else { return nil }
        return "com.googleusercontent.apps." + dropLast(suffix.count)
    }
}

private extension URL {
    var queryParameters: [String: String] {
        URLComponents(url: self, resolvingAgainstBaseURL: false)?.queryItems?.reduce(into: [:]) { result, item in
            result[item.name] = item.value
        } ?? [:]
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private struct AttendanceState: Codable {
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

    mutating func set(date: String, to kind: DayKind) throws {
        guard let index = profiles.firstIndex(where: { $0.id == activeProfileId }) else { return }
        try profiles[index].set(date: date, to: kind)
    }

    mutating func updateSettings(name: String, targetPct: Double, leaveAllowance: Int, year: Int) {
        guard let index = profiles.firstIndex(where: { $0.id == activeProfileId }) else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            profiles[index].name = trimmedName
        }
        profiles[index].settings.targetPct = targetPct
        profiles[index].settings.leaveAllowances[String(year)] = leaveAllowance
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
        activeProfile.metrics(from: start, through: end)
    }

    func leaveBreakdown(year: Int, today: String) -> LeaveBreakdown {
        activeProfile.leaveBreakdown(year: year, today: today)
    }
}

private struct AttendanceProfile: Codable {
    var id: String
    var name: String
    var createdAtISO: String?
    var settings: ProfileSettings
    var officeMarks: [String]
    var leaveMarks: [String]
    var wfhMarks: [String]
    var sicknessMarks: [String]
    var nwdMarks: [String]

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
        nwdMarks: [String]
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
    }

    static func defaultProfile() -> AttendanceProfile {
        AttendanceProfile(
            id: "p-\(Int(Date().timeIntervalSince1970))",
            name: "Default profile",
            createdAtISO: DateHelpers.todayISO(),
            settings: ProfileSettings(targetPct: 40, leaveAllowances: [String(DateHelpers.currentYear): 25]),
            officeMarks: [],
            leaveMarks: [],
            wfhMarks: [],
            sicknessMarks: [],
            nwdMarks: []
        )
    }

    func normalized() -> AttendanceProfile {
        var copy = self
        copy.officeMarks = Array(Set(copy.officeMarks)).sorted()
        copy.leaveMarks = Array(Set(copy.leaveMarks)).sorted()
        copy.wfhMarks = Array(Set(copy.wfhMarks)).sorted()
        copy.sicknessMarks = Array(Set(copy.sicknessMarks)).sorted()
        copy.nwdMarks = Array(Set(copy.nwdMarks)).sorted()
        if copy.createdAtISO == nil {
            copy.createdAtISO = DateHelpers.todayISO()
        }
        return copy
    }

    func allowance(for year: Int) -> Int {
        settings.leaveAllowances[String(year)] ?? 0
    }

    func kind(for date: String) -> DayKind {
        if officeMarks.contains(date) { return .office }
        if leaveMarks.contains(date) { return .leave }
        if sicknessMarks.contains(date) { return .sickness }
        if wfhMarks.contains(date) { return .wfh }
        if DateHelpers.isBankHoliday(date) { return .bankHoliday }
        if DateHelpers.isWeekend(date) { return .weekend }
        if nwdMarks.contains(date) { return .nwd }
        return .unassigned
    }

    mutating func set(date: String, to kind: DayKind) throws {
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
        self = normalized()
    }

    private mutating func clear(_ date: String) {
        officeMarks.removeAll { $0 == date }
        leaveMarks.removeAll { $0 == date }
        wfhMarks.removeAll { $0 == date }
        sicknessMarks.removeAll { $0 == date }
        nwdMarks.removeAll { $0 == date }
    }

    func metrics(from start: String, through end: String) -> Metrics {
        var metrics = Metrics()
        for date in DateHelpers.dates(from: start, through: end) {
            let working = DateHelpers.isMetricsWorkingDay(date, excludingNWD: nwdMarks)
            if working {
                metrics.workingDays += 1
            }
            switch kind(for: date) {
            case .office where working:
                metrics.office += 1
                metrics.tracked += 1
            case .wfh where working:
                metrics.wfh += 1
                metrics.tracked += 1
            case .leave where working:
                metrics.leave += 1
            case .sickness where working:
                metrics.sickness += 1
            case .nwd:
                metrics.nwd += 1
            case .unassigned where working:
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

private struct ProfileSettings: Codable {
    var targetPct: Double
    var leaveAllowances: [String: Int]

    static func defaultSettings() -> ProfileSettings {
        ProfileSettings(targetPct: 40, leaveAllowances: [String(DateHelpers.currentYear): 25])
    }
}

private struct Metrics {
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

    func percentLabel(for count: Int) -> String? {
        guard tracked > 0 else { return nil }
        return String(format: "%.1f%%", Double(count) / Double(tracked) * 100)
    }

    func statusLabel(target: Double) -> String {
        guard let officeShare else { return "Status: N/A" }
        let diff = officeShare - target
        if abs(diff) <= 0.5 { return "On track" }
        return diff > 0 ? "Ahead" : "Behind"
    }

    func officeDaysNeeded(for target: Double) -> Int {
        guard target > 0, target < 100 else { return 0 }
        let required = (target / 100) * Double(tracked) - Double(office)
        return max(0, Int(ceil(required)))
    }
}

private struct LeaveBreakdown {
    let taken: Int
    let booked: Int
    let allowance: Int
    let remaining: Int
}

private enum DayKind: String, Codable, Identifiable {
    case office
    case wfh
    case leave
    case sickness
    case nwd
    case unassigned
    case weekend
    case bankHoliday

    var id: String { rawValue }

    static let actionKinds: [DayKind] = [.office, .wfh, .leave, .sickness, .nwd, .unassigned]

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
        case .sickness: .sickRed
        case .nwd: .nwdGray
        case .bankHoliday: .holidayGreen
        case .unassigned, .weekend: Color.cardBackgroundElevated
        }
    }
}

// MARK: - Date helpers

private struct Month {
    let year: Int
    let month: Int

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

    var gridDays: [CalendarDay] {
        let lead = DateHelpers.mondayLeadSlots(year: year, month: month)
        let days = DateHelpers.daysInMonth(year: year, month: month)
        return (0..<lead).map { _ in CalendarDay.empty() } +
            (1...days).map { day in
                CalendarDay(day: day, iso: DateHelpers.iso(year: year, month: month, day: day))
            }
    }

    var assignableDates: [String] {
        gridDays.compactMap(\.iso).filter {
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

private struct CalendarDay: Identifiable {
    let id = UUID()
    let day: Int
    let iso: String?

    static func empty() -> CalendarDay {
        CalendarDay(day: 0, iso: nil)
    }
}

private enum DateHelpers {
    static let weekdayLetters = ["M", "T", "W", "T", "F", "S", "S"]
    static let monthNames = Calendar.current.monthSymbols
    static let london = TimeZone(identifier: "Europe/London") ?? .current
    static let bankHolidays: Set<String> = [
        "2025-01-01", "2025-04-18", "2025-04-21", "2025-05-05", "2025-05-26", "2025-08-25", "2025-12-25", "2025-12-26",
        "2026-01-01", "2026-04-03", "2026-04-06", "2026-05-04", "2026-05-25", "2026-08-31", "2026-12-25", "2026-12-28",
        "2027-01-01", "2027-03-26", "2027-03-29", "2027-05-03", "2027-05-31", "2027-08-30", "2027-12-27", "2027-12-28"
    ]

    static var currentYear: Int {
        todayParts().year
    }

    static func todayParts() -> (year: Int, month: Int, day: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = london
        let parts = calendar.dateComponents([.year, .month, .day], from: Date())
        return (parts.year ?? 2026, parts.month ?? 1, parts.day ?? 1)
    }

    static func todayISO() -> String {
        let parts = todayParts()
        return iso(year: parts.year, month: parts.month, day: parts.day)
    }

    static func iso(year: Int, month: Int, day: Int) -> String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    static func date(from iso: String) -> Date? {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = london
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static func daysInMonth(year: Int, month: Int) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = london
        let date = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
        return calendar.range(of: .day, in: .month, for: date)?.count ?? 30
    }

    static func mondayLeadSlots(year: Int, month: Int) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = london
        let date = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
        let weekday = calendar.component(.weekday, from: date)
        return (weekday + 5) % 7
    }

    static func isWeekend(_ iso: String) -> Bool {
        guard let date = date(from: iso) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = london
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 || weekday == 7
    }

    static func weekdayNumber(_ iso: String) -> Int {
        guard let date = date(from: iso) else { return 0 }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = london
        let weekday = calendar.component(.weekday, from: date)
        return ((weekday + 5) % 7) + 1
    }

    static func isoWeekNumber(_ iso: String) -> Int {
        guard let date = date(from: iso) else { return 0 }
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = london
        return calendar.component(.weekOfYear, from: date)
    }

    static func isBankHoliday(_ iso: String) -> Bool {
        bankHolidays.contains(iso) && !isWeekend(iso)
    }

    static func bankHolidayCount(year: Int, through end: String) -> Int {
        bankHolidays.filter { holiday in
            holiday.hasPrefix("\(year)-") && holiday <= end && !isWeekend(holiday)
        }.count
    }

    static func isAssignableWorkday(_ iso: String, excludingNWD nwd: [String]) -> Bool {
        !isWeekend(iso) && !isBankHoliday(iso) && !nwd.contains(iso)
    }

    static func isMetricsWorkingDay(_ iso: String, excludingNWD nwd: [String]) -> Bool {
        !isWeekend(iso) && !isBankHoliday(iso)
    }

    static func dates(from start: String, through end: String) -> [String] {
        guard var cursor = date(from: start), let endDate = date(from: end) else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = london
        var result: [String] = []
        while cursor <= endDate {
            let parts = calendar.dateComponents([.year, .month, .day], from: cursor)
            result.append(iso(year: parts.year ?? 0, month: parts.month ?? 1, day: parts.day ?? 1))
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? endDate.addingTimeInterval(1)
        }
        return result
    }
}

// MARK: - Styling

private extension View {
    func sectionLabel() -> some View {
        self
            .font(.caption.weight(.heavy))
            .tracking(1.7)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
    }

    func cardStyle() -> some View {
        self
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            }
            .shadow(color: Color.black.opacity(0.28), radius: 18, y: 8)
    }

    func glassPanel(cornerRadius: CGFloat = 26) -> some View {
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.75), lineWidth: 0.8)
            }
            .shadow(color: Color.black.opacity(0.08), radius: 24, y: 12)
    }

    func heroPanel() -> some View {
        self
            .background(
                LinearGradient(
                    colors: [Color(hex: "242426"), Color(hex: "18181A")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 30, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
            }
            .shadow(color: Color.black.opacity(0.34), radius: 24, y: 12)
    }

    func inputStyle() -> some View {
        self
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundStyle(Color.white)
    }
}

private extension Color {
    static let appBackground = Color(hex: "000000")

    static let cardBackground = Color(hex: "1C1C1E")

    static let systemGroupedFill = Color(hex: "2C2C2E")

    static let cardBackgroundElevated = Color(hex: "2C2C2E")

    static let slate = Color(hex: "8090a8")

    static let gold = Color(hex: "d6c51f")

    static let officeBlue = Color(hex: "0A84FF")

    static let wfhPurple = Color(hex: "BF5AF2")

    static let leaveOrange = Color(hex: "FF9F0A")

    static let leaveTaken = Color(hex: "FFD60A")

    static let leaveBooked = Color(hex: "FF6B6B")

    static let sickRed = Color(hex: "FF453A")

    static let nwdGray = Color(hex: "8E8E93")

    static let holidayGreen = Color(hex: "30D158")

    init(hex: String) {
        self.init(uiColor: UIColor(hex: hex))
    }
}

private extension UIColor {
    convenience init(hex: String) {
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        self.init(
            red: CGFloat((rgb >> 16) & 0xff) / 255,
            green: CGFloat((rgb >> 8) & 0xff) / 255,
            blue: CGFloat(rgb & 0xff) / 255,
            alpha: 1
        )
    }
}
