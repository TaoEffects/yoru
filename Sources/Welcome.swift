import SwiftUI

enum YoruUsageMode: String, CaseIterable, Identifiable {
    case player, library, complete

    static let preferenceKey = "usageMode"
    static var current: Self {
        UserDefaults.standard.string(forKey: preferenceKey).flatMap(Self.init(rawValue:)) ?? .complete
    }

    var id: Self { self }
    var hasLibrary: Bool { self != .player }
    var hasDownloads: Bool { self == .complete }

    var tabs: [Model.Tab] {
        switch self {
        case .player: return [.player]
        case .library: return [.home, .library, .player]
        case .complete: return Model.Tab.allCases
        }
    }

    var startTab: Model.Tab {
        switch self {
        case .player: return .player
        case .library: return .library
        case .complete: return .home
        }
    }

    var title: String {
        switch self {
        case .player: return "Lecteur"
        case .library: return "Bibliothèque"
        case .complete: return "Complet"
        }
    }

    var icon: String {
        switch self {
        case .player: return "play.rectangle"
        case .library: return "square.grid.2x2"
        case .complete: return "sparkles"
        }
    }

    var detail: String {
        switch self {
        case .player: return "Ouvre tes vidéos, avec les pistes audio et les sous-titres à portée de main."
        case .library: return "Retrouve tes films et tes séries dans une bibliothèque qui suit ta progression."
        case .complete: return "Ajoute les fiches d’animes, les recommandations et les téléchargements."
        }
    }
}

struct WelcomeView: View {
    let titlebarClearance: CGFloat
    let finish: (YoruUsageMode) -> Void

    @Environment(\.yoruTheme) private var theme
    @Environment(\.yoruLabels) private var labels
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("lightweight") private var lightweight = false
    @State private var selection: YoruUsageMode?

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    LanguageChoice()
                    heading
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 212), spacing: 12)], spacing: 12) {
                        ForEach(YoruUsageMode.allCases) { mode in card(mode) }
                    }
                    VStack(spacing: 11) {
                        Button {
                            if let selection { finish(selection) }
                        } label: {
                            Label(labels("Continuer"), systemImage: "arrow.right")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(ControlStyle(accent: true, horizontalPadding: 19))
                        .disabled(selection == nil)
                        Text(labels("Tu peux changer de mode dans les réglages."))
                            .font(YoruTypography.text(15)).foregroundStyle(theme.mutedText)
                    }
                }
                .frame(maxWidth: 850)
                .padding(.horizontal, 30)
                .padding(.top, titlebarClearance + 22)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
        }
        .background { ArtBackdrop() }
        .foregroundStyle(theme.primary)
        .environment(\.directionalLayer, 1)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 18, weight: .medium)).foregroundStyle(theme.accent)
                    .accessibilityHidden(true)
                Text("Yoru").font(YoruTypography.display(35, italic: true))
            }
            Text(labels("Que veux-tu faire avec Yoru ?"))
                .font(YoruTypography.display(43))
                .accessibilityAddTraits(.isHeader)
        }
    }

    private func card(_ mode: YoruUsageMode) -> some View {
        let selected = selection == mode
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return Button { selection = mode } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: mode.icon).font(.system(size: 23, weight: .medium))
                    Spacer(minLength: 0)
                    if selected { Image(systemName: "checkmark.circle.fill").font(.system(size: 19)) }
                }
                .foregroundStyle(theme.accent)
                .frame(height: 31)
                .accessibilityHidden(true)
                Text(labels(mode.title)).font(YoruTypography.text(23, strong: true))
                Text(L.tr(mode.detail))
                    .font(YoruTypography.text(16)).foregroundStyle(theme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 167, alignment: .topLeading)
            .modifier(Glass(radius: 20, tint: selected ? theme.accent.opacity(0.16) : nil, fallback: theme.card))
            .overlay(shape.strokeBorder(selected ? theme.accent.opacity(0.8) : theme.divider, lineWidth: selected ? 1.6 : 1)
                .allowsHitTesting(false))
            .contentShape(shape)
        }
        .buttonStyle(DirectionalPlainStyle(radius: 20, priority: selected ? 1 : 0))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .animation(reduceMotion || lightweight ? nil : YoruMotion.selection, value: selected)
    }
}
