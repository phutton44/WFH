import QuickLook
import SwiftUI
import UIKit

struct GeneratedYearReport: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
}

struct YearReportPDFRenderer {
    static func render(year: Int, profile: AttendanceProfile, userEmail: String?) throws -> URL {
        let report = YearReportData(year: year, profile: profile, userEmail: userEmail)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WFH-Attendance-\(year)-Report.pdf")

        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        try renderer.writePDF(to: url) { context in
            context.beginPage()
            draw(report: report, in: page)
            context.beginPage()
            drawMonthMapsPage(report: report, in: page)
        }
        return url
    }

    private static func draw(report: YearReportData, in page: CGRect) {
        let margin: CGFloat = 30
        let contentWidth = page.width - margin * 2

        Palette.paper.setFill()
        UIBezierPath(rect: page).fill()

        drawText(report.yearTitle, in: CGRect(x: margin, y: 25, width: 390, height: 26), font: .boldSystemFont(ofSize: 19), color: Palette.ink)
        drawText("Annual Attendance Insights", in: CGRect(x: margin, y: 53, width: 260, height: 16), font: .systemFont(ofSize: 10, weight: .semibold), color: Palette.muted)
        drawText(report.ownerLine, in: CGRect(x: page.width - margin - 270, y: 31, width: 270, height: 14), font: .systemFont(ofSize: 8.5, weight: .semibold), color: Palette.muted, alignment: .right)
        drawText("Generated \(DateHelpers.readableToday)", in: CGRect(x: page.width - margin - 270, y: 49, width: 270, height: 14), font: .systemFont(ofSize: 8.5), color: Palette.muted, alignment: .right)

        let heroY: CGFloat = 82
        let heroHeight: CGFloat = 118
        drawHeroScore(report: report, rect: CGRect(x: margin, y: heroY, width: 178, height: heroHeight))
        drawInsightPanel(report: report, rect: CGRect(x: margin + 194, y: heroY, width: contentWidth - 194, height: heroHeight))

        drawTargetOutlook(report: report, rect: CGRect(x: margin, y: 217, width: contentWidth, height: 142))

        let splitGap: CGFloat = 14
        let splitWidth = (contentWidth - splitGap) / 2
        drawCompositionPanel(report: report, rect: CGRect(x: margin, y: 375, width: splitWidth, height: 126))
        drawActionPanel(report: report, rect: CGRect(x: margin + splitWidth + splitGap, y: 375, width: splitWidth, height: 126))

        drawCompactMonthlyTable(rows: report.months, x: margin, y: 518, width: contentWidth)
        drawLeaveFooter(report: report, rect: CGRect(x: margin, y: 746, width: contentWidth, height: 58))

        drawText(
            "Leave, bank holidays and non-working days are excluded from office-target working-day totals.",
            in: CGRect(x: margin, y: page.height - 27, width: contentWidth, height: 12),
            font: .systemFont(ofSize: 7.5),
            color: Palette.muted,
            alignment: .center
        )
    }

    private static func drawMonthMapsPage(report: YearReportData, in page: CGRect) {
        let margin: CGFloat = 30
        let contentWidth = page.width - margin * 2

        Palette.paper.setFill()
        UIBezierPath(rect: page).fill()

        drawText("Year Month Maps", in: CGRect(x: margin, y: 25, width: 300, height: 24), font: .boldSystemFont(ofSize: 20), color: Palette.ink)
        drawText(report.monthMapSubtitle, in: CGRect(x: margin, y: 51, width: 340, height: 14), font: .systemFont(ofSize: 8.6, weight: .semibold), color: Palette.muted)
        drawText(report.ownerLine, in: CGRect(x: page.width - margin - 270, y: 31, width: 270, height: 14), font: .systemFont(ofSize: 8.5, weight: .semibold), color: Palette.muted, alignment: .right)
        drawText("Generated \(DateHelpers.readableToday)", in: CGRect(x: page.width - margin - 270, y: 49, width: 270, height: 14), font: .systemFont(ofSize: 8.5), color: Palette.muted, alignment: .right)

        let cardGap: CGFloat = 10
        let cardWidth = (contentWidth - cardGap * 2) / 3
        let cardHeight: CGFloat = 157
        let startY: CGFloat = 83
        for (index, row) in report.months.enumerated() {
            let column = index % 3
            let cardRow = index / 3
            let rect = CGRect(
                x: margin + CGFloat(column) * (cardWidth + cardGap),
                y: startY + CGFloat(cardRow) * (cardHeight + cardGap),
                width: cardWidth,
                height: cardHeight
            )
            drawYearMonthMap(row: row, rect: rect, target: report.target)
        }

        drawText(
            "Months before the recording start are shown out of scope and excluded from annual totals.",
            in: CGRect(x: margin, y: page.height - 27, width: contentWidth, height: 12),
            font: .systemFont(ofSize: 7.5),
            color: Palette.muted,
            alignment: .center
        )
    }

    private static func drawHeroScore(report: YearReportData, rect: CGRect) {
        drawRoundedRect(rect, fill: Palette.card, stroke: Palette.line, radius: 14)
        drawText("Office score", in: CGRect(x: rect.minX + 14, y: rect.minY + 12, width: rect.width - 28, height: 12), font: .systemFont(ofSize: 8.5, weight: .heavy), color: Palette.muted)
        drawProgressRing(
            percent: report.officeShare,
            target: report.target,
            center: CGPoint(x: rect.minX + 55, y: rect.minY + 60),
            radius: 28
        )
        drawText(report.percentText(report.officeShare), in: CGRect(x: rect.minX + 102, y: rect.minY + 33, width: 62, height: 30), font: .boldSystemFont(ofSize: 24), color: Palette.ink, alignment: .center)
        drawText("target \(report.percentText(report.target))", in: CGRect(x: rect.minX + 102, y: rect.minY + 63, width: 62, height: 13), font: .systemFont(ofSize: 8, weight: .semibold), color: Palette.muted, alignment: .center)

        let statusColor = report.officeDaysNeeded == 0 ? Palette.wfh : Palette.sick
        statusColor.setFill()
        UIBezierPath(roundedRect: CGRect(x: rect.minX + 14, y: rect.maxY - 19, width: rect.width - 28, height: 13), cornerRadius: 6.5).fill()
        drawText(report.officeDaysNeeded == 0 ? "On target" : "\(report.officeDaysNeeded) office days needed", in: CGRect(x: rect.minX + 18, y: rect.maxY - 17, width: rect.width - 36, height: 9), font: .systemFont(ofSize: 7, weight: .bold), color: .white, alignment: .center)
    }

    private static func drawInsightPanel(report: YearReportData, rect: CGRect) {
        drawRoundedRect(rect, fill: Palette.card, stroke: Palette.line, radius: 14)
        drawText(report.headline, in: CGRect(x: rect.minX + 14, y: rect.minY + 12, width: rect.width - 28, height: 17), font: .boldSystemFont(ofSize: 13), color: Palette.ink)
        drawWrappedText(report.summary, in: CGRect(x: rect.minX + 14, y: rect.minY + 33, width: rect.width - 28, height: 32), font: .systemFont(ofSize: 8.7, weight: .medium), color: Palette.muted)

        let chips = [
            ("Logged", "\(report.loggedDays)/\(report.compositionTotal)"),
            ("Office", "\(report.yearMetrics.office)"),
            ("WFH", "\(report.yearMetrics.wfh)"),
            ("Unassigned", "\(report.yearMetrics.unassigned)")
        ]
        let chipGap: CGFloat = 7
        let chipWidth = (rect.width - 28 - chipGap * 3) / 4
        for (index, chip) in chips.enumerated() {
            let chipRect = CGRect(x: rect.minX + 14 + CGFloat(index) * (chipWidth + chipGap), y: rect.maxY - 40, width: chipWidth, height: 26)
            drawRoundedRect(chipRect, fill: Palette.paper, stroke: Palette.line, radius: 8)
            drawText(chip.0, in: CGRect(x: chipRect.minX + 5, y: chipRect.minY + 4, width: chipRect.width - 10, height: 9), font: .systemFont(ofSize: 6.5, weight: .semibold), color: Palette.muted, alignment: .center)
            drawText(chip.1, in: CGRect(x: chipRect.minX + 5, y: chipRect.minY + 13, width: chipRect.width - 10, height: 11), font: .systemFont(ofSize: 9, weight: .bold), color: Palette.ink, alignment: .center)
        }
    }

