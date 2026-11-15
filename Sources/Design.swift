import SwiftUI
import CoreText

enum PlayerTitleStyle: String, CaseIterable, Identifiable {
    case wordmark, japanese
    var id: Self { self }
}

struct InterfaceLabels {
    var lowercase = false

    func callAsFunction(_ label: String) -> String {
        guard lowercase, let first = label.first, first.isUppercase,
              label.dropFirst().first?.isUppercase != true else { return label }
        return first.lowercased() + label.dropFirst()
    }
}

private struct InterfaceLabelsKey: EnvironmentKey {
    static let defaultValue = InterfaceLabels()
}

extension EnvironmentValues {
    var yoruLabels: InterfaceLabels {
        get { self[InterfaceLabelsKey.self] }
        set { self[InterfaceLabelsKey.self] = newValue }
    }
}

enum YoruTypography {
    static let registered: Bool = {
        var regular = false
        for variant in ["Regular", "Italic"] {
            guard let url = Bundle.main.url(forResource: "InstrumentSerif-" + variant, withExtension: "ttf", subdirectory: "Fonts") else { continue }
            let didRegister = CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            if variant == "Regular" { regular = didRegister }
        }
        return regular
    }()

    private static let sansRegistered: Bool = {
        ["Regular", "Semibold", "Display"].allSatisfy { variant in
            guard let url = Bundle.main.url(forResource: "BricolageGrotesque-" + variant, withExtension: "ttf",
                                            subdirectory: "Fonts") else { return false }
            return CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()

    static func text(_ size: CGFloat, strong: Bool = false) -> Font {
        guard sansRegistered else { return .system(size: size, weight: strong ? .semibold : .regular) }
        return .custom(strong ? "BricolageGrotesque-Semibold" : "BricolageGrotesque-Regular", size: size, relativeTo: .body)
    }

    static func display(_ size: CGFloat, italic: Bool = false) -> Font {
        if !italic, sansRegistered { return .custom("BricolageGrotesque-Display", size: size, relativeTo: .largeTitle) }
        guard registered else { return italic ? .system(size: size, design: .serif).italic() : .system(size: size, design: .serif) }
        return .custom(italic ? "InstrumentSerif-Italic" : "InstrumentSerif-Regular", size: size, relativeTo: .largeTitle)
    }
}

enum YoruMotion {
    static let selection = Animation.spring(response: 0.30, dampingFraction: 0.82, blendDuration: 0.12)
    static let reveal = Animation.spring(response: 0.38, dampingFraction: 0.88, blendDuration: 0.15)
}

struct SearchField: View {
    @Environment(\.yoruTheme) private var theme
    @Environment(\.yoruLabels) private var labels
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("lightweight") private var lightweight = false
    @FocusState private var focused: Bool
    let title: String
    @Binding var value: String
    var icon: String?

    var body: some View {
        HStack(spacing: 9) {
            if let icon {
                Image(systemName: icon).foregroundStyle(focused ? theme.accent : theme.mutedText)
                    .accessibilityHidden(true)
            }
            TextField(labels(title), text: $value, prompt: Text(labels(title)).foregroundColor(theme.mutedText))
                .textFieldStyle(.plain).focused($focused)
                .font(YoruTypography.text(16, strong: true))
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .modifier(Glass(radius: 100, tint: focused ? theme.accent.opacity(0.17) : nil, fallback: theme.card))
        .overlay(Capsule().strokeBorder(focused ? theme.accent.opacity(0.7) : .clear, lineWidth: 1.5)
            .allowsHitTesting(false))
        .contentShape(Capsule())
        .onTapGesture { focused = true }
        .animation(reduceMotion || lightweight ? nil : YoruMotion.selection, value: focused)
    }
}

struct SectionHeading: View {
    @Environment(\.yoruLabels) private var labels
    @Environment(\.yoruTheme) private var theme
    let title: String
    var count: Int?
    var compact = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 11) {
            Text(labels(title)).font(YoruTypography.display(compact ? 27 : 36))
                .accessibilityAddTraits(.isHeader)
            if let count {
                Text(count.formatted()).font(.caption.monospacedDigit()).foregroundStyle(theme.mutedText)
                    .accessibilityLabel("\(count) éléments")
            }
        }
    }
}

struct ProgressLine: View {
    var fraction: Double
    var tint: Color
    var track: Color
    var height: CGFloat = 3

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(tint).frame(width: geometry.size.width * min(max(fraction.isFinite ? fraction : 0, 0), 1))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}
