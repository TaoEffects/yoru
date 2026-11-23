import SwiftUI
import AppKit

struct Stage: View {
    @ObservedObject var model: Model
    @ObservedObject var player: Player
    var fullscreen: Bool
    let navigationClearance: CGFloat
    @Binding var controls: Bool
    @State private var ending = IntroSession()
    @State private var nextCountdown: Int?
    @State private var subtitlePanel = false
    @State private var audioOutputPanel = false
    @State private var advanced = false
    @State private var queue = false
    private final class Visibility { var lastActivity = 0.0 }
    @State private var visibility = Visibility()
    @State private var seekValue: Double?
    @State private var footerHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.yoruLabels) private var labels
    @AppStorage("lightweight") private var lightweight = false
    @AppStorage("playerTitleStyle") private var titleStyle: PlayerTitleStyle = .wordmark
    @AppStorage("animatePlaybackButtons") private var animatePlaybackButtons = true
    @State private var seekBackward = 0
    @State private var seekForward = 0
    @State private var previousPulse = 0
    @State private var nextPulse = 0
    @AppStorage("showSeekButtons") private var showSeekButtons = false
    @AppStorage("showAudioOutputButton") private var showAudioOutputButton = false
    @AppStorage("seekButtonSeconds") private var seekButtonSeconds = 10
    @AppStorage("playerControlsTimeout") private var controlsTimeout = 2
    @AppStorage("autoAdvanceAtEnding") private var autoAdvanceAtEnding = true
    @AppStorage("englishInSubtitleCycle") private var englishInSubtitleCycle = false
    @AppStorage("introBehavior") private var introBehavior: IntroBehavior = .adaptive
    private let playlistWidth: CGFloat = 232

    private struct FooterHeight: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
    }

    var body: some View {
        GeometryReader { geometry in
            stage(compactControls: geometry.size.width - (queue ? playlistWidth + 9 : 0) < 680)
        }
    }

    private func stage(compactControls: Bool) -> some View {
        HStack(spacing: 0) {
            ZStack {
                Color.black.ignoresSafeArea(.container, edges: .top)
                VideoView(player: player).ignoresSafeArea(.container, edges: .top).accessibilityHidden(true)
                if let episode = model.current {
                    PlaybackSurfaceInput(player: player, mediaID: episode.id,
                                         enabled: player.loaded && !player.pictureInPictureActive && !model.settings
                                             && !model.playerDownloadsOpen && !subtitlePanel && !audioOutputPanel) {
                        queue = false
                        model.closePlayerDownloads()
                        activity()
                    } doubleClick: {
                        NSApp.keyWindow?.toggleFullScreen(nil)
                    }
                    .accessibilityHidden(true)
                    if player.pictureInPictureActive {
                        Button { player.stopPictureInPicture() } label: {
                            Label(labels("Revenir au lecteur"), systemImage: "pip.exit")
                        }
                        .buttonStyle(ControlStyle())
                    }
                    VStack(alignment: .leading) {
                        if controls || player.paused {
                            VStack(alignment: .leading, spacing: 5) {
                                PlaybackTitle(episode: episode, model: model, style: titleStyle)
                                    .id(episode.id + "|" + String(model.state.shows[episode.showID]?.aniListID ?? 0))
                                if episode.number != nil { Text(labels(episode.display)).font(.callout).foregroundStyle(.white.opacity(0.8)) }
                            }.padding(.horizontal, 17).padding(.vertical, 11)
                                .modifier(VideoGlass(radius: 23))
                        }
                        Spacer(minLength: 10)
                        VStack(alignment: .leading, spacing: 5) {
                            playbackNotice
                            if controls || player.paused || subtitlePanel {
                                if let offer = model.seasonOffer(for: episode) {
                                    HStack {
                                        Spacer()
                                        if offer.announced {
                                            Text("Saison \(offer.next) annoncée").padding(8).background(.black.opacity(0.7), in: Capsule())
                                        } else {
                                            Button { model.downloadSeason(offer, inPlayer: true) } label: {
                                                Label(labels("Télécharger la saison \(offer.next)"), systemImage: "arrow.down.to.line")
                                            }.buttonStyle(ControlStyle()).disabled(model.addingTorrent)
                                                .padding(4).background(.black.opacity(0.7), in: Capsule())
                                        }
                                    }
                                }
                                if !model.playerDownloadsOpen, let transfer = model.activeTransfers.first(where: { $0.id == model.focusedTransfer }) ?? model.activeTransfers.first {
                                    Button { model.openPlayerDownloads() } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: "arrow.down.circle.fill")
                                            Text(transfer.label).lineLimit(1)
                                            ProgressView(value: transfer.fraction).frame(width: 70).tint(mint)
                                            Text(transfer.fraction.formatted(.percent.precision(.fractionLength(0)))).monospacedDigit()
                                        }.font(.caption.weight(.semibold)).padding(8)
                                            .background(.black.opacity(0.68), in: Capsule())
                                    }.buttonStyle(DirectionalPlainStyle()).help("Voir les transferts")
                                }
                                controlsBar(compact: compactControls)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background {
                            GeometryReader { geometry in
                                Color.clear.preference(key: FooterHeight.self, value: geometry.size.height)
                            }
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, 18 + navigationClearance).padding(.bottom, 6)
                    .opacity(model.playerDownloadsOpen ? 0 : 1)
                    .allowsHitTesting(!model.playerDownloadsOpen)
                    .accessibilityHidden(model.playerDownloadsOpen)
                } else {
                    VStack(spacing: 14) {
                        Image(systemName: "play.rectangle").font(.system(size: 58, weight: .thin)).foregroundStyle(mint)
                        Text(labels("Glisse une vidéo ici")).font(YoruTypography.display(28))
                        Button(labels("Ouvrir une vidéo…")) { model.chooseVideos() }.buttonStyle(ControlStyle(accent: true))
                        if model.allowsDownloads {
                            Button(labels("Téléchargements")) { model.openPlayerDownloads() }.buttonStyle(ControlStyle())
                        }
                    }
                }
                if !player.error.isEmpty {
                    Text(player.error).font(.callout).padding(14).background(.black.opacity(0.9), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .background {
                EventActivity { _ in activity() }.frame(width: 0, height: 0)
            }
            .overlay {
                Group {
                    if player.speedBoosted {
                        Label("×2", systemImage: "forward.fill")
                            .font(YoruTypography.text(18, strong: true))
                            .padding(.horizontal, 18).padding(.vertical, 10)
                            .modifier(VideoGlass(radius: 100))
                            .accessibilityLabel(labels("Vitesse ×2"))
                            .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    }
                }
                .allowsHitTesting(false)
            }
            .overlay(alignment: .trailing) {
                if model.playerDownloadsOpen {
                    DownloadView(model: model, inPlayer: true)
                        .frame(width: 396)
                        .clipShape(RoundedRectangle(cornerRadius: 27))
                        .modifier(Glass(radius: 27, tint: .black.opacity(0.62), fallback: panel))
                        .shadow(color: .black.opacity(0.4), radius: 18, x: -6)
                        .padding(.horizontal, 12).padding(.bottom, 12).padding(.top, 12 + navigationClearance)
                        .transition(bounceButtons ? YoruMotion.panel : .identity)
                        .environment(\.yoruTheme, .nuit)
                        .environment(\.directionalLayer, 1)
                }
            }
            if queue { playlist.transition(bounceButtons ? YoruMotion.panel : .identity) }
        }
        .onAppear { activity(); updateSubtitleClearance() }
        .onDisappear {
            player.cancelSpeedBoost()
            NSCursor.setHiddenUntilMouseMoves(false)
            player.subtitleClearance(0, animated: false)
        }
        .onPreferenceChange(FooterHeight.self) { height in
            footerHeight = height
            updateSubtitleClearance()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResizeNotification)) { _ in updateSubtitleClearance() }
        .onChange(of: subtitlePanel) { open in
            if open { audioOutputPanel = false }
            activity()
        }
        .onChange(of: audioOutputPanel) { open in
            if open { subtitlePanel = false }
            activity()
        }
        .onChange(of: showAudioOutputButton) { enabled in
            if !enabled { audioOutputPanel = false }
        }
        .onChange(of: model.playerDownloadsOpen) { open in
            if open { queue = false; audioOutputPanel = false; subtitlePanel = false }
            activity()
            updateSubtitleClearance()
        }
        .onChange(of: fullscreen) { _ in queue = false; activity() }
        .onReceive(NotificationCenter.default.publisher(for: .yoruPlaybackActivity)) { _ in activity() }
        .onReceive(NotificationCenter.default.publisher(for: .yoruSubtitleOptions)) { _ in
            reveal()
            subtitlePanel.toggle()
        }
        .onChange(of: player.paused) { _ in activity(); updateSubtitleClearance() }
        .onChange(of: player.pictureInPictureActive) { _ in updateSubtitleClearance() }
        .onChange(of: controlsTimeout) { _ in activity() }
        .onChange(of: autoAdvanceAtEnding) { enabled in
            ending = IntroSession()
            if !enabled { nextCountdown = nil }
        }
        .onChange(of: model.current) { _ in
            ending = IntroSession()
            nextCountdown = nil
            activity()
            updateSubtitleClearance()
        }
        .onChange(of: player.position) { _ in
            if controls, controlsTimeout > 0, !player.paused, !subtitlePanel, !audioOutputPanel, !model.playerDownloadsOpen, seekValue == nil,
               ProcessInfo.processInfo.systemUptime - visibility.lastActivity > Double(controlsTimeout) {
                controls = false
                if fullscreen, !queue { NSCursor.setHiddenUntilMouseMoves(true) }
            }
            if seekValue == nil, !subtitlePanel, !audioOutputPanel, !model.playerDownloadsOpen { model.introTick(); tickEnding() }
        }
        .animation(reduceMotion || lightweight ? nil : YoruMotion.reveal, value: controls)
        .animation(bounceButtons ? YoruMotion.pageChange : nil, value: queue)
        .animation(bounceButtons ? YoruMotion.pageChange : nil, value: model.playerDownloadsOpen)
        .animation(bounceButtons ? YoruMotion.pageChange : nil, value: player.speedBoosted)
    }

    private func updateSubtitleClearance() {
        let active = model.current != nil && !player.pictureInPictureActive && !model.playerDownloadsOpen
        player.subtitleClearance(active ? max(0, footerHeight - 10) : 0, animated: !reduceMotion && !lightweight)
    }

    private func activity() {
        model.introActivity()
        reveal()
    }

    private func tickEnding() {
        guard autoAdvanceAtEnding else { return }
        ending.lastActivity = visibility.lastActivity
        let action = ending.assess(mode: .countdown, uptime: ProcessInfo.processInfo.systemUptime,
                                  position: player.position, playing: !player.paused,
                                  inside: player.currentSkip?.kind == "ed" && model.next != nil)
        switch action {
        case .countdown(let seconds):
            if nextCountdown != seconds { nextCountdown = seconds }
        case .skip:
            ending.resolved = true
            nextCountdown = nil
            model.startNextEpisode()
        case .none:
            if nextCountdown != nil { nextCountdown = nil }
        }
    }

    private func reveal() {
        NSCursor.setHiddenUntilMouseMoves(false)
        visibility.lastActivity = ProcessInfo.processInfo.systemUptime
        if !controls { controls = true }
    }

    private var bounceButtons: Bool { animatePlaybackButtons && !reduceMotion && !lightweight }

    private var playbackNotice: some View {
        ZStack(alignment: .trailing) {
            if let countdown = nextCountdown {
                HStack(spacing: 6) {
                    Button(labels("Rester")) { ending.resolved = true; nextCountdown = nil }
                        .buttonStyle(ControlStyle())
                    Button { model.startNextEpisode() } label: {
                        Label(labels("Épisode suivant · \(countdown) s"), systemImage: "play.fill")
                    }.buttonStyle(ControlStyle(accent: true))
                }
                .padding(6).modifier(VideoGlass(radius: 100))
                .transition(bounceButtons ? YoruMotion.playbackNotice : .identity)
            } else if let skip = player.currentSkip {
                HStack(spacing: 6) {
                    if skip.kind == "op", !model.introKept, introBehavior != .manual {
                        Button(labels("Garder l’intro")) { model.keepIntro() }
                            .buttonStyle(ControlStyle()).help("Annule le saut automatique")
                    }
                    Button { model.skipSegment(skip) } label: {
                        Label(labels(model.introCountdown.map { "\(skip.label) · \($0) s" } ?? skip.label),
                              systemImage: "forward.end.fill")
                    }.buttonStyle(ControlStyle(accent: true)).help("Raccourci S")
                }
                .padding(6).modifier(VideoGlass(radius: 100))
                .transition(bounceButtons ? YoruMotion.playbackNotice : .identity)
            } else if model.introUndo != nil {
                Button(labels("Revoir l’intro")) { model.undoIntro() }
                    .buttonStyle(ControlStyle()).padding(6)
                    .transition(bounceButtons ? YoruMotion.playbackNotice : .identity)
            } else if player.paused, player.duration > 0, player.position >= player.duration - 1, model.next != nil {
                Button(labels("Épisode suivant")) { model.startNextEpisode() }
                    .buttonStyle(ControlStyle(accent: true))
                    .transition(bounceButtons ? YoruMotion.playbackNotice : .identity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .animation(bounceButtons ? YoruMotion.pageChange : nil, value: model.introUndo != nil)
        .animation(bounceButtons ? YoruMotion.pageChange : nil, value: player.currentSkip?.kind)
        .animation(bounceButtons ? YoruMotion.pageChange : nil, value: nextCountdown != nil)
    }

    private func controlsBar(compact: Bool) -> some View {
        VStack(spacing: 5) {
            PlaybackTimeline(player: player, episode: model.current, seekValue: $seekValue,
                             previewsEnabled: !model.playerDownloadsOpen && !subtitlePanel && !model.settings)
            if compact && (showSeekButtons || showAudioOutputButton) {
                HStack(spacing: 6) {
                    if showSeekButtons {
                        seekButton(forward: false, compact: true)
                        seekButton(forward: true, compact: true)
                    }
                    if showAudioOutputButton {
                        AudioOutputControl(player: player, showingChoices: $audioOutputPanel, iconOnly: true, compact: true)
                    }
                    Spacer()
                }
            }
            HStack(spacing: 9) {
                HStack(spacing: 6) {
                    Button { player.setVolume(player.volume == 0 ? 80 : 0) } label: {
                        Image(systemName: player.volume == 0 ? "speaker.slash" : "speaker.wave.2")
                            .frame(width: 20, height: 26)
                    }
                    .buttonStyle(DirectionalPlainStyle(radius: 8))
                    .accessibilityLabel(labels(player.volume == 0 ? "Réactiver le son" : "Couper le son"))
                    Slider(value: Binding(get: { player.volume }, set: player.setVolume), in: 0...100)
                        .frame(maxWidth: compact ? 60 : 85).tint(mint).accessibilityLabel("Volume")
                        .directionalValue { player.setVolume(player.volume + 5 * $0) }
                    if showAudioOutputButton && !compact {
                        AudioOutputControl(player: player, showingChoices: $audioOutputPanel, iconOnly: true)
                    }
                    if showSeekButtons && !compact {
                        seekButton(forward: false)
                        seekButton(forward: true)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                GlassGroup {
                  HStack(spacing: 9) {
                    Button {
                        if let previous = model.previous { previousPulse += 1; model.play(previous) }
                    } label: {
                        Image(systemName: "backward.end.fill").playbackBounce(previousPulse, enabled: bounceButtons)
                    }.buttonStyle(transportStyle(compact: compact)).help("Épisode précédent").accessibilityLabel("Épisode précédent").disabled(model.previous == nil)
                    Button { player.toggle() } label: {
                        Image(systemName: player.paused ? "play.fill" : "pause.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .contentTransition(.opacity)
                            .animation(bounceButtons ? YoruMotion.selection : nil, value: player.paused)
                            .playbackBounce(player.paused, enabled: bounceButtons)
                            .frame(width: compact ? 53 : 64, height: compact ? 40 : 48)
                            .foregroundStyle(.white)
                            .contentShape(Capsule())
                            .modifier(Glass(radius: 100, tint: mint.opacity(0.36), interactive: true,
                                            fallback: Color(red: 0.12, green: 0.35, blue: 0.29)))
                    }.buttonStyle(DirectionalPlainStyle(radius: 100, priority: 3))
                        .help("Lecture / pause · Espace\nMaintenir Espace pour lire à ×2")
                        .accessibilityLabel(player.paused ? "Lecture" : "Pause")
                    Button { nextPulse += 1; model.startNextEpisode() } label: {
                        Image(systemName: "forward.end.fill").playbackBounce(nextPulse, enabled: bounceButtons)
                    }.buttonStyle(transportStyle(compact: compact)).help("Épisode suivant").accessibilityLabel("Épisode suivant").disabled(model.next == nil)
                  }
                }
                HStack(spacing: 6) {
                Button { model.cycleSubtitles(); reveal() } label: {
                    let active = player.tracks.first { $0.kind == "sub" && $0.id == player.activeSubtitle }?.shortLanguage
                    let label = active == "ja" ? "JP" : active?.uppercased().nonEmpty ?? "Aucun"
                    if compact {
                        Image(systemName: "captions.bubble").accessibilityLabel("Sous-titres · " + label)
                    } else {
                        Label(label, systemImage: "captions.bubble")
                    }
                }.buttonStyle(transportStyle(compact: compact, selected: subtitlePanel))
                    .background(SubtitleOptionsAnchor { subtitlePanel.toggle(); reveal() })
                    .popover(isPresented: $subtitlePanel, arrowEdge: .top) {
                        subtitles.environment(\.directionalLayer, 1)
                            .environment(\.directionalBack, { subtitlePanel = false })
                    }
                    .accessibilityAction(named: Text("Options des sous-titres")) { subtitlePanel.toggle(); reveal() }
                    .help(englishInSubtitleCycle ? "Clic gauche pour JP, FR, EN ou Aucun. Clic droit pour les options."
                        : "Clic gauche pour JP, FR ou Aucun. Clic droit pour les options.")
                Button {
                    if player.pictureInPictureActive {
                        player.stopPictureInPicture()
                    } else if let episode = model.current {
                        model.closePlayerDownloads()
                        player.startPictureInPicture(title: episode.title) { [weak model] in model?.tab = .player }
                    }
                    activity()
                } label: {
                    Image(systemName: player.pictureInPictureActive ? "pip.exit" : "pip.enter")
                }
                .buttonStyle(transportStyle(compact: compact, selected: player.pictureInPictureActive))
                .help(labels(player.pictureInPictureActive ? "Revenir au lecteur" : "Image dans l’image"))
                .accessibilityLabel(labels(player.pictureInPictureActive ? "Revenir au lecteur" : "Image dans l’image"))
                .disabled(!player.loaded && !player.pictureInPictureActive)
                Button { model.closePlayerDownloads(); queue.toggle() } label: { Image(systemName: "list.bullet") }
                    .buttonStyle(transportStyle(compact: compact, selected: queue)).help("Liste de lecture").accessibilityLabel("Liste de lecture")
                Button { NSApp.keyWindow?.toggleFullScreen(nil) } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                    .buttonStyle(transportStyle(compact: compact)).help("Plein écran · F").accessibilityLabel("Plein écran")
                }.frame(maxWidth: .infinity, alignment: .trailing)
            }
        }.padding(.horizontal, 15).padding(.vertical, 7)
            .modifier(VideoGlass(radius: 28))
    }

    private func transportStyle(compact: Bool, selected: Bool = false) -> ControlStyle {
        ControlStyle(selected: selected, horizontalPadding: compact ? 9 : 15, compact: compact)
    }

    private func seekButton(forward: Bool, compact: Bool = false) -> some View {
        let step = [5, 10, 15, 30].contains(seekButtonSeconds) ? seekButtonSeconds : 10
        let action = forward ? "Avancer de \(step) s" : "Reculer de \(step) s"
        return Button {
            activity()
            if forward { seekForward += 1 } else { seekBackward += 1 }
            player.seek(player.position + Double(forward ? step : -step))
        } label: {
            Image(systemName: "\(forward ? "goforward" : "gobackward").\(step)")
                .font(.system(size: 17, weight: .semibold))
                .playbackBounce(forward ? seekForward : seekBackward, enabled: bounceButtons)
        }.buttonStyle(ControlStyle(horizontalPadding: 9, compact: compact))
            .help(labels(action)).accessibilityLabel(labels(action)).disabled(player.duration <= 0)
    }

    private var subtitles: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 11) {
                Text("Sous-titres").font(YoruTypography.display(23))
                let language = player.tracks.first { $0.kind == "sub" && $0.id == player.activeSubtitle }?.shortLanguage
                HStack {
                    Button("FR") { model.pickSubtitles("fr", remember: true) }.buttonStyle(ControlStyle(selected: language == "fr"))
                    Button("Aucun") { model.pickSubtitles("off", remember: true) }.buttonStyle(ControlStyle(selected: language == nil))
                    Button("JP") { model.pickSubtitles("ja", remember: true) }.buttonStyle(ControlStyle(selected: language == "ja"))
                    Spacer()
                    DirectionalMenu { Text(labels("Autres pistes")) } actions: { close in
                        ForEach(player.tracks.filter { $0.kind == "sub" }) { track in
                            Button(track.label) { close(); model.chooseTrack(track) }.buttonStyle(ControlStyle())
                        }
                        Divider()
                        Button("Ajouter un fichier…") { close(); model.chooseSubtitle() }.buttonStyle(ControlStyle())
                        Button("Chercher en anglais") { close(); model.pickSubtitles("en") }.buttonStyle(ControlStyle())
                    }.fixedSize()
                }
                if model.workingSubtitles { ProgressView().controlSize(.small) }
                if !model.subtitleStatus.isEmpty { Text(model.subtitleStatus).font(.caption).foregroundStyle(soft) }
                ForEach(model.subtitleOptions) { result in
                    Button { model.chooseCandidate(result) } label: { Label(result.name, systemImage: "arrow.down") }
                        .buttonStyle(DirectionalPlainStyle()).font(.caption).lineLimit(2)
                }
                Divider()
                Text("Décalage").font(.headline)
                HStack {
                    Button("Plus tôt") { model.changeDelay(player.delay - 0.25) }.buttonStyle(ControlStyle())
                    Text(String(format: "%+.2f s", player.delay)).monospacedDigit().frame(minWidth: 50)
                    Button("Plus tard") { model.changeDelay(player.delay + 0.25) }.buttonStyle(ControlStyle())
                    Button("Réinitialiser") { model.changeDelay(0) }.buttonStyle(DirectionalPlainStyle()).font(.caption)
                }
                HStack {
                    Button("Recaler automatiquement") { model.autoSynchronize() }.buttonStyle(ControlStyle())
                        .disabled(model.workingSubtitles)
                    Button("Boucle d’essai") { player.toggleLoop() }.buttonStyle(ControlStyle())
                }
                if model.canAlignTwoPoints {
                    Button(model.syncAnchor == nil ? "Retenir le premier point" : "Appliquer les deux points") { model.syncPoint() }
                        .buttonStyle(DirectionalPlainStyle()).foregroundStyle(mint).disabled(model.workingSubtitles)
                }
                DirectionalDisclosure(expanded: $advanced, title: labels("Audio et repères")) {
                    VStack(alignment: .leading, spacing: 10) {
                        DirectionalMenu {
                            Text(labels("Piste audio"))
                        } actions: { close in
                            ForEach(player.tracks.filter { $0.kind == "audio" }) { track in
                                Button(track.label) { close(); player.audio(track.id) }.buttonStyle(ControlStyle())
                            }
                        }
                        if let kind = model.modifyingSkip {
                            Button(model.markStart == nil ? "Utiliser ce point comme début" : "Utiliser ce point comme fin") {
                                if model.markStart == nil { model.markStart = player.position }
                                else { model.saveSkip(kind) }
                                subtitlePanel = false
                            }
                            Button("Annuler le repère") { model.modifyingSkip = nil; model.markStart = nil }
                        } else {
                            Button("Préparer un repère d’intro") { model.modifyingSkip = "op"; model.markStart = player.position; subtitlePanel = false }
                            Button("Préparer un repère de fin") { model.modifyingSkip = "ed"; model.markStart = player.position; subtitlePanel = false }
                        }
                    }.padding(.top, 8)
                }
            }.padding(16)
        }.frame(width: 415, height: min(540, model.subtitleOptions.isEmpty ? (advanced ? 455 : 315) : 460))
            .modifier(Glass(radius: 25, tint: .black.opacity(0.40), fallback: ink))
    }

    private var playlist: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(labels("Liste de lecture")).font(YoruTypography.display(23)).padding(.horizontal, 15)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(model.playlist) { episode in
                            Button { model.play(episode) } label: {
                                HStack {
                                    Image(systemName: model.current == episode ? "play.fill" : model.progress(episode).watched ? "checkmark" : "play").foregroundStyle(mint)
                                    EpisodeStill(episode: episode, width: 47, height: 29)
                                    Text(episode.number.map {
                                        labels(episode.season == model.current?.season ? "Épisode \($0)" : episode.display)
                                    } ?? episode.title)
                                        .font(YoruTypography.text(15, strong: true)).lineLimit(2)
                                    Spacer()
                                }.padding(10).background(model.current == episode ? mint.opacity(0.14) : .clear, in: Capsule()).contentShape(Rectangle())
                            }.buttonStyle(DirectionalPlainStyle()).id(episode.id)
                        }
                    }.padding(.horizontal, 7)
                }.onAppear { if let current = model.current { proxy.scrollTo(current.id) } }
            }
        }.padding(.vertical, 17).frame(width: playlistWidth)
            .modifier(Glass(radius: 27, tint: .black.opacity(0.46), fallback: panel))
            .padding(.top, 9 + navigationClearance).padding(.bottom, 9).padding(.trailing, 9)
    }
}

