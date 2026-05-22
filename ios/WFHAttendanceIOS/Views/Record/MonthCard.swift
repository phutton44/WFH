import SwiftUI

struct MonthCard: View {
    let days: [CalendarDay]
    let dayKinds: [String: DayKind]
    @Binding var selectedDates: Set<String>
    let columns: [GridItem]
    let isEditable: Bool
    let isBeforeRecordingStart: Bool
    let markManualSelection: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LazyVGrid(columns: columns, spacing: 5) {
                ForEach(Array(DateHelpers.weekdayLetters.enumerated()), id: \.offset) { _, label in
                    Text(label)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(days) { day in
                    if let iso = day.iso {
                        let kind = dayKinds[iso] ?? .unassigned
                        DayCell(
                            day: day.day,
                            kind: kind,
                            isSelected: selectedDates.contains(iso),
                            isToday: iso == DateHelpers.todayISO(),
                            isDisabled: isBeforeRecordingStart
                        )
                        .onTapGesture {
                            guard isEditable else { return }
                            guard kind != .weekend, kind != .bankHoliday else { return }
                            markManualSelection()
                            if selectedDates.contains(iso) {
                                selectedDates.remove(iso)
                            } else {
                                selectedDates.insert(iso)
                            }
                        }
                    } else {
                        Color.clear
                            .frame(height: 42)
                    }
                }
            }

            CalendarLegend()
        }
    }
}

struct CalendarLegend: View {
    private let items: [(String, Color)] = [
        ("Office", .officeBlue),
        ("WFH", .wfhPurple),
        ("Leave", .leaveOrange),
        ("Sick", .holidayGreen),
        ("NWD", .nwdGray),
        ("Bank holiday", .sickRed)
    ]

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 88), spacing: 8, alignment: .leading)],
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(items, id: \.0) { item in
                LegendItem(item.0, color: item.1)
            }
        }
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(.secondary)
        .minimumScaleFactor(0.72)
        .lineLimit(1)
        .padding(.top, 6)
    }
}

struct LegendItem: View {
    let label: String
    let color: Color

    init(_ label: String, color: Color) {
        self.label = label
        self.color = color
    }

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
        }
    }
}

struct DayCell: View {
    let day: Int
    let kind: DayKind
    let isSelected: Bool
    let isToday: Bool
    var isDisabled = false

    var body: some View {
        ZStack {
            dayNumber
                .offset(y: kind.tileLabel.isEmpty ? 0 : -6)

            if !kind.tileLabel.isEmpty {
                VStack {
                    Spacer()
                    Text(kind.tileLabel)
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(0.55)
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .foregroundStyle(tagColor)
                        .padding(.bottom, 5)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 42)
        .background(cellBackground, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            if isDisabled {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.black.opacity(0.32))
            }
        }
        .overlay {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(borderColor, lineWidth: isSelected ? 2.5 : (isToday ? 1.5 : 0))
                if isToday {
                    Circle()
                        .fill(Color.primaryText)
                        .frame(width: 5, height: 5)
                        .padding(5)
                }
            }
        }
        .opacity(isDisabled ? 0.46 : (kind == .weekend ? 0.58 : 1))
    }

    private var dayNumber: some View {
        Text("\(day)")
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
            .foregroundStyle(foregroundColor)
    }

    private var cellBackground: Color {
        if isSelected, kind == .unassigned { return Color.cardBackground.opacity(0.62) }
        switch kind {
        case .office:
            return Color.officeBlue.opacity(0.82)
        case .wfh:
            return Color.wfhPurple.opacity(0.82)
        case .leave:
            return Color.leaveOrange.opacity(0.82)
        case .sickness:
            return Color.holidayGreen.opacity(0.82)
        case .nwd:
            return Color.nwdGray.opacity(0.45)
        case .bankHoliday:
            return Color.sickRed.opacity(0.82)
        case .weekend:
            return Color.clear
        case .unassigned:
            return Color.clear
        }
    }

    private var borderColor: Color {
        if isSelected { return Color.holidayGreen }
        if isToday { return Color.primaryText.opacity(0.20) }
        return .clear
    }

    private var foregroundColor: Color {
        if kind == .weekend { return Color.slate }
        if !kind.tileLabel.isEmpty { return Color.black.opacity(0.82) }
        if kind == .unassigned { return .secondary }
        return Color.primaryText
    }

    private var tagColor: Color {
        switch kind {
        case .office, .wfh, .leave, .sickness, .nwd, .bankHoliday:
            return Color.black.opacity(0.82)
        case .weekend, .unassigned:
            return .secondary
        }
    }

}
