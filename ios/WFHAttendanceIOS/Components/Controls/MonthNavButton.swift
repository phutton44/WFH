import SwiftUI

struct MonthNavButton: View {
    let systemName: String
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title3.weight(.bold))
                .foregroundStyle(isDisabled ? Color.secondary.opacity(0.55) : Color.holidayGreen)
                .frame(width: 36, height: 36)
                .background(Color.cardBackgroundElevated.opacity(isDisabled ? 0.55 : 1), in: Circle())
                .overlay {
                    Circle()
                        .stroke(Color.borderSubtle, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}
