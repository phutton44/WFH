import SwiftUI

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
    }
}

// MARK: - Auth

private struct AuthView: View {
    @EnvironmentObject private var store: AttendanceStore
    @State private var mode: AuthMode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(hex: "07111f"), Color(hex: "102033"), Color(hex: "0b141f")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("WFH Attendance")
                                .font(.system(size: 42, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .minimumScaleFactor(0.75)
                            Text("Track office days, WFH, leave, sickness, and non-working days with a native calendar built for your phone.")
                                .font(.callout)
                                .foregroundStyle(.white.opacity(0.72))
                                .lineSpacing(3)
                        }
                        .padding(.top, 32)

                        VStack(spacing: 18) {
                            Picker("Mode", selection: $mode) {
                                Text("Sign in").tag(AuthMode.signIn)
                                Text("Create").tag(AuthMode.register)
                            }
                            .pickerStyle(.segmented)

                            VStack(spacing: 14) {
                                TextField("Email", text: $email)
                                    .textInputAutocapitalization(.never)
                                    .keyboardType(.emailAddress)
                                    .textContentType(.emailAddress)
                                    .inputStyle()

                                SecureField("Password", text: $password)
                                    .textContentType(mode == .signIn ? .password : .newPassword)
                                    .inputStyle()

                                if mode == .register {
                                    SecureField("Confirm password", text: $confirmPassword)
                                        .textContentType(.newPassword)
                                        .inputStyle()

                                    Text("Use at least 12 characters, one uppercase letter, and one special character.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }

                            Button {
                                Task { await submit() }
                            } label: {
                                HStack {
                                    if store.isBusy {
                                        ProgressView()
                                            .tint(.white)
                                    }
                                    Text(mode == .signIn ? "Sign in" : "Create account")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(store.isBusy)
                        }
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    }
                    .padding(22)
                }
            }
        }
    }

    private func submit() async {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !password.isEmpty else {
            store.presentError("Enter your email and password.")
            return
        }
        if mode == .register {
            guard password == confirmPassword else {
                store.presentError("Those passwords do not match.")
                return
            }
            await store.register(email: trimmed, password: password)
        } else {
            await store.signIn(email: trimmed, password: password)
        }
    }
}

private enum AuthMode {
    case signIn
    case register
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
                SettingsScreen()
            }
            .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
            .tag(HomeTab.settings)
        }
        .tint(.teal)
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
    case settings
}

private struct CalendarScreen: View {
    @EnvironmentObject private var store: AttendanceStore
    @State private var visibleMonth = Month.current()
    @State private var selectedDate = DateHelpers.todayISO()

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HeaderCard(month: visibleMonth)

                SummaryGrid(metrics: store.metrics(for: visibleMonth))

                MonthCard(
                    month: visibleMonth,
                    selectedDate: $selectedDate,
                    columns: columns
                )

                DayActionCard(date: selectedDate)
            }
            .padding(16)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("Attendance")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    visibleMonth = visibleMonth.shifted(by: -1)
                    selectedDate = visibleMonth.clampedSelection(selectedDate)
                } label: {
                    Image(systemName: "chevron.left")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack {
                    Button {
                        visibleMonth = Month.current()
                        selectedDate = DateHelpers.todayISO()
                    } label: {
                        Text("Today")
                    }
                    Button {
                        visibleMonth = visibleMonth.shifted(by: 1)
                        selectedDate = visibleMonth.clampedSelection(selectedDate)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                }
            }
        }
        .refreshable {
            await store.loadState()
        }
    }
}

private struct HeaderCard: View {
    @EnvironmentObject private var store: AttendanceStore
    let month: Month

    var body: some View {
        let year = month.year
        let ytd = store.yearMetrics(year: year)
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(month.title)
                        .font(.system(.title, design: .rounded, weight: .bold))
                    Text(store.user?.email ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button("Sign out") {
                    store.signOut()
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
            }

            HStack(spacing: 16) {
                RingMetric(
                    value: ytd.officeShare,
                    title: "YTD office",
                    subtitle: "\(ytd.office) office · \(ytd.wfh) WFH"
                )
                VStack(alignment: .leading, spacing: 10) {
                    Label("\(ytd.leave) leave booked", systemImage: "sun.max.fill")
                        .foregroundStyle(Color.orange)
                    Label("\(ytd.sickness) sickness days", systemImage: "cross.case.fill")
                        .foregroundStyle(Color.pink)
                    Label("\(store.profile.settings.targetPct.formatted(.number.precision(.fractionLength(0...1))))% target", systemImage: "target")
                        .foregroundStyle(Color.teal)
                }
                .font(.subheadline.weight(.medium))
            }
        }
        .padding(20)
        .cardStyle()
    }
}

