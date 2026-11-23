import SwiftUI

struct AudioOutput: Identifiable, Equatable {
    let id: String
    let name: String

    static let system = AudioOutput(id: "auto", name: "Sortie macOS")
}

struct AudioOutputControl: View {
    @ObservedObject var player: Player
    @Binding var showingChoices: Bool
    @Environment(\.yoruLabels) private var labels
    @Environment(\.yoruTheme) private var theme
    @Environment(\.directionalLayer) private var layer
    var iconOnly = false
    var compact = false

    private var current: String {
        outputLabel(player.audioOutputs.first { $0.id == player.configuredAudioOutput } ?? .system)
    }

    var body: some View {
        Button { showingChoices.toggle() } label: {
            if iconOnly {
                Image(systemName: "hifispeaker")
            } else {
                HStack(spacing: 8) {
                    Text(current).lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                }
            }
        }
        .buttonStyle(ControlStyle(selected: showingChoices, horizontalPadding: iconOnly ? 11 : 15, compact: compact))
        .help(iconOnly ? labels("Sortie audio") : current)
        .accessibilityLabel(labels("Sortie audio"))
        .accessibilityValue(current)
        .popover(isPresented: $showingChoices, arrowEdge: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 9) {
                    Text(labels("Sortie audio")).font(YoruTypography.display(23))
                    if player.preferredAudioOutput != player.configuredAudioOutput {
                        Text(labels("Périphérique indisponible. Sortie macOS utilisée."))
                            .font(.callout).foregroundStyle(theme.mutedText)
                    }
                    ForEach(player.audioOutputs) { output in
                        let configured = output.id == player.configuredAudioOutput
                        Button {
                            player.chooseAudioOutput(output)
                            showingChoices = false
                        } label: {
                            HStack(spacing: 8) {
                                Text(outputLabel(output)).lineLimit(2)
                                Spacer(minLength: 0)
                                if configured { Image(systemName: "checkmark").accessibilityHidden(true) }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(ControlStyle(selected: configured))
                        .accessibilityAddTraits(configured ? .isSelected : [])
                    }
                }
                .padding(14)
            }
            .frame(width: 280, height: min(340, 56 + CGFloat(player.audioOutputs.count) * 51
                + (player.preferredAudioOutput != player.configuredAudioOutput ? 36 : 0)))
            .environment(\.directionalLayer, layer + 1)
            .environment(\.directionalBack, { showingChoices = false })
        }
    }

    private func outputLabel(_ output: AudioOutput) -> String {
        output.id == AudioOutput.system.id ? labels(output.name) : output.name
    }
}
