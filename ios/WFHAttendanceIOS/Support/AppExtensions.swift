import Foundation
import SwiftUI
import UIKit

enum AppAppearanceMode: String, CaseIterable, Identifiable {
    case dark
    case light

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dark: "Dark"
        case .light: "Light"
        }
    }

    var iconName: String {
        switch self {
        case .dark: "moon.fill"
        case .light: "sun.max.fill"
        }
    }

    var colorScheme: ColorScheme {
        switch self {
        case .dark: .dark
        case .light: .light
        }
    }

    static func resolved(from rawValue: String) -> AppAppearanceMode {
        AppAppearanceMode(rawValue: rawValue) ?? .dark
    }
}

extension Bundle {
    var googleIOSClientID: String {
        String(object(forInfoDictionaryKey: "GOOGLE_IOS_CLIENT_ID") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var googleIOSCallbackScheme: String? {
        let value = String(object(forInfoDictionaryKey: "GOOGLE_IOS_CALLBACK_SCHEME") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var appleSignInEnabled: Bool {
        String(object(forInfoDictionaryKey: "ENABLE_APPLE_SIGN_IN") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased() == "YES"
    }
}

extension String {
    var googleCallbackScheme: String? {
        let suffix = ".apps.googleusercontent.com"
        guard hasSuffix(suffix) else { return nil }
        return "com.googleusercontent.apps." + dropLast(suffix.count)
    }
}

extension URL {
    var queryParameters: [String: String] {
        URLComponents(url: self, resolvingAgainstBaseURL: false)?.queryItems?.reduce(into: [:]) { result, item in
            result[item.name] = item.value
        } ?? [:]
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

extension View {
    func horizontalSwipe(_ action: @escaping (Int) -> Void) -> some View {
        simultaneousGesture(
            DragGesture(minimumDistance: 28)
                .onEnded { value in
                    let horizontal = value.translation.width
                    let vertical = abs(value.translation.height)
                    guard abs(horizontal) > 70, abs(horizontal) > vertical * 1.35 else { return }
                    action(horizontal < 0 ? 1 : -1)
                }
        )
    }

    func sectionLabel() -> some View {
        self
            .font(.caption.weight(.heavy))
            .tracking(1.7)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
    }

    func cardStyle() -> some View {
        self
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.borderSubtle, lineWidth: 0.5)
            }
            .shadow(color: Color.cardShadow, radius: 18, y: 8)
    }

    func glassPanel(cornerRadius: CGFloat = 26) -> some View {
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.borderSubtle, lineWidth: 0.8)
            }
            .shadow(color: Color.black.opacity(0.08), radius: 24, y: 12)
    }
}

extension Color {
    static let appBackground = Color.adaptive(light: "FBF8F3", dark: "000000")

    static let cardBackground = Color.adaptive(light: "FFFFFC", dark: "1C1C1E")

    static let cardBackgroundElevated = Color.adaptive(light: "F8E8D8", dark: "2C2C2E")

    static let primaryText = Color.adaptive(light: "2F332E", dark: "FFFFFF")

    static let secondaryText = Color.adaptive(light: "6F756C", dark: "A8AFBA")

    static let borderSubtle = Color.adaptive(light: "D9C9BA", dark: "FFFFFF", darkAlpha: 0.08)

    static let cardShadow = Color.adaptive(light: "A8896D", lightAlpha: 0.14, dark: "000000", darkAlpha: 0.28)

    static let unassignedFill = Color.adaptive(light: "DCD3CA", dark: "FFFFFF", darkAlpha: 0.18)

    static let slate = Color.adaptive(light: "8D837B", dark: "8090a8")

    static let officeBlue = Color.adaptive(light: "D87952", dark: "0A84FF")

    static let wfhPurple = Color.adaptive(light: "78B68A", dark: "BF5AF2")

    static let leaveOrange = Color.adaptive(light: "DDB84E", dark: "FFD60A")

    static let leaveTaken = Color.adaptive(light: "E4C95E", dark: "FFE66D")

    static let leaveBooked = Color.adaptive(light: "C89143", dark: "FFB300")

    static let sickRed = Color.adaptive(light: "D87977", dark: "FF453A")

    static let nwdGray = Color.adaptive(light: "AFA69E", dark: "8E8E93")

    static let holidayGreen = Color.adaptive(light: "95BF5E", dark: "30D158")

    init(hex: String) {
        self.init(uiColor: UIColor(hex: hex))
    }

    static func adaptive(light: String, lightAlpha: CGFloat = 1, dark: String, darkAlpha: CGFloat = 1) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark, alpha: darkAlpha)
                : UIColor(hex: light, alpha: lightAlpha)
        })
    }
}

extension UIColor {
    convenience init(hex: String) {
        self.init(hex: hex, alpha: 1)
    }

    convenience init(hex: String, alpha: CGFloat) {
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        self.init(
            red: CGFloat((rgb >> 16) & 0xff) / 255,
            green: CGFloat((rgb >> 8) & 0xff) / 255,
            blue: CGFloat(rgb & 0xff) / 255,
            alpha: alpha
        )
    }
}
