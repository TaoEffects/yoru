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
    @State private var advanced = false
    @State private var queue = false
    private final class Visibility { var lastActivity = 0.0 }
    @State private var visibility = Visibility()
    @State private var seekValue: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.yoruLabels) private var labels
    @AppStorage("lightweight") private var lightweight = false
    @AppStorage("playerTitleStyle") private var titleStyle: PlayerTitleStyle = .wordmark
    @AppStorage("showSeekButtons") private var showSeekButtons = false
    @AppStorage("seekButtonSeconds") private var seekButtonSeconds = 10
    @AppStorage("playerControlsTimeout") private var controlsTimeout = 2
    @AppStorage("autoAdvanceAtEnding") private var autoAdvanceAtEnding = true
    @AppStorage("englishInSubtitleCycle") private var englishInSubtitleCycle = false
    @AppStorage("introBehavior") private var introBehavior: IntroBehavior = .adaptive

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                Color.black.ignoresSafeArea(.container, edges: .top)
                VideoView(player: player).ignoresSafeArea(.container, edges: .top).accessibilityHidden(true)
                if let episode = model.current {
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(TapGesture(count: 2).onEnded { NSApp.keyWindow?.toggleFullScreen(nil) }
                            .exclusively(before: TapGesture().onEnded { queue = false; model.closePlayerDownloads(); activity() }))
                    VStack(alignment: .leading) {
                        if controls || player.paused {
                            VStack(alignment: .leading, spacing: 5) {
                                PlaybackTitle(episode: episode, model: model, style: titleStyle)
                                    .id(episode.id + "|" + String(model.state.shows[episode.showID]?.aniListID ?? 0))
                                if episode.number != nil { Text(labels(episode.display)).font(.callout).foregroundStyle(.white.opacity(0.8)) }
                            }.padding(.horizontal, 17).padding(.vertical, 11)
                                .modifier(VideoGlass(radius: 23))
                        }
                        Spacer()
                        HStack {
                            Spacer()
                            if let countdown = nextCountdown {
                                HStack(spacing: 6) {
                                    Button(labels("Rester")) { ending.resolved = true; nextCountdown = nil }.buttonStyle(ControlStyle())
                                    Button { model.startNextEpisode() } label: {
                                        Label(labels("Épisode suivant · \(countdown) s"), systemImage: "play.fill")
                                    }.buttonStyle(ControlStyle(accent: true))
                                }.padding(6).modifier(Glass(radius: 100, tint: .black.opacity(0.45), fallback: .black.opacity(0.70)))
                            } else if let skip = player.currentSkip {
                                HStack(spacing: 6) {
                                    if skip.kind == "op", !model.introKept, introBehavior != .manual {
                                        Button(labels("Garder l’intro")) { model.keepIntro() }.buttonStyle(ControlStyle()).help("Annule le saut automatique")
                                    }
                                    Button { model.skipSegment(skip) } label: {
                                        Label(labels(model.introCountdown.map { "\(skip.label) · \($0) s" } ?? skip.label), systemImage: "forward.end.fill")
                                    }.buttonStyle(ControlStyle(accent: true)).help("Raccourci S")
                                }.padding(6).modifier(Glass(radius: 100, tint: .black.opacity(0.45), fallback: .black.opacity(0.70)))
                            } else if model.introUndo != nil {
                                Button(labels("Revoir l’intro")) { model.undoIntro() }
                                    .buttonStyle(ControlStyle()).padding(6)
                            } else if player.paused, player.duration > 0, player.position >= player.duration - 1, model.next != nil {
                                Button(labels("Épisode suivant")) { model.startNextEpisode() }.buttonStyle(ControlStyle(accent: true))
                            }
                        }
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
                                }.buttonStyle(.plain).help("Voir les transferts")
                            }
                            controlsBar
                        }
                    }.padding(.horizontal, 20).padding(.top, 18 + navigationClearance).padding(.bottom, 6)
                } else {
                    VStack(spacing: 14) {
                        Image(systemName: "play.rectangle").font(.system(size: 58, weight: .thin)).foregroundStyle(mint)
                        Text(labels("Glisse une vidéo ici")).font(YoruTypography.display(28))
                        Button(labels("Ouvrir une vidéo…")) { model.chooseVideos() }.buttonStyle(ControlStyle(accent: true))
                        Button(labels("Téléchargements")) { model.openPlayerDownloads() }.buttonStyle(ControlStyle())
                    }
                }
                if !player.error.isEmpty {
                    Text(player.error).font(.callout).padding(14).background(.black.opacity(0.9), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .background {
                EventActivity { _ in activity() }.frame(width: 0, height: 0)
            }
            .overlay(alignment: .trailing) {
                if model.playerDownloadsOpen {
                    DownloadView(model: model, inPlayer: true)
                        .frame(width: 396)
                        .clipShape(RoundedRectangle(cornerRadius: 27))
                        .modifier(Glass(radius: 27, tint: .black.opacity(0.62), fallback: panel))
                        .shadow(color: .black.opacity(0.4), radius: 18, x: -6)
                        .padding(.horizontal, 12).padding(.bottom, 12).padding(.top, 12 + navigationClearance)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                        .environment(\.yoruTheme, .nuit)
                }
            }
            if queue { playlist }
        }
        .onAppear { activity(); updateSubtitleClearance() }
        .onDisappear { NSCursor.setHiddenUntilMouseMoves(false); player.subtitleClearance(false) }
        .onChange(of: controls) { _ in updateSubtitleClearance() }
        .onChange(of: subtitlePanel) { _ in activity() }
        .onChange(of: model.playerDownloadsOpen) { open in
            if open { queue = false }
            activity()
        }
        .onChange(of: fullscreen) { _ in queue = false; activity() }
        .onReceive(NotificationCenter.default.publisher(for: .yoruPlaybackActivity)) { _ in activity() }
        .onReceive(NotificationCenter.default.publisher(for: .yoruSubtitleOptions)) { _ in
            reveal()
            subtitlePanel.toggle()
        }
        .onChange(of: player.paused) { _ in activity(); updateSubtitleClearance() }
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
            if controls, controlsTimeout > 0, !player.paused, !subtitlePanel, !model.playerDownloadsOpen, seekValue == nil,
               ProcessInfo.processInfo.systemUptime - visibility.lastActivity > Double(controlsTimeout) {
                controls = false
                if fullscreen, !queue { NSCursor.setHiddenUntilMouseMoves(true) }
            }
            if seekValue == nil, !subtitlePanel, !model.playerDownloadsOpen { model.introTick(); tickEnding() }
        }
        .animation(reduceMotion || lightweight ? nil : YoruMotion.reveal, value: controls)
        .animation(reduceMotion || lightweight ? nil : YoruMotion.reveal, value: queue)
        .animation(reduceMotion || lightweight ? nil : YoruMotion.reveal, value: model.playerDownloadsOpen)
    }

    private func updateSubtitleClearance() {
        player.subtitleClearance(model.current != nil && (controls || player.paused))
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

    private var controlsBar: some View {
        VStack(spacing: 5) {
            PlaybackTimeline(player: player, episode: model.current, seekValue: $seekValue,
                             previewsEnabled: !model.playerDownloadsOpen && !subtitlePanel && !model.settings)
                .id(queue)
            if showSeekButtons && queue {
                HStack(spacing: 6) {
                    seekButton(forward: false)
                    seekButton(forward: true)
                    Spacer()
                }
            }
            HStack(spacing: 9) {
                HStack(spacing: 6) {
                    Image(systemName: player.volume == 0 ? "speaker.slash" : "speaker.wave.2")
                        .onTapGesture { player.setVolume(player.volume == 0 ? 80 : 0) }
                    Slider(value: Binding(get: { player.volume }, set: player.setVolume), in: 0...100)
                        .frame(maxWidth: queue ? 60 : 85).tint(mint).accessibilityLabel("Volume")
                    if showSeekButtons && !queue {
                        seekButton(forward: false)
                        seekButton(forward: true)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                GlassGroup {
                  HStack(spacing: 9) {
                    Button { if let previous = model.previous { model.play(previous) } } label: {
                        Image(systemName: "backward.end.fill")
                    }.buttonStyle(ControlStyle()).help("Épisode précédent").accessibilityLabel("Épisode précédent").disabled(model.previous == nil)
                    Button { player.toggle() } label: {
                        Image(systemName: player.paused ? "play.fill" : "pause.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .contentTransition(.opacity)
                            .animation(reduceMotion || lightweight ? nil : YoruMotion.selection, value: player.paused)
                            .frame(width: 64, height: 48)
                            .foregroundStyle(.white)
                            .contentShape(Capsule())
                            .modifier(Glass(radius: 100, tint: mint.opacity(0.36), interactive: true,
                                            fallback: Color(red: 0.12, green: 0.35, blue: 0.29)))
                    }.buttonStyle(.plain).help("Lecture / pause · Espace").accessibilityLabel(player.paused ? "Lecture" : "Pause")
                    Button { model.startNextEpisode() } label: {
                        Image(systemName: "forward.end.fill")
                    }.buttonStyle(ControlStyle()).help("Épisode suivant").accessibilityLabel("Épisode suivant").disabled(model.next == nil)
                  }
                }
                HStack(spacing: 6) {
                Button { model.cycleSubtitles(); reveal() } label: {
                    let active = player.tracks.first { $0.kind == "sub" && $0.id == player.activeSubtitle }?.shortLanguage
                    let label = active == "ja" ? "JP" : active?.uppercased().nonEmpty ?? "Aucun"
                    if queue {
                        Image(systemName: "captions.bubble").accessibilityLabel("Sous-titres · " + label)
                    } else {
                        Label(label, systemImage: "captions.bubble")
                    }
                }.buttonStyle(ControlStyle(selected: subtitlePanel))
                    .background(SubtitleOptionsAnchor { subtitlePanel.toggle(); reveal() })
                    .popover(isPresented: $subtitlePanel, arrowEdge: .top) { subtitles }
                    .accessibilityAction(named: Text("Options des sous-titres")) { subtitlePanel.toggle(); reveal() }
                    .help(englishInSubtitleCycle ? "Clic gauche pour JP, FR, EN ou Aucun. Clic droit pour les options."
                        : "Clic gauche pour JP, FR ou Aucun. Clic droit pour les options.")
                Button { model.openPlayerDownloads() } label: {
                    Image(systemName: model.activeTransfers.isEmpty ? "arrow.down.to.line" : "arrow.down.circle.fill")
                }.buttonStyle(ControlStyle(selected: model.playerDownloadsOpen)).help("Téléchargements")
                    .accessibilityLabel("Téléchargements")
                Button { model.closePlayerDownloads(); queue.toggle() } label: { Image(systemName: "list.bullet") }.buttonStyle(ControlStyle(selected: queue)).help("Liste de lecture")
                Button { NSApp.keyWindow?.toggleFullScreen(nil) } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }.buttonStyle(ControlStyle()).help("Plein écran · F")
                }.frame(maxWidth: .infinity, alignment: .trailing)
            }
        }.padding(.horizontal, 15).padding(.vertical, 7)
            .modifier(VideoGlass(radius: 28))
    }

    private func seekButton(forward: Bool) -> some View {
        let step = [5, 10, 15, 30].contains(seekButtonSeconds) ? seekButtonSeconds : 10
        let action = forward ? "Avancer de \(step) s" : "Reculer de \(step) s"
        return Button {
            activity()
            player.seek(player.position + Double(forward ? step : -step))
        } label: {
            Image(systemName: "\(forward ? "goforward" : "gobackward").\(step)")
                .font(.system(size: 17, weight: .semibold))
        }.buttonStyle(ControlStyle(horizontalPadding: 9))
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
                    Menu("Autres pistes") {
                        ForEach(player.tracks.filter { $0.kind == "sub" }) { track in
                            Button(track.label) { model.chooseTrack(track) }
                        }
                        Divider()
                        Button("Ajouter un fichier…") { model.chooseSubtitle() }
                        Button("Chercher en anglais") { model.pickSubtitles("en") }
                    }.fixedSize()
                }
                if model.workingSubtitles { ProgressView().controlSize(.small) }
                if !model.subtitleStatus.isEmpty { Text(model.subtitleStatus).font(.caption).foregroundStyle(soft) }
                ForEach(model.subtitleOptions) { result in
                    Button { model.chooseCandidate(result) } label: { Label(result.name, systemImage: "arrow.down") }
                        .buttonStyle(.plain).font(.caption).lineLimit(2)
                }
                Divider()
                Text("Décalage").font(.headline)
                HStack {
                    Button("Plus tôt") { model.changeDelay(player.delay - 0.25) }.buttonStyle(ControlStyle())
                    Text(String(format: "%+.2f s", player.delay)).monospacedDigit().frame(minWidth: 50)
                    Button("Plus tard") { model.changeDelay(player.delay + 0.25) }.buttonStyle(ControlStyle())
                    Button("Réinitialiser") { model.changeDelay(0) }.buttonStyle(.plain).font(.caption)
                }
                HStack {
                    Button("Recaler automatiquement") { model.autoSynchronize() }.buttonStyle(ControlStyle())
                        .disabled(model.workingSubtitles)
                    Button("Boucle d’essai") { player.toggleLoop() }.buttonStyle(ControlStyle())
                }
                if model.canAlignTwoPoints {
                    Button(model.syncAnchor == nil ? "Retenir le premier point" : "Appliquer les deux points") { model.syncPoint() }
                        .buttonStyle(.plain).foregroundStyle(mint).disabled(model.workingSubtitles)
                }
                DisclosureGroup("Audio et repères", isExpanded: $advanced) {
                    VStack(alignment: .leading, spacing: 10) {
                        Menu("Piste audio") {
                            ForEach(player.tracks.filter { $0.kind == "audio" }) { track in
                                Button(track.label) { player.audio(track.id) }
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
                            }.buttonStyle(.plain).id(episode.id)
                        }
                    }.padding(.horizontal, 7)
                }.onAppear { if let current = model.current { proxy.scrollTo(current.id) } }
            }
        }.padding(.vertical, 17).frame(width: 232)
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
            .task(id: style) {
                guard style == .japanese else { return }
                let title = await model.japaneseTitle(for: episode)
                if !Task.isCancelled { native = title }
            }
    }
}

