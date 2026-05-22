import SwiftUI

struct InsightsMonthHeader: View {
    let month: Month
    let scope: InsightScope
    let previous: () -> Void
    let next: () -> Void
    let today: () -> Void
    let canGoPrevious: Bool
    let printReport: () -> Void

    var body: some View {
        if scope == .year {
            yearHeader
        } else {
            monthHeader
        }
    }

    private var monthHeader: some View {
        ZStack {
            HStack {
                MonthNavButton(systemName: "chevron.left", isDisabled: !canGoPrevious, action: previous)
                Spacer()
                HStack(spacing: 8) {
                    PrintInsightButton(action: printReport)
                    MonthNavButton(systemName: "chevron.right", action: next)
                }
            }

            VStack(spacing: 3) {
                Text("Monthly Insights")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primaryText)
                Text(month.title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var yearHeader: some View {
        ZStack {
            HStack {
                MonthNavButton(systemName: "chevron.left", isDisabled: !canGoPrevious, action: previous)
                Spacer()
                HStack(spacing: 8) {
                    PrintInsightButton(action: printReport)
                    MonthNavButton(systemName: "chevron.right", action: next)
                }
            }

            VStack(spacing: 3) {
                Text("Yearly Insights")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primaryText)
                Text(String(month.year))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

struct PrintInsightButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "printer.fill")
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
        .accessibilityLabel("Print report")
    }
}
