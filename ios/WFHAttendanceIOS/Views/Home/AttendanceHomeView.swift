import SwiftUI

struct AttendanceHomeView: View {
    @EnvironmentObject private var store: AttendanceStore
    @State private var selectedTab: HomeTab = .calendar
    @State private var recordMonth = Month.current()
    @State private var yearInsightMonth = Month.current()

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                CalendarScreen(visibleMonth: $recordMonth)
            }
            .tabItem { Label("Record", systemImage: "record.circle.fill") }
            .tag(HomeTab.calendar)

            NavigationStack {
                KPIScreen(scope: .month, month: $recordMonth)
            }
            .tabItem { Label("Month", systemImage: "calendar") }
            .tag(HomeTab.monthInsights)

            NavigationStack {
                KPIScreen(scope: .year, month: $yearInsightMonth)
            }
            .tabItem { Label("Year", systemImage: "chart.bar.xaxis") }
            .tag(HomeTab.yearInsights)

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

enum HomeTab {
    case calendar
    case monthInsights
    case yearInsights
    case settings
}