    private static func drawTargetOutlook(report: YearReportData, rect: CGRect) {
        drawRoundedRect(rect, fill: Palette.card, stroke: Palette.line, radius: 14)
        drawText("Office target outlook", in: CGRect(x: rect.minX + 14, y: rect.minY + 12, width: 180, height: 14), font: .boldSystemFont(ofSize: 12), color: Palette.ink)
        drawText("A cleaner view of where the year stands and how the remaining unassigned days need to land.", in: CGRect(x: rect.minX + 14, y: rect.minY + 29, width: rect.width - 28, height: 11), font: .systemFont(ofSize: 7.5, weight: .medium), color: Palette.muted)

        let gap: CGFloat = 18
        let columnWidth = (rect.width - 28 - gap) / 2
        let left = CGRect(x: rect.minX + 14, y: rect.minY + 54, width: columnWidth, height: 66)
        let right = CGRect(x: left.maxX + gap, y: left.minY, width: columnWidth, height: left.height)

        drawText("Current office share", in: CGRect(x: left.minX, y: left.minY, width: left.width, height: 10), font: .systemFont(ofSize: 7.2, weight: .bold), color: Palette.muted)
        drawText(report.percentText(report.officeShare), in: CGRect(x: left.minX, y: left.minY + 13, width: 58, height: 22), font: .boldSystemFont(ofSize: 19), color: Palette.ink)
        drawText("target \(report.percentText(report.target))", in: CGRect(x: left.maxX - 68, y: left.minY + 17, width: 68, height: 10), font: .systemFont(ofSize: 7.2, weight: .bold), color: Palette.target, alignment: .right)
        drawProgressBar(
            value: report.officeShare,
            marker: report.target,
            maxValue: 100,
            rect: CGRect(x: left.minX, y: left.minY + 41, width: left.width, height: 14),
            fill: report.officeShare >= report.target ? Palette.wfh : Palette.office
        )
        drawText(report.bestMonthLine, in: CGRect(x: left.minX, y: left.minY + 58, width: left.width, height: 10), font: .systemFont(ofSize: 6.6, weight: .semibold), color: Palette.muted)

        drawText("Remaining unassigned days", in: CGRect(x: right.minX, y: right.minY, width: right.width, height: 10), font: .systemFont(ofSize: 7.2, weight: .bold), color: Palette.muted)
        drawText("\(report.yearMetrics.unassigned)", in: CGRect(x: right.minX, y: right.minY + 13, width: 58, height: 22), font: .boldSystemFont(ofSize: 19), color: Palette.ink)
        drawText(report.remainingPlanTitle, in: CGRect(x: right.minX + 62, y: right.minY + 17, width: right.width - 62, height: 10), font: .systemFont(ofSize: 7.2, weight: .bold), color: Palette.office, alignment: .right)
        drawOpenDayPlanBar(report: report, rect: CGRect(x: right.minX, y: right.minY + 41, width: right.width, height: 14))
        drawText(report.remainingPlanLine, in: CGRect(x: right.minX, y: right.minY + 58, width: right.width, height: 10), font: .systemFont(ofSize: 6.6, weight: .semibold), color: Palette.muted)
    }

    private static func drawCompositionPanel(report: YearReportData, rect: CGRect) {
        drawRoundedRect(rect, fill: Palette.card, stroke: Palette.line, radius: 14)
        drawText("Year composition", in: CGRect(x: rect.minX + 14, y: rect.minY + 12, width: 150, height: 14), font: .boldSystemFont(ofSize: 12), color: Palette.ink)
        drawDonut(report: report, center: CGPoint(x: rect.minX + 58, y: rect.minY + 70), radius: 36)

        let legendX = rect.minX + 108
        let items: [(String, Int, UIColor)] = [
            ("Office", report.yearMetrics.office, Palette.office),
            ("WFH", report.yearMetrics.wfh, Palette.wfh),
            ("Leave", report.yearMetrics.leave, Palette.leave),
            ("Sick", report.yearMetrics.sickness, Palette.sick),
            ("NWD", report.yearMetrics.nwd, Palette.nwd),
            ("Unassigned", report.yearMetrics.unassigned, Palette.open)
        ]
        for (index, item) in items.enumerated() {
            let y = rect.minY + 35 + CGFloat(index) * 13.5
            item.2.setFill()
            UIBezierPath(ovalIn: CGRect(x: legendX, y: y + 3, width: 6, height: 6)).fill()
            drawText(item.0, in: CGRect(x: legendX + 10, y: y, width: 54, height: 10), font: .systemFont(ofSize: 7.3, weight: .semibold), color: Palette.muted)
            drawText("\(item.1)", in: CGRect(x: rect.maxX - 42, y: y, width: 28, height: 10), font: .systemFont(ofSize: 7.5, weight: .bold), color: Palette.ink, alignment: .right)
        }
    }

    private static func drawActionPanel(report: YearReportData, rect: CGRect) {
        drawRoundedRect(rect, fill: Palette.card, stroke: Palette.line, radius: 14)
        drawText("What this means", in: CGRect(x: rect.minX + 14, y: rect.minY + 12, width: 160, height: 14), font: .boldSystemFont(ofSize: 12), color: Palette.ink)
        drawWrappedText(report.actionSummary, in: CGRect(x: rect.minX + 14, y: rect.minY + 32, width: rect.width - 28, height: 33), font: .systemFont(ofSize: 8.3, weight: .medium), color: Palette.muted)

        let rowY = rect.minY + 76
        let cardWidth = (rect.width - 38) / 3
        let cards = [
            ("Need", "\(report.officeDaysNeeded)", "office"),
            ("Unassigned", "\(report.yearMetrics.unassigned)", "days"),
            ("Pace", report.paceText, "needed")
        ]
        for (index, card) in cards.enumerated() {
            let miniRect = CGRect(x: rect.minX + 14 + CGFloat(index) * (cardWidth + 5), y: rowY, width: cardWidth, height: 36)
            drawRoundedRect(miniRect, fill: Palette.paper, stroke: Palette.line, radius: 8)
            drawText(card.0, in: CGRect(x: miniRect.minX + 4, y: miniRect.minY + 5, width: miniRect.width - 8, height: 8), font: .systemFont(ofSize: 6.4, weight: .bold), color: Palette.muted, alignment: .center)
            drawText(card.1, in: CGRect(x: miniRect.minX + 4, y: miniRect.minY + 14, width: miniRect.width - 8, height: 13), font: .systemFont(ofSize: 10.5, weight: .heavy), color: Palette.ink, alignment: .center)
            drawText(card.2, in: CGRect(x: miniRect.minX + 4, y: miniRect.minY + 27, width: miniRect.width - 8, height: 7), font: .systemFont(ofSize: 5.8, weight: .medium), color: Palette.muted, alignment: .center)
        }
    }

    private static func drawCompactMonthlyTable(rows: [YearReportMonthRow], x: CGFloat, y: CGFloat, width: CGFloat) {
        let tableHeight: CGFloat = 211
        drawRoundedRect(CGRect(x: x, y: y, width: width, height: tableHeight), fill: Palette.card, stroke: Palette.line, radius: 14)
        drawText("Month-by-Month", in: CGRect(x: x + 14, y: y + 12, width: 170, height: 14), font: .boldSystemFont(ofSize: 12), color: Palette.ink)
        drawText("All year data at a glance.", in: CGRect(x: x + 170, y: y + 14, width: width - 184, height: 10), font: .systemFont(ofSize: 7.5, weight: .medium), color: Palette.muted, alignment: .right)

        let columns: [(String, CGFloat, NSTextAlignment)] = [
            ("Month", 54, .left),
            ("Working days", 58, .center),
            ("Office", 40, .center),
            ("WFH", 36, .center),
            ("Leave", 36, .center),
            ("Sick", 32, .center),
            ("NWD", 32, .center),
            ("BH", 32, .center),
            ("Unassigned", 50, .center),
            ("Logged", 42, .center),
            ("Office %", 52, .center)
        ]
        let tableWidth = columns.reduce(CGFloat(0)) { $0 + $1.1 }
        let startX = x + (width - tableWidth) / 2
        let headerY = y + 35
        let headerHeight: CGFloat = 17
        let rowHeight: CGFloat = 12.9

        drawRoundedRect(CGRect(x: startX, y: headerY, width: tableWidth, height: headerHeight), fill: Palette.greenWash, stroke: .clear, radius: 8)
        var cursorX = startX
        for column in columns {
            drawText(column.0, in: CGRect(x: cursorX + 4, y: headerY + 4, width: column.1 - 8, height: 9), font: .systemFont(ofSize: 6.6, weight: .bold), color: Palette.ink, alignment: column.2)
            cursorX += column.1
        }

        for (index, row) in rows.enumerated() {
            let rowY = headerY + headerHeight + CGFloat(index) * rowHeight
            if index % 2 == 1 {
                Palette.paper.setFill()
                UIBezierPath(rect: CGRect(x: startX, y: rowY, width: tableWidth, height: rowHeight)).fill()
            }
            let values = [
                row.monthName,
                "\(row.metrics.workingDays)",
                "\(row.metrics.office)",
                "\(row.metrics.wfh)",
                "\(row.metrics.leave)",
                "\(row.metrics.sickness)",
                "\(row.metrics.nwd)",
                "\(row.bankHolidayCount)",
                "\(row.metrics.unassigned)",
                "\(row.logged)",
                row.metrics.workingDays == 0 ? "-" : "\(Int(row.metrics.monthOfficeShare.rounded()))%"
            ]
            cursorX = startX
            for (valueIndex, value) in values.enumerated() {
                drawText(value, in: CGRect(x: cursorX + 4, y: rowY + 2.4, width: columns[valueIndex].1 - 8, height: 8.5), font: .systemFont(ofSize: 6.7, weight: valueIndex == 0 ? .semibold : .regular), color: valueIndex == 0 ? Palette.ink : Palette.muted, alignment: columns[valueIndex].2)
                cursorX += columns[valueIndex].1
            }
        }
    }

