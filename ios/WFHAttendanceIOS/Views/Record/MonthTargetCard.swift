import SwiftUI

struct MonthTargetCard: View {
    let metrics: Metrics
    let target: Double

    var body: some View {
        let share = metrics.monthOfficeShare
        let onTarget = share >= target
        let targetOffset = CGFloat(min(max(target / 100, 0), 1))
        let officeOffset = CGFloat(min(max(share / 100, 0), 1))
        let unassignedOffset = CGFloat(min(max(Double(metrics.unassigned) / Double(max(metrics.workingDays, 1)), 0), 1))
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(share, specifier: "%.0f")")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.primaryText)
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

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("\(metrics.unassigned) unassigned")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(metrics.unassigned == 0 ? Color.holidayGreen : Color.leaveOrange)
                    Spacer()
                    Text("\(metrics.workingDays) working days")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.officeBlue.opacity(0.86))
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.cardBackgroundElevated)
                            .overlay {
                                Capsule()
                                    .stroke(Color.borderSubtle, lineWidth: 1)
                            }
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color.holidayGreen, Color.officeBlue],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: proxy.size.width * (1 - unassignedOffset))
                            .shadow(color: Color.officeBlue.opacity(0.38), radius: 8)
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color.leaveOrange, Color.sickRed],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: proxy.size.width * unassignedOffset)
                            .offset(x: proxy.size.width * (1 - unassignedOffset))
                            .shadow(color: Color.leaveOrange.opacity(0.36), radius: 8)
                    }
                }
                .frame(height: 10)
            }

            Divider()
                .overlay(Color.borderSubtle)

            HStack {
                Text(targetHelpText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.primaryText)
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
        if metrics.workingDays == 0 {
            return "No working days in this month."
        }
        let needed = metrics.officeDaysNeededForMonthTarget(target)
        if needed <= 0 {
            if metrics.unassigned == 0 {
                return String(format: "Month complete and on target for %.0f%%.", target)
            }
            return String(format: "On target so far. \(metrics.unassigned) day\(metrics.unassigned == 1 ? "" : "s") still to assign.")
        }
        if needed > metrics.unassigned {
            return String(format: "\(needed) more office day\(needed == 1 ? "" : "s") needed for %.0f%%.", target)
        }
        return String(format: "\(needed) office day\(needed == 1 ? "" : "s") needed for %.0f%%.", target)
    }
}
