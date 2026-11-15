import SwiftUI
import AppKit
import UniformTypeIdentifiers

let ink = Color(red: 0.047, green: 0.061, blue: 0.081)
let panel = Color(red: 0.081, green: 0.100, blue: 0.125)
let mint = Color(red: 0.64, green: 0.94, blue: 0.84)
let soft = Color(red: 0.62, green: 0.67, blue: 0.74)

struct Glass: ViewModifier {
    var radius: CGFloat = 24
    var tint: Color? = nil
    var interactive = false
    var fallback: Color? = nil
    @AppStorage("lightweight") private var lightweight = false
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if #available(macOS 26, *), !lightweight {
            content.glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            content.background(fallback ?? (scheme == .dark ? panel : Color.white).opacity(0.95), in: shape)
                .overlay(shape.strokeBorder((scheme == .dark ? Color.white : ink).opacity(0.12)).allowsHitTesting(false))
        }
    }
}

struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 5
    @ViewBuilder var content: Content
    @AppStorage("lightweight") private var lightweight = false

    var body: some View {
        if #available(macOS 26, *), !lightweight {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

struct ControlStyle: ButtonStyle {
    @Environment(\.yoruTheme) private var theme
    var selected = false
    var accent = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    @AppStorage("lightweight") private var lightweight = false
    func makeBody(configuration: Configuration) -> some View {
        let dark = scheme == .dark
        let base = dark ? Color.white : ink
        let tint = dark && theme != .nuit ? mint : theme.accent
        let promoted = accent || selected
        let filledFallback = accent ? tint : selected ? tint.opacity(0.15) : base.opacity(configuration.isPressed ? 0.16 : 0.07)
        let text: Color
        if #available(macOS 26, *), !lightweight { text = selected && !accent ? tint : base }
        else { text = accent ? (dark ? ink : .white) : selected ? tint : base }
        return configuration.label.font(YoruTypography.text(15, strong: true))
            .padding(.horizontal, 15).padding(.vertical, 8).frame(minHeight: 42)
            .foregroundStyle(text)
            .contentShape(Capsule())
            .modifier(Glass(radius: 100, tint: promoted ? tint.opacity(accent ? 0.32 : 0.23) : nil,
                            interactive: enabled && !reduceMotion, fallback: filledFallback))
            .opacity(enabled ? 1 : 0.47)
            .scaleEffect(configuration.isPressed && !reduceMotion && !lightweight ? 0.97 : 1)
            .animation(reduceMotion || lightweight ? nil : YoruMotion.selection, value: configuration.isPressed)
    }
}

@main struct YoruApp: App {
    @StateObject private var model = Model()
    var body: some Scene {
        WindowGroup("Yoru Public") {
            RootView(model: model)
                .frame(minWidth: 780, minHeight: 510)
                .dynamicTypeSize(.large)
                .onOpenURL { model.openFiles([$0]) }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in model.saveProgress() }
        }
        .defaultSize(width: 1150, height: 735)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Ouvrir une vidéo…") { model.chooseVideos() }.keyboardShortcut("o")
                Button("Choisir le dossier Movies…") { model.chooseFolder() }
            }
            CommandGroup(replacing: .appSettings) {
                Button("Réglages…") { model.settings = true }.keyboardShortcut(",")
            }
            CommandMenu("Lecture") {
                Button("Plein écran") { NSApp.keyWindow?.toggleFullScreen(nil) }.keyboardShortcut("f", modifiers: [.option, .command])
                Button("Ouvrir les sous-titres…") { model.chooseSubtitle() }
                Button("Épisode précédent") { if let previous = model.previous { model.play(previous) } }.disabled(model.previous == nil)
                Button("Épisode suivant") { model.startNextEpisode() }.disabled(model.next == nil)
            }
        }
    }
}

private struct NavigationTabBounds: PreferenceKey {
    static let defaultValue: [Model.Tab: Anchor<CGRect>] = [:]
    static func reduce(value: inout [Model.Tab: Anchor<CGRect>], nextValue: () -> [Model.Tab: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, latest in latest }
    }
}

private struct NavigationScroll: NSViewRepresentable {
    let select: (Int) -> Void

    final class Monitor: NSView {
        var select: ((Int) -> Void)?
        private var token: Any?
        private var movement: CGFloat = 0
        private var stepped = false
        private var timestamp: Double = 0

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let token { NSEvent.removeMonitor(token); self.token = nil }
            guard window != nil else { return }
            token = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.scroll(event) == true ? nil : event
            }
        }

        private func scroll(_ event: NSEvent) -> Bool {
            guard event.window == window, bounds.contains(convert(event.locationInWindow, from: nil)) else { return false }
            guard event.momentumPhase.isEmpty else { return true }
            if event.phase == .began || event.timestamp - timestamp > 0.24 {
                movement = 0
                stepped = false
            }
            timestamp = event.timestamp
            let horizontal = event.scrollingDeltaX
            let vertical = event.scrollingDeltaY
            let delta = abs(horizontal) > abs(vertical) ? horizontal : vertical
            guard delta != 0, !stepped else { return true }
            movement += delta
            if !event.hasPreciseScrollingDeltas || abs(movement) >= 24 {
                stepped = true
                select?(movement < 0 ? 1 : -1)
            }
            return true
        }

        deinit { if let token { NSEvent.removeMonitor(token) } }
    }

    func makeNSView(context: Context) -> Monitor { Monitor() }
    func updateNSView(_ view: Monitor, context: Context) { view.select = select }
}