    private static func drawLeaveFooter(report: YearReportData, rect: CGRect) {
        drawRoundedRect(rect, fill: Palette.card, stroke: Palette.line, radius: 14)
        let items = [
            ("Taken leave", "\(report.leave.taken)", "used"),
            ("Booked leave", "\(report.leave.booked)", "planned"),
            ("Remaining", "\(report.leave.remaining)", "of \(report.leave.allowance)"),
            ("Bank holidays", "\(report.bankHolidayCount)", "excluded"),
            ("Other absence", "\(report.yearMetrics.sickness + report.yearMetrics.nwd)", "sick + NWD")
        ]
        let itemWidth = rect.width / CGFloat(items.count)
        for (index, item) in items.enumerated() {
            let itemRect = CGRect(x: rect.minX + CGFloat(index) * itemWidth, y: rect.minY + 10, width: itemWidth, height: 38)
            drawText(item.0, in: CGRect(x: itemRect.minX + 4, y: itemRect.minY, width: itemRect.width - 8, height: 9), font: .systemFont(ofSize: 6.8, weight: .bold), color: Palette.muted, alignment: .center)
            drawText(item.1, in: CGRect(x: itemRect.minX + 4, y: itemRect.minY + 11, width: itemRect.width - 8, height: 17), font: .systemFont(ofSize: 15, weight: .heavy), color: Palette.ink, alignment: .center)
            drawText(item.2, in: CGRect(x: itemRect.minX + 4, y: itemRect.minY + 29, width: itemRect.width - 8, height: 8), font: .systemFont(ofSize: 6.4, weight: .medium), color: Palette.muted, alignment: .center)
        }
    }

    private static func drawYearMonthMap(row: YearReportMonthRow, rect: CGRect, target: Double) {
        drawRoundedRect(rect, fill: Palette.card, stroke: Palette.line, radius: 12)
        drawText(row.month.title, in: CGRect(x: rect.minX + 10, y: rect.minY + 9, width: 96, height: 13), font: .systemFont(ofSize: 9.2, weight: .heavy), color: Palette.ink)
        drawText(row.scopeLabel, in: CGRect(x: rect.maxX - 70, y: rect.minY + 11, width: 60, height: 9), font: .systemFont(ofSize: 5.8, weight: .bold), color: row.isInScope ? Palette.target : Palette.muted, alignment: .right)

        let gridX = rect.minX + 10
        let gridY = rect.minY + 30
        let cell: CGFloat = 10
        let gap: CGFloat = 2
        for (index, letter) in DateHelpers.weekdayLetters.enumerated() {
            drawText(letter, in: CGRect(x: gridX + CGFloat(index) * (cell + gap), y: gridY, width: cell, height: 7), font: .systemFont(ofSize: 4.8, weight: .bold), color: Palette.muted, alignment: .center)
        }
        for day in row.gridDays {
            guard let number = day.day else { continue }
            let x = gridX + CGFloat(day.column) * (cell + gap)
            let y = gridY + 10 + CGFloat(day.row) * (cell + gap)
            let fill = day.isOutOfScope ? Palette.outOfScope : yearMapColor(for: day.kind)
            drawRoundedRect(CGRect(x: x, y: y, width: cell, height: cell), fill: fill, stroke: .clear, radius: 2.5)
            if !day.isOutOfScope {
                drawText("\(number)", in: CGRect(x: x + 1, y: y + 2.2, width: cell - 2, height: 5.5), font: .systemFont(ofSize: 4.4, weight: .heavy), color: yearMapTextColor(for: day.kind), alignment: .center)
            }
        }

        let statX = rect.minX + 103
        let statY = rect.minY + 34
        let stats = [
            ("Office", "\(row.metrics.office)", Palette.office),
            ("WFH", "\(row.metrics.wfh)", Palette.wfh),
            ("Leave", "\(row.metrics.leave)", Palette.leave),
            ("Sick", "\(row.metrics.sickness)", Palette.sick),
            ("NWD", "\(row.metrics.nwd)", Palette.nwd),
            ("BH", "\(row.bankHolidayCount)", Palette.bankHoliday),
            ("Unassigned", "\(row.metrics.unassigned)", Palette.open)
        ]
        for (index, stat) in stats.enumerated() {
            let y = statY + CGFloat(index) * 10.5
            stat.2.setFill()
            UIBezierPath(ovalIn: CGRect(x: statX, y: y + 2.4, width: 4, height: 4)).fill()
            drawText(stat.0, in: CGRect(x: statX + 7, y: y, width: 35, height: 8), font: .systemFont(ofSize: 5.0, weight: .semibold), color: Palette.muted)
            drawText(stat.1, in: CGRect(x: rect.maxX - 24, y: y, width: 14, height: 8), font: .systemFont(ofSize: 5.4, weight: .bold), color: Palette.ink, alignment: .right)
        }

        let summaryY = rect.maxY - 41
        let officeShareText = row.metrics.workingDays == 0 ? "-" : "\(Int(row.metrics.monthOfficeShare.rounded()))%"
        let miniStats = [
            ("Workdays", "\(row.assignedWorkingDays)/\(row.metrics.workingDays)"),
            ("Office %", officeShareText),
            ("Need", "\(row.officeDaysNeeded(target))")
        ]
        let miniWidth = (rect.width - 28) / 3
        for (index, item) in miniStats.enumerated() {
            let miniRect = CGRect(x: rect.minX + 10 + CGFloat(index) * (miniWidth + 4), y: summaryY, width: miniWidth, height: 27)
            drawRoundedRect(miniRect, fill: Palette.paper, stroke: Palette.line, radius: 6)
            drawText(item.0, in: CGRect(x: miniRect.minX + 3, y: miniRect.minY + 4, width: miniRect.width - 6, height: 6), font: .systemFont(ofSize: 4.6, weight: .bold), color: Palette.muted, alignment: .center)
            drawText(item.1, in: CGRect(x: miniRect.minX + 3, y: miniRect.minY + 12, width: miniRect.width - 6, height: 9), font: .systemFont(ofSize: 6.4, weight: .heavy), color: Palette.ink, alignment: .center)
        }
    }

    private static func yearMapColor(for kind: DayKind) -> UIColor {
        switch kind {
        case .office: Palette.office
        case .wfh: Palette.wfh
        case .leave: Palette.leave
        case .sickness: Palette.sick
        case .nwd: Palette.nwd
        case .bankHoliday: Palette.bankHoliday
        case .weekend: Palette.weekend
        case .unassigned: Palette.open
        }
    }

    private static func yearMapTextColor(for kind: DayKind) -> UIColor {
        switch kind {
        case .unassigned, .weekend:
            Palette.muted
        default:
            .white
        }
    }

    private static func drawProgressRing(percent: Double, target _: Double, center: CGPoint, radius: CGFloat) {
        let startAngle = CGFloat(-Double.pi / 2)
        let percentEnd = startAngle + CGFloat(min(max(percent, 0), 100) / 100 * 2 * Double.pi)

        Palette.ringTrack.setStroke()
        let track = UIBezierPath(arcCenter: center, radius: radius, startAngle: 0, endAngle: CGFloat(Double.pi * 2), clockwise: true)
        track.lineWidth = 9
        track.stroke()

        Palette.office.setStroke()
        let progress = UIBezierPath(arcCenter: center, radius: radius, startAngle: startAngle, endAngle: percentEnd, clockwise: true)
        progress.lineWidth = 9
        progress.lineCapStyle = .round
        progress.stroke()
    }

    private static func drawProgressBar(value: Double, marker: Double, maxValue: Double, rect: CGRect, fill: UIColor) {
        let maxValue = max(maxValue, 1)
        let fillWidth = rect.width * CGFloat(min(max(value, 0), maxValue) / maxValue)
        let markerX = rect.minX + rect.width * CGFloat(min(max(marker, 0), maxValue) / maxValue)

        drawRoundedRect(rect, fill: Palette.ringTrack, stroke: .clear, radius: rect.height / 2)
        if fillWidth > 0 {
            drawRoundedRect(CGRect(x: rect.minX, y: rect.minY, width: fillWidth, height: rect.height), fill: fill, stroke: .clear, radius: rect.height / 2)
        }

        Palette.target.setStroke()
        let markerPath = UIBezierPath()
        markerPath.move(to: CGPoint(x: markerX, y: rect.minY - 3))
        markerPath.addLine(to: CGPoint(x: markerX, y: rect.maxY + 3))
        markerPath.lineWidth = 1.6
        markerPath.stroke()
    }

