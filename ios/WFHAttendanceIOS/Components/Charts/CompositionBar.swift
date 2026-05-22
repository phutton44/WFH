import SwiftUI

struct CompositionBar: View {
    let metrics: Metrics

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 1) {
                Segment(count: metrics.office, total: metrics.workingDays, width: proxy.size.width, color: .officeBlue)
                Segment(count: metrics.wfh, total: metrics.workingDays, width: proxy.size.width, color: .wfhPurple)
                Segment(count: metrics.sickness, total: metrics.workingDays, width: proxy.size.width, color: .holidayGreen)
                Segment(count: metrics.unassigned, total: metrics.workingDays, width: proxy.size.width, color: Color.unassignedFill)
            }
            .clipShape(Capsule())
            .background(Color.unassignedFill, in: Capsule())
        }
        .frame(height: 8)
    }
}

struct Segment: View {
    let count: Int
    let total: Int
    let width: CGFloat
    let color: Color

    var body: some View {
        color
            .frame(width: total > 0 ? max(count == 0 ? 0 : 2, width * CGFloat(count) / CGFloat(total)) : 0)
    }
}
