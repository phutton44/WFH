import SwiftUI

struct WeekByWeekCard: View {
    @EnvironmentObject private var store: AttendanceStore
    let month: Month
    var compact = false
    var dense = false
    var cutoffISO: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: dense ? 2 : (compact ? 3 : 4)) {
                HStack(alignment: .firstTextBaseline) {
                    WidgetTitle("\(DateHelpers.monthNames[month.month - 1]) month view")
                    Spacer()
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("Current Date")
                            .font(.system(size: compact ? 8 : 9, weight: .heavy))
                            .foregroundStyle(Color.primaryText)
                            .textCase(.uppercase)
                        Text(DateHelpers.readableToday)
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(Color.holidayGreen)
                            .lineLimit(1)
                            .minimumScaleFactor(0.74)
                    }
                }
                .padding(.horizontal, 2)

                HStack {
                    ForEach(Array(DateHelpers.weekdayLetters.enumerated()), id: \.offset) { _, day in
                        Text(day)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.primaryText)
                            .frame(maxWidth: .infinity)
                    }
                }

                ForEach(monthRows.indices, id: \.self) { rowIndex in
                    HStack(spacing: dense ? 2 : (compact ? 3 : 4)) {
                        ForEach(monthRows[rowIndex], id: \.id) { cell in
                            WeekCell(cell: cell, compact: compact, dense: dense)
                        }
                    }
                }

                DayTypeLegendRow(compact: compact)
                    .padding(.top, dense ? 1 : (compact ? 2 : 4))
            }
            .padding(dense ? 5 : (compact ? 6 : 8))
            .cardStyle()
        }
    }

    private var monthRows: [[InsightWeekCell]] {
        var cells = month.gridDays.map { day in
            guard let iso = day.iso else {
                return InsightWeekCell(id: day.id, day: nil, kind: .unassigned, inMonth: false, isToday: false)
            }
            let actualKind = store.kind(for: iso)
            let kind = displayKind(for: iso, actualKind: actualKind)
            return InsightWeekCell(id: iso, day: day.day, kind: kind, inMonth: true, isToday: iso == DateHelpers.todayISO())
        }
        while !cells.count.isMultiple(of: 7) {
            cells.append(InsightWeekCell(id: "empty-tail-\(cells.count)", day: nil, kind: .unassigned, inMonth: false, isToday: false))
        }
        return stride(from: 0, to: cells.count, by: 7).map { startIndex in
            Array(cells[startIndex..<min(startIndex + 7, cells.count)])
        }
    }

    private func displayKind(for iso: String, actualKind: DayKind) -> DayKind {
        guard let cutoffISO, iso > cutoffISO else { return actualKind }
        switch actualKind {
        case .weekend, .bankHoliday:
            return actualKind
        default:
            return .unassigned
        }
    }
}

struct InsightWeekCell: Identifiable {
    let id: String
    let day: Int?
    let kind: DayKind
    let inMonth: Bool
    let isToday: Bool
}

struct WeekCell: View {
    let cell: InsightWeekCell
    var compact = false
    var dense = false

    var body: some View {
        Text(cell.day.map(String.init) ?? "")
            .font((compact ? Font.caption2 : Font.caption).weight(.bold))
            .foregroundStyle(cell.inMonth ? .white : .clear)
            .frame(maxWidth: .infinity)
            .frame(height: dense ? 15 : (compact ? 18 : 23))
            .background(cell.inMonth ? cell.kind.insightColor : Color.clear, in: RoundedRectangle(cornerRadius: compact ? 4 : 5, style: .continuous))
            .overlay(alignment: .bottom) {
                if cell.isToday {
                    Text(".")
                        .font(.system(size: compact ? 13 : 15, weight: .black))
                        .foregroundStyle(Color.primaryText)
                        .offset(y: compact ? 4 : 5)
                }
            }
    }
}