    private static func drawOpenDayPlanBar(report: YearReportData, rect: CGRect) {
        let total = max(report.yearMetrics.unassigned, 1)
        let neededWidth = rect.width * CGFloat(min(report.officeDaysNeeded, report.yearMetrics.unassigned)) / CGFloat(total)
        let flexibleWidth = max(0, rect.width - neededWidth)

        guard let graphics = UIGraphicsGetCurrentContext() else { return }
        graphics.saveGState()
        UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2).addClip()
        Palette.ringTrack.setFill()
        UIBezierPath(rect: rect).fill()
        if neededWidth > 0 {
            Palette.office.setFill()
            UIBezierPath(rect: CGRect(x: rect.minX, y: rect.minY, width: neededWidth, height: rect.height)).fill()
        }
        if flexibleWidth > 0 {
            Palette.wfh.setFill()
            UIBezierPath(rect: CGRect(x: rect.minX + neededWidth, y: rect.minY, width: flexibleWidth, height: rect.height)).fill()
        }
        graphics.restoreGState()
    }

    private static func drawDonut(report: YearReportData, center: CGPoint, radius: CGFloat) {
        let total = max(report.compositionTotal, 1)
        let segments: [(Int, UIColor)] = [
            (report.yearMetrics.office, Palette.office),
            (report.yearMetrics.wfh, Palette.wfh),
            (report.yearMetrics.leave, Palette.leave),
            (report.yearMetrics.sickness, Palette.sick),
            (report.yearMetrics.nwd, Palette.nwd),
            (report.yearMetrics.unassigned, Palette.open)
        ]

        Palette.ringTrack.setStroke()
        let track = UIBezierPath(arcCenter: center, radius: radius, startAngle: 0, endAngle: CGFloat(Double.pi * 2), clockwise: true)
        track.lineWidth = 11
        track.stroke()

        var cursor = CGFloat(-Double.pi / 2)
        for segment in segments where segment.0 > 0 {
            let angle = CGFloat(Double(segment.0) / Double(total) * 2 * Double.pi)
            segment.1.setStroke()
            let path = UIBezierPath(arcCenter: center, radius: radius, startAngle: cursor, endAngle: cursor + angle, clockwise: true)
            path.lineWidth = 11
            path.lineCapStyle = .butt
            path.stroke()
            cursor += angle
        }

        drawText("\(Int(report.loggedShare.rounded()))%", in: CGRect(x: center.x - 22, y: center.y - 11, width: 44, height: 15), font: .systemFont(ofSize: 13, weight: .heavy), color: Palette.ink, alignment: .center)
        drawText("logged", in: CGRect(x: center.x - 22, y: center.y + 5, width: 44, height: 9), font: .systemFont(ofSize: 6.2, weight: .semibold), color: Palette.muted, alignment: .center)
    }

    private static func drawRoundedRect(_ rect: CGRect, fill: UIColor, stroke: UIColor, radius: CGFloat) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: radius)
        fill.setFill()
        path.fill()
        guard stroke != .clear else { return }
        stroke.setStroke()
        path.lineWidth = 0.8
        path.stroke()
    }

    private static func drawText(_ text: String, in rect: CGRect, font: UIFont, color: UIColor, alignment: NSTextAlignment = .left) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        text.draw(
            with: rect,
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ],
            context: nil
        )
    }

    private static func drawWrappedText(_ text: String, in rect: CGRect, font: UIFont, color: UIColor, alignment: NSTextAlignment = .left) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 1.1
        text.draw(
            with: rect,
            options: [.usesLineFragmentOrigin],
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ],
            context: nil
        )
    }

    private enum Palette {
        static let ink = UIColor(hex: "24312A")
        static let muted = UIColor(hex: "6C746B")
        static let paper = UIColor(hex: "FAF3EA")
        static let card = UIColor(hex: "FFFDF8")
        static let line = UIColor(hex: "E7D9CA")
        static let office = UIColor(hex: "D87952")
        static let wfh = UIColor(hex: "78B68A")
        static let leave = UIColor(hex: "DDB84E")
        static let sick = UIColor(hex: "D87977")
        static let nwd = UIColor(hex: "AFA69E")
        static let open = UIColor(hex: "DCD3CA")
        static let bankHoliday = UIColor(hex: "C84F4A")
        static let weekend = UIColor(hex: "EFE7DD")
        static let outOfScope = UIColor(hex: "F4ECE2")
        static let greenWash = UIColor(hex: "E7F1D8")
        static let ringTrack = UIColor(hex: "EDE2D7")
        static let target = UIColor(hex: "3F8C77")
    }
}

struct MonthReportPDFRenderer {
    static func render(
        month: Month,
        profile: AttendanceProfile,
        userEmail: String?,
        rangeMode: InsightRangeMode,
        cutoffISO: String?
    ) throws -> URL {
        let report = MonthReportData(
            month: month,
            profile: profile,
            userEmail: userEmail,
            rangeMode: rangeMode,
            cutoffISO: cutoffISO
        )
        let suffix = rangeMode == .yearToDate ? "MTD" : "Recorded"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WFH-Attendance-\(month.key)-\(suffix)-Report.pdf")

        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        try renderer.writePDF(to: url) { context in
            context.beginPage()
            draw(report: report, in: page)
        }
        return url
    }

    private static func draw(report: MonthReportData, in page: CGRect) {
        let margin: CGFloat = 30
        let contentWidth = page.width - margin * 2
        let splitGap: CGFloat = 14
        let splitWidth = (contentWidth - splitGap) / 2

        Palette.paper.setFill()
        UIBezierPath(rect: page).fill()

        drawText("Monthly Attendance Insights", in: CGRect(x: margin, y: 25, width: 330, height: 26), font: .boldSystemFont(ofSize: 22), color: Palette.ink)
        drawText(report.subtitle, in: CGRect(x: margin, y: 53, width: 260, height: 16), font: .systemFont(ofSize: 10, weight: .semibold), color: Palette.muted)
        drawText(report.ownerLine, in: CGRect(x: page.width - margin - 270, y: 31, width: 270, height: 14), font: .systemFont(ofSize: 8.5, weight: .semibold), color: Palette.muted, alignment: .right)
        drawText("Generated \(DateHelpers.readableToday)", in: CGRect(x: page.width - margin - 270, y: 49, width: 270, height: 14), font: .systemFont(ofSize: 8.5), color: Palette.muted, alignment: .right)

        drawMonthHero(report: report, rect: CGRect(x: margin, y: 82, width: 178, height: 118))
        drawMonthInsightPanel(report: report, rect: CGRect(x: margin + 194, y: 82, width: contentWidth - 194, height: 118))
        drawMonthTargetPanel(report: report, rect: CGRect(x: margin, y: 217, width: contentWidth, height: 123))

        drawCalendarPanel(report: report, rect: CGRect(x: margin, y: 357, width: splitWidth, height: 172))
        drawMonthBalancePanel(report: report, rect: CGRect(x: margin + splitWidth + splitGap, y: 357, width: splitWidth, height: 172))

        drawMonthProgressPanel(report: report, rect: CGRect(x: margin, y: 546, width: splitWidth, height: 118))
        drawMonthActionPanel(report: report, rect: CGRect(x: margin + splitWidth + splitGap, y: 546, width: splitWidth, height: 118))
        drawMonthFooter(report: report, rect: CGRect(x: margin, y: 681, width: contentWidth, height: 112))

        drawText(
            "Month-to-Date hides future assigned working days. Leave, bank holidays and non-working days are excluded from office-target totals.",
            in: CGRect(x: margin, y: page.height - 32, width: contentWidth, height: 18),
            font: .systemFont(ofSize: 7.4),
            color: Palette.muted,
            alignment: .center
        )
    }

    private static func drawMonthHero(report: MonthReportData, rect: CGRect) {
        drawRoundedRect(rect, fill: Palette.card, stroke: Palette.line, radius: 14)
        drawText("Office score", in: CGRect(x: rect.minX + 14, y: rect.minY + 12, width: rect.width - 28, height: 12), font: .systemFont(ofSize: 8.5, weight: .heavy), color: Palette.muted)
        drawProgressRing(
            percent: report.officeShare,
            target: report.target,
            center: CGPoint(x: rect.minX + 55, y: rect.minY + 60),
            radius: 28
        )
        drawText(report.percentText(report.officeShare), in: CGRect(x: rect.minX + 102, y: rect.minY + 33, width: 62, height: 30), font: .boldSystemFont(ofSize: 24), color: Palette.ink, alignment: .center)
        drawText("target \(report.percentText(report.target))", in: CGRect(x: rect.minX + 102, y: rect.minY + 63, width: 62, height: 13), font: .systemFont(ofSize: 8, weight: .semibold), color: Palette.muted, alignment: .center)

        let statusColor = report.officeDaysNeeded == 0 ? Palette.wfh : Palette.sick
        statusColor.setFill()
        UIBezierPath(roundedRect: CGRect(x: rect.minX + 14, y: rect.maxY - 19, width: rect.width - 28, height: 13), cornerRadius: 6.5).fill()
        drawText(report.statusPill, in: CGRect(x: rect.minX + 18, y: rect.maxY - 17, width: rect.width - 36, height: 9), font: .systemFont(ofSize: 7, weight: .bold), color: .white, alignment: .center)
    }

    private static func drawMonthInsightPanel(report: MonthReportData, rect: CGRect) {
        drawRoundedRect(rect, fill: Palette.card, stroke: Palette.line, radius: 14)
        drawText(report.headline, in: CGRect(x: rect.minX + 14, y: rect.minY + 12, width: rect.width - 28, height: 17), font: .boldSystemFont(ofSize: 13), color: Palette.ink)
        drawWrappedText(report.summary, in: CGRect(x: rect.minX + 14, y: rect.minY + 33, width: rect.width - 28, height: 32), font: .systemFont(ofSize: 8.7, weight: .medium), color: Palette.muted)

        let chips = [
            ("Assigned", "\(report.assignedWorkingDays)/\(report.metrics.workingDays)"),
            ("Office", "\(report.metrics.office)"),
            ("WFH", "\(report.metrics.wfh)"),
            ("Unassigned", "\(report.metrics.unassigned)")
        ]
        let chipGap: CGFloat = 7
        let chipWidth = (rect.width - 28 - chipGap * 3) / 4
        for (index, chip) in chips.enumerated() {
            let chipRect = CGRect(x: rect.minX + 14 + CGFloat(index) * (chipWidth + chipGap), y: rect.maxY - 40, width: chipWidth, height: 26)
            drawRoundedRect(chipRect, fill: Palette.paper, stroke: Palette.line, radius: 8)
            drawText(chip.0, in: CGRect(x: chipRect.minX + 5, y: chipRect.minY + 4, width: chipRect.width - 10, height: 9), font: .systemFont(ofSize: 6.5, weight: .semibold), color: Palette.muted, alignment: .center)
            drawText(chip.1, in: CGRect(x: chipRect.minX + 5, y: chipRect.minY + 13, width: chipRect.width - 10, height: 11), font: .systemFont(ofSize: 9, weight: .bold), color: Palette.ink, alignment: .center)
        }
    }

