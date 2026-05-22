import SwiftUI

struct MonthDetailsCard: View {
    let month: Month
    let metrics: Metrics
    let leave: LeaveBreakdown
    let bankHolidayCount: Int
    var compact = false
    var dense = false
    var rangeLabel: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: dense ? 5 : (compact ? 7 : 10)) {
                monthComposition
            }
            .padding(dense ? 6 : (compact ? 8 : 11))
            .cardStyle()
        }
    }

    private var monthComposition: some View {
        VStack(alignment: .leading, spacing: dense ? 5 : (compact ? 7 : 9)) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(DateHelpers.monthNames[month.month - 1]) composition")
                            .font((compact ? Font.caption : Font.subheadline).weight(.bold))
                            .foregroundStyle(Color.primaryText)
                        if let rangeLabel {
                            Text(rangeLabel)
                                .font(.caption2.weight(.heavy))
                                .foregroundStyle(Color.holidayGreen)
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                        }
                    }
                    Text("\(metrics.assignedWorkingDays) of \(metrics.workingDays) working days logged")
                        .font((compact ? Font.caption2 : Font.caption).weight(.semibold))
                        .foregroundStyle(Color.primaryText)
                }
                Spacer()
                Text("\(Int(metrics.monthOfficeShare.rounded()))%")
                    .font((compact ? Font.subheadline : Font.title3).weight(.black))
                    .foregroundStyle(Color.officeBlue)
            }

            CompositionBar(metrics: metrics)

            LazyVGrid(columns: compactColumns, alignment: .leading, spacing: dense ? 4 : (compact ? 5 : 8)) {
                MonthDetailPill(label: "Office", value: metrics.office, color: .officeBlue, compact: compact)
                MonthDetailPill(label: "WFH", value: metrics.wfh, color: .wfhPurple, compact: compact)
                MonthDetailPill(label: "Leave", value: metrics.leave, color: .leaveOrange, compact: compact)
                MonthDetailPill(label: "Sick", value: metrics.sickness, color: .holidayGreen, compact: compact)
                MonthDetailPill(label: "NWD", value: metrics.nwd, color: .nwdGray, compact: compact)
                MonthDetailPill(label: "Bank holiday", value: bankHolidayCount, color: .sickRed, compact: compact)
                MonthDetailPill(label: "Unassigned", value: metrics.unassigned, color: Color.unassignedFill, compact: compact)
            }
        }
    }

    private var compactColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: compact ? 5 : 8),
            GridItem(.flexible(), spacing: compact ? 5 : 8),
            GridItem(.flexible(), spacing: compact ? 5 : 8)
        ]
    }
}

struct MonthDetailPill: View {
    let label: String
    let value: Int
    let color: Color
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 4 : 6) {
            Circle()
                .fill(color)
                .frame(width: compact ? 6 : 7, height: compact ? 6 : 7)
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 2)
            Text("\(value)")
                .font((compact ? Font.caption2 : Font.caption).weight(.heavy))
                .foregroundStyle(Color.primaryText)
        }
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 5 : 8)
        .background(Color.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous))
    }
}
