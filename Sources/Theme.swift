import SwiftUI

enum YoruTheme: String, CaseIterable, Identifiable {
    case creme, aurore, nuit, iris, lagon, framboise, peche
    var id: Self { self }
    var name: String {
        switch self {
        case .creme: return "Crème"
        case .aurore: return "Aurore"
        case .nuit: return "Nuit"
        case .iris: return "Iris"
        case .lagon: return "Lagon"
        case .framboise: return "Framboise"
        case .peche: return "Pêche"
        }
    }
    var colorScheme: ColorScheme {
        switch self {
        case .nuit, .iris, .lagon, .framboise: return .dark
        case .creme, .aurore, .peche: return .light
        }
    }
    var background: Color {
        switch self {
        case .creme: return Color(red: 0.968, green: 0.952, blue: 0.919)
        case .aurore: return Color(red: 0.935, green: 0.963, blue: 0.953)
        case .nuit: return Color(red: 0.078, green: 0.086, blue: 0.083)
        case .iris: return Color(red: 0.094, green: 0.060, blue: 0.162)
        case .lagon: return Color(red: 0.038, green: 0.087, blue: 0.156)
        case .framboise: return Color(red: 0.146, green: 0.056, blue: 0.106)
        case .peche: return Color(red: 0.999, green: 0.916, blue: 0.854)
        }
    }
    var primary: Color { colorScheme == .dark ? Color(red: 0.963, green: 0.953, blue: 0.944) : ink }
    var mutedText: Color { colorScheme == .dark ? Color.white.opacity(0.66) : muted }
    var card: Color {
        switch self {
        case .creme: return Color(red: 0.990, green: 0.979, blue: 0.953)
        case .aurore: return Color(red: 0.982, green: 0.994, blue: 0.984)
        case .nuit: return Color(red: 0.114, green: 0.130, blue: 0.119)
        case .iris: return Color(red: 0.162, green: 0.102, blue: 0.248)
        case .lagon: return Color(red: 0.065, green: 0.150, blue: 0.243)
        case .framboise: return Color(red: 0.226, green: 0.086, blue: 0.168)
        case .peche: return Color(red: 1.00, green: 0.966, blue: 0.918)
        }
    }
    var accent: Color {
        switch self {
        case .creme: return Color(red: 0.23, green: 0.35, blue: 0.24)
        case .aurore: return Color(red: 0.06, green: 0.37, blue: 0.34)
        case .nuit: return Color(red: 0.81, green: 0.90, blue: 0.68)
        case .iris: return Color(red: 0.82, green: 0.71, blue: 1.00)
        case .lagon: return Color(red: 0.52, green: 0.84, blue: 1.00)
        case .framboise: return Color(red: 1.00, green: 0.64, blue: 0.79)
        case .peche: return Color(red: 0.61, green: 0.25, blue: 0.16)
        }
    }
    var glow: Color { self == .aurore ? mint : accent }
    var secondaryGlow: Color? {
        switch self {
        case .iris: return Color(red: 0.64, green: 0.26, blue: 0.82)
        case .lagon: return Color(red: 0.21, green: 0.75, blue: 0.72)
        case .framboise: return Color(red: 0.90, green: 0.30, blue: 0.48)
        case .peche: return Color(red: 0.98, green: 0.44, blue: 0.40)
        default: return nil
        }
    }
    var divider: Color { primary.opacity(colorScheme == .dark ? 0.13 : 0.11) }
    var navigationSurface: Color {
        self == .nuit ? Color(red: 0.16, green: 0.18, blue: 0.16) : card
    }
    var tint: Color { accent.opacity(colorScheme == .dark ? 0.13 : 0.085) }
}

private struct YoruThemeKey: EnvironmentKey {
    static let defaultValue = YoruTheme.creme
}

extension EnvironmentValues {
    var yoruTheme: YoruTheme {
        get { self[YoruThemeKey.self] }
        set { self[YoruThemeKey.self] = newValue }
    }
}
