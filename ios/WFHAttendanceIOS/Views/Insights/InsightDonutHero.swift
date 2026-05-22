import SwiftUI

struct InsightDonutHero: View {
    let month: Month
    let title: String
    let metrics: Metrics
    let outlookMetrics: Metrics?
    let percent: Double
    let target: Double
    var compact = false
    var dense = false

    var body: some View {
        Group {
            if compact {
                VStack(alignment: .leading, spacing: 6) {
                    WidgetTitle(title)

                    HStack(spacing: 12) {
                        ZStack {
                            DonutRing(office: metrics.office, wfh: metrics.wfh, lineWidth: 13)
                                .frame(width: 66, height: 66)
                            Text("\(percent, specifier: "%.0f")")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.primaryText)
                            + Text("%")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.primaryText)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(statusTitle)
                                .font(.caption.weight(.heavy))
                                .foregroundStyle(statusTint)
                            HStack(spacing: 10) {
                                HeroKeyRow(value: metrics.office, label: "Office", color: .officeBlue)
                                HeroKeyRow(value: metrics.wfh, label: "WFH", color: .wfhPurple)
                            }
                            HeroKeyRow(value: metrics.tracked, label: "Worked", color: Color.primaryText.opacity(0.78))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: dense ? 8 : 13) {
                    WidgetTitle(title)

                    HStack(alignment: .center, spacing: dense ? 10 : 16) {
                        ZStack {
                            DonutRing(office: metrics.office, wfh: metrics.wfh, lineWidth: dense ? 14 : 18)
                                .frame(width: dense ? 88 : 112, height: dense ? 88 : 112)
                            Text("\(percent, specifier: "%.0f")")
                                .font(.system(size: dense ? 27 : 32, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.primaryText)
                            + Text("%")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(Color.primaryText)
                        }

                        VStack(alignment: .leading, spacing: dense ? 6 : 10) {
                            HStack(spacing: 7) {
                                Text(statusTitle)
                                    .font(.subheadline.weight(.heavy))
                                    .foregroundStyle(statusTint)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                Text("\(Int(target.rounded()))% target")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(Color.primaryText)
                                    .lineLimit(1)
                            }

                            HStack(spacing: 7) {
                                HeroMetricTile(value: metrics.office, label: "Office", color: .officeBlue, dense: dense)
                                HeroMetricTile(value: metrics.wfh, label: "WFH", color: .wfhPurple, dense: dense)
                            }

                            HeroMetricTile(value: metrics.tracked, label: "Worked days", color: Color.primaryText.opacity(0.72), dense: dense)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    VStack(spacing: dense ? 5 : 7) {
                        HeroInsightChip(text: targetInsightText, tint: targetInsightTint, dense: dense)
                        HeroInsightChip(text: loggedInsightText, tint: workingDaysAhead == 0 ? .officeBlue : .leaveOrange, dense: dense)
                    }
                }
            }
        }
        .padding(compact ? 9 : (dense ? 10 : 14))
        .cardStyle()
    }

    private var targetInsightText: String {
        if let outlookMetrics {
            let requiredOfficeDays = Int(ceil((target / 100) * Double(outlookMetrics.workingDays)))
            let needed = max(0, requiredOfficeDays - metrics.office)
            let targetLabel = "\(Int(target.rounded()))%"
            if needed == 0 {
                return "Monthly \(targetLabel) forecast met with \(metrics.office) office day\(metrics.office == 1 ? "" : "s") logged"
            }
            return "Need \(needed) office day\(needed == 1 ? "" : "s")"
        }

        let delta = percent - target
        if delta >= 0 {
            return "\(String(format: "%.0f", delta)) percentage points above your \(Int(target.rounded()))% target"
        }

        let needed = metrics.officeDaysNeededForMonthTarget(target)
        if needed == 0 {
            return "\(String(format: "%.0f", abs(delta))) percentage points below your \(Int(target.rounded()))% target"
        }
        return "\(needed) more office day\(needed == 1 ? "" : "s") needed to reach \(Int(target.rounded()))%"
    }

    private var loggedInsightText: String {
        if outlookMetrics != nil {
            if workingDaysAhead == 0 {
                return "No working days left ahead in this month"
            }
            return "\(workingDaysAhead) working day\(workingDaysAhead == 1 ? "" : "s") still ahead this month"
        }

        if metrics.unassigned == 0 {
            return "All \(metrics.workingDays) working days are logged"
        }
        return "\(metrics.unassigned) working day\(metrics.unassigned == 1 ? "" : "s") still unassigned"
    }

    private var workingDaysAhead: Int {
        guard let outlookMetrics else { return 0 }
        return max(0, outlookMetrics.workingDays - metrics.workingDays)
    }

    private var isOnTarget: Bool {
        guard let outlookMetrics else { return percent >= target }
        let requiredOfficeDays = Int(ceil((target / 100) * Double(outlookMetrics.workingDays)))
        return metrics.office >= requiredOfficeDays
    }

    private var statusTitle: String {
        isOnTarget ? "On target" : (outlookMetrics == nil ? "Below target" : "Need to attend office")
    }

    private var statusTint: Color {
        isOnTarget ? .holidayGreen : .sickRed
    }

    private var targetInsightTint: Color {
        statusTint
    }
}

struct HeroMetricTile: View {
    let value: Int
    let label: String
    let color: Color
    var dense = false

    var body: some View {
        VStack(alignment: .leading, spacing: dense ? 2 : 4) {
            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                Text(label)
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(Color.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            Text("\(value)")
                .font((dense ? Font.subheadline : Font.title3).weight(.black))
                .foregroundStyle(Color.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, dense ? 7 : 8)
        .padding(.vertical, dense ? 6 : 9)
        .background(Color.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: dense ? 8 : 10, style: .continuous))
    }
}

struct HeroInsightChip: View {
    let text: String
    let tint: Color
    var dense = false

    var body: some View {
        Text(text)
            .font((dense ? Font.caption2 : Font.caption).weight(.heavy))
            .foregroundStyle(tint)
            .lineLimit(2)
            .minimumScaleFactor(0.82)
            .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, dense ? 8 : 10)
        .padding(.vertical, dense ? 6 : 9)
        .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: dense ? 8 : 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: dense ? 8 : 10, style: .continuous)
                .stroke(tint.opacity(0.20), lineWidth: 1)
        }
    }
}

struct HeroKeyRow: View {
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 8, height: 8)
            Text("\(value)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.primaryText)
                .frame(width: 25, alignment: .leading)
            Text(label.uppercased())
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.35)
                .foregroundStyle(Color.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            Spacer(minLength: 0)
        }
    }
}

struct DonutRing: View {
    let office: Int
    let wfh: Int
    var lineWidth: CGFloat = 20

    var body: some View {
        let total = max(office + wfh, 1)
        let officeEnd = Double(office) / Double(total)
        ZStack {
            Circle()
                .stroke(Color.cardBackgroundElevated, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: 1)
                .stroke(Color.wfhPurple, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Circle()
                .trim(from: 0, to: officeEnd)
                .stroke(Color.officeBlue, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}
