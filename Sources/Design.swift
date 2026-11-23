import SwiftUI
import CoreText

enum InterfaceDefaults {
    static let theme = YoruTheme.framboise
    static let lowercase = false
    static let inlinePlayerNavigation = false
}

enum PlayerTitleStyle: String, CaseIterable, Identifiable {
    case wordmark, japanese
    var id: Self { self }
}

enum PlaybackArrows: String, CaseIterable {
    case hybrid, playback, navigation

    var title: String {
        switch self {
        case .hybrid: return "Navigation en pause"
        case .playback: return "Avance, recul et volume"
        case .navigation: return "Navigation dans l’interface"
        }
    }

    func controlsVideo(paused: Bool) -> Bool {
        self == .playback || (self == .hybrid && !paused)
    }
}

struct InterfaceLabels {
    var lowercase = false

    func callAsFunction(_ label: String) -> String {
        let label = L.tr(label)
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
    static let focus = Animation.spring(response: 0.29, dampingFraction: 0.80, blendDuration: 0.10)
    static let pageChange = Animation.easeInOut(duration: 0.23)
    static let press = Animation.easeOut(duration: 0.10)
    static var page: AnyTransition { .opacity.combined(with: .offset(x: -14)) }
    static var panel: AnyTransition { .move(edge: .trailing).combined(with: .opacity) }
    static var playbackNotice: AnyTransition { .opacity.combined(with: .scale(scale: 0.94, anchor: .trailing)) }
}

struct GlassButtonMotion: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    @AppStorage("lightweight") private var lightweight = false
    @AppStorage("animatePlaybackButtons") private var animateButtons = true
    var pressed: Bool
    var radius: CGFloat

    func body(content: Content) -> some View {
        let animates = animateButtons && !reduceMotion && !lightweight && enabled
        let active = pressed && animates
        content
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(.white.opacity(active ? 0.32 : 0), lineWidth: 1.5)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
            .scaleEffect(active ? 0.972 : 1)
            .animation(animates ? (active ? YoruMotion.press : YoruMotion.selection) : nil, value: active)
    }
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
        .directionalTarget(radius: 100) { focused = true }
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


extension View {
    @ViewBuilder func playbackBounce<Value: Equatable>(_ value: Value, enabled: Bool) -> some View {
        if #available(macOS 14, *), enabled { symbolEffect(.bounce, value: value) }
        else { self }
    }
}