private struct SummaryGrid: View {
    let metrics: Metrics

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatTile(title: "Office", value: "\(metrics.office)", icon: "building.2.fill", color: .green)
            StatTile(title: "WFH", value: "\(metrics.wfh)", icon: "house.fill", color: .teal)
            StatTile(title: "Leave", value: "\(metrics.leave)", icon: "sun.max.fill", color: .orange)
            StatTile(title: "Open days", value: "\(metrics.unassigned)", icon: "questionmark.circle.fill", color: .blue)
        }
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title2.bold())
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .cardStyle()
    }
}

private struct MonthCard: View {
    @EnvironmentObject private var store: AttendanceStore
    let month: Month
    @Binding var selectedDate: String
    let columns: [GridItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Month planner")
                    .font(.headline)
                Spacer()
                Text("Tap a day")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(DateHelpers.weekdayLabels, id: \.self) { label in
                    Text(label)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(month.gridDays) { day in
                    if let iso = day.iso {
                        DayCell(
                            day: day.day,
                            kind: store.kind(for: iso),
                            isSelected: selectedDate == iso,
                            isToday: iso == DateHelpers.todayISO()
                        )
                        .onTapGesture {
                            selectedDate = iso
                        }
                    } else {
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
            }
        }
        .padding(16)
        .cardStyle()
    }
}

private struct DayCell: View {
    let day: Int
    let kind: DayKind
    let isSelected: Bool
    let isToday: Bool

    var body: some View {
        VStack(spacing: 5) {
            Text("\(day)")
                .font(.system(.body, design: .rounded, weight: isSelected ? .bold : .semibold))
            Circle()
                .fill(kind.color)
                .frame(width: 6, height: 6)
                .opacity(kind == .unassigned ? 0.28 : 1)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .background(cellBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            if isToday {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.teal.opacity(0.8), lineWidth: 1.5)
            }
        }
        .foregroundStyle(isSelected ? .white : .primary)
    }

    private var cellBackground: Color {
        if isSelected { return .teal }
        if kind == .weekend || kind == .bankHoliday { return Color.secondary.opacity(0.08) }
        return kind.color.opacity(0.12)
    }
}

private struct DayActionCard: View {
    @EnvironmentObject private var store: AttendanceStore
    let date: String

    var body: some View {
        let kind = store.kind(for: date)
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(DateHelpers.friendlyDate(date))
                        .font(.headline)
                    Text(kind.title)
                        .font(.subheadline)
                        .foregroundStyle(kind.color)
                }
                Spacer()
                Image(systemName: kind.icon)
                    .font(.title2)
                    .foregroundStyle(kind.color)
                    .frame(width: 44, height: 44)
                    .background(kind.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 15))
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(DayKind.actionKinds) { action in
                    Button {
                        Task { await store.set(date: date, to: action) }
                    } label: {
                        Label(action.actionTitle, systemImage: action.icon)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                    }
                    .buttonStyle(.bordered)
                    .tint(action.color)
                    .disabled(!store.canApply(action, to: date))
                }
            }
        }
        .padding(16)
        .cardStyle()
    }
}

private struct SettingsScreen: View {
    @EnvironmentObject private var store: AttendanceStore
    @State private var targetPct = 40.0
    @State private var leaveAllowance = 25.0

    var body: some View {
        Form {
            Section("Attendance target") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Office target")
                        Spacer()
                        Text("\(targetPct, specifier: "%.1f")%")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $targetPct, in: 0...100, step: 0.5)
                }
            }

            Section("Annual leave") {
                Stepper(value: $leaveAllowance, in: 0...60, step: 1) {
                    HStack {
                        Text("\(DateHelpers.currentYear) allowance")
                        Spacer()
                        Text("\(Int(leaveAllowance)) days")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Button {
                    Task {
                        await store.updateSettings(
                            targetPct: targetPct,
                            leaveAllowance: Int(leaveAllowance),
                            year: DateHelpers.currentYear
                        )
                    }
                } label: {
                    Label("Save settings", systemImage: "checkmark.circle.fill")
                }
            }

            Section("Account") {
                Text(store.user?.email ?? "")
                Button("Sign out", role: .destructive) {
                    store.signOut()
                }
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            targetPct = store.profile.settings.targetPct
            leaveAllowance = Double(store.profile.allowance(for: DateHelpers.currentYear))
        }
    }
}

