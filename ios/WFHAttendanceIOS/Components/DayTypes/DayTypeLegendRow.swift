import SwiftUI

struct DayTypeLegendRow: View {
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 6 : 9) {
            ForEach(DayTypeInfo.primary) { item in
                HStack(spacing: 3) {
                    Circle()
                        .fill(item.color)
                        .frame(width: compact ? 5 : 6, height: compact ? 5 : 6)
                    Text(item.shortLabel)
                        .font(.system(size: compact ? 8 : 9, weight: .bold))
                        .foregroundStyle(Color.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            Spacer(minLength: 0)
        }
    }
}
