import SwiftUI

struct CalendarScreen: View {
    @EnvironmentObject private var store: AttendanceStore
    @Binding var visibleMonth: Month
    @State private var selectedDates: Set<String> = []
    @State private var selectedFromSelectAll = false
    @State private var showingDaysExplained = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)

    var body: some View {
        let gridDays = visibleMonth.gridDays
        let dayKinds = store.kinds(for: gridDays.compactMap(\.iso))
        let assignableDates = Set(visibleMonth.assignableDates)
        let metrics = store.metrics(for: visibleMonth)
        let isLocked = store.isMonthLocked(visibleMonth)
        let isBeforeRecordingStart = store.isBeforeRecordingStart(visibleMonth)
        let isEditable = !isLocked && !isBeforeRecordingStart
        let canGoPrevious = visibleMonth.key > store.profile.recordingStartMonthKey
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    MonthHeader(
                        month: visibleMonth,
                        metrics: metrics,
                        previous: { moveMonth(-1) },
                        next: { moveMonth(1) },
                        selectYear: { selectYear($0) },
                        yearOptions: selectableYears,
                        isLocked: isLocked,
                        isBeforeRecordingStart: isBeforeRecordingStart,
                        canGoPrevious: canGoPrevious,
                        showDaysExplained: {
                            showingDaysExplained = true
                        },
                        toggleLock: {
                            guard !isBeforeRecordingStart else { return }
                            Task {
                                await store.setMonth(visibleMonth, locked: !isLocked)
                                selectedDates.removeAll()
                            }
                        }
                    )

                    MonthTargetCard(metrics: metrics, target: store.profile.settings.targetPct)

                    MonthCard(
                        days: gridDays,
                        dayKinds: dayKinds,
                        selectedDates: $selectedDates,
                        columns: columns,
                        isEditable: isEditable,
                        isBeforeRecordingStart: isBeforeRecordingStart,
                        markManualSelection: {
                            selectedFromSelectAll = false
                        }
                    )

                    MonthGlanceCard(
                        month: visibleMonth,
                        metrics: metrics,
                        isEditable: isEditable,
                        selectAllWorkingDays: {
                            selectedDates = assignableDates
                            selectedFromSelectAll = true
                        }
                    )
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, selectedDates.isEmpty ? 180 : 310)
            }
            .background(Color.appBackground.ignoresSafeArea())

            if !selectedDates.isEmpty, isEditable {
                SelectionActionSheet(
                    dates: selectedDates,
                    apply: { kind in
                        Task {
                            let shouldOfferUndo = selectedFromSelectAll
                            await store.set(dates: selectedDates, to: kind, allowBulkUndo: shouldOfferUndo)
                            selectedDates.removeAll()
                            selectedFromSelectAll = false
                        }
                    },
                    clearEntries: {
                        Task {
                            await store.set(dates: selectedDates, to: .unassigned)
                            selectedDates.removeAll()
                            selectedFromSelectAll = false
                        }
                    },
                    dismiss: {
                        selectedDates.removeAll()
                        selectedFromSelectAll = false
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: selectedDates.isEmpty)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(selectedDates.isEmpty ? .visible : .hidden, for: .tabBar)
        .sheet(isPresented: $showingDaysExplained) {
            DaysExplainedSheet()
                .presentationDetents([.height(460), .large])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            snapToRecordingStartIfNeeded()
        }
        .onChange(of: isEditable) { _, editable in
            if !editable {
                selectedDates.removeAll()
                selectedFromSelectAll = false
            }
        }
        .onChange(of: store.profile.recordingStartMonthKey) { _, _ in
            snapToRecordingStartIfNeeded()
        }
        .refreshable {
            await store.loadState()
        }
        .horizontalSwipe { direction in
            guard selectedDates.isEmpty else { return }
            moveMonth(direction)
        }
    }

    private func moveMonth(_ delta: Int) {
        let target = visibleMonth.shifted(by: delta)
        guard target.key >= store.profile.recordingStartMonthKey else { return }
        visibleMonth = target
        selectedDates.removeAll()
        selectedFromSelectAll = false
    }

    private func snapToRecordingStartIfNeeded() {
        guard visibleMonth.key < store.profile.recordingStartMonthKey,
              let startMonth = Month(key: store.profile.recordingStartMonthKey) else { return }
        visibleMonth = startMonth
        selectedDates.removeAll()
        selectedFromSelectAll = false
    }

    private func selectYear(_ year: Int) {
        let target = Month(year: year, month: visibleMonth.month)
        if target.key < store.profile.recordingStartMonthKey,
           let startMonth = Month(key: store.profile.recordingStartMonthKey) {
            visibleMonth = startMonth
        } else {
            visibleMonth = target
        }
        selectedDates.removeAll()
        selectedFromSelectAll = false
    }

    private var selectableYears: [Int] {
        let startYear = store.profile.recordingStartMonthParts.year
        guard startYear <= DateHelpers.currentYear + 3 else { return [startYear] }
        return Array(startYear...(DateHelpers.currentYear + 3))
    }
}
