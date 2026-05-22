import SwiftUI

struct SettingsScreen: View {
    @EnvironmentObject private var store: AttendanceStore
    @AppStorage("appearanceMode") private var appearanceModeRaw = AppAppearanceMode.dark.rawValue
    @State private var name = ""
    @State private var targetPct = 40.0
    @State private var leaveAllowance = 25.0
    @State private var leaveYear = DateHelpers.currentYear
    @State private var recordingStartYear = DateHelpers.currentYear
    @State private var recordingStartMonth = DateHelpers.currentMonth
    @State private var hasLoadedSettings = false
    @State private var showingAbout = false

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                ShippedByPaulCard()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Profile")
                        .font(.subheadline.weight(.bold))

                    HStack(spacing: 8) {
                        Text(initials)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(Color.primaryText)
                            .frame(width: 34, height: 34)
                            .background(
                                LinearGradient(colors: [.holidayGreen, .wfhPurple], startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: Circle()
                            )
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Your name", text: $name)
                                .font(.subheadline.weight(.semibold))
                                .textInputAutocapitalization(.words)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .background(Color.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                    }
                }
                .padding(8)
                .settingsCardStyle()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Appearance")
                        .font(.subheadline.weight(.bold))

                    Picker("Appearance", selection: $appearanceModeRaw) {
                        ForEach(AppAppearanceMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.iconName)
                                .tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Appearance mode")
                }
                .padding(8)
                .settingsCardStyle()

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Text("Office Target")
                            .font(.subheadline.weight(.bold))

                        Spacer(minLength: 6)

                        Text("\(targetPct, specifier: "%.1f")%")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .monospacedDigit()

                        Stepper("", value: $targetPct, in: 0...100, step: 0.5)
                            .labelsHidden()
                            .tint(.cyan)
                            .accessibilityLabel("Office target")
                            .accessibilityValue("\(targetPct, specifier: "%.1f") percent")
                    }
                }
                .padding(8)
                .settingsCardStyle()

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Text("Recording Start Date")
                            .font(.subheadline.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)

                        Spacer(minLength: 6)

                        HStack(spacing: 6) {
                            Picker("Start month", selection: $recordingStartMonth) {
                                ForEach(1...12, id: \.self) { month in
                                    Text(DateHelpers.monthNames[month - 1]).tag(month)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(.cyan)
                            .accessibilityLabel("Recording start month")

                            Picker("Start year", selection: $recordingStartYear) {
                                ForEach(recordingStartYearOptions, id: \.self) { year in
                                    Text(String(year)).tag(year)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(.cyan)
                            .accessibilityLabel("Recording start year")
                        }
                    }

                }
                .padding(8)
                .settingsCardStyle()

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Text("Annual Leave")
                            .font(.subheadline.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)

                        Spacer(minLength: 6)

                        Text("\(Int(leaveAllowance)) days")
                            .font(.headline.weight(.bold))
                            .monospacedDigit()
                            .frame(minWidth: 72, alignment: .trailing)

                        Stepper("", value: $leaveAllowance, in: 0...60, step: 1)
                            .labelsHidden()
                            .tint(.cyan)
                            .accessibilityLabel("\(String(leaveYear)) annual leave allowance")
                            .accessibilityValue("\(Int(leaveAllowance)) days")

                        Picker("Leave year", selection: $leaveYear) {
                            ForEach(leaveYearOptions, id: \.self) { year in
                                Text(String(year)).tag(year)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(.cyan)
                        .accessibilityLabel("Leave year")
                    }
                    .padding(.horizontal, 9)
                }
                .padding(8)
                .settingsCardStyle()

                VStack(alignment: .leading, spacing: 5) {
                    Button {
                        showingAbout = true
                    } label: {
                        HStack(spacing: 10) {
                            Label("About", systemImage: "info.circle")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Color.primaryText)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.secondaryText)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("About this app")
                }
                .padding(8)
                .settingsCardStyle()

                VStack(alignment: .leading, spacing: 5) {
                    Text("Account")
                        .font(.subheadline.weight(.bold))
                    Text(store.user?.email ?? "")
                        .font(.subheadline)
                        .textSelection(.enabled)
                    Divider()
                        .overlay(Color.borderSubtle)
                    Button(role: .destructive) {
                        store.signOut()
                    } label: {
                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                            .font(.subheadline.weight(.heavy))
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.sickRed.opacity(0.92), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .stroke(Color.sickRed.opacity(0.35), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
                .settingsCardStyle()

            }
            .padding(8)
            .padding(.bottom, 24)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("Settings")
        .sheet(isPresented: $showingAbout) {
            AboutAppSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            name = store.profile.name
            targetPct = store.profile.settings.targetPct
            let startParts = store.profile.recordingStartMonthParts
            recordingStartYear = startParts.year
            recordingStartMonth = startParts.month
            leaveYear = DateHelpers.currentYear
            clampLeaveYearToRecordingStart()
            leaveAllowance = Double(store.profile.allowance(for: leaveYear))
            hasLoadedSettings = true
        }
        .onChange(of: leaveYear) { _, year in
            leaveAllowance = Double(store.profile.allowance(for: year))
        }
        .onChange(of: recordingStartMonthKey) { _, _ in
            clampLeaveYearToRecordingStart()
        }
        .task(id: autosaveKey) {
            guard hasLoadedSettings else { return }
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            await store.updateSettings(
                name: name,
                targetPct: targetPct,
                leaveAllowance: Int(leaveAllowance),
                year: leaveYear,
                recordingStartMonth: recordingStartMonthKey
            )
        }
    }

    private var autosaveKey: String {
        "\(name)|\(targetPct)|\(leaveYear)|\(Int(leaveAllowance))|\(recordingStartMonthKey)"
    }

    private var leaveYearOptions: [Int] {
        let startYear = recordingStartYear
        let nearbyYears = Set(startYear...max(startYear, DateHelpers.currentYear + 3))
        let configuredYears = Set(store.profile.settings.leaveAllowances.keys.compactMap(Int.init))
        return Array(nearbyYears.union(configuredYears).filter { $0 >= startYear }).sorted()
    }

    private var recordingStartYearOptions: [Int] {
        Array(DateHelpers.currentYear...(DateHelpers.currentYear + 1))
    }

    private var recordingStartMonthKey: String {
        DateHelpers.monthKey(year: recordingStartYear, month: recordingStartMonth)
    }

    private var initials: String {
        let parts = name.split(separator: " ")
        let raw = parts.prefix(2).compactMap(\.first).map(String.init).joined()
        return raw.isEmpty ? "OA" : raw.uppercased()
    }

    private func clampLeaveYearToRecordingStart() {
        if leaveYear < recordingStartYear {
            leaveYear = recordingStartYear
            leaveAllowance = Double(store.profile.allowance(for: recordingStartYear))
        }
    }
}

private struct AboutAppSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Work Attendance helps you keep a simple, honest record of where your working days go. Mark each day as office, work from home, annual leave, sickness, or non-working, then use the calendar and insight views to see whether you are on track against your office attendance target.")
                    .font(.body)
                    .foregroundStyle(Color.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text("It also tracks annual leave allowance, recording start dates, monthly progress, year-to-date totals, and report exports so your attendance picture stays clear without spreadsheet wrestling.")
                    .font(.body)
                    .foregroundStyle(Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text("A working day is a weekday that is available to be counted as either office or work from home. Annual leave, sickness, bank holidays, weekends, and non-working days are excluded from office target calculations.")
                    .font(.body)
                    .foregroundStyle(Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()
            }
            .padding(18)
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("About")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.subheadline.weight(.bold))
                }
            }
        }
    }
}

struct ShippedByPaulCard: View {
    var body: some View {
        HStack(spacing: 10) {
            Image("PaulAvatar")
                .resizable()
                .scaledToFill()
                .frame(width: 54, height: 54)
                .clipShape(Circle())
                .padding(4)
                .background(Color.cardBackgroundElevated, in: Circle())
                .overlay {
                    Circle()
                        .stroke(Color.borderSubtle, lineWidth: 1)
                }
                .shadow(color: Color.cardShadow, radius: 8, x: 0, y: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text("Somehow shipped")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.primaryText)
                Text("Vibe coded by non-developer Paul Hutton")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.mint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Text("17 May 2026")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.cyan.opacity(0.88))
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.borderSubtle, lineWidth: 1)
        }
    }
}

private extension View {
    func settingsCardStyle() -> some View {
        self
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.borderSubtle, lineWidth: 0.5)
            }
            .shadow(color: Color.cardShadow, radius: 10, y: 4)
    }
}