struct RootView: View {
    @ObservedObject var model: Model
    @State private var keyMonitor: Any?
    @State private var dropTarget = false
    @State private var fullscreen = false
    @State private var fullscreenHeader = false
    private let navigationHeight: CGFloat = 62
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("lightweight") private var lightweight = false
    @AppStorage("theme") private var theme: YoruTheme = .creme
    private let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        let inPlayer = model.tab == .player
        let showsNavigation = !inPlayer || !fullscreen || fullscreenHeader
        ZStack(alignment: .top) {
            Group {
                switch model.tab {
                case .home: HomeView(model: model)
                case .library: LibraryView(model: model)
                case .player:
                    Stage(model: model, player: model.player, fullscreen: fullscreen,
                          navigationClearance: showsNavigation ? navigationHeight : 0)
                case .downloads: DownloadView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, inPlayer ? 0 : navigationHeight)
        }
        .overlay(alignment: .top) {
            if showsNavigation {
                header
                    .frame(height: navigationHeight)
                    .transition(reduceMotion || lightweight ? .identity : .offset(y: -navigationHeight).combined(with: .opacity))
            }
        }
        .background {
            EventActivity { event in
                guard fullscreen, model.tab == .player, event.type == .mouseMoved,
                      let content = event.window?.contentView else { return }
                let point = content.convert(event.locationInWindow, from: nil)
                let distance = content.isFlipped ? point.y : content.bounds.maxY - point.y
                let visible = (0...(fullscreenHeader ? 86.0 : 32.0)).contains(distance)
                if visible != fullscreenHeader {
                    withAnimation(reduceMotion || lightweight ? nil : .easeOut(duration: 0.16)) { fullscreenHeader = visible }
                }
            }.frame(width: 0, height: 0)
        }
        .background(model.tab == .player ? ink : theme.background)
        .font(YoruTypography.text(15))
        .foregroundStyle(model.tab == .player ? Color.white : theme.primary)
        .environment(\.yoruTheme, theme)
        .preferredColorScheme(model.tab == .player ? .dark : theme.colorScheme)
        .overlay {
            if dropTarget { RoundedRectangle(cornerRadius: 16).strokeBorder(mint, lineWidth: 3).padding(8).allowsHitTesting(false) }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTarget) { providers in
            let group = DispatchGroup()
            let urls = NSMutableArray()
            for provider in providers {
                group.enter()
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url { DispatchQueue.main.async { urls.add(url); group.leave() } }
                    else { group.leave() }
                }
            }
            group.notify(queue: .main) { model.openFiles(urls.compactMap { $0 as? URL }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) }
            return !providers.isEmpty
        }
        .onAppear {
            model.refresh()
            if keyMonitor == nil { keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { key($0) ? nil : $0 } }
            runSelfTest()
        }
        .onDisappear { if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil } }
        .onReceive(timer) { _ in model.timer(); Task { await model.checkTransfers() } }
        .onChange(of: model.tab) { tab in if tab != .player { model.closePlayerDownloads() } }
        .onChange(of: model.libraryReady) { ready in
            if ready { Task { await model.discover() } }
        }
        .onChange(of: model.state.history.values.filter(\.watched).count) { _ in Task { await model.discover() } }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in fullscreenHeader = false; fullscreen = true }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in fullscreenHeader = false; fullscreen = false }
        .sheet(isPresented: $model.settings) { SettingsView(model: model).preferredColorScheme(.dark) }
        .alert("Yoru", isPresented: Binding(get: { !model.message.isEmpty }, set: { if !$0 { model.message = "" } })) {
            Button("OK") { model.message = "" }
        } message: { Text(model.message) }
    }

    private var header: some View {
        let player = model.tab == .player
        let tint = player ? YoruTheme.nuit.accent : theme.accent
        let primary = player ? Color.white : theme.primary
        let secondary = player ? Color.white.opacity(0.62) : theme.mutedText

        return ZStack {
            HStack {
                HStack(spacing: 7) {
                    Image(systemName: "moon.stars.fill").font(.system(size: 15, weight: .medium)).foregroundStyle(tint)
                    Text("Yoru").font(YoruTypography.display(31, italic: true)).foregroundStyle(primary).offset(y: -1)
                }.accessibilityElement(children: .combine)
                Spacer()
                if !model.activeTransfers.isEmpty || !model.availableDownloads.isEmpty {
                    Button {
                        model.selectDownloadPane(.transfers)
                        model.tab = .downloads
                    } label: {
                        Image(systemName: model.activeTransfers.isEmpty ? "play.rectangle" : "arrow.down.circle")
                            .font(.system(size: 16)).foregroundStyle(tint)
                    }.buttonStyle(ControlStyle()).accessibilityLabel("Ouvrir les transferts").help("Ouvrir les transferts")
                        .disabled(model.addingTorrent)
                }
                Button { model.settings = true } label: {
                    Image(systemName: "gearshape").font(.system(size: 15, weight: .medium))
                }.buttonStyle(ControlStyle()).accessibilityLabel("Réglages").help("Réglages")
            }
            HStack(spacing: 2) {
                ForEach(Model.Tab.allCases, id: \.self) { tab in
                    let selected = model.tab == tab
                    Button { model.tab = tab } label: {
                        Label(tab.rawValue, systemImage: tab == .home ? "house" : tab == .library ? "square.grid.2x2" : tab == .player ? "play.rectangle" : "arrow.down.to.line")
                            .font(YoruTypography.text(15, strong: true))
                            .foregroundStyle(selected ? primary : secondary)
                            .padding(.horizontal, 13)
                            .frame(height: 40)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .keyboardShortcut(tab == .home ? "0" : tab == .library ? "1" : tab == .player ? "2" : "3")
                    .anchorPreference(key: NavigationTabBounds.self, value: .bounds) { [tab: $0] }
                }
            }
            .backgroundPreferenceValue(NavigationTabBounds.self) { positions in
                GeometryReader { geometry in
                    if let anchor = positions[model.tab] {
                        let bounds = geometry[anchor]
                        Capsule().fill(.clear)
                            .modifier(Glass(radius: 100, tint: tint.opacity(0.24), fallback: tint.opacity(0.14)))
                            .frame(width: bounds.width, height: bounds.height)
                            .position(x: bounds.midX, y: bounds.midY)
                            .animation(reduceMotion || lightweight ? nil : YoruMotion.reveal, value: model.tab)
                    }
                }.allowsHitTesting(false)
            }
            .background {
                NavigationScroll { direction in
                    let tabs = Model.Tab.allCases
                    guard let index = tabs.firstIndex(of: model.tab), tabs.indices.contains(index + direction) else { return }
                    model.tab = tabs[index + direction]
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 5)
        .modifier(Glass(radius: 27, tint: player ? .black.opacity(0.23) : nil,
                        fallback: player ? .black.opacity(0.60) : theme.card))
        .padding(.horizontal, 13).padding(.vertical, 5)
    }

    private func key(_ event: NSEvent) -> Bool {
        if event.keyCode == 53, model.tab == .player, model.playerDownloadsOpen, !model.settings {
            if model.inspected != nil, !model.addingTorrent { model.inspected = nil }
            else { model.closePlayerDownloads() }
            return true
        }
        guard !model.settings, model.message.isEmpty, (model.inspected == nil || (model.tab != .downloads && !model.playerDownloadsOpen)), event.window?.firstResponder is NSTextView == false,
              event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return false }
        let code = event.keyCode
        if model.tab == .library {
            let list = model.displayed
            guard !list.isEmpty else { return false }
            let index = list.firstIndex { $0.id == model.selected } ?? 0
            let episodes = model.seasonEpisodes
            let ep = episodes.firstIndex { $0.id == model.libraryEpisodeFocus } ?? 0
            if code == 53, !model.episodeSelection.isEmpty {
                model.clearEpisodeSelection()
                return true
            }
            if event.modifierFlags.contains(.shift), !episodes.isEmpty, code == 123 || code == 124 {
                let next = min(episodes.count - 1, max(0, ep + (code == 123 ? -1 : 1)))
                model.selectEpisodeRange(through: episodes[next])
                return true
            }
            switch code {
            case 125: model.select(list[min(list.count - 1, index + 1)].id)
            case 126: model.select(list[max(0, index - 1)].id)
            case 123 where !episodes.isEmpty: model.libraryEpisodeFocus = episodes[max(0, ep - 1)].id
            case 124 where !episodes.isEmpty: model.libraryEpisodeFocus = episodes[min(episodes.count - 1, ep + 1)].id
            case 36 where !episodes.isEmpty && model.episodeSelection.isEmpty: model.play(episodes[ep])
            default: return false
            }
            return true
        }
        guard model.tab == .player, model.current != nil else { return false }
        NotificationCenter.default.post(name: .yoruPlaybackActivity, object: nil)
        switch code {
        case 49: model.player.toggle()
        case 123: model.player.seek(model.player.position - 5)
        case 124: model.player.seek(model.player.position + 5)
        case 125: model.player.setVolume(model.player.volume - 5)
        case 126: model.player.setVolume(model.player.volume + 5)
        default:
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "f": NSApp.keyWindow?.toggleFullScreen(nil)
            case "d": model.openPlayerDownloads()
            case "c":
                if event.modifierFlags.contains(.shift) {
                    NotificationCenter.default.post(name: .yoruSubtitleOptions, object: nil)
                } else { model.cycleSubtitles() }
            case "s":
                guard let segment = model.player.currentSkip else { return false }
                model.skipSegment(segment)
            default: return false
            }
        }
        return true
    }

    private func runSelfTest() {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--self-test"), flag + 1 < arguments.count else { return }
        let url = URL(fileURLWithPath: arguments[flag + 1])
        Task {
            NSApp.activate(ignoringOtherApps: true)
            if arguments.contains("--test-ending") {
                for _ in 0..<16 where !model.libraryReady { try? await Task.sleep(nanoseconds: 100_000_000) }
            }
            model.openURLs([url])
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            let loaded = model.player.loaded && model.player.duration > 0 && model.player.position > 0 && model.player.surface.renderedFrames > 0 && model.player.error.isEmpty
            print("PLAYBACK loaded=\(model.player.loaded) duration=\(model.player.duration) position=\(model.player.position) tracks=\(model.player.tracks.count) skips=\(model.player.skips.count) frames=\(model.player.surface.renderedFrames) error=\(model.player.error)")
            if loaded, let flag = arguments.firstIndex(of: "--test-torrent-panel"), arguments.indices.contains(flag + 1) {
                let item = URL(fileURLWithPath: arguments[flag + 1])
                model.openFiles([item])
                guard model.tab == .player, model.playerDownloadsOpen, model.inspected?.torrent == item,
                      model.preview?.files.count == 2, model.chosenFiles.count == 2 else { exit(11) }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                model.closePlayerDownloads()
                print("TORRENT PANEL open/import/preview/close, stayed on player with ongoing playback")
                exit(model.tab == .player && model.player.position > 3 && !model.playerDownloadsOpen ? 0 : 12)
            }
            if loaded, arguments.contains("--test-ending") {
                guard let target = model.next,
                      let ending = model.player.skips.first(where: { $0.kind == "ed" }),
                      model.previous != nil else { exit(8) }
                model.player.seek(ending.start + 1)
                for _ in 0..<40 where model.current?.id != target.id {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                }
                guard model.current?.id == target.id else {
                    print("ENDING failed position=\(model.player.position) target=\(ending.start) paused=\(model.player.paused) skip=\(String(describing: model.player.currentSkip)) next=\(String(describing: model.next?.number))")
                    exit(9)
                }
                print("ENDING countdown advanced to episode \(target.number ?? -1), previous available")
                try? await Task.sleep(nanoseconds: 750_000_000)
                exit(model.player.loaded ? 0 : 10)
            }
            if loaded, arguments.contains("--test-fullscreen"), let window = NSApp.windows.first(where: { $0.isVisible }) {
                let initialFrames = model.player.surface.renderedFrames
                window.toggleFullScreen(nil)
                try? await Task.sleep(nanoseconds: 1_300_000_000)
                let entered = window.styleMask.contains(.fullScreen)
                if entered, arguments.contains("--test-fullscreen-nav"), let content = window.contentView {
                    func move(_ distance: CGFloat) {
                        let y = content.isFlipped ? distance : content.bounds.maxY - distance
                        let point = content.convert(NSPoint(x: content.bounds.midX, y: y), to: nil)
                        if let event = NSEvent.mouseEvent(with: .mouseMoved, location: point, modifierFlags: [],
                            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                            context: nil, eventNumber: 0, clickCount: 0, pressure: 0) {
                            NSApp.postEvent(event, atStart: false)
                        }
                    }
                    move(16)
                    try? await Task.sleep(nanoseconds: 320_000_000)
                    let headerShown = fullscreenHeader
                    move(160)
                    try? await Task.sleep(nanoseconds: 320_000_000)
                    guard headerShown, !fullscreenHeader else { print("FULLSCREEN NAV failed"); exit(13) }
                    print("FULLSCREEN NAV revealed and dismissed")
                }
                window.toggleFullScreen(nil)
                try? await Task.sleep(nanoseconds: 1_300_000_000)
                let exited = !window.styleMask.contains(.fullScreen)
                print("FULLSCREEN entered=\(entered) exited=\(exited) new-frames=\(model.player.surface.renderedFrames - initialFrames)")
                if !entered || !exited || model.player.surface.renderedFrames <= initialFrames { exit(4) }
            }
            if loaded, let track = model.player.tracks.first(where: { $0.kind == "sub" }) {
                model.chooseTrack(track)
                model.changeDelay(0.5)
                model.player.seek(3)
                try? await Task.sleep(nanoseconds: 600_000_000)
                print("CONTROLS sid=\(String(describing: model.player.activeSubtitle)) delay=\(model.player.delay) position=\(model.player.position)")
                if arguments.contains("--hold-preview") { try? await Task.sleep(nanoseconds: 8_000_000_000) }
                exit(model.player.activeSubtitle == track.id && model.player.delay == 0.5 && model.player.position >= 3 ? 0 : 3)
            }
            exit(loaded ? 0 : 1)
        }
    }
}

