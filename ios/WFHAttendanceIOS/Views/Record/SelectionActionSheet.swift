import SwiftUI

struct SelectionActionSheet: View {
    let dates: Set<String>
    let apply: (DayKind) -> Void
    let clearEntries: () -> Void
    let dismiss: () -> Void
    @GestureState private var dragOffset: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(dates.count) day\(dates.count == 1 ? "" : "s") selected")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Color.primaryText)
                    Text("Tap a type to apply")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.title2)
                        .foregroundStyle(Color.primaryText)
                        .frame(width: 46, height: 46)
                        .background(Color.cardBackgroundElevated, in: Circle())
                }
                .buttonStyle(.plain)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                SheetTypeButton(kind: .office) { apply(.office) }
                SheetTypeButton(kind: .wfh) { apply(.wfh) }
                SheetTypeButton(kind: .leave) { apply(.leave) }
                SheetTypeButton(kind: .sickness) { apply(.sickness) }
                SheetTypeButton(kind: .nwd) { apply(.nwd) }
                SheetTypeButton(kind: .unassigned, title: "Clear") { clearEntries() }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 24)
        .background(.ultraThinMaterial, in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28))
        .overlay(alignment: .bottom) {
            Capsule()
                .fill(Color.primaryText.opacity(0.35))
                .frame(width: 140, height: 5)
                .padding(.bottom, 10)
        }
        .overlay {
            UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28)
                .stroke(Color.borderSubtle, lineWidth: 1)
        }
        .offset(y: max(0, dragOffset))
        .gesture(
            DragGesture(minimumDistance: 12)
                .updating($dragOffset) { value, state, _ in
                    guard value.translation.height > 0 else { return }
                    state = value.translation.height
                }
                .onEnded { value in
                    let isDownward = value.translation.height > abs(value.translation.width)
                    if isDownward, value.translation.height > 80 {
                        dismiss()
                    }
                }
        )
    }
}

struct SheetTypeButton: View {
    let kind: DayKind
    var title: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: kind.sheetIcon)
                    .font(.title2)
                    .foregroundStyle(kind.color)
                Text(title ?? kind.shortTitle)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(kind == .unassigned ? Color.sickRed : Color.primaryText)
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 82)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var backgroundColor: Color {
        if kind == .unassigned { return Color.sickRed.opacity(0.34) }
        return kind.color.opacity(0.42)
    }

    private var borderColor: Color {
        if kind == .unassigned { return Color.sickRed.opacity(0.55) }
        return kind.color.opacity(0.62)
    }
}
