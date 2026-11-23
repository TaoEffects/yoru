import AppKit
import SwiftUI

enum BrowsePlayback: String, CaseIterable {
    case bubble, pictureInPicture, off

    var title: String {
        switch self {
        case .bubble: return "Bulle dans Yoru"
        case .pictureInPicture: return "Image dans l’image"
        case .off: return "Désactivé"
        }
    }
}

private struct MiniPlaybackClearanceKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var miniPlaybackClearance: CGFloat {
        get { self[MiniPlaybackClearanceKey.self] }
        set { self[MiniPlaybackClearanceKey.self] = newValue }
    }
}

struct MiniPlaybackView: View {
    @ObservedObject var model: Model
    let episode: Episode

    @Environment(\.yoruTheme) private var theme
    @Environment(\.yoruLabels) private var labels
    @State private var paused = true
    @State private var poster: NSImage?

    private var coverURL: URL? { model.anime[episode.showID]?.coverImage?.large }

    var body: some View {
        HStack(spacing: 9) {
            playbackLink
            GlassGroup(spacing: 3) {
                HStack(spacing: 3) {
                    control("backward.end.fill", name: "Précédent") {
                        guard let previous = model.previous else { return }
                        keepBrowsing { model.play(previous) }
                    }.disabled(model.previous == nil)
                    control(paused ? "play.fill" : "pause.fill", name: paused ? "Reprendre" : "Pause", accent: true) {
                        model.player.toggle()
                    }
                    control("forward.end.fill", name: "Suivant") {
                        keepBrowsing { model.startNextEpisode() }
                    }.disabled(model.next == nil)
                }
            }
        }
        .padding(6)
        .frame(maxWidth: 375)
        .modifier(Glass(radius: 22, tint: theme.tint, fallback: theme.navigationSurface))
        .onReceive(model.player.$paused.removeDuplicates()) { paused = $0 }
        .task(id: coverURL) {
            poster = coverURL.flatMap {
                URLCache.shared.cachedResponse(for: URLRequest(url: $0)).flatMap { NSImage(data: $0.data) }
            }
        }
    }

    private var playbackLink: some View {
        Button { model.tab = .player } label: {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9).fill(theme.tint)
                    if let poster {
                        Image(nsImage: poster).resizable().scaledToFill()
                            .frame(width: 36, height: 37).clipped()
                    } else {
                        Image(systemName: "play.rectangle")
                            .font(.system(size: 16, weight: .medium)).foregroundStyle(theme.accent)
                    }
                }
                .frame(width: 36, height: 37)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(episode.title).font(YoruTypography.text(15, strong: true)).lineLimit(1)
                    if episode.number != nil {
                        Text(labels(episode.display)).font(YoruTypography.text(13)).foregroundStyle(theme.mutedText).lineLimit(1)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.mutedText)
                    .accessibilityHidden(true)
            }
            .padding(4)
            .contentShape(RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(DirectionalPlainStyle(radius: 15))
        .help(labels("Revenir au lecteur") + " · " + episode.title)
        .accessibilityHint(labels("Revenir au lecteur"))
    }

    private func control(_ icon: String, name: String, accent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 13, weight: .semibold)).frame(width: 18)
        }
        .buttonStyle(ControlStyle(accent: accent, horizontalPadding: 7, compact: true))
        .help(labels(name))
        .accessibilityLabel(labels(name))
    }

    private func keepBrowsing(_ play: () -> Void) {
        let tab = model.tab
        play()
        model.tab = tab
    }
}
