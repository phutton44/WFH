import SwiftUI

struct LeaveInfographicCard: View {
    let leave: LeaveBreakdown

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(Color.borderSubtle, lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: usedProgress)
                        .stroke(
                            AngularGradient(colors: [.leaveTaken, .leaveBooked, .holidayGreen, .leaveTaken], center: .center),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(leave.remaining)")
                            .font(.system(size: 25, weight: .black, design: .rounded))
                            .foregroundStyle(leave.remaining < 0 ? Color.sickRed : Color.primaryText)
                            .monospacedDigit()
                        Text("LEFT")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 86, height: 86)

                VStack(alignment: .leading, spacing: 7) {
                    Text(statusText)
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(statusColor)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)

                    LeaveSegmentBar(leave: leave)
                        .frame(height: 12)

                    HStack(spacing: 7) {
                        LeaveMiniStat(label: "Taken", value: leave.taken, color: .leaveTaken)
                        LeaveMiniStat(label: "Booked", value: leave.booked, color: .leaveBooked)
                        LeaveMiniStat(label: "Allowance", value: leave.allowance, color: .nwdGray)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 8) {
                LeaveLegendPill(label: "Used", value: leave.taken + leave.booked, color: .leaveOrange)
                LeaveLegendPill(label: "Free", value: max(0, leave.remaining), color: .holidayGreen)
                if leave.remaining < 0 {
                    LeaveLegendPill(label: "Over", value: abs(leave.remaining), color: .sickRed)
                }
            }
        }
        .padding(10)
        .background(Color.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.borderSubtle, lineWidth: 1)
        }
    }

    private var usedProgress: Double {
        guard leave.allowance > 0 else { return 0 }
        return min(max(Double(leave.taken + leave.booked) / Double(leave.allowance), 0), 1)
    }

    private var statusText: String {
        if leave.remaining < 0 {
            return "\(abs(leave.remaining)) day\(abs(leave.remaining) == 1 ? "" : "s") over allowance"
        }
        if leave.remaining == 0 {
            return "Allowance fully planned"
        }
        return "\(leave.remaining) day\(leave.remaining == 1 ? "" : "s") still available"
    }

    private var statusColor: Color {
        leave.remaining < 0 ? .sickRed : (leave.remaining == 0 ? .leaveOrange : .holidayGreen)
    }
}

struct LeaveSegmentBar: View {
    let leave: LeaveBreakdown

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                Segment(count: leave.taken, total: total, width: proxy.size.width, color: .leaveTaken)
                Segment(count: leave.booked, total: total, width: proxy.size.width, color: .leaveBooked)
                Segment(count: max(0, leave.remaining), total: total, width: proxy.size.width, color: .holidayGreen.opacity(0.55))
            }
            .clipShape(Capsule())
            .background(Color.borderSubtle, in: Capsule())
        }
    }

    private var total: Int {
        max(leave.allowance, leave.taken + leave.booked, 1)
    }
}

struct LeaveMiniStat: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.subheadline.weight(.black))
                .foregroundStyle(Color.primaryText)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LeaveLegendPill: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 2)
            Text("\(value)")
                .font(.caption2.weight(.black))
                .foregroundStyle(Color.primaryText)
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