    private static func drawMonthTargetPanel(report: MonthReportData, rect: CGRect) {
        drawRoundedRect(rect, fill: Palette.card, stroke: Palette.line, radius: 14)
        drawText("Target outlook", in: CGRect(x: rect.minX + 14, y: rect.minY + 12, width: 160, height: 14), font: .boldSystemFont(ofSize: 12), color: Palette.ink)
        drawText(report.rangeDescription, in: CGRect(x: rect.minX + 14, y: rect.minY + 29, width: rect.width - 28, height: 11), font: .systemFont(ofSize: 7.5, weight: .medium), color: Palette.muted)

        let gap: CGFloat = 18
        let columnWidth = (rect.width - 28 - gap) / 2
        let left = CGRect(x: rect.minX + 14, y: rect.minY + 55, width: columnWidth, height: 50)
        let right = CGRect(x: left.maxX + gap, y: left.minY, width: columnWidth, height: left.height)

        drawText("Selected range", in: CGRect(x: left.minX, y: left.minY, width: left.width, height: 10), font: .systemFont(ofSize: 7.2, weight: .bold), color: Palette.muted)
        drawText(report.percentText(report.officeShare), in: CGRect(x: left.minX, y: left.minY + 13, width: 58, height: 22), font: .boldSystemFont(ofSize: 19), color: Palette.ink)
        drawText("target \(report.percentText(report.target))", in: CGRect(x: left.maxX - 68, y: left.minY + 17, width: 68, height: 10), font: .systemFont(ofSize: 7.2, weight: .bold), color: Palette.target, alignment: .right)
        drawProgressBar(value: report.officeShare, marker: report.target, maxValue: 100, rect: CGRect(x: left.minX, y: left.minY + 39, width: left.width, height: 13), fill: report.officeShare >= report.target ? Palette.wfh : Palette.office)

        drawText(report.rightPlannerTitle, in: CGRect(x: right.minX, y: right.minY, width: right.width, height: 10), font: .systemFont(ofSize: 7.2, weight: .bold), color: Palette.muted)
        drawText(report.rightPlannerValue, in: CGRect(x: right.minX, y: right.minY + 13, width: 58, height: 22), font: .boldSystemFont(ofSize: 19), color: Palette.ink)
        drawText(report.rightPlannerCallout, in: CGRect(x: right.minX + 62, y: right.minY + 17, width: right.width - 62, height: 10), font: .systemFont(ofSize: 7.2, weight: .bold), color: Palette.office, alignment: .right)
        drawOpenDayPlanBar(needed: report.officeDaysNeeded, open: report.metrics.unassigned, rect: CGRect(x: right.minX, y: right.minY + 39, width: right.width, height: 13))
    }

    private static func drawCalendarPanel(report: MonthReportData, rect: CGRect) {
        drawRoundedRect(rect, fill: Palette.card, stroke: Palette.line, radius: 14)
        drawText("Month Map", in: CGRect(x: rect.minX + 14, y: rect.minY + 12, width: 100, height: 14), font: .boldSystemFont(ofSize: 12), color: Palette.ink)
        drawText(report.modeLabel, in: CGRect(x: rect.maxX - 120, y: rect.minY + 14, width: 106, height: 10), font: .systemFont(ofSize: 7.2, weight: .bold), color: Palette.muted, alignment: .right)

        let gridX = rect.minX + 14
        let gridY = rect.minY + 34
        let cell: CGFloat = 18
        let gap: CGFloat = 3
        for (index, letter) in DateHelpers.weekdayLetters.enumerated() {
            drawText(letter, in: CGRect(x: gridX + CGFloat(index) * (cell + gap), y: gridY, width: cell, height: 9), font: .systemFont(ofSize: 6.6, weight: .bold), color: Palette.muted, alignment: .center)
        }
        for day in report.gridDays {
            let x = gridX + CGFloat(day.column) * (cell + gap)
            let y = gridY + 13 + CGFloat(day.row) * (cell + gap)
            guard let number = day.day else { continue }
            drawRoundedRect(CGRect(x: x, y: y, width: cell, height: cell), fill: color(for: day.kind).withAlphaComponent(day.isFutureHidden ? 0.32 : 1), stroke: .clear, radius: 5)
            drawText("\(number)", in: CGRect(x: x + 2, y: y + 5, width: cell - 4, height: 9), font: .systemFont(ofSize: 6.8, weight: .heavy), color: textColor(for: day.kind), alignment: .center)
        }

        drawSideLegend(items: report.legendItems, x: gridX + 158, y: rect.minY + 39, width: rect.maxX - gridX - 172)
    }

    private static func drawMonthBalancePanel(report: MonthReportData, rect: CGRect) {
        drawRoundedRect(rect, fill: Palette.card, stroke: Palette.line, radius: 14)
        drawText("Office/WFH balance", in: CGRect(x: rect.minX + 14, y: rect.minY + 12, width: 150, height: 14), font: .boldSystemFont(ofSize: 12), color: Palette.ink)
        drawWrappedText(report.balanceLine, in: CGRect(x: rect.minX + 14, y: rect.minY + 32, width: rect.width - 28, height: 25), font: .systemFont(ofSize: 8.2, weight: .medium), color: Palette.muted)

        let barRect = CGRect(x: rect.minX + 14, y: rect.minY + 68, width: rect.width - 28, height: 16)
        drawStackedBar(
            segments: [
                (report.metrics.office, Palette.office),
                (report.metrics.wfh, Palette.wfh)
            ],
            total: max(report.workedDays, 1),
            rect: barRect
        )
        drawText("Office \(report.metrics.office)", in: CGRect(x: barRect.minX, y: barRect.maxY + 8, width: 80, height: 10), font: .systemFont(ofSize: 7, weight: .bold), color: Palette.office)
        drawText("WFH \(report.metrics.wfh)", in: CGRect(x: barRect.maxX - 80, y: barRect.maxY + 8, width: 80, height: 10), font: .systemFont(ofSize: 7, weight: .bold), color: Palette.wfh, alignment: .right)

        let cards = [
            ("Office share", report.percentText(report.officeShare)),
            ("WFH share", report.percentText(report.wfhShare)),
            ("Assigned", "\(report.assignedWorkingDays)/\(report.metrics.workingDays)")
        ]
        let cardWidth = (rect.width - 38) / 3
        for (index, card) in cards.enumerated() {
            let miniRect = CGRect(x: rect.minX + 14 + CGFloat(index) * (cardWidth + 5), y: rect.maxY - 42, width: cardWidth, height: 30)
            drawRoundedRect(miniRect, fill: Palette.paper, stroke: Palette.line, radius: 8)
            drawText(card.0, in: CGRect(x: miniRect.minX + 4, y: miniRect.minY + 5, width: miniRect.width - 8, height: 7), font: .systemFont(ofSize: 5.4, weight: .bold), color: Palette.muted, alignment: .center)
            drawText(card.1, in: CGRect(x: miniRect.minX + 4, y: miniRect.minY + 13, width: miniRect.width - 8, height: 12), font: .systemFont(ofSize: 9.4, weight: .heavy), color: Palette.ink, alignment: .center)
        }
    }

    private static func drawMonthProgressPanel(report: MonthReportData, rect: CGRect) {
        drawRoundedRect(rect, fill: Palette.card, stroke: Palette.line, radius: 14)
        drawText("Month progress", in: CGRect(x: rect.minX + 14, y: rect.minY + 12, width: 130, height: 14), font: .boldSystemFont(ofSize: 12), color: Palette.ink)
        drawText(report.progressLine, in: CGRect(x: rect.minX + 14, y: rect.minY + 30, width: rect.width - 28, height: 10), font: .systemFont(ofSize: 7.2, weight: .medium), color: Palette.muted)

        let loggedBar = CGRect(x: rect.minX + 14, y: rect.minY + 55, width: rect.width - 28, height: 12)
        drawText("Working days assigned", in: CGRect(x: loggedBar.minX, y: loggedBar.minY - 14, width: 110, height: 9), font: .systemFont(ofSize: 6.6, weight: .bold), color: Palette.muted)
        drawText("\(report.assignedWorkingDays)/\(report.metrics.workingDays)", in: CGRect(x: loggedBar.maxX - 55, y: loggedBar.minY - 14, width: 55, height: 9), font: .systemFont(ofSize: 6.6, weight: .bold), color: Palette.ink, alignment: .right)
        drawProgressBar(value: report.completionShare, marker: 100, maxValue: 100, rect: loggedBar, fill: Palette.wfh)

        let officeBar = CGRect(x: rect.minX + 14, y: rect.minY + 88, width: rect.width - 28, height: 12)
        drawText("Office target", in: CGRect(x: officeBar.minX, y: officeBar.minY - 14, width: 100, height: 9), font: .systemFont(ofSize: 6.6, weight: .bold), color: Palette.muted)
        drawText("\(report.percentText(report.officeShare)) / \(report.percentText(report.target))", in: CGRect(x: officeBar.maxX - 65, y: officeBar.minY - 14, width: 65, height: 9), font: .systemFont(ofSize: 6.6, weight: .bold), color: Palette.ink, alignment: .right)
        drawProgressBar(value: report.officeShare, marker: report.target, maxValue: 100, rect: officeBar, fill: report.officeShare >= report.target ? Palette.wfh : Palette.office)
    }

