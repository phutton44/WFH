import SwiftUI

struct QuarterScoreboardCard: View {
    @EnvironmentObject private var store: AttendanceStore
    let year: Int
    let mode: QuarterScoreboardMode
    var compact = false
    var dense = false
    var highlightedQuarter: Int?
    var cutoffISO: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: dense ? 5 : (compact ? 7 : 10)) {
                WidgetTitle(cutoffISO == nil ? mode.title : "Quarterly Outlook Forecast")

                HStack(spacing: dense ? 4 : (compact ? 6 : 10)) {
                    ForEach(1...4, id: \.self) { quarter in
                        QuarterTile(
                            title: "Q\(quarter)",
                            metrics: metrics(for: quarter),
                            isCurrent: quarter == activeQuarter,
                            percentageBasis: cutoffISO == nil ? mode.percentageBasis : .workingDays,
                            showsWorkingDays: true,
                            compact: compact,
                            dense: dense
                        )
                    }
                }
            }
            .padding(dense ? 6 : (compact ? 8 : 16))
            .cardStyle()
        }
    }

    private var currentQuarter: Int {
        let current = DateHelpers.todayParts()
        guard current.year == year else { return 0 }
        return ((current.month - 1) / 3) + 1
    }

    private var activeQuarter: Int {
        highlightedQuarter ?? currentQuarter
    }

    private func metrics(for quarter: Int) -> Metrics? {
        if let cutoffISO {
            let startMonth = (quarter - 1) * 3 + 1
            let endMonth = startMonth + 2
            let start = DateHelpers.iso(year: year, month: startMonth, day: 1)
            let endOfQuarter = DateHelpers.iso(year: year, month: endMonth, day: DateHelpers.daysInMonth(year: year, month: endMonth))
            let quarterMetrics = store.metrics(from: start, through: endOfQuarter, respectingRecordingStart: true)
            guard start <= cutoffISO else {
                var forecast = Metrics()
                forecast.workingDays = quarterMetrics.workingDays
                forecast.unassigned = quarterMetrics.workingDays
                return forecast
            }
            let loggedEnd = min(cutoffISO, endOfQuarter)
            var forecast = store.metrics(from: start, through: loggedEnd, respectingRecordingStart: true)
            forecast.workingDays = quarterMetrics.workingDays
            forecast.unassigned = max(0, quarterMetrics.workingDays - forecast.assignedWorkingDays)
            return forecast
        }

        let startMonth = (quarter - 1) * 3 + 1
        let endMonth = startMonth + 2
        let start = DateHelpers.iso(year: year, month: startMonth, day: 1)
        let endOfQuarter = DateHelpers.iso(year: year, month: endMonth, day: DateHelpers.daysInMonth(year: year, month: endMonth))
        return store.metrics(from: start, through: endOfQuarter, respectingRecordingStart: true)
    }
}

enum QuarterScoreboardMode {
    case recordedInformation

    var title: String {
        "Quarterly Outlook"
    }

    var percentageBasis: QuarterPercentageBasis {
        .recordedDays
    }
}

enum QuarterPercentageBasis {
    case workingDays
    case recordedDays
}

struct QuarterTile: View {
    let title: String
    let metrics: Metrics?
    let isCurrent: Bool
    let percentageBasis: QuarterPercentageBasis
    var showsWorkingDays = false
    var compact = false
    var dense = false

    var body: some View {
        VStack(spacing: dense ? 2 : (compact ? 4 : 8)) {
            Text(title)
                .font((compact ? Font.caption2 : Font.caption).weight(.heavy))
                .foregroundStyle(Color.primaryText)
            if let metrics {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(String(format: "%.0f", percentage(for: metrics)))
                        .font((compact ? Font.subheadline : Font.title2).weight(.bold))
                        .foregroundStyle(Color.officeBlue)
                    Text("%")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.primaryText)
                }
                HStack(spacing: 6) {
                    Label("\(metrics.office)", systemImage: "circle.fill")
                        .foregroundStyle(Color.officeBlue)
                    Label("\(metrics.wfh)", systemImage: "circle.fill")
                        .foregroundStyle(Color.wfhPurple)
                }
                .font(.caption2.weight(.semibold))
                if showsWorkingDays {
                    Text("\(metrics.workingDays) working")
                        .font(.system(size: compact ? 8 : 9, weight: .heavy))
                        .foregroundStyle(Color.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            } else {
                Text("-")
                    .font((compact ? Font.subheadline : Font.title).weight(.bold))
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
        .padding(.vertical, dense ? 5 : (compact ? 7 : 14))
        .background(Color.cardBackgroundElevated.opacity(isCurrent ? 1 : 0.35), in: RoundedRectangle(cornerRadius: compact ? 10 : 16, style: .continuous))
        .overlay {
            if isCurrent {
                RoundedRectangle(cornerRadius: compact ? 10 : 16, style: .continuous)
                    .stroke(Color.borderSubtle, lineWidth: 1.5)
            }
        }
    }

    private func percentage(for metrics: Metrics) -> Double {
        switch percentageBasis {
        case .workingDays:
            metrics.monthOfficeShare
        case .recordedDays:
            metrics.officeShare ?? 0
        }
    }
}
