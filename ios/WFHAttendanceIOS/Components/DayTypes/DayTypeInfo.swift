import SwiftUI

struct DayTypeInfo: Identifiable {
    let id: DayKind
    let shortLabel: String
    let title: String
    let description: String
    let color: Color

    static let primary: [DayTypeInfo] = [
        DayTypeInfo(id: .office, shortLabel: "Office", title: "Office", description: "You worked from the office.", color: .officeBlue),
        DayTypeInfo(id: .wfh, shortLabel: "WFH", title: "Work from home", description: "You worked remotely from home.", color: .wfhPurple),
        DayTypeInfo(id: .leave, shortLabel: "Leave", title: "Annual leave", description: "A day taken from annual leave.", color: .leaveOrange),
        DayTypeInfo(id: .sickness, shortLabel: "Sick", title: "Sickness", description: "A sickness absence day.", color: .holidayGreen),
        DayTypeInfo(id: .nwd, shortLabel: "NWD", title: "Non-working day", description: "A normal working day excluded from office/WFH totals.", color: .nwdGray),
        DayTypeInfo(id: .bankHoliday, shortLabel: "BH", title: "Bank holiday", description: "A public holiday, excluded from working-day targets.", color: .sickRed)
    ]

    static let allExplained: [DayTypeInfo] = primary + [
        DayTypeInfo(id: .unassigned, shortLabel: "Unassigned", title: "Unassigned", description: "A working day still waiting to be recorded.", color: Color.unassignedFill),
        DayTypeInfo(id: .weekend, shortLabel: "Weekend", title: "Weekend", description: "Saturday or Sunday, outside normal working-day totals.", color: Color.cardBackgroundElevated)
    ]
}