    private static func drawMonthActionPanel(report: MonthReportData, rect: CGRect) {
        drawRoundedRect(rect, fill: Palette.card, stroke: Palette.line, radius: 14)
        drawText("What this means", in: CGRect(x: rect.minX + 14, y: rect.minY + 12, width: 160, height: 14), font: .boldSystemFont(ofSize: 12), color: Palette.ink)
        drawWrappedText(report.actionSummary, in: CGRect(x: rect.minX + 14, y: rect.minY + 33, width: rect.width - 28, height: 34), font: .systemFont(ofSize: 8.2, weight: .medium), color: Palette.muted)
        let cards = [
            ("Need", "\(report.officeDaysNeeded)", "office"),
            ("Unassigned", "\(report.metrics.unassigned)", "days"),
            ("Ahead", "\(report.workingDaysAhead)", "working")
        ]
        let cardWidth = (rect.width - 38) / 3
        for (index, card) in cards.enumerated() {
            let miniRect = CGRect(x: rect.minX + 14 + CGFloat(index) * (cardWidth + 5), y: rect.maxY - 42, width: cardWidth, height: 30)
            drawRoundedRect(miniRect, fill: Palette.paper, stroke: Palette.line, radius: 8)
            drawText(card.0, in: CGRect(x: miniRect.minX + 4, y: miniRect.minY + 4, width: miniRect.width - 8, height: 7), font: .systemFont(ofSize: 5.8, weight: .bold), color: Palette.muted, alignment: .center)
            drawText(card.1, in: CGRect(x: miniRect.minX + 4, y: miniRect.minY + 11, width: miniRect.width - 8, height: 12), font: .systemFont(ofSize: 10, weight: .heavy), color: Palette.ink, alignment: .center)
            drawText(card.2, in: CGRect(x: miniRect.minX + 4, y: miniRect.minY + 23, width: miniRect.width - 8, height: 6), font: .systemFont(ofSize: 5.2, weight: .medium), color: Palette.muted, alignment: .center)
        }
    }

    private static func drawMonthFooter(report: MonthReportData, rect: CGRect) {
        drawRoundedRect(rect, fill: Palette.card, stroke: Palette.line, radius: 14)
        let items = [
            ("Office", "\(report.metrics.office)", "days"),
            ("WFH", "\(report.metrics.wfh)", "days"),
            ("Leave", "\(report.metrics.leave)", "days"),
            ("Sick", "\(report.metrics.sickness)", "days"),
            ("NWD", "\(report.metrics.nwd)", "days"),
            ("Bank holiday", "\(report.bankHolidayCount)", "days"),
            ("Unassigned", "\(report.metrics.unassigned)", "days")
        ]
        let itemWidth = rect.width / CGFloat(items.count)
        for (index, item) in items.enumerated() {
            let itemRect = CGRect(x: rect.minX + CGFloat(index) * itemWidth, y: rect.minY + 15, width: itemWidth, height: 42)
            drawText(item.0, in: CGRect(x: itemRect.minX + 4, y: itemRect.minY, width: itemRect.width - 8, height: 9), font: .systemFont(ofSize: 6.8, weight: .bold), color: Palette.muted, alignment: .center)
            drawText(item.1, in: CGRect(x: itemRect.minX + 4, y: itemRect.minY + 11, width: itemRect.width - 8, height: 17), font: .systemFont(ofSize: 15, weight: .heavy), color: Palette.ink, alignment: .center)
            drawText(item.2, in: CGRect(x: itemRect.minX + 4, y: itemRect.minY + 29, width: itemRect.width - 8, height: 8), font: .systemFont(ofSize: 6.4, weight: .medium), color: Palette.muted, alignment: .center)
        }
        drawText(report.footerLine, in: CGRect(x: rect.minX + 16, y: rect.maxY - 32, width: rect.width - 32, height: 14), font: .systemFont(ofSize: 8, weight: .semibold), color: Palette.muted, alignment: .center)
    }

    private static func drawProgressRing(percent: Double, target _: Double, center: CGPoint, radius: CGFloat) {
        let startAngle = CGFloat(-Double.pi / 2)
        let percentEnd = startAngle + CGFloat(min(max(percent, 0), 100) / 100 * 2 * Double.pi)
        Palette.ringTrack.setStroke()
        let track = UIBezierPath(arcCenter: center, radius: radius, startAngle: 0, endAngle: CGFloat(Double.pi * 2), clockwise: true)
        track.lineWidth = 9
        track.stroke()
        Palette.office.setStroke()
        let progress = UIBezierPath(arcCenter: center, radius: radius, startAngle: startAngle, endAngle: percentEnd, clockwise: true)
        progress.lineWidth = 9
        progress.lineCapStyle = .round
        progress.stroke()
    }

    private static func drawProgressBar(value: Double, marker: Double, maxValue: Double, rect: CGRect, fill: UIColor) {
        let maxValue = max(maxValue, 1)
        let fillWidth = rect.width * CGFloat(min(max(value, 0), maxValue) / maxValue)
        let markerX = rect.minX + rect.width * CGFloat(min(max(marker, 0), maxValue) / maxValue)
        drawRoundedRect(rect, fill: Palette.ringTrack, stroke: .clear, radius: rect.height / 2)
        if fillWidth > 0 {
            drawRoundedRect(CGRect(x: rect.minX, y: rect.minY, width: fillWidth, height: rect.height), fill: fill, stroke: .clear, radius: rect.height / 2)
        }
        Palette.target.setStroke()
        let markerPath = UIBezierPath()
        markerPath.move(to: CGPoint(x: markerX, y: rect.minY - 3))
        markerPath.addLine(to: CGPoint(x: markerX, y: rect.maxY + 3))
        markerPath.lineWidth = 1.6
        markerPath.stroke()
    }

    private static func drawOpenDayPlanBar(needed: Int, open: Int, rect: CGRect) {
        let total = max(open, 1)
        let neededWidth = rect.width * CGFloat(min(needed, open)) / CGFloat(total)
        guard let graphics = UIGraphicsGetCurrentContext() else { return }
        graphics.saveGState()
        UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2).addClip()
        Palette.wfh.setFill()
        UIBezierPath(rect: rect).fill()
        if neededWidth > 0 {
            Palette.office.setFill()
            UIBezierPath(rect: CGRect(x: rect.minX, y: rect.minY, width: neededWidth, height: rect.height)).fill()
        }
        graphics.restoreGState()
    }

    private static func drawStackedBar(segments: [(value: Int, color: UIColor)], total: Int, rect: CGRect) {
        let total = max(total, 1)
        guard let graphics = UIGraphicsGetCurrentContext() else { return }
        drawRoundedRect(rect, fill: Palette.ringTrack, stroke: .clear, radius: rect.height / 2)
        graphics.saveGState()
        UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2).addClip()
        var cursor = rect.minX
        for segment in segments where segment.value > 0 {
            let width = rect.width * CGFloat(segment.value) / CGFloat(total)
            segment.color.setFill()
            UIBezierPath(rect: CGRect(x: cursor, y: rect.minY, width: width, height: rect.height)).fill()
            cursor += width
        }
        graphics.restoreGState()
    }

    private static func drawDonut(report: MonthReportData, center: CGPoint, radius: CGFloat) {
        let total = max(report.compositionTotal, 1)
        let segments: [(Int, UIColor)] = [
            (report.metrics.office, Palette.office),
            (report.metrics.wfh, Palette.wfh),
            (report.metrics.leave, Palette.leave),
            (report.metrics.sickness, Palette.sick),
            (report.metrics.nwd, Palette.nwd),
            (report.metrics.unassigned, Palette.open)
        ]
        Palette.ringTrack.setStroke()
        let track = UIBezierPath(arcCenter: center, radius: radius, startAngle: 0, endAngle: CGFloat(Double.pi * 2), clockwise: true)
        track.lineWidth = 11
        track.stroke()
        var cursor = CGFloat(-Double.pi / 2)
        for segment in segments where segment.0 > 0 {
            let angle = CGFloat(Double(segment.0) / Double(total) * 2 * Double.pi)
            segment.1.setStroke()
            let path = UIBezierPath(arcCenter: center, radius: radius, startAngle: cursor, endAngle: cursor + angle, clockwise: true)
            path.lineWidth = 11
            path.stroke()
            cursor += angle
        }
        drawText("\(Int(report.loggedShare.rounded()))%", in: CGRect(x: center.x - 22, y: center.y - 11, width: 44, height: 15), font: .systemFont(ofSize: 13, weight: .heavy), color: Palette.ink, alignment: .center)
        drawText("logged", in: CGRect(x: center.x - 22, y: center.y + 5, width: 44, height: 9), font: .systemFont(ofSize: 6.2, weight: .semibold), color: Palette.muted, alignment: .center)
    }

    private static func drawSideLegend(items: [(String, UIColor)], x: CGFloat, y: CGFloat, width: CGFloat) {
        for (index, item) in items.enumerated() {
            let itemY = y + CGFloat(index) * 13
            item.1.setFill()
            UIBezierPath(ovalIn: CGRect(x: x, y: itemY + 3, width: 5, height: 5)).fill()
            drawText(item.0, in: CGRect(x: x + 8, y: itemY, width: width - 8, height: 10), font: .systemFont(ofSize: 5.8, weight: .bold), color: Palette.muted)
        }
    }

    private static func color(for kind: DayKind) -> UIColor {
        switch kind {
        case .office: Palette.office
        case .wfh: Palette.wfh
        case .leave: Palette.leave
        case .sickness: Palette.sick
        case .nwd: Palette.nwd
        case .bankHoliday: Palette.bankHoliday
        case .weekend: Palette.weekend
        case .unassigned: Palette.open
        }
    }

    private static func textColor(for kind: DayKind) -> UIColor {
        switch kind {
        case .unassigned, .weekend:
            Palette.muted
        default:
            .white
        }
    }

    private static func drawRoundedRect(_ rect: CGRect, fill: UIColor, stroke: UIColor, radius: CGFloat) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: radius)
        fill.setFill()
        path.fill()
        guard stroke != .clear else { return }
        stroke.setStroke()
        path.lineWidth = 0.8
        path.stroke()
    }

    private static func drawText(_ text: String, in rect: CGRect, font: UIFont, color: UIColor, alignment: NSTextAlignment = .left) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        text.draw(
            with: rect,
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph],
            context: nil
        )
    }

    private static func drawWrappedText(_ text: String, in rect: CGRect, font: UIFont, color: UIColor, alignment: NSTextAlignment = .left) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 1.1
        text.draw(
            with: rect,
            options: [.usesLineFragmentOrigin],
            attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph],
            context: nil
        )
    }

    private enum Palette {
        static let ink = UIColor(hex: "24312A")
        static let muted = UIColor(hex: "6C746B")
        static let paper = UIColor(hex: "FAF3EA")
        static let card = UIColor(hex: "FFFDF8")
        static let line = UIColor(hex: "E7D9CA")
        static let office = UIColor(hex: "D87952")
        static let wfh = UIColor(hex: "78B68A")
        static let leave = UIColor(hex: "DDB84E")
        static let sick = UIColor(hex: "D87977")
        static let nwd = UIColor(hex: "AFA69E")
        static let open = UIColor(hex: "DCD3CA")
        static let bankHoliday = UIColor(hex: "C84F4A")
        static let weekend = UIColor(hex: "EFE7DD")
        static let ringTrack = UIColor(hex: "EDE2D7")
        static let target = UIColor(hex: "3F8C77")
    }
}

