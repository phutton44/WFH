import SwiftUI

struct BulkUndoBar: View {
    let message: String
    let undo: () -> Void
    let keep: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(message)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.primaryText.opacity(0.88))

            HStack(spacing: 9) {
                Button(action: undo) {
                    Label("Undo", systemImage: "arrow.uturn.backward.circle.fill")
                        .font(.subheadline.weight(.heavy))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.primaryText)
                .background(Color.sickRed, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                Button(action: keep) {
                    Label("Keep it", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.heavy))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.black.opacity(0.86))
                .background(Color.holidayGreen, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.borderSubtle, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.32), radius: 18, y: 9)
    }
}

struct LeaveShortfallCard: View {
    let warning: LeaveShortfallWarning
    let dismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.sickRed, Color.leaveOrange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 86, height: 86)
                        .shadow(color: Color.sickRed.opacity(0.45), radius: 22, y: 10)

                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 46, weight: .black))
                        .foregroundStyle(Color.primaryText)
                }

                VStack(spacing: 8) {
                    Text("Hold up")
                        .font(.title2.weight(.black))
                        .foregroundStyle(Color.primaryText)

                    Text("You don't have enough annual leave left for \(String(warning.year)).")
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.primaryText.opacity(0.82))
                }

                HStack(spacing: 10) {
                    LeaveShortfallStat(title: "Left", value: warning.remaining, tint: .holidayGreen)
                    LeaveShortfallStat(title: "Requested", value: warning.requested, tint: .leaveOrange)
                    LeaveShortfallStat(title: "Deficit", value: warning.deficit, tint: .sickRed)
                }

                Text("Reduce the selected leave by \(warning.deficit) day\(warning.deficit == 1 ? "" : "s"), or increase your annual allowance in Settings.")
                    .font(.footnote.weight(.medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.primaryText.opacity(0.72))

                Button(action: dismiss) {
                    Text("Got it")
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(Color.black.opacity(0.88))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color.holidayGreen, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(18)
            .frame(maxWidth: 360)
            .background(Color.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.borderSubtle, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.45), radius: 26, y: 16)
            .padding(.horizontal, 24)
        }
    }
}

struct LeaveShortfallStat: View {
    let title: String
    let value: Int
    let tint: Color

    var body: some View {
        VStack(spacing: 5) {
            Text("\(value)")
                .font(.title3.weight(.black))
                .foregroundStyle(tint)

            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.primaryText.opacity(0.68))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(tint.opacity(0.28), lineWidth: 1)
        }
    }
}

struct SyncPill: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.75)
            Text(text)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
    }
}
