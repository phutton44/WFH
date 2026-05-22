import SwiftUI

struct MonthHeader: View {
    let month: Month
    let metrics: Metrics
    let previous: () -> Void
    let next: () -> Void
    let selectYear: (Int) -> Void
    let yearOptions: [Int]
    let isLocked: Bool
    let isBeforeRecordingStart: Bool
    let canGoPrevious: Bool
    let showDaysExplained: () -> Void
    let toggleLock: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Menu {
                        ForEach(yearOptions, id: \.self) { year in
                            Button(String(year)) {
                                selectYear(year)
                            }
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
                        .foregroundStyle(Color.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text("\(metrics.workingDays) working days · \(metrics.unassigned) unassigned")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.primaryText)
                    if isBeforeRecordingStart {
                        Text("Before recording start")
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(Color.primaryText)
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    RecordInfoButton(action: showDaysExplained)
                    LockMonthButton(isLocked: isLocked, isDisabled: isBeforeRecordingStart, action: toggleLock)
                    MonthNavButton(systemName: "chevron.left", isDisabled: !canGoPrevious, action: previous)
                    MonthNavButton(systemName: "chevron.right", action: next)
                }
                .padding(.top, 2)
            }
        }
    }
}

struct RecordInfoButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "info.circle.fill")
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.holidayGreen)
                .frame(width: 36, height: 36)
                .background(Color.cardBackgroundElevated, in: Circle())
                .overlay {
                    Circle()
                        .stroke(Color.borderSubtle, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Day Types Explained")
    }
}

struct LockMonthButton: View {
    let isLocked: Bool
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isDisabled ? "lock.fill" : (isLocked ? "lock.fill" : "lock.open.fill"))
                .font(.title3.weight(.bold))
                .foregroundStyle(isDisabled ? Color.secondary : (isLocked ? Color.black.opacity(0.84) : Color.holidayGreen))
                .frame(width: 36, height: 36)
                .background(isDisabled ? Color.cardBackgroundElevated.opacity(0.55) : (isLocked ? Color.holidayGreen : Color.cardBackgroundElevated), in: Circle())
                .overlay {
                    Circle()
                        .stroke(isLocked && !isDisabled ? Color.holidayGreen.opacity(0.38) : Color.borderSubtle, lineWidth: 1)
                }
                .shadow(color: isLocked && !isDisabled ? Color.holidayGreen.opacity(0.45) : .clear, radius: 14)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(isDisabled ? "Before recording start" : (isLocked ? "Unlock month" : "Lock month"))
    }
}