private struct MonthReportData {
    let month: Month
    let profileName: String
    let userEmail: String?
    let rangeMode: InsightRangeMode
    let cutoffISO: String?
    let target: Double
    let metrics: Metrics
    let fullMonthMetrics: Metrics
    let gridDays: [MonthReportGridDay]

    init(month: Month, profile: AttendanceProfile, userEmail: String?, rangeMode: InsightRangeMode, cutoffISO: String?) {
        self.month = month
        profileName = profile.name
        self.userEmail = userEmail
        self.rangeMode = rangeMode
        self.cutoffISO = cutoffISO
        target = profile.settings.targetPct
        fullMonthMetrics = profile.metrics(from: month.startISO, through: month.endISO, respectingRecordingStart: true)
        if rangeMode == .yearToDate {
            if let cutoffISO {
                metrics = profile.metrics(from: month.startISO, through: cutoffISO, respectingRecordingStart: true)
            } else {
                metrics = Metrics()
            }
        } else {
            metrics = fullMonthMetrics
        }

        let marks = AttendanceMarkIndex(profile: profile)
        gridDays = month.gridDays.enumerated().map { index, day in
            guard let iso = day.iso else {
                return MonthReportGridDay(day: nil, kind: .unassigned, row: index / 7, column: index % 7, isFutureHidden: false)
            }
            let actualKind = marks.kind(for: iso)
            let hidden = rangeMode == .yearToDate && (cutoffISO == nil || iso > (cutoffISO ?? ""))
            let displayKind: DayKind
            if hidden {
                switch actualKind {
                case .weekend, .bankHoliday:
                    displayKind = actualKind
                default:
                    displayKind = .unassigned
                }
            } else {
                displayKind = actualKind
            }
            return MonthReportGridDay(day: day.day, kind: displayKind, row: index / 7, column: index % 7, isFutureHidden: hidden)
        }
    }

    var ownerLine: String {
        if let userEmail, !userEmail.isEmpty {
            return "\(profileName) · \(userEmail)"
        }
        return profileName
    }

    var subtitle: String {
        "\(month.title) · \(modeLabel)"
    }

    var modeLabel: String {
        rangeMode == .yearToDate ? "Month-to-Date" : "User Recorded"
    }

    var rangeDescription: String {
        if rangeMode == .yearToDate {
            return "Based on user recorded data up to \(cutoffISO ?? "today"), with the rest of the month shown as unassigned."
        }
        return "Based on all user recorded data for the selected month."
    }

    var officeShare: Double {
        metrics.monthOfficeShare
    }

    var loggedDays: Int {
        metrics.office + metrics.wfh + metrics.leave + metrics.sickness + metrics.nwd
    }

    var assignedWorkingDays: Int {
        metrics.assignedWorkingDays
    }

    var workedDays: Int {
        metrics.office + metrics.wfh
    }

    var compositionTotal: Int {
        metrics.office + metrics.wfh + metrics.leave + metrics.sickness + metrics.nwd + metrics.unassigned
    }

    var loggedShare: Double {
        guard compositionTotal > 0 else { return 0 }
        return Double(loggedDays) / Double(compositionTotal) * 100
    }

    var wfhShare: Double {
        guard workedDays > 0 else { return 0 }
        return Double(metrics.wfh) / Double(workedDays) * 100
    }

    var completionShare: Double {
        guard metrics.workingDays > 0 else { return 0 }
        return Double(assignedWorkingDays) / Double(metrics.workingDays) * 100
    }

    var officeDaysNeeded: Int {
        metrics.officeDaysNeededForMonthTarget(target)
    }

    var workingDaysAhead: Int {
        guard rangeMode == .yearToDate else { return 0 }
        return max(0, fullMonthMetrics.workingDays - metrics.workingDays)
    }

    var statusPill: String {
        officeDaysNeeded == 0 ? "On target" : "\(officeDaysNeeded) office day\(officeDaysNeeded == 1 ? "" : "s") needed"
    }

    var headline: String {
        if officeDaysNeeded == 0 {
            return "\(modeLabel) is on target"
        }
        return "\(officeDaysNeeded) office day\(officeDaysNeeded == 1 ? "" : "s") needed for target"
    }

    var summary: String {
        if officeDaysNeeded == 0 {
            return "The selected range is meeting the \(percentText(target)) office target with \(metrics.office) office day\(metrics.office == 1 ? "" : "s") logged."
        }
        if metrics.unassigned == 0 {
            return "The selected range is below target and there are no unassigned working days left in this view."
        }
        return "Mark \(officeDaysNeeded) of the \(metrics.unassigned) unassigned working day\(metrics.unassigned == 1 ? "" : "s") as office to meet the \(percentText(target)) target."
    }

    var actionSummary: String {
        if officeDaysNeeded == 0 {
            return "No catch-up is needed for this selected view. Keep future days balanced so the month stays on target."
        }
        guard metrics.unassigned > 0 else {
            return "The target cannot be recovered in this selected view unless existing records are changed."
        }
        return "\(officeDaysNeeded) of the remaining \(metrics.unassigned) unassigned working day\(metrics.unassigned == 1 ? "" : "s") need to become office days."
    }

    var balanceLine: String {
        guard workedDays > 0 else {
            return "No office or WFH days are logged in this selected view yet."
        }
        return "\(metrics.office) office day\(metrics.office == 1 ? "" : "s") and \(metrics.wfh) WFH day\(metrics.wfh == 1 ? "" : "s") are logged. Office is \(percentText(officeShare)) of the month against the \(percentText(target)) target."
    }

    var progressLine: String {
        if metrics.workingDays == 0 {
            return "There are no working days in this selected view."
        }
        return "\(assignedWorkingDays) of \(metrics.workingDays) working days assigned; \(metrics.unassigned) unassigned."
    }

    var rightPlannerTitle: String {
        rangeMode == .yearToDate ? "Days still ahead" : "Unassigned working days"
    }

    var rightPlannerValue: String {
        rangeMode == .yearToDate ? "\(workingDaysAhead)" : "\(metrics.unassigned)"
    }

    var rightPlannerCallout: String {
        officeDaysNeeded == 0 ? "no catch-up" : "\(officeDaysNeeded) office needed"
    }

    var footerLine: String {
        if rangeMode == .yearToDate {
            return "\(metrics.workingDays) working days are in the selected range; \(workingDaysAhead) working days are still ahead in \(month.title)."
        }
        return "\(assignedWorkingDays) of \(metrics.workingDays) working days are assigned in \(month.title)."
    }