struct LibraryView: View {
    @ObservedObject var model: Model
    @Environment(\.yoruTheme) private var theme
    @State private var editShow: Series?
    @State private var planSheet = false
    @State private var plannedTitle = ""
    @State private var backdrop: URL?
    @State private var seasonCover: URL?
    @State private var episodeFrames: [String: CGRect] = [:]
    @State private var episodeSweep: EpisodeSweep?
    @State private var suppressClickUntil = 0.0
    @Namespace private var episodeGrid
    @AppStorage("lightweight") private var lightweight = false

    private struct EpisodeSweep {
        let start: String
        let initial: Set<String>
        let adding: Bool
        var end: String
    }

    private struct EpisodeFrames: PreferenceKey {
        static let defaultValue: [String: CGRect] = [:]
        static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
            value.merge(nextValue()) { _, new in new }
        }
    }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        GeometryReader { geometry in
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    SectionHeading(title: "Bibliothèque", compact: true)
                    Spacer()
                    Button { plannedTitle = ""; planSheet = true } label: { Image(systemName: "plus") }.buttonStyle(ControlStyle()).help("Ajouter une série à regarder")
                }
                HStack {
                    SearchField(title: "Rechercher", value: $model.filter, icon: "magnifyingglass")
                        .onChange(of: model.filter) { _ in if model.selectedSeries == nil { model.select(model.displayed.first?.id) } }
                    Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(ControlStyle()).help("Actualiser")
                }
                HStack {
                    Button("Tout") { model.watchlistOnly = false; if model.selectedSeries == nil { model.select(model.displayed.first?.id) } }
                        .buttonStyle(ControlStyle(selected: !model.watchlistOnly))
                    Button("À regarder") { model.watchlistOnly = true; if model.selectedSeries == nil { model.select(model.displayed.first?.id) } }
                        .buttonStyle(ControlStyle(selected: model.watchlistOnly))
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 5) {
                            ForEach(model.displayed) { item in
                                Button { model.select(item.id) } label: {
                                    HStack(spacing: 10) {
                                        AnimeCover(title: item.query, id: model.state.shows[item.id]?.aniListID, preview: item.episodes.first, width: 36, height: 51)
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(item.title).font(YoruTypography.text(16, strong: true)).lineLimit(2)
                                            let total = item.episodes.count
                                            let watched = item.episodes.filter { model.progress($0).watched }.count
                                            Text(total == 0 ? "À regarder" : total == 1 && item.episodes.first?.number == nil ? "Vidéo" : "\(watched) / \(total) vus")
                                                .font(YoruTypography.text(13)).foregroundStyle(theme.mutedText)
                                        }
                                        Spacer(minLength: 4)
                                        if let score = model.score(item) { Text(score.formatted()).font(.system(size: 12, weight: .medium)).foregroundStyle(theme.accent) }
                                    }
                                    .padding(.horizontal, 13).padding(.vertical, 10)
                                    .background(model.selected == item.id ? theme.tint : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                                    .overlay(alignment: .leading) {
                                        if model.selected == item.id { Capsule().fill(theme.accent).frame(width: 2, height: 21).allowsHitTesting(false) }
                                    }
                                    .contentShape(Rectangle())
                                }.buttonStyle(.plain).id(item.id)
                            }
                        }
                    }
                    .onChange(of: model.selected) { id in if let id { proxy.scrollTo(id) } }
                }
                Text(model.folder.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                    .font(.caption).foregroundStyle(theme.mutedText).lineLimit(1)
            }
            .padding(18).frame(width: min(365, max(244, geometry.size.width * 0.245)))
            .modifier(Glass(radius: 27, tint: theme.card.opacity(0.3), fallback: theme.card))
            .padding(.leading, 13).padding(.vertical, 7)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 19) {
                        if let show = model.selectedSeries {
                            title(show)
                            metadata(show)
                            if let offer = model.suggestedSeason, offer.showID == show.id,
                               model.librarySeason == nil || model.librarySeason == offer.current {
                                SeasonOfferCard(offer: offer) { model.findSeason(offer) }
                            }
                            seasons(show)
                            episodeCards
                        } else {
                            VStack(alignment: .leading, spacing: 13) {
                                SectionHeading(title: "Ta bibliothèque")
                                Text("Choisis un dossier ou glisse une vidéo dans la fenêtre.").foregroundStyle(theme.mutedText)
                                Button("Choisir un dossier…") { model.chooseFolder() }.buttonStyle(ControlStyle(accent: true))
                            }.padding(.vertical, 45)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(geometry.size.width > 1250 ? 34 : 23)
                        .padding(.bottom, model.episodeSelection.isEmpty && model.watchUndoCount == 0 ? 0 : 100)
                }.onChange(of: model.libraryEpisodeFocus) { id in if let id { proxy.scrollTo(id) } }
                    .overlay(alignment: .bottom) { selectionBar }
                    .animation(motion, value: !model.episodeSelection.isEmpty || model.watchUndoCount > 0)
            }
        }
        .background { ArtBackdrop(url: backdrop) }
        }
        .task(id: (model.selected ?? "") + "|" + String(model.librarySeason ?? 0) + "|" + String(model.selected.flatMap { model.state.shows[$0]?.aniListID } ?? 0)) {
            backdrop = nil
            seasonCover = nil
            guard let show = model.selectedSeries else { backdrop = nil; seasonCover = nil; return }
            let id = model.state.shows[show.id]?.aniListID
            let season = await ArtworkCatalog.shared.season(model.librarySeason ?? 1, title: show.query, id: id)
            let art: Anime?
            if let season { art = season }
            else { art = await ArtworkCatalog.shared.match(show.query, id: id) }
            guard !Task.isCancelled else { return }
            withAnimation(motion) {
                backdrop = art?.bannerImage ?? art?.coverImage?.large
                seasonCover = art?.coverImage?.large
            }
        }
        .sheet(item: $editShow) { show in EditShow(model: model, show: show) }
        .onDisappear { model.clearEpisodeSelection() }
        .sheet(isPresented: $planSheet) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Ajouter à regarder").font(.title2.bold())
                TextField("Titre de la série", text: $plannedTitle).textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("Annuler") { planSheet = false }.keyboardShortcut(.cancelAction)
                    Button("Ajouter") { model.plan(plannedTitle); planSheet = false }
                        .buttonStyle(ControlStyle(accent: true)).keyboardShortcut(.defaultAction).disabled(plannedTitle.trimmed.isEmpty)
                }
            }.padding(22).frame(width: 405)
        }
    }

    private var motion: Animation? { reduceMotion || lightweight ? nil : YoruMotion.reveal }

    private var episodeCards: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 13)], spacing: 13) {
            ForEach(model.seasonEpisodes) { episode in
                row(episode).background {
                    GeometryReader { geometry in
                        Color.clear.preference(key: EpisodeFrames.self, value: [episode.id: geometry.frame(in: .named(episodeGrid))])
                    }
                }.id(episode.id)
            }
        }
        .contentShape(Rectangle())
        .coordinateSpace(name: episodeGrid)
        .onPreferenceChange(EpisodeFrames.self) { episodeFrames = $0 }
        .simultaneousGesture(DragGesture(minimumDistance: 7, coordinateSpace: .named(episodeGrid))
            .onChanged { movement in
                if episodeSweep == nil,
                   let start = episodeFrames.first(where: { $0.value.contains(movement.startLocation) })?.key {
                    episodeSweep = EpisodeSweep(start: start, initial: model.episodeSelection,
                                                adding: !model.episodeSelection.contains(start), end: start)
                }
                guard var sweep = episodeSweep else { return }
                if let end = episodeFrames.first(where: { $0.value.contains(movement.location) })?.key {
                    sweep.end = end
                    episodeSweep = sweep
                }
                let range = model.episodeRange(from: sweep.start, to: sweep.end)
                let selected = sweep.adding ? sweep.initial.union(range) : sweep.initial.subtracting(range)
                if selected != model.episodeSelection { model.episodeSelection = selected }
            }
            .onEnded { _ in
                if episodeSweep != nil { suppressClickUntil = ProcessInfo.processInfo.systemUptime + 0.17 }
                episodeSweep = nil
            })
    }

    @ViewBuilder private var selectionBar: some View {
        let count = model.episodeSelection.count
        if count > 0 || model.watchUndoCount > 0 {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) { selectionSummary(count); selectionActions(count) }
                VStack(alignment: .leading, spacing: 7) { selectionSummary(count); selectionActions(count) }
            }
            .padding(10).modifier(Glass(radius: 25, tint: theme.card.opacity(0.35), fallback: theme.card))
            .padding(.horizontal, 13).padding(.bottom, 12)
            .transition(.offset(y: reduceMotion || lightweight ? 0 : 13).combined(with: .opacity))
        }
    }

    private func selectionSummary(_ count: Int) -> some View {
        Text(count == 0
             ? (model.watchUndoCount == 1 ? "1 épisode modifié" : "\(model.watchUndoCount) épisodes modifiés")
             : (count == 1 ? "1 épisode choisi" : "\(count) épisodes choisis"))
            .font(YoruTypography.text(15, strong: true)).fixedSize()
    }

    private func selectionActions(_ count: Int) -> some View {
        HStack(spacing: 6) {
            if count > 0 {
                Button("Marquer vus") { model.markEpisodeSelection(watched: true) }
                    .buttonStyle(ControlStyle(accent: true))
                Button("Marquer non vus") { model.markEpisodeSelection(watched: false) }
                    .buttonStyle(ControlStyle())
                Button { model.clearEpisodeSelection() } label: { Image(systemName: "xmark") }
                    .buttonStyle(ControlStyle()).accessibilityLabel("Quitter la sélection")
            } else {
                Button("Annuler") { model.undoEpisodeWatchChange() }.buttonStyle(ControlStyle())
            }
        }.fixedSize()
    }

    private func chooseEpisodeCard(_ episode: Episode) {
        guard episodeSweep == nil, ProcessInfo.processInfo.systemUptime >= suppressClickUntil else { return }
        if NSEvent.modifierFlags.contains(.shift) { model.selectEpisodeRange(through: episode) }
        else if !model.episodeSelection.isEmpty { model.toggleEpisodeSelection(episode) }
        else { model.libraryEpisodeFocus = episode.id; model.play(episode) }
    }

    @ViewBuilder func seasons(_ show: Series) -> some View {
        let seasons = Set(show.episodes.compactMap(\.season)).sorted()
        if !show.episodes.isEmpty {
            ScrollView(.horizontal) {
                HStack {
                    if !seasons.isEmpty {
                        Button("Tous") { model.selectSeason(nil) }.buttonStyle(ControlStyle(selected: model.librarySeason == nil))
                        ForEach(seasons, id: \.self) { number in
                            Button("Saison \(number)") { model.selectSeason(number) }
                                .buttonStyle(ControlStyle(selected: model.librarySeason == number))
                        }
                    } else { Text(show.episodes.count == 1 ? "Vidéo" : "Épisodes").font(.title2.bold()) }
                }.padding(.vertical, 2)
            }.scrollIndicators(.hidden)
        }
    }

    func title(_ show: Series) -> some View {
        let episodes = model.seasonEpisodes
        let watched = episodes.filter { model.progress($0).watched }.count
        return HStack(alignment: .center, spacing: 17) {
            AnimeCover(title: show.query, id: model.state.shows[show.id]?.aniListID, url: seasonCover,
                       preview: episodes.first, width: 83, height: 122)
            VStack(alignment: .leading, spacing: 10) {
                Text(show.title)
                    .font(YoruTypography.display(48))
                    .textSelection(.enabled).lineLimit(2).minimumScaleFactor(0.75)
                    .accessibilityAddTraits(.isHeader)
                if !episodes.isEmpty, episodes.contains(where: { $0.number != nil }) {
                    HStack(spacing: 8) {
                        if let season = model.librarySeason { Text("Saison \(season)") }
                        Text("\(watched) / \(episodes.count) vus")
                            .monospacedDigit()
                    }.font(YoruTypography.text(14)).foregroundStyle(.white.opacity(0.75))
                }
                HStack(spacing: 6) {
                    if let first = episodes.first(where: { !model.progress($0).watched }) ?? episodes.first {
                        Button { model.play(first) } label: {
                            Label(model.progress(first).seconds > 3 ? "Reprendre" : "Regarder", systemImage: "play.fill")
                        }.buttonStyle(ControlStyle(accent: true))
                    }
                    Button { model.findDownloads(show) } label: {
                        Label("Trouver un pack", systemImage: "arrow.down.to.line")
                    }.buttonStyle(ControlStyle())
                    Button {
                        model.updateShow(show.id) { $0.watchlist.toggle() }
                        if model.selectedSeries == nil { model.select(model.displayed.first?.id) }
                    } label: {
                        Image(systemName: model.state.shows[show.id]?.watchlist == true ? "bookmark.fill" : "bookmark")
                    }.buttonStyle(ControlStyle()).accessibilityLabel("À regarder").help("À regarder")
                    Button { editShow = show } label: {
                        Image(systemName: "slider.horizontal.3")
                    }.buttonStyle(ControlStyle()).accessibilityLabel("Modifier les informations").help("Modifier le titre, la note ou le lien")
                }
                if let link = model.state.shows[show.id]?.nautiljonURL, let url = URL(string: link), url.scheme == "https" {
                    Link("Nautiljon", destination: url).font(.caption).foregroundStyle(YoruTheme.nuit.accent)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18).frame(maxWidth: .infinity, minHeight: 169, alignment: .leading)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .environment(\.yoruTheme, .nuit)
        .background {
            GeometryReader { geometry in
                ZStack(alignment: .trailing) {
                    Color(red: 0.087, green: 0.105, blue: 0.092)
                    WideArtwork(url: backdrop)
                        .frame(width: geometry.size.width * 0.66)
                        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.24)],
                                             startPoint: .leading, endPoint: .trailing))
                    LinearGradient(colors: [
                        Color(red: 0.063, green: 0.078, blue: 0.068),
                        Color(red: 0.063, green: 0.078, blue: 0.068).opacity(0.86),
                        .black.opacity(0.51)
                    ], startPoint: .leading, endPoint: .trailing)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(.white.opacity(0.10)).allowsHitTesting(false))
    }

    @ViewBuilder func metadata(_ show: Series) -> some View {
        if let anime = model.anime[show.id] {
            VStack(alignment: .leading, spacing: 8) {
                if let next = anime.nextAiringEpisode {
                    Text("Épisode \(next.episode) · \(Date(timeIntervalSince1970: next.airingAt).formatted(date: .abbreviated, time: .shortened))")
                        .foregroundStyle(theme.accent).font(.callout)
                }
                ForEach((anime.relations?.edges ?? []).filter { $0.node.type == "ANIME" && ["SEQUEL", "SPIN_OFF", "PREQUEL", "SIDE_STORY"].contains($0.relationType) }.prefix(5), id: \.node.id) { edge in
                    Button {
                        model.search = edge.node.title.romaji ?? edge.node.title.english ?? ""
                        model.episodeNumber = ""; model.seasonNumber = ""; model.packs = true
                        model.tab = .downloads
                        model.searchTorrents()
                    } label: {
                        HStack {
                            CoverArt(url: edge.node.coverImage?.large, width: 24, height: 33, radius: 4)
                            Label((["SEQUEL": "Suite", "SPIN_OFF": "Spin-off", "PREQUEL": "Précédent", "SIDE_STORY": "Histoire annexe"][edge.relationType] ?? "") + " · " + (edge.node.title.romaji ?? edge.node.title.english ?? ""), systemImage: "arrow.up.right")
                        }
                    }.buttonStyle(.plain).foregroundStyle(theme.mutedText).font(.callout)
                    .contextMenu {
                        Button("Ajouter à regarder") {
                            if let title = edge.node.title.romaji ?? edge.node.title.english {
                                model.plan(title, catalogID: edge.node.id)
                            }
                        }
                    }
                }
            }
        } else if model.matches.isEmpty {
            Button(model.metadataBusy ? "Recherche…" : "Voir les suites et prochaines sorties") { model.metadata(for: show) }
                .buttonStyle(.plain).foregroundStyle(theme.accent).disabled(model.metadataBusy)
        }
        if !model.matches.isEmpty {
            Menu("Associer à une fiche AniList") {
                ForEach(model.matches) { result in Button(result.name) { model.assign(result, to: show) } }
            }.fixedSize()
        }
    }

    func row(_ episode: Episode) -> some View {
        let status = model.progress(episode)
        let focused = model.libraryEpisodeFocus == episode.id
        let selected = model.episodeSelection.contains(episode.id)
        let title = model.librarySeason != nil
            ? episode.number.map { String(format: "%02d", $0) } ?? episode.title
            : episode.display
        let selecting = !model.episodeSelection.isEmpty
        let action = selecting ? (selected ? "Retirer de la sélection" : "Sélectionner") : "Lire"
        return Button { chooseEpisodeCard(episode) } label: {
            VStack(spacing: 0) {
                Rectangle().fill(theme.card)
                    .aspectRatio(2.18, contentMode: .fit)
                    .overlay {
                        GeometryReader { geometry in
                            EpisodeStill(episode: episode, width: geometry.size.width, height: geometry.size.height)
                        }
                    }
                    .overlay(alignment: .bottomLeading) {
                        if status.seconds > 3 && !status.watched {
                            ProgressLine(fraction: status.fraction, tint: YoruTheme.nuit.accent, track: .black.opacity(0.40))
                        }
                    }
                    .overlay(alignment: .center) {
                        if focused && !selecting {
                            Image(systemName: "play.fill").font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(.black.opacity(0.6), in: Circle())
                        }
                    }
                    .clipped()
                    .overlay(alignment: .topTrailing) {
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 24, weight: .semibold)).foregroundStyle(.black, theme.accent)
                                .padding(9).transition(.scale(scale: 0.82).combined(with: .opacity))
                        }
                    }
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(YoruTypography.text(17, strong: true)).lineLimit(2)
                        if status.seconds > 3 && !status.watched {
                            Text("Reprendre à " + formatTime(status.seconds))
                                .font(YoruTypography.text(13).monospacedDigit()).foregroundStyle(theme.mutedText)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if status.watched {
                        Label("Vu", systemImage: "checkmark")
                            .font(YoruTypography.text(13, strong: true)).foregroundStyle(theme.accent)
                    }
                }.padding(.horizontal, 10).padding(.vertical, 9).frame(minHeight: 38)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .modifier(HoverCard())
            .background(selected ? theme.tint : Color.clear, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected || focused ? theme.accent.opacity(0.84) : .clear, lineWidth: selected ? 2 : 1)
                .allowsHitTesting(false))
            .contentShape(Rectangle())
        }
            .buttonStyle(.plain)
            .accessibilityLabel(action + " · " + episode.display)
            .accessibilityValue(status.watched ? "Vu" : status.seconds > 3 ? "Reprendre à " + formatTime(status.seconds) : "")
            .animation(reduceMotion || lightweight ? nil : YoruMotion.selection, value: selected)
            .highPriorityGesture(TapGesture().modifiers(.shift).onEnded {
                guard episodeSweep == nil else { return }
                model.selectEpisodeRange(through: episode)
            })
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityAction(named: status.watched ? "Marquer non vu" : "Marquer vu") { model.toggleWatched(episode) }
            .contextMenu {
                Button(selected ? "Retirer de la sélection" : "Sélectionner cet épisode") { model.toggleEpisodeSelection(episode) }
                Button("Lire depuis le début") { model.play(episode, restart: true) }
                Button(status.watched ? "Marquer non vu" : "Marquer vu") { model.toggleWatched(episode) }
                Button("Chercher cette version") { if let item = model.selectedSeries { model.findDownloads(item, episode: episode) } }
                Button("Afficher dans le Finder") { NSWorkspace.shared.activateFileViewerSelecting([episode.url]) }
            }
    }
}

