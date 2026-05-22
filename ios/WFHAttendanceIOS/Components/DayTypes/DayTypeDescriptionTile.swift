import SwiftUI

struct DayTypeDescriptionTile: View {
    let item: DayTypeInfo
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 5) {
            HStack(spacing: 5) {
                Circle()
                    .fill(item.color)
                    .frame(width: compact ? 6 : 7, height: compact ? 6 : 7)
                Text(item.shortLabel)
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Text(item.description)
                .font(.system(size: compact ? 8 : 9, weight: .semibold))
                .foregroundStyle(Color.white)
                .lineLimit(compact ? 2 : 3)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, minHeight: compact ? 43 : 52, alignment: .topLeading)
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 6 : 8)
        .background(Color.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous))
    }
}