extension Notification.Name {
    static let yoruSubtitleOptions = Notification.Name("io.github.taoeffects.yoru.subtitleOptions")
    static let yoruPlaybackActivity = Notification.Name("io.github.taoeffects.yoru.playbackActivity")
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

struct SettingsView: View {
    @ObservedObject var model: Model
    @Environment(\.dismiss) private var dismiss
    @AppStorage("preferredSubtitle") private var preferred = "fr"
    @AppStorage("theme") private var theme: YoruTheme = .creme
    @AppStorage("lightweight") private var lightweight = false
    @AppStorage("lowercaseInterface") private var lowercaseInterface = false
    @AppStorage("playerTitleStyle") private var titleStyle: PlayerTitleStyle = .wordmark
    @AppStorage("showSeekButtons") private var showSeekButtons = false
    @AppStorage("seekButtonSeconds") private var seekButtonSeconds = 10
    @AppStorage("playerControlsTimeout") private var controlsTimeout = 2
    @AppStorage("fitPlaybackOnFirstOpen") private var fitPlaybackOnFirstOpen = true
    @AppStorage("inlinePlayerNavigation") private var inlinePlayerNavigation = true
    @AppStorage("hidePlayerNavigationWithControls") private var hidePlayerNavigationWithControls = true
    @AppStorage("autoAdvanceAtEnding") private var autoAdvanceAtEnding = true
    @AppStorage("introBehavior") private var introBehavior: IntroBehavior = .adaptive
    @AppStorage("englishInSubtitleCycle") private var englishInSubtitleCycle = false
    @AppStorage("showRecommendations") private var showRecommendations = true
    @AppStorage("showArtworkBlur") private var showArtworkBlur = true
    @AppStorage("automaticDownloadSelection") private var automaticDownloadSelection = true
    @AppStorage("torrentGroups") private var groups = NyaaSource.defaults
    @AppStorage("minimumSeeds") private var seeds = 8
    @State private var jimaku = ""
    @State private var openKey = ""
    @State private var openUser = ""
    @State private var openPassword = ""
    private var labels: InterfaceLabels { InterfaceLabels(lowercase: lowercaseInterface) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(labels("Réglages")).font(YoruTypography.display(31)).padding(.bottom, 5)
            ScrollView {
                Form {
                    Section(labels("Bibliothèque")) {
                        Button(labels("Choisir le dossier…")) { model.chooseFolder() }.buttonStyle(ControlStyle())
                        Toggle(labels("Afficher les recommandations"), isOn: $showRecommendations).toggleStyle(.switch)
                    }
                    Section("Nautiljon") {
                        Button(labels("Importer la liste « vus »…")) { importNautiljon(watchlist: false) }
                            .buttonStyle(ControlStyle())
                        Button(labels("Importer la liste « à voir »…")) { importNautiljon(watchlist: true) }
                            .buttonStyle(ControlStyle())
                    }
                    Section(labels("Apparence")) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(labels("Thème")).font(YoruTypography.text(15, strong: true))
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), alignment: .leading)], spacing: 6) {
                                ForEach(YoruTheme.allCases) { item in
                                    Button { theme = item } label: {
                                        HStack(spacing: 7) {
                                            Circle().fill(item.accent).frame(width: 10, height: 10)
                                            Text(item.name)
                                        }
                                    }.buttonStyle(ControlStyle(selected: theme == item, horizontalPadding: 8))
                                        .accessibilityAddTraits(theme == item ? .isSelected : [])
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Picker(labels("Titre dans le lecteur"), selection: $titleStyle) {
                            Text(labels("Police Yoru")).tag(PlayerTitleStyle.wordmark)
                            Text(labels("Japonais si disponible")).tag(PlayerTitleStyle.japanese)
                        }
                        Picker(labels("Position de la barre du lecteur"), selection: $inlinePlayerNavigation) {
                            Text(labels("À côté des boutons macOS")).tag(true)
                            Text(labels("Sous les boutons macOS")).tag(false)
                        }
                        Toggle(labels("Masquer la barre avec les commandes"), isOn: $hidePlayerNavigationWithControls)
                            .toggleStyle(.switch)
                        Toggle(labels("Libellés en minuscules"), isOn: $lowercaseInterface).toggleStyle(.switch)
                        Toggle(labels("Fonds floutés"), isOn: $showArtworkBlur).toggleStyle(.switch)
                        Toggle(labels("Interface légère"), isOn: $lightweight).toggleStyle(.switch)
                    }
                    Section(labels("Lecture")) {
                        Toggle(labels("Ajuster la fenêtre à la première lecture"), isOn: $fitPlaybackOnFirstOpen).toggleStyle(.switch)
                        Toggle(labels("Afficher les boutons d’avance et de recul"), isOn: $showSeekButtons).toggleStyle(.switch)
                        if showSeekButtons {
                            Picker(labels("Durée d’un saut"), selection: $seekButtonSeconds) {
                                ForEach([5, 10, 15, 30], id: \.self) { Text("\($0) s").tag($0) }
                            }
                        }
                        Picker(labels("Masquer les commandes"), selection: $controlsTimeout) {
                            Text(labels("Jamais")).tag(0)
                            ForEach([2, 3, 5, 8], id: \.self) { Text(labels("Après \($0) s")).tag($0) }
                        }
                        Picker(labels("Sauter l’intro"), selection: $introBehavior) {
                            ForEach(IntroBehavior.allCases) { Text(labels($0.title)).tag($0) }
                        }
                        Toggle(labels("Enchaîner au générique de fin"), isOn: $autoAdvanceAtEnding).toggleStyle(.switch)
                    }
                    Section("Sous-titres") {
                        Picker("Langue préférée", selection: $preferred) {
                            Text("Français").tag("fr"); Text("Japonais").tag("ja"); Text("Anglais").tag("en"); Text("Aucun").tag("off")
                        }
                        Toggle(labels("Inclure l’anglais dans le cycle des sous-titres"), isOn: $englishInSubtitleCycle).toggleStyle(.switch)
                        SecureField("Clé Jimaku", text: $jimaku)
                        SecureField("Clé OpenSubtitles", text: $openKey)
                        TextField("Identifiant OpenSubtitles", text: $openUser)
                        SecureField("Mot de passe OpenSubtitles", text: $openPassword)
                        Text(FileManager.default.isExecutableFile(atPath: FileManager.support.appendingPathComponent("sync/bin/ffsubsync").path)
                             ? "Recalage automatique installé." : "Pour le recalage automatique, lance install-sync.sh depuis le projet.")
                            .font(.caption).foregroundStyle(soft)
                    }
                    Section("Téléchargements") {
                        Toggle(labels("Choisir automatiquement les versions"), isOn: $automaticDownloadSelection).toggleStyle(.switch)
                        TextField("Comptes Nyaa acceptés", text: $groups)
                        DisclosureGroup("Sources repérées sur Nyaa") {
                            ForEach(NyaaSource.catalog) { source in
                                let enabled = NyaaSource.accounts(groups).contains(source.id)
                                HStack(spacing: 9) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Link(source.label + (source.label == source.id ? "" : " · " + source.id), destination: source.url)
                                        Text(source.sample).font(.system(size: 13)).foregroundStyle(soft)
                                    }
                                    Spacer()
                                    Button(enabled ? "Activé" : "Ajouter") {
                                        var accounts = NyaaSource.accounts(groups).filter { $0 != source.id }
                                        if !enabled { accounts.append(source.id) }
                                        groups = accounts.joined(separator: ",")
                                    }.buttonStyle(ControlStyle(selected: enabled))
                                        .accessibilityLabel(enabled ? "Désactiver " + source.label : "Activer " + source.label)
                                }
                            }
                        }
                        Stepper("Minimum de seeders · \(seeds)", value: $seeds, in: 1...500)

                    }
                }.formStyle(.grouped).scrollContentBackground(.hidden)
            }
            HStack {
                Spacer()
                Button("Fermer") { dismiss() }.buttonStyle(ControlStyle()).keyboardShortcut(.cancelAction)
                Button("Enregistrer les identifiants") {
                    for (key, value) in [("jimaku", jimaku), ("open-key", openKey), ("open-user", openUser), ("open-password", openPassword)] {
                        if value != Vault.get(key) { Vault.set(key, value) }
                    }
                    dismiss()
                    Task { await model.checkTransfers() }
                }.buttonStyle(ControlStyle(accent: true)).keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(width: 555, height: 610)
            .modifier(Glass(radius: 27, tint: .black.opacity(0.32), fallback: ink))
            .onAppear {
                jimaku = Vault.get("jimaku"); openKey = Vault.get("open-key"); openUser = Vault.get("open-user"); openPassword = Vault.get("open-password")
            }
    }

    private func importNautiljon(watchlist: Bool) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let url = panel.url else { return }
        dismiss()
        if watchlist { model.importNautiljonWatchlist(url) }
        else { model.importRatings(url) }
    }
}
