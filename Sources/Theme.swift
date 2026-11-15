import SwiftUI

enum YoruTheme: String, CaseIterable, Identifiable {
    case creme, aurore, nuit
    var id: Self { self }
    var name: String {
        switch self {
        case .creme: return "Crème"
        case .aurore: return "Aurore"
        case .nuit: return "Nuit"
        }
    }
    var colorScheme: ColorScheme { self == .nuit ? .dark : .light }
    var background: Color {
        switch self {
        case .creme: return Color(red: 0.968, green: 0.952, blue: 0.919)
        case .aurore: return Color(red: 0.935, green: 0.963, blue: 0.953)
        case .nuit: return Color(red: 0.078, green: 0.086, blue: 0.083)
        }
    }
    var primary: Color { self == .nuit ? Color(red: 0.963, green: 0.953, blue: 0.920) : ink }
    var mutedText: Color { self == .nuit ? Color(red: 0.660, green: 0.702, blue: 0.674) : muted }
    var card: Color {
        switch self {
        case .creme: return Color(red: 0.990, green: 0.979, blue: 0.953)
        case .aurore: return Color(red: 0.982, green: 0.994, blue: 0.984)
        case .nuit: return Color(red: 0.114, green: 0.130, blue: 0.119)
        }
    }
    var accent: Color {
        switch self {
        case .creme: return Color(red: 0.23, green: 0.35, blue: 0.24)
        case .aurore: return Color(red: 0.06, green: 0.37, blue: 0.34)
        case .nuit: return Color(red: 0.81, green: 0.90, blue: 0.68)
        }
    }
    var glow: Color { self == .aurore ? mint : accent }
    var divider: Color { primary.opacity(self == .nuit ? 0.13 : 0.11) }
    var tint: Color { accent.opacity(self == .nuit ? 0.10 : 0.085) }
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