private struct PlaybackTitle: View {
    let episode: Episode
    let model: Model
    let style: PlayerTitleStyle
    @State private var native: String?

    var body: some View {
        let japanese = style == .japanese ? native : nil
        Text(japanese ?? episode.title)
            .font(japanese == nil ? YoruTypography.display(32, italic: true) : .system(size: 25, weight: .medium, design: .serif))
            .lineLimit(2).minimumScaleFactor(0.75)
            .help(japanese ?? episode.title)
            .task(id: style) {
                guard style == .japanese else { return }
                let title = await model.japaneseTitle(for: episode)
                if !Task.isCancelled { native = title }
            }
    }
}

extension Notification.Name {
    static let yoruSubtitleOptions = Notification.Name("local.yoru.subtitleOptions")
    static let yoruPlaybackActivity = Notification.Name("local.yoru.playbackActivity")
}

struct SubtitleOptionsAnchor: NSViewRepresentable {
    let action: () -> Void

    final class Anchor: NSView {
        var eventToken: Any?
        var action: (() -> Void)?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let eventToken { NSEvent.removeMonitor(eventToken); self.eventToken = nil }
            guard window != nil else { return }
            eventToken = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
                guard let self, event.window === self.window,
                      event.type == .rightMouseDown || event.modifierFlags.contains(.control),
                      self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else { return event }
                self.action?()
                return nil
            }
        }
        deinit { if let eventToken { NSEvent.removeMonitor(eventToken) } }
    }

    func makeNSView(context: Context) -> Anchor { Anchor() }
    func updateNSView(_ view: Anchor, context: Context) { view.action = action }
}

struct EventActivity: NSViewRepresentable {
    let callback: (NSEvent) -> Void
    final class Monitor: NSView {
        var token: Any?
        var callback: ((NSEvent) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let token { NSEvent.removeMonitor(token); self.token = nil }
            guard window != nil else { return }
            window?.acceptsMouseMovedEvents = true
            token = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .keyDown, .leftMouseDown, .scrollWheel, .leftMouseDragged]) { [weak self] event in
                if event.window == self?.window { self?.callback?(event) }
                return event
            }
        }
        deinit { if let token { NSEvent.removeMonitor(token) } }
    }
    func makeNSView(context: Context) -> Monitor { Monitor() }
    func updateNSView(_ view: Monitor, context: Context) { view.callback = callback }
}