private struct RingMetric: View {
    let value: Double?
    let title: String
    let subtitle: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 12)
            Circle()
                .trim(from: 0, to: value.map { min(max($0 / 100, 0), 1) } ?? 0)
                .stroke(
                    AngularGradient(colors: [.teal, .green, .teal], center: .center),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text(value.map { "\($0, specifier: "%.0f")%" } ?? "N/A")
                    .font(.title3.bold())
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(16)
        }
        .frame(width: 136, height: 136)
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

    func signIn(email: String, password: String) async {
        await authenticate(path: "/api/auth/login", email: email, password: password)
    }

    func register(email: String, password: String) async {
        await authenticate(path: "/api/auth/register", email: email, password: password)
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

    func updateSettings(targetPct: Double, leaveAllowance: Int, year: Int) async {
        state.updateSettings(targetPct: targetPct, leaveAllowance: leaveAllowance, year: year)
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

    func canApply(_ kind: DayKind, to date: String) -> Bool {
        state.canApply(kind, to: date)
    }

    func metrics(for month: Month) -> Metrics {
        state.metrics(from: month.startISO, through: month.endISO)
    }

    func yearMetrics(year: Int) -> Metrics {
        let start = "\(year)-01-01"
        let end = min(DateHelpers.todayISO(), "\(year)-12-31")
        return state.metrics(from: start, through: end)
    }

    private func authenticate(path: String, email: String, password: String) async {
        isBusy = true
        defer { isBusy = false }
        do {
            let body = AuthRequest(email: email, password: password)
            let response: AuthResponse = try await client.request(path: path, method: "POST", body: body)
            client.token = response.token
            user = response.user
            UserDefaults.standard.set(response.token, forKey: tokenKey)
            if let userData = try? JSONEncoder().encode(response.user) {
                UserDefaults.standard.set(userData, forKey: userKey)
            }
            await loadState()
        } catch {
            presentError(error.localizedDescription)
        }
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

private struct AuthRequest: Encodable {
    let email: String
    let password: String
}

private struct AuthResponse: Decodable {
    let token: String
    let user: AuthUser
}

private struct AuthUser: Codable {
    let id: String
    let email: String
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

    func canApply(_ kind: DayKind, to date: String) -> Bool {
        if kind == .unassigned { return true }
        if kind == .nwd { return !DateHelpers.isWeekend(date) && !DateHelpers.isBankHoliday(date) }
        return DateHelpers.isAssignableWorkday(date, excludingNWD: activeProfile.nwdMarks)
    }

    mutating func updateSettings(targetPct: Double, leaveAllowance: Int, year: Int) {
        guard let index = profiles.firstIndex(where: { $0.id == activeProfileId }) else { return }
        profiles[index].settings.targetPct = targetPct
        profiles[index].settings.leaveAllowances[String(year)] = leaveAllowance
    }

    func metrics(from start: String, through end: String) -> Metrics {
        activeProfile.metrics(from: start, through: end)
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
}

private struct ProfileSettings: Codable {
    var targetPct: Double
    var leaveAllowances: [String: Int]

    static func defaultSettings() -> ProfileSettings {
        ProfileSettings(targetPct: 40, leaveAllowances: [String(DateHelpers.currentYear): 25])
    }
}

private struct Metrics {
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

    var color: Color {
        switch self {
        case .office: .green
        case .wfh: .teal
        case .leave: .orange
        case .sickness: .pink
        case .nwd: .purple
        case .unassigned: .blue
        case .weekend: .gray
        case .bankHoliday: .red
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

    func clampedSelection(_ current: String) -> String {
        let day = min(Int(current.suffix(2)) ?? 1, DateHelpers.daysInMonth(year: year, month: month))
        return DateHelpers.iso(year: year, month: month, day: day)
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
    static let weekdayLabels = ["M", "T", "W", "T", "F", "S", "S"]
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

    static func friendlyDate(_ iso: String) -> String {
        guard let date = date(from: iso) else { return iso }
        let formatter = DateFormatter()
        formatter.timeZone = london
        formatter.dateStyle = .full
        return formatter.string(from: date)
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

    static func isBankHoliday(_ iso: String) -> Bool {
        bankHolidays.contains(iso) && !isWeekend(iso)
    }

    static func isAssignableWorkday(_ iso: String, excludingNWD nwd: [String]) -> Bool {
        !isWeekend(iso) && !isBankHoliday(iso) && !nwd.contains(iso)
    }

    static func isMetricsWorkingDay(_ iso: String, excludingNWD nwd: [String]) -> Bool {
        isAssignableWorkday(iso, excludingNWD: nwd)
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
    func cardStyle() -> some View {
        self
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.08), radius: 18, y: 10)
    }

    func inputStyle() -> some View {
        self
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(Color.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundStyle(Color.black)
    }
}

private extension Color {
    static let appBackground = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(hex: "07111f") : UIColor(hex: "f4f7fb")
    })

    static let cardBackground = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(hex: "101927") : UIColor.white
    })

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
