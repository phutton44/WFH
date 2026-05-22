import SwiftUI

struct YearCompositionLeaveCard: View {
    let year: Int
    let metrics: Metrics
    let leave: LeaveBreakdown
    let bankHolidayCount: Int
    let rangeLabel: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Year composition")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.primaryText)
                if let rangeLabel {
                    Text(rangeLabel)
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(Color.holidayGreen)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("\(metrics.assignedWorkingDays) of \(metrics.workingDays) working days logged")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            CompositionBar(metrics: metrics)

            LazyVGrid(columns: compactColumns, alignment: .leading, spacing: 6) {
                MonthDetailPill(label: "Office", value: metrics.office, color: .officeBlue, compact: true)
                MonthDetailPill(label: "WFH", value: metrics.wfh, color: .wfhPurple, compact: true)
                MonthDetailPill(label: "Sick", value: metrics.sickness, color: .holidayGreen, compact: true)
                MonthDetailPill(label: "NWD", value: metrics.nwd, color: .nwdGray, compact: true)
                MonthDetailPill(label: "Bank holiday", value: bankHolidayCount, color: .sickRed, compact: true)
                MonthDetailPill(label: "Unassigned", value: metrics.unassigned, color: Color.unassignedFill, compact: true)
            }

            LeaveInfographicCard(leave: leave)
        }
        .padding(11)
        .cardStyle()
    }

    private var compactColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 6),
            GridItem(.flexible(), spacing: 6)
        ]
    }
}
