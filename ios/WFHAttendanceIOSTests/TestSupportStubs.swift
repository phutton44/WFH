import SwiftUI

extension Color {
    static let cardBackgroundElevated = Color.black
    static let officeBlue = Color.blue
    static let wfhPurple = Color.purple
    static let leaveOrange = Color.orange
    static let holidayGreen = Color.green
    static let nwdGray = Color.gray
    static let sickRed = Color.red
}

struct LeaveShortfallWarning: Identifiable, Equatable {
    let id = UUID()
    let year: Int
    let remaining: Int
    let requested: Int
    let deficit: Int
}

enum AppError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message):
            return message
        }
    }
}