    var legendItems: [(String, UIColor)] {
        [
            ("Office", UIColor(hex: "D87952")),
            ("WFH", UIColor(hex: "78B68A")),
            ("Leave", UIColor(hex: "DDB84E")),
            ("Sick", UIColor(hex: "D87977")),
            ("NWD", UIColor(hex: "AFA69E")),
            ("Unassigned", UIColor(hex: "DCD3CA")),
            ("Bank holiday", UIColor(hex: "C84F4A"))
        ]
    }

    var bankHolidayCount: Int {
        gridDays.filter { $0.day != nil && $0.kind == .bankHoliday }.count
    }

    func percentText(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

}

private struct MonthReportGridDay {
    let day: Int?
    let kind: DayKind
    let row: Int
    let column: Int
    let isFutureHidden: Bool
}

private struct YearReportData {
    let year: Int
    let profileName: String
    let userEmail: String?
    let target: Double
    let months: [YearReportMonthRow]
    let yearMetrics: Metrics
    let leave: LeaveBreakdown
    let bankHolidayCount: Int
    let recordingStartMonthKey: String
    let yearStartMonth: Int

    init(year: Int, profile: AttendanceProfile, userEmail: String?) {
        self.year = year
        profileName = profile.name
        self.userEmail = userEmail
        target = profile.settings.targetPct
        recordingStartMonthKey = profile.recordingStartMonthKey
        yearStartMonth = profile.yearStartMonth
        let marks = AttendanceMarkIndex(profile: profile)
        months = profile.reportingYearMonths(for: year).map { period in
            let metrics = profile.metrics(from: period.startISO, through: period.endISO, respectingRecordingStart: true)
            return YearReportMonthRow(
                month: period,
                metrics: metrics,
                marks: marks,
                recordingStartMonthKey: profile.recordingStartMonthKey
            )
        }
        let bounds = profile.reportingYearBounds(for: year)
        let start = max(bounds.startISO, DateHelpers.monthStartISO(profile.recordingStartMonthKey))
        let end = bounds.endISO
        yearMetrics = profile.metrics(from: start, through: end, respectingRecordingStart: true)
        leave = profile.leaveBreakdown(year: year, today: DateHelpers.todayISO())
        bankHolidayCount = YearReportData.countBankHolidays(from: start, through: end)
    }

    var ownerLine: String {
        if let userEmail, !userEmail.isEmpty {
            return "\(profileName) · \(userEmail)"
        }
        return profileName
    }

    var monthMapSubtitle: String {
        let start = DateHelpers.monthParts(fromKey: recordingStartMonthKey)
        let startTitle = start.map { "\(DateHelpers.monthNames[$0.month - 1]) \($0.year)" } ?? recordingStartMonthKey
        return "Recording start: \(startTitle) · Year starts \(DateHelpers.monthNames[yearStartMonth - 1])"
    }

    var yearTitle: String {
        let bounds = DateHelpers.reportingYearBounds(year: year, startMonth: yearStartMonth)
        return "\(DateHelpers.readableDate(bounds.startISO)) - \(DateHelpers.readableDate(bounds.endISO))"
    }

    var workedDays: Int {
        yearMetrics.office + yearMetrics.wfh
    }

    var loggedDays: Int {
        yearMetrics.office + yearMetrics.wfh + yearMetrics.leave + yearMetrics.sickness + yearMetrics.nwd
    }

    var officeDaysNeeded: Int {
        yearMetrics.officeDaysNeededForMonthTarget(target)
    }

    var officeShare: Double {
        yearMetrics.monthOfficeShare
    }

    var loggedShare: Double {
        guard compositionTotal > 0 else { return 0 }
        return Double(loggedDays) / Double(compositionTotal) * 100
    }

    var compositionTotal: Int {
        yearMetrics.office + yearMetrics.wfh + yearMetrics.leave + yearMetrics.sickness + yearMetrics.nwd + yearMetrics.unassigned
    }

    var headline: String {
        if officeDaysNeeded == 0 {
            return "On track for \(percentText(target))"
        }
        return "\(officeDaysNeeded) office days needed for target"
    }

    var summary: String {
        if officeDaysNeeded == 0 {
            return "Office attendance is meeting the target. Keep an eye on unassigned days so the final mix does not drift late in the year."
        }
        if yearMetrics.unassigned == 0 {
            return "The year is fully assigned, so the current office mix is now the final reported position unless records are changed."
        }
        return "There are \(yearMetrics.unassigned) unassigned working days left in the report. Mark \(officeDaysNeeded) of them as office to bring the year back to target."
    }

    var actionSummary: String {
        if officeDaysNeeded == 0 {
            return "No immediate office catch-up is needed. The best next step is keeping future months balanced as they are logged."
        }
        guard yearMetrics.unassigned > 0 else {
            return "The target shortfall cannot be recovered from unassigned days because all working days have already been assigned."
        }
        return "Use the remaining unassigned days deliberately: \(officeDaysNeeded) of \(yearMetrics.unassigned) need to become office days to land the year at \(percentText(target))."
    }

    var paceText: String {
        guard officeDaysNeeded > 0 else { return "OK" }
        guard yearMetrics.unassigned > 0 else { return "n/a" }
        return "\(Int(ceil(Double(officeDaysNeeded) / Double(yearMetrics.unassigned) * 100)))%"
    }

    var bestMonthLine: String {
        let monthsWithWorkingDays = months.filter { $0.metrics.workingDays > 0 }
        guard let best = monthsWithWorkingDays.max(by: { $0.metrics.monthOfficeShare < $1.metrics.monthOfficeShare }) else {
            return "No working-day data is available for this year yet."
        }
        return "Best logged month: \(best.monthName) at \(percentText(best.metrics.monthOfficeShare))."
    }

    var remainingPlanTitle: String {
        guard officeDaysNeeded > 0 else { return "No catch-up needed" }
        return "\(officeDaysNeeded) office needed"
    }

    var remainingPlanLine: String {
        guard yearMetrics.unassigned > 0 else { return "No unassigned working days remain." }
        if officeDaysNeeded == 0 {
            return "\(yearMetrics.unassigned) days remain flexible."
        }
        let flexible = max(yearMetrics.unassigned - officeDaysNeeded, 0)
        return "\(officeDaysNeeded) office + \(flexible) flexible days."
    }

    func percentText(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    private static func countBankHolidays(from start: String, through end: String) -> Int {
        var count = 0
        DateHelpers.forEachDate(from: start, through: end) { date in
            if DateHelpers.isBankHoliday(date) {
                count += 1
            }
        }
        return count
    }
}

private struct YearReportMonthRow {
    let month: Month
    let metrics: Metrics
    let gridDays: [YearReportMonthGridDay]
    let isInScope: Bool
    let bankHolidayCount: Int

    init(month: Month, metrics: Metrics, marks: AttendanceMarkIndex, recordingStartMonthKey: String) {
        self.month = month
        self.metrics = metrics
        let inScope = month.key >= recordingStartMonthKey
        isInScope = inScope
        bankHolidayCount = inScope ? YearReportMonthRow.countBankHolidays(from: month.startISO, through: month.endISO) : 0
        gridDays = month.gridDays.enumerated().map { index, day in
            guard let iso = day.iso else {
                return YearReportMonthGridDay(
                    day: nil,
                    kind: .unassigned,
                    row: index / 7,
                    column: index % 7,
                    isOutOfScope: false
                )
            }
            return YearReportMonthGridDay(
                day: day.day,
                kind: marks.kind(for: iso),
                row: index / 7,
                column: index % 7,
                isOutOfScope: month.key < recordingStartMonthKey
            )
        }
    }

    var monthName: String {
        String(DateHelpers.monthNames[month.month - 1].prefix(3))
    }

    var logged: Int {
        metrics.office + metrics.wfh + metrics.leave + metrics.sickness + metrics.nwd
    }

    var assignedWorkingDays: Int {
        metrics.assignedWorkingDays
    }

    var scopeLabel: String {
        isInScope ? "In scope" : "Before start"
    }

    func officeDaysNeeded(_ target: Double) -> Int {
        metrics.officeDaysNeededForMonthTarget(target)
    }

    private static func countBankHolidays(from start: String, through end: String) -> Int {
        var count = 0
        DateHelpers.forEachDate(from: start, through: end) { iso in
            if DateHelpers.isBankHoliday(iso) {
                count += 1
            }
        }
        return count
    }
}

private struct YearReportMonthGridDay {
    let day: Int?
    let kind: DayKind
    let row: Int
    let column: Int
    let isOutOfScope: Bool
}

struct YearReportPreviewSheet: View {
    let url: URL
    let title: String
    @Environment(\.dismiss) private var dismiss
    @State private var isSharing = false

    var body: some View {
        NavigationStack {
            PDFQuickLookView(url: url)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            PDFPrintController.print(url: url)
                        } label: {
                            Image(systemName: "printer.fill")
                        }
                        .accessibilityLabel("Print PDF")

                        Button {
                            isSharing = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Share PDF")
                    }
                }
        }
        .sheet(isPresented: $isSharing) {
            ShareSheet(items: [url])
        }
    }
}

private struct PDFQuickLookView: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
        context.coordinator.url = url
        uiViewController.reloadData()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private enum PDFPrintController {
    static func print(url: URL) {
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = url.deletingPathExtension().lastPathComponent
        controller.printInfo = info
        controller.printingItem = url
        controller.present(animated: true)
    }
}