func formatTime(_ seconds: Double) -> String {
    let total = Int(seconds.isFinite ? max(0, seconds) : 0)
    return total >= 3600 ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60) : String(format: "%d:%02d", total / 60, total % 60)
}

struct EditShow: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var model: Model
    let show: Series
    @State var title = ""
    @State var query = ""
    @State var rating = ""
    @State var link = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Modifier la fiche").font(.title.bold())
            TextField("Titre affiché", text: $title)
            TextField("Nom pour la recherche", text: $query)
            TextField("Note sur 10", text: $rating)
            TextField("Lien Nautiljon", text: $link)
            HStack {
                Spacer()
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Enregistrer") {
                    let value = Double(rating.replacingOccurrences(of: ",", with: "."))
                    model.updateShow(show.id) {
                        $0.title = title.trimmed; $0.query = query.trimmed
                        $0.rating = value.map { min(10, max(0, $0)) }
                        $0.nautiljonURL = link.trimmed.nonEmpty
                    }
                    model.refresh()
                    dismiss()
                }.buttonStyle(ControlStyle(accent: true)).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 430)
            .onAppear {
                title = show.title; query = show.query
                rating = model.score(show)?.formatted() ?? ""
                link = model.state.shows[show.id]?.nautiljonURL ?? ""
            }
    }
}
