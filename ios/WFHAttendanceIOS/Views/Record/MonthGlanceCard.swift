import SwiftUI

struct MonthGlanceCard: View {
    let month: Month
    let metrics: Metrics
    let isEditable: Bool
    let selectAllWorkingDays: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(DateHelpers.monthNames[month.month - 1]) at a glance")
                    .font(.caption2.weight(.heavy))
                    .tracking(1.6)
                    .foregroundStyle(Color.white)
                    .textCase(.uppercase)

                Text("\(metrics.tracked) of \(metrics.workingDays) working days tracked.")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.primaryText)

                CompositionBar(metrics: metrics)

                LazyVGrid(columns: glanceColumns, spacing: 5) {
                    GlanceStat(label: "Office", value: metrics.office, color: .officeBlue)
                    GlanceStat(label: "WFH", value: metrics.wfh, color: .wfhPurple)
                    GlanceStat(label: "Leave", value: metrics.leave, color: .leaveOrange)
                    GlanceStat(label: "Sick", value: metrics.sickness, color: .holidayGreen)
                    GlanceStat(label: "NWD", value: metrics.nwd, color: .nwdGray)
                    GlanceStat(label: "Bank holiday", value: bankHolidayCount, color: .sickRed)
                    GlanceStat(label: "Unassigned", value: metrics.unassigned, color: .secondary)
                }
            }
            .padding(9)
            .cardStyle()

            GlanceActionButton(title: "Select all working days") {
                guard isEditable else { return }
                selectAllWorkingDays()
            }
            .padding(.top, 5)
            .opacity(isEditable ? 1 : 0.55)
        }
    }

    private var bankHolidayCount: Int {
        var count = 0
        DateHelpers.forEachDate(from: month.startISO, through: month.endISO) { iso in
            if DateHelpers.isBankHoliday(iso) {
                count += 1
            }
        }
        return count
    }

    private var glanceColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 4), count: 4)
    }
}

struct GlanceActionButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.heavy))
                .foregroundStyle(Color.black.opacity(0.84))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .padding(.vertical, 12)
                .background(Color.holidayGreen.opacity(0.92), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.borderSubtle, lineWidth: 1)
                }
                .shadow(color: Color.holidayGreen.opacity(0.30), radius: 12, y: 6)
        }
        .buttonStyle(GlowingPressButtonStyle())
    }
}

struct GlowingPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .brightness(configuration.isPressed ? 0.08 : 0)
            .animation(.spring(response: 0.22, dampingFraction: 0.62), value: configuration.isPressed)
    }
}

struct GlanceStat: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 3, height: 17)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(value)")
                    .font(.caption.bold())
                    .foregroundStyle(Color.primaryText)
                Text(label)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 24, alignment: .topLeading)
    }
}
