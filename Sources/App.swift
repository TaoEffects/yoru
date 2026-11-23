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

struct VideoGlass: ViewModifier {
    let radius: CGFloat

    func body(content: Content) -> some View {
        content.modifier(Glass(radius: radius, tint: .black.opacity(0.54), fallback: .black.opacity(0.73)))
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

struct ControlStyle: PrimitiveButtonStyle {
    var selected = false
    var accent = false
    var horizontalPadding: CGFloat = 15
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        Button(configuration)
            .buttonStyle(VisualControlStyle(selected: selected, accent: accent, horizontalPadding: horizontalPadding, compact: compact))
            .directionalTarget(radius: 100, animatesButton: true, action: configuration.trigger)
    }
}

private struct VisualControlStyle: ButtonStyle {
    @Environment(\.yoruTheme) private var theme
    var selected = false
    var accent = false
    var horizontalPadding: CGFloat = 15
    var compact = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    @AppStorage("animatePlaybackButtons") private var animateButtons = true
    @AppStorage("lightweight") private var lightweight = false
    func makeBody(configuration: Configuration) -> some View {
        let dark = scheme == .dark
        let base = dark ? Color.white : ink
        let tint = dark && theme.colorScheme == .light ? mint : theme.accent
        let promoted = accent || selected
        let filledFallback = accent ? tint : selected ? tint.opacity(0.15) : base.opacity(configuration.isPressed ? 0.16 : 0.07)
        let text: Color
        if #available(macOS 26, *), !lightweight { text = selected && !accent ? tint : base }
        else { text = accent ? (dark ? ink : .white) : selected ? tint : base }
        return configuration.label.font(YoruTypography.text(15, strong: true))
            .padding(.horizontal, horizontalPadding).padding(.vertical, compact ? 5 : 8)
            .frame(minHeight: compact ? 32 : 42)
            .foregroundStyle(text)
            .contentShape(Capsule())
            .modifier(Glass(radius: 100, tint: promoted ? tint.opacity(accent ? 0.32 : 0.23) : nil,
                            interactive: enabled && animateButtons && !reduceMotion, fallback: filledFallback))
            .opacity(enabled ? 1 : 0.47)
            .modifier(GlassButtonMotion(pressed: configuration.isPressed, radius: 100))
    }
}

@main struct YoruApp: App {
    @StateObject private var model = Model()
    @AppStorage("interfaceLanguage") private var interfaceLanguage = "system"
    @AppStorage(YoruUsageMode.preferenceKey) private var usagePreference = ""
    var body: some Scene {
        WindowGroup("Yoru Public") {
            GeometryReader { geometry in
                RootView(model: model, topInset: geometry.safeAreaInsets.top)
                    .ignoresSafeArea(.container, edges: .top)
            }
            .frame(minWidth: 780, minHeight: 510)
            .dynamicTypeSize(.large)
            .environment(\.locale, Locale(identifier: L.code))
            .onOpenURL { model.openFiles([$0]) }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in model.saveProgress() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1150, height: 735)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(L.tr("Ouvrir une vidéo…")) { model.chooseVideos() }.keyboardShortcut("o")
                if YoruUsageMode(rawValue: usagePreference)?.hasLibrary == true {
                    Button(L.tr("Choisir le dossier de la bibliothèque…")) { model.chooseFolder(thenOpenLibrary: true) }
                }
            }
            CommandGroup(replacing: .appSettings) {
                Button(L.tr("Réglages…")) { model.settings = true }.keyboardShortcut(",").disabled(usagePreference.isEmpty)
            }
            CommandMenu(L.tr("Lecture")) {
                Button(L.tr("Plein écran")) { NSApp.keyWindow?.toggleFullScreen(nil) }.keyboardShortcut("f", modifiers: [.option, .command])
                Button(L.tr("Ajuster la fenêtre en 16:9")) { if let window = NSApp.keyWindow { fitPlaybackWindow(window) } }
                    .disabled(model.tab != .player)
                Button(L.tr("Ouvrir les sous-titres…")) { model.chooseSubtitle() }
                Button(L.tr("Épisode précédent")) { if let previous = model.previous { model.play(previous) } }.disabled(model.previous == nil)
                Button(L.tr("Épisode suivant")) { model.startNextEpisode() }.disabled(model.next == nil)
            }
        }
    }
}

@discardableResult private func fitPlaybackWindow(_ window: NSWindow) -> Bool {
    guard !window.styleMask.contains(.fullScreen), let area = window.screen?.visibleFrame else { return false }
    let ratio = 16.0 / 9.0
    let old = window.frame
    let minWidth = max(window.minSize.width, window.minSize.height * ratio)
    let maxWidth = min(area.width, area.height * ratio)
    guard minWidth <= maxWidth else { return false }
    let width = min(max(old.width, minWidth), maxWidth)
    let height = width / ratio
    let x = min(max(old.minX, area.minX), area.maxX - width)
    let y = min(max(old.maxY - height, area.minY), area.maxY - height)
    window.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true, animate: false)
    return abs(window.frame.width / window.frame.height - ratio) < 0.01
}

private struct WindowAttachment: NSViewRepresentable {
    let onAttach: (NSWindow) -> Void

    final class Anchor: NSView {
        var onAttach: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                guard let self, let window else { return }
                onAttach?(window)
            }
        }
    }

    func makeNSView(context: Context) -> Anchor { Anchor() }
    func updateNSView(_ view: Anchor, context: Context) { view.onAttach = onAttach }
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
    @AppStorage("interfaceLanguage") private var interfaceLanguage = "system"
    let topInset: CGFloat
    @State private var keyMonitor: Any?
    @State private var spacePress = PlaybackPress()
    @State private var navigation = DirectionalNavigation()
    @State private var controllers = ControllerInput()
    @State private var dropTarget = false
    @State private var fullscreen = false
    @State private var fullscreenHeader = false
    @State private var playbackControls = true
    @State private var sizedForPlayback = false
    @State private var libraryBackdrop: URL?
    private final class WindowReference { weak var window: NSWindow? }
    @State private var windowReference = WindowReference()
    private let navigationHeight: CGFloat = 62
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage("lightweight") private var lightweight = false
    @AppStorage("theme") private var theme: YoruTheme = InterfaceDefaults.theme
    @AppStorage("lowercaseInterface") private var lowercaseInterface = InterfaceDefaults.lowercase
    @AppStorage("fitPlaybackOnFirstOpen") private var fitPlaybackOnFirstOpen = true
    @AppStorage("inlinePlayerNavigation") private var inlinePlayerNavigation = InterfaceDefaults.inlinePlayerNavigation
    @AppStorage("hidePlayerNavigationWithControls") private var hidePlayerNavigationWithControls = true
    @State private var browsingPictureInPicture = false
    @State private var pictureInPictureActive = false
    @AppStorage("browsePlayback") private var browsePlayback: BrowsePlayback = .bubble
    @AppStorage("animatePlaybackButtons") private var animateButtons = true
    @AppStorage("playbackArrows") private var playbackArrows: PlaybackArrows = .hybrid
    @AppStorage(YoruUsageMode.preferenceKey) private var usagePreference = ""
    private var labels: InterfaceLabels { InterfaceLabels(lowercase: lowercaseInterface) }
    private var usage: YoruUsageMode? {
        if CommandLine.arguments.contains("--self-test") { return .complete }
        return YoruUsageMode(rawValue: usagePreference)
    }
    private let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        screen
        .onDrop(of: [.fileURL], isTargeted: $dropTarget, perform: openDroppedFiles)
        .onAppear(perform: begin)
        .onDisappear(perform: end)
        .onReceive(timer) { _ in
            model.timer()
            if usage?.hasDownloads == true || !model.activeTransfers.isEmpty { Task { await model.checkTransfers() } }
        }
        .onChange(of: usagePreference) { _ in
            guard let usage else { return }
            navigation.clear()
            applyMode(usage)
        }
        .onChange(of: model.tab) { tab in
            cancelPlaybackHold()
            model.presentedAnime = nil
            model.watchlistOpen = false
            if tab != .player { model.closePlayerDownloads() }
            sizeFirstPlayback()
            updateBrowsingPlayback()
        }
        .onChange(of: model.current?.id) { _ in cancelPlaybackHold(); sizeFirstPlayback(); updateBrowsingPlayback() }
        .onChange(of: browsePlayback) { _ in updateBrowsingPlayback() }
        .onReceive(model.player.$loaded.removeDuplicates()) { loaded in
            if loaded { Task { @MainActor in updateBrowsingPlayback() } }
            else { cancelPlaybackHold() }
        }
        .onReceive(model.player.$pictureInPictureActive.removeDuplicates()) { pictureInPictureActive = $0 }
        .onChange(of: model.settings) { _ in cancelPlaybackHold() }
        .onChange(of: model.playerDownloadsOpen) { _ in cancelPlaybackHold() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in cancelPlaybackHold() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) {
            if ($0.object as? NSWindow) === windowReference.window { cancelPlaybackHold() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in sizeFirstPlayback() }
        .onChange(of: model.libraryReady) { ready in
            if ready { Task { await model.discover() } }
        }
        .onChange(of: model.state.history.values.filter(\.watched).count) { _ in Task { await model.discover() } }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in fullscreenHeader = false; fullscreen = true }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in fullscreenHeader = false; fullscreen = false }
        .sheet(isPresented: $model.settings) { SettingsView(model: model) }
        .alert("Yoru", isPresented: Binding(get: { !model.message.isEmpty }, set: { if !$0 { model.message = "" } })) {
            Button("OK") { model.message = "" }
        } message: { Text(L.tr(model.message)) }
        .buttonStyle(DirectionalPlainStyle())
        .environment(\.directionalNavigation, navigation)
    }

    @ViewBuilder private var screen: some View {
        if usage != nil { layout }
        else {
            WelcomeView(titlebarClearance: max(topInset, 32)) { mode in usagePreference = mode.rawValue }
                .environment(\.yoruTheme, theme)
                .environment(\.yoruLabels, labels)
                .preferredColorScheme(theme.colorScheme)
        }
    }

    private func applyMode(_ mode: YoruUsageMode) {
        if model.current == nil || !mode.tabs.contains(model.tab) { model.tab = mode.startTab }
        if !mode.hasDownloads { model.closePlayerDownloads() }
        if mode.hasLibrary { model.refresh() }
        if mode.hasDownloads, model.libraryReady {
            Task { await model.discover(); await model.checkTransfers(force: true) }
        }
    }

    private var layout: some View {
        let inPlayer = model.tab == .player
        let showMini = !inPlayer && model.current != nil && browsePlayback == .bubble && !pictureInPictureActive
        let visibleWithControls = playbackControls || !hidePlayerNavigationWithControls
        let showsNavigation = !inPlayer || (fullscreen ? fullscreenHeader && visibleWithControls : model.current == nil || visibleWithControls)
        let titlebar = fullscreen ? 0 : max(topInset, 32)
        let inlineNavigation = inPlayer && !fullscreen && inlinePlayerNavigation
        let headerOffset = inlineNavigation ? 0 : titlebar
        let headerHeight: CGFloat = inlineNavigation ? 44 : navigationHeight
        let navigationClearance = headerOffset + headerHeight
        let showPage = reduceMotion || lightweight || inPlayer ? AnyTransition.identity : YoruMotion.page
        return ZStack(alignment: .top) {
            Group {
                if model.watchlistOpen {
                    WatchlistGallery(model: model, navigationClearance: navigationClearance)
                        .opacity(model.presentedAnime == nil ? 1 : 0)
                        .disabled(model.presentedAnime != nil)
                        .accessibilityHidden(model.presentedAnime != nil)
                } else if model.presentedAnime == nil {
                    switch model.tab {
                    case .home: HomeView(model: model, navigationClearance: navigationClearance)
                    case .library:
                        LibraryView(model: model, backdrop: $libraryBackdrop, navigationClearance: navigationClearance)
                    case .player:
                        Stage(model: model, player: model.player, fullscreen: fullscreen,
                              navigationClearance: fullscreen && !fullscreenHeader ? 0 : navigationClearance,
                              controls: $playbackControls)
                    case .downloads: DownloadView(model: model).padding(.top, navigationClearance)
                    }
                }
                if let presentation = model.presentedAnime {
                    AnimeProfileView(model: model, presentation: presentation, navigationClearance: navigationClearance)
                        .id(presentation.id)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(showPage)
        }
        .animation(reduceMotion || lightweight || inPlayer ? nil : YoruMotion.pageChange, value: model.tab)
        .animation(reduceMotion || lightweight ? nil : YoruMotion.pageChange, value: model.presentedAnime?.id)
        .animation(reduceMotion || lightweight ? nil : YoruMotion.pageChange, value: model.watchlistOpen)
        .overlay(alignment: .top) {
            ZStack(alignment: .top) {
                if !inPlayer {
                    menuEdgeFade(height: navigationClearance + 38)
                }
                if showsNavigation {
                    header(compact: inlineNavigation)
                        .frame(height: headerHeight)
                        .padding(.top, headerOffset)
                        .transition(reduceMotion || lightweight ? .identity : .offset(y: -6).combined(with: .opacity))
                }
            }
            .animation(reduceMotion || lightweight ? nil : YoruMotion.reveal, value: showsNavigation)
        }
        .background {
            EventActivity { event in
                guard fullscreen, model.tab == .player, event.type == .mouseMoved,
                      let content = event.window?.contentView else { return }
                let point = content.convert(event.locationInWindow, from: nil)
                let distance = content.isFlipped ? point.y : content.bounds.maxY - point.y
                let visible = (0...(content.bounds.height * (fullscreenHeader ? 0.55 : 0.48))).contains(distance)
                if visible != fullscreenHeader {
                    withAnimation(reduceMotion || lightweight ? nil : .easeOut(duration: 0.16)) { fullscreenHeader = visible }
                }
            }.frame(width: 0, height: 0)
        }
        .background {
            switch model.tab {
            case .home:
                if theme.secondaryGlow != nil { ArtBackdrop() }
                else { theme.background }
            case .library: ArtBackdrop(url: libraryBackdrop)
            case .player: ink
            case .downloads: ArtBackdrop()
            }
        }
        .background {
            WindowAttachment { window in
                windowReference.window = window
                sizeFirstPlayback()
            }.frame(width: 0, height: 0)
        }
        .font(YoruTypography.text(15))
        .foregroundStyle(model.tab == .player ? Color.white : theme.primary)
        .environment(\.miniPlaybackClearance, showMini ? (model.quickDownloadStatus.isEmpty ? 61 : 106) : 0)
        .environment(\.yoruTheme, theme)
        .environment(\.yoruLabels, labels)
        .preferredColorScheme(model.tab == .player ? .dark : theme.colorScheme)
        .overlay {
            if dropTarget { RoundedRectangle(cornerRadius: 16).strokeBorder(mint, lineWidth: 3).padding(8).allowsHitTesting(false) }
        }
        .overlay(alignment: .bottomTrailing) {
            if showMini, let episode = model.current {
                MiniPlaybackView(model: model, episode: episode)
                    .environment(\.yoruTheme, theme)
                    .environment(\.yoruLabels, labels)
                    .padding(.trailing, 19)
                    .padding(.bottom, model.quickDownloadStatus.isEmpty ? 16 : 61)
                    .transition(.opacity.combined(with: .offset(y: 8)))
            }
        }
        .overlay(alignment: .bottom) {
            if !model.quickDownloadStatus.isEmpty {
                HStack(spacing: 9) {
                    ProgressView().controlSize(.small)
                    Text(labels(model.quickDownloadStatus)).font(YoruTypography.text(15, strong: true))
                }
                .padding(.horizontal, 18).padding(.vertical, 10)
                .foregroundStyle(theme.primary)
                .background(theme.navigationSurface, in: Capsule())
                .padding(.bottom, inPlayer ? 105 : 16)
                .allowsHitTesting(false)
            }
        }
    }

    private func updateBrowsingPlayback() {
        if model.tab == .player || browsePlayback != .pictureInPicture {
            if browsingPictureInPicture {
                browsingPictureInPicture = false
                model.player.stopPictureInPicture(restore: false)
            }
            return
        }
        guard !browsingPictureInPicture, !model.player.pictureInPictureActive,
              model.player.loaded, let episode = model.current else { return }
        browsingPictureInPicture = true
        model.player.startPictureInPicture(title: episode.title) { [weak model] in model?.tab = .player }
    }

    private func begin() {
        if let usage { applyMode(usage) }
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .leftMouseDown, .rightMouseDown], handler: handleEvent)
        }
        controllers.receive = { input in _ = navigate(input, in: NSApp.keyWindow) }
        controllers.start()
        sizeFirstPlayback()
        runSelfTest()
    }

    private func end() {
        cancelPlaybackHold()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
        controllers.stop()
        controllers.receive = nil
    }

    private func handleEvent(_ event: NSEvent) -> NSEvent? {
        if event.type == .keyUp {
            guard event.keyCode == 49, spacePress.isPressed else { return event }
            let held = spacePress.release()
            if !held, canHoldSpace(in: event.window) {
                model.player.toggle()
                NotificationCenter.default.post(name: .yoruPlaybackActivity, object: nil)
            }
            return nil
        }
        if event.type == .keyDown, event.keyCode == 49, spacePress.isPressed { return nil }
        if event.type != .keyDown {
            if let window = event.window { navigation.point(at: event.locationInWindow, in: window) }
            else { navigation.clear() }
            return event
        }
        return key(event) ? nil : event
    }

    private func canHoldSpace(in window: NSWindow?) -> Bool {
        guard let window else { return false }
        return window === windowReference.window && window.isKeyWindow && window.attachedSheet == nil
            && !(window.firstResponder is NSTextView) && !navigation.hasOverlay(in: window)
            && model.tab == .player && model.current != nil && model.player.loaded
            && !model.player.pictureInPictureActive && !model.settings && model.message.isEmpty
            && !model.playerDownloadsOpen && !model.watchlistOpen && model.presentedAnime == nil
    }

    private func cancelPlaybackHold() {
        spacePress.cancel()
        model.player.cancelSpeedBoost()
    }





    private func openDroppedFiles(_ providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        let urls = NSMutableArray()
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { DispatchQueue.main.async { urls.add(url); group.leave() } }
                else { group.leave() }
            }
        }
        group.notify(queue: .main) {
            let files = urls.compactMap { $0 as? URL }
            model.openFiles(files.sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            })
        }
        return !providers.isEmpty
    }

    private func sizeFirstPlayback() {
        guard fitPlaybackOnFirstOpen, !sizedForPlayback, !fullscreen, model.tab == .player,
              model.current != nil, let window = windowReference.window ?? NSApp.keyWindow, window.sheetParent == nil else { return }
        sizedForPlayback = fitPlaybackWindow(window)
    }

    private func menuEdgeFade(height: CGFloat) -> some View {
        Group {
            if lightweight || reduceTransparency { theme.background }
            else { Rectangle().fill(.regularMaterial) }
        }
        .frame(height: height)
        .mask(alignment: .top) {
            LinearGradient(stops: [
                .init(color: .black, location: 0),
                .init(color: .black.opacity(0.90), location: 0.30),
                .init(color: .black.opacity(0.54), location: 0.63),
                .init(color: .black.opacity(0.12), location: 0.87),
                .init(color: .clear, location: 1)
            ], startPoint: .top, endPoint: .bottom)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var menuGlass: some View {
        if #available(macOS 26, *), !lightweight, !reduceTransparency {
            Capsule().fill(.clear)
                .glassEffect(.clear, in: Capsule())
                .background(theme.background.opacity(0.14), in: Capsule())
        } else if !lightweight, !reduceTransparency {
            Capsule().fill(.thinMaterial)
                .overlay(Capsule().strokeBorder(theme.divider))
        } else {
            Capsule().fill(theme.navigationSurface)
                .overlay(Capsule().strokeBorder(theme.divider))
        }
    }

    private func header(compact: Bool) -> some View {
        let player = model.tab == .player
        let tint = player ? YoruTheme.nuit.accent : theme.accent
        let primary = player ? Color.white : theme.primary
        let secondary = player ? Color.white.opacity(0.62) : theme.primary.opacity(0.80)

        let tabs = usage?.tabs ?? []
        return ZStack {
            HStack {
                HStack(spacing: 7) {
                    Image(systemName: "moon.stars.fill").font(.system(size: compact ? 13 : 15, weight: .medium)).foregroundStyle(tint)
                    Text("Yoru").font(YoruTypography.display(compact ? 26 : 31, italic: true)).foregroundStyle(primary).offset(y: -1)
                }.accessibilityElement(children: .combine)
                Spacer()
                Button { model.settings = true } label: {
                    Image(systemName: "gearshape").font(.system(size: 15, weight: .medium))
                }.buttonStyle(ControlStyle(horizontalPadding: compact ? 11 : 15, compact: compact))
                    .accessibilityLabel("Réglages").help("Réglages")
            }
            HStack(spacing: 2) {
                ForEach(tabs, id: \.self) { tab in
                    let selected = model.tab == tab
                    let transfers = tab == .downloads ? model.activeTransfers.count : 0
                    Button {
                        model.presentedAnime = nil
                        model.watchlistOpen = false
                        if transfers > 0, model.tab != .downloads { model.selectDownloadPane(.transfers) }
                        model.tab = tab
                    } label: {
                        HStack(spacing: 6) {
                            Label(labels(tab.rawValue), systemImage: tab == .home ? "house" : tab == .library ? "square.grid.2x2" : tab == .player ? "play.rectangle" : "arrow.down.to.line")
                            if transfers > 0 {
                                Text(transfers.formatted()).monospacedDigit()
                                    .font(YoruTypography.text(12, strong: true)).foregroundStyle(tint)
                            }
                        }
                            .font(YoruTypography.text(compact ? 14 : 15, strong: true))
                            .foregroundStyle(selected ? primary : secondary)
                            .padding(.horizontal, compact ? 8 : 13)
                            .frame(height: compact ? 32 : 40)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(DirectionalPlainStyle(radius: 100, priority: selected ? 1 : 0))
                    .accessibilityLabel(transfers > 0 ? "\(labels(tab.rawValue)), \(transfers) en cours" : labels(tab.rawValue))
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
                    guard let index = tabs.firstIndex(of: model.tab), tabs.indices.contains(index + direction) else { return }
                    model.tab = tabs[index + direction]
                }
            }
        }
        .padding(.horizontal, compact ? 12 : 16).padding(.vertical, compact ? 3 : 5)
        .background {
            if player {
                Capsule().fill(.clear)
                    .modifier(VideoGlass(radius: 27))
            } else {
                menuGlass
            }
        }
        .padding(.horizontal, 13).padding(.vertical, compact ? 3 : 5)
        .padding(.leading, compact ? 72 : 0)
    }

    private func navigate(_ input: NavigationInput, in window: NSWindow?) -> Bool {
        guard let window else { return false }
        if !model.message.isEmpty {
            switch input {
            case .activate, .back: model.message = ""; return true
            case .move, .playPause: return false
            }
        }
        let main = window === windowReference.window
        if case .back = input {
            if let editor = window.firstResponder as? NSTextView, editor.isFieldEditor {
                return window.makeFirstResponder(nil)
            }
            if navigation.closeOverlay(in: window) { return true }
            if model.settings { model.settings = false; return true }
            if !main { return NSApp.sendAction(Selector(("cancelOperation:")), to: nil, from: nil) }
            if model.presentedAnime != nil { model.presentedAnime = nil; navigation.clear(); return true }
            if model.watchlistOpen { model.watchlistOpen = false; navigation.clear(); return true }
            if model.tab == .player, model.playerDownloadsOpen {
                if model.inspected != nil, !model.addingTorrent { model.inspected = nil }
                else { model.closePlayerDownloads() }
                return true
            }
            if model.tab == .library, !model.episodeSelection.isEmpty {
                model.clearEpisodeSelection()
                return true
            }
            if navigation.hasFocus { navigation.clear(); return true }
            return false
        }
        if case .playPause = input {
            guard main, model.current != nil else { return false }
            model.player.toggle()
            NotificationCenter.default.post(name: .yoruPlaybackActivity, object: nil)
            return true
        }
        if let editor = window.firstResponder as? NSTextView {
            guard editor.isFieldEditor, case .move(let direction) = input, direction.vertical,
                  window.makeFirstResponder(nil) else { return false }
        }
        let player = main && model.tab == .player && model.current != nil
        if player {
            let hidden = !playbackControls
            if fullscreen { fullscreenHeader = true }
            NotificationCenter.default.post(name: .yoruPlaybackActivity, object: nil)
            if hidden {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    guard window.isKeyWindow, model.tab == .player else { return }
                    if case .move(let direction) = input { navigation.move(direction, in: window) }
                    if case .activate = input { navigation.activate(in: window) }
                }
                return true
            }
        }
        switch input {
        case .move(let direction): return navigation.move(direction, in: window)
        case .activate:
            if navigation.activate(in: window) { return true }
            if !main, let button = window.defaultButtonCell?.controlView as? NSButton, button.isEnabled {
                button.performClick(nil)
                return true
            }
            return false
        case .back, .playPause: return false
        }
    }

    private func key(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags
        guard flags.intersection([.command, .control]).isEmpty,
              let window = event.window, window.isKeyWindow else { return false }
        let main = window === windowReference.window
        let code = event.keyCode
        if code == 53 {
            return navigate(.back, in: window)
        }
        guard model.message.isEmpty else { return false }
        if let direction = NavigationDirection(keyCode: code) {
            if window.firstResponder is NSTextView,
               (!direction.vertical || !flags.intersection([.option, .shift]).isEmpty) { return false }
            let playingVideo = main && model.tab == .player && model.current != nil
            let videoShortcut = flags.contains(.option) || (flags.isDisjoint(with: [.shift])
                && playbackArrows.controlsVideo(paused: model.player.paused))
            if playingVideo, videoShortcut, !navigation.hasOverlay(in: window), !model.playerDownloadsOpen {
                navigation.clear()
                switch direction {
                case .left: model.player.seek(model.player.position - 5)
                case .right: model.player.seek(model.player.position + 5)
                case .down: model.player.setVolume(model.player.volume - 5)
                case .up: model.player.setVolume(model.player.volume + 5)
                }
                NotificationCenter.default.post(name: .yoruPlaybackActivity, object: nil)
                return true
            }
            if flags.contains(.option) { return false }
            if main, flags.contains(.shift), model.tab == .library, !direction.vertical {
                let episodes = model.seasonEpisodes
                guard !episodes.isEmpty else { return false }
                let index = episodes.firstIndex { $0.id == model.libraryEpisodeFocus } ?? 0
                let next = max(0, min(episodes.count - 1, index + Int(direction.sign)))
                model.selectEpisodeRange(through: episodes[next])
                return true
            }
            return navigate(.move(direction), in: window)
        }
        guard !(window.firstResponder is NSTextView) else { return false }
        if code == 36 || code == 76 { return navigate(.activate, in: window) }
        guard main, !model.settings, !flags.contains(.option) else { return false }
        guard model.tab == .player, model.current != nil else { return false }
        NotificationCenter.default.post(name: .yoruPlaybackActivity, object: nil)
        switch event.keyCode {
        case 49:
            guard canHoldSpace(in: window), !event.isARepeat else { return false }
            spacePress.begin {
                if canHoldSpace(in: window) { model.player.beginSpeedBoost(.keyboard) }
                else { spacePress.cancel() }
            } released: {
                model.player.endSpeedBoost(.keyboard)
            }
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
            if arguments.contains("--test-services") {
                do {
                    let entries = try await Catalog.lookup("Frieren")
                    let items = try await TorrentSearch.search("Judas", groups: "Judas", minimumSeeds: 1, packs: false, episode: nil, season: nil)
                    guard let item = items.first, !entries.isEmpty else { exit(2) }
                    let view = try await TorrentSearch.preview(item)
                    print("SERVICES anilist=\(entries.count) nyaa=\(items.count) verified=\(view.files.count)")
                } catch { print("SERVICES \(error)"); exit(2) }
            }
            NSApp.activate(ignoringOtherApps: true)
            if arguments.contains("--test-ending") {
                for _ in 0..<16 where !model.libraryReady { try? await Task.sleep(nanoseconds: 100_000_000) }
            }
            model.openURLs([url])
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            let loaded = model.player.loaded && model.player.duration > 0 && model.player.position > 0 && model.player.surface.renderedFrames > 0 && model.player.error.isEmpty
            print("PLAYBACK loaded=\(model.player.loaded) duration=\(model.player.duration) position=\(model.player.position) tracks=\(model.player.tracks.count) skips=\(model.player.skips.count) frames=\(model.player.surface.renderedFrames) error=\(model.player.error)")
            if loaded, arguments.contains("--test-player-chrome"),
               let window = windowReference.window ?? NSApp.keyWindow {
                let ratio = window.frame.width / window.frame.height
                for _ in 0..<26 where playbackControls { try? await Task.sleep(nanoseconds: 150_000_000) }
                let hidden = !playbackControls
                NotificationCenter.default.post(name: .yoruPlaybackActivity, object: nil)
                try? await Task.sleep(nanoseconds: 150_000_000)
                print("CHROME ratio=\(ratio) idle-hidden=\(hidden) revealed=\(playbackControls)")
                exit(abs(ratio - 16.0 / 9.0) < 0.01 && hidden && playbackControls ? 0 : 16)
            }
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
                    move(content.bounds.height * 0.43)
                    try? await Task.sleep(nanoseconds: 320_000_000)
                    let headerShown = fullscreenHeader
                    move(content.bounds.height * 0.75)
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
    @Environment(\.miniPlaybackClearance) private var miniPlaybackClearance
    @ObservedObject var model: Model
    @Binding var backdrop: URL?
    let navigationClearance: CGFloat
    @Environment(\.yoruTheme) private var theme
    @Environment(\.yoruLabels) private var labels
    @State private var editShow: Series?
    @State private var planSheet = false
    @State private var plannedTitle = ""
    @State private var seasonCover: URL?
    @State private var episodeFrames: [String: CGRect] = [:]
    @State private var episodeSweep: EpisodeSweep?
    @State private var suppressClickUntil = 0.0
    @State private var pendingTrash: [Episode] = []
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
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 7) {
                    Text(labels("Bibliothèque")).font(YoruTypography.display(27))
                        .accessibilityAddTraits(.isHeader).lineLimit(1).minimumScaleFactor(0.88)
                    Spacer()
                    Button { plannedTitle = ""; planSheet = true } label: { Image(systemName: "plus") }
                        .buttonStyle(ControlStyle(horizontalPadding: 11)).accessibilityLabel("Ajouter une série à regarder")
                    Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(ControlStyle(horizontalPadding: 11)).accessibilityLabel("Actualiser")
                }
                SearchField(title: "Rechercher", value: $model.filter, icon: "magnifyingglass")
                    .onChange(of: model.filter) { _ in if model.selectedSeries == nil { model.select(model.displayed.first?.id) } }
                HStack(spacing: 6) {
                    ForEach(Model.LibraryFilter.allCases) { filter in
                        Button { model.selectLibraryFilter(filter) } label: {
                            Text(labels(filter.rawValue)).lineLimit(1).frame(maxWidth: .infinity)
                        }
                            .buttonStyle(ControlStyle(selected: model.libraryFilter == filter, horizontalPadding: 5))
                            .accessibilityAddTraits(model.libraryFilter == filter ? .isSelected : [])
                    }
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(model.displayed) { item in
                                Button { model.select(item.id) } label: {
                                    HStack(spacing: 12) {
                                        AnimeCover(title: item.query, id: model.state.shows[item.id]?.aniListID, preview: item.episodes.first, width: 46, height: 62)
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(item.title).font(YoruTypography.text(17, strong: true)).lineLimit(2)
                                            let total = item.episodes.count
                                            let watched = item.episodes.filter { model.progress($0).watched }.count
                                            Text(labels(total == 0 ? "À voir" : total == 1 && item.episodes.first?.number == nil ? "Vidéo" : "\(watched) / \(total) vus"))
                                                .font(YoruTypography.text(14)).foregroundStyle(theme.mutedText)
                                        }
                                        Spacer(minLength: 4)
                                        if let score = model.score(item) { Text(score.formatted()).font(YoruTypography.text(14, strong: true)).foregroundStyle(theme.accent) }
                                    }
                                    .padding(.horizontal, 10).padding(.vertical, 9)
                                    .background(model.selected == item.id ? theme.tint : Color.clear, in: RoundedRectangle(cornerRadius: 16))
                                    .overlay(alignment: .leading) {
                                        if model.selected == item.id { Capsule().fill(theme.accent).frame(width: 2, height: 21).allowsHitTesting(false) }
                                    }
                                    .contentShape(Rectangle())
                                }.buttonStyle(DirectionalPlainStyle(radius: 16, priority: model.selected == item.id ? 2 : 0)).id(item.id)
                                    .accessibilityAddTraits(model.selected == item.id ? .isSelected : [])
                                    .animation(motion, value: model.selected)
                            }
                            if model.displayed.isEmpty {
                                Text(labels(model.filter.trimmed.isEmpty ? "Aucune série ici" : "Aucun résultat"))
                                    .font(YoruTypography.text(15)).foregroundStyle(theme.mutedText)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 9)
                            }
                        }.padding(4)
                    }
                    .onChange(of: model.selected) { id in if let id { proxy.scrollTo(id) } }
                }
                Label((model.folder.path as NSString).abbreviatingWithTildeInPath, systemImage: "folder")
                    .font(YoruTypography.text(13)).foregroundStyle(theme.mutedText).lineLimit(1)
            }
            .padding(17).frame(width: min(374, max(288, geometry.size.width * 0.29)))
            .modifier(Glass(radius: 27, tint: theme.card.opacity(0.3), fallback: theme.card))
            .padding(.leading, 13).padding(.vertical, 7)
            .padding(.top, navigationClearance)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 19) {
                        if let show = model.selectedSeries {
                            title(show)
                            metadata(show)
                            if model.allowsDownloads, let offer = model.suggestedSeason, offer.showID == show.id,
                               model.librarySeason == nil || model.librarySeason == offer.current {
                                SeasonOfferCard(offer: offer, model: model)
                            }
                            HStack(spacing: 12) {
                                seasons(show)
                                Spacer(minLength: 0)
                                if !model.seasonEpisodes.isEmpty {
                                    Button {
                                        let selected = model.seasonEpisodes.filter { model.episodeSelection.contains($0.id) }
                                        let focused = model.seasonEpisodes.first { $0.id == model.libraryEpisodeFocus }
                                        if !selected.isEmpty { pendingTrash = selected }
                                        else if let episode = focused ?? model.seasonEpisodes.first { pendingTrash = [episode] }
                                    } label: {
                                        Label(labels("Corbeille"), systemImage: "trash")
                                    }.buttonStyle(ControlStyle())
                                }
                            }
                            episodeCards
                        } else {
                            VStack(alignment: .leading, spacing: 13) {
                                SectionHeading(title: "Ta bibliothèque")
                                if model.series.isEmpty {
                                    Text(labels("Choisis un dossier ou glisse une vidéo dans la fenêtre.")).foregroundStyle(theme.mutedText)
                                    Button(labels("Choisir un dossier…")) { model.chooseFolder() }.buttonStyle(ControlStyle(accent: true))
                                }
                            }.padding(.vertical, 45)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(geometry.size.width > 1250 ? 34 : 23)
                        .padding(.top, navigationClearance)
                        .padding(.bottom, miniPlaybackClearance + (model.episodeSelection.isEmpty && model.watchUndoCount == 0 ? 0 : 100))
                }.onChange(of: model.libraryEpisodeFocus) { id in if let id { proxy.scrollTo(id) } }
                    .overlay(alignment: .bottom) { selectionBar.padding(.bottom, miniPlaybackClearance) }
                    .animation(motion, value: !model.episodeSelection.isEmpty || model.watchUndoCount > 0)
            }
        }
        }
        .task(id: (model.selected ?? "") + "|" + String(model.librarySeason ?? 0) + "|" + String(model.selected.flatMap { model.state.shows[$0]?.aniListID } ?? 0)) {
            backdrop = nil
            seasonCover = nil
            guard let show = model.selectedSeries else { return }
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
        .alert(labels("Mettre à la corbeille ?"), isPresented: Binding(
            get: { !pendingTrash.isEmpty }, set: { if !$0 { pendingTrash = [] } }
        ), presenting: pendingTrash) { episodes in
            Button(labels("Mettre à la corbeille"), role: .destructive) { model.trashEpisodes(episodes) }
            Button(labels("Annuler"), role: .cancel) {}
        } message: { episodes in
            Text(episodes.count == 1 ? episodes[0].url.lastPathComponent : "\(episodes.count) vidéos")
        }
        .onDisappear { model.clearEpisodeSelection() }
        .sheet(isPresented: $planSheet) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Ajouter à regarder").font(.title2.bold())
                DirectionalTextField(title: "Titre de la série", text: $plannedTitle).textFieldStyle(.roundedBorder)
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
                Button(labels("Marquer vus")) { model.markEpisodeSelection(watched: true) }
                    .buttonStyle(ControlStyle(accent: true))
                Button(labels("Marquer non vus")) { model.markEpisodeSelection(watched: false) }
                    .buttonStyle(ControlStyle())
                Button { model.clearEpisodeSelection() } label: { Image(systemName: "xmark") }
                    .buttonStyle(ControlStyle()).accessibilityLabel("Quitter la sélection")
            } else {
                Button(labels("Annuler")) { model.undoEpisodeWatchChange() }.buttonStyle(ControlStyle())
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
                        Button(labels("Tous")) { model.selectSeason(nil) }.buttonStyle(ControlStyle(selected: model.librarySeason == nil))
                        ForEach(seasons, id: \.self) { number in
                            Button(labels("Saison \(number)")) { model.selectSeason(number) }
                                .buttonStyle(ControlStyle(selected: model.librarySeason == number))
                        }
                    } else { Text(labels(show.episodes.count == 1 ? "Vidéo" : "Épisodes")).font(.title2.bold()) }
                }.padding(.vertical, 2)
            }.scrollIndicators(.hidden)
        }
    }

    private func libraryPrimaryActions(_ show: Series, resume: Episode?, episodes: [Episode]) -> some View {
        HStack(spacing: 6) {
            if let first = resume ?? episodes.first(where: { !model.progress($0).watched }) ?? episodes.first {
                Button { model.play(first) } label: {
                    Label(labels(resume == nil ? "Regarder" : "Reprendre"), systemImage: "play.fill")
                }.buttonStyle(ControlStyle(accent: true))
                    .help(resume.map { $0.display + " · " + formatTime(model.progress($0).seconds) } ?? first.display)
            }
            if model.allowsDownloads {
                Button { model.downloadLibrarySeason(show) } label: {
                    DownloadLabel(title: labels("Télécharger"))
                }.buttonStyle(ControlStyle()).disabled(model.addingTorrent)
                    .contextMenu { Button(labels("Choisir une version")) { model.findDownloads(show) } }
            }
        }
    }

    private func librarySecondaryActions(_ show: Series) -> some View {
        HStack(spacing: 6) {
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
    }

    func title(_ show: Series) -> some View {
        let episodes = model.seasonEpisodes
        let watched = episodes.filter { model.progress($0).watched }.count
        let resume = model.resumeEpisode(in: episodes)
        return HStack(alignment: .center, spacing: 17) {
            AnimeCover(title: show.query, id: model.state.shows[show.id]?.aniListID, url: seasonCover,
                       preview: episodes.first, width: 83, height: 122)
            VStack(alignment: .leading, spacing: 10) {
                Text(show.title)
                    .font(YoruTypography.display(48))
                    .textSelection(.enabled).lineLimit(3).minimumScaleFactor(0.75)
                    .accessibilityAddTraits(.isHeader)
                    .help(show.title)
                if !episodes.isEmpty, episodes.contains(where: { $0.number != nil }) {
                    HStack(spacing: 8) {
                        if let season = model.librarySeason { Text("Saison \(season)") }
                        Text("\(watched) / \(episodes.count) vus")
                            .monospacedDigit()
                    }.font(YoruTypography.text(14)).foregroundStyle(.white.opacity(0.75))
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        libraryPrimaryActions(show, resume: resume, episodes: episodes)
                        librarySecondaryActions(show)
                    }.fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 7) {
                        libraryPrimaryActions(show, resume: resume, episodes: episodes)
                        librarySecondaryActions(show)
                    }
                }
                if let link = model.state.shows[show.id]?.nautiljonURL, let url = URL(string: link), url.scheme == "https" {
                    Link("Nautiljon", destination: url).font(.caption).foregroundStyle(YoruTheme.nuit.accent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
                    }.buttonStyle(DirectionalPlainStyle()).foregroundStyle(theme.mutedText).font(.callout)
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
                .buttonStyle(DirectionalPlainStyle()).foregroundStyle(theme.accent).disabled(model.metadataBusy)
        }
        if !model.matches.isEmpty {
            DirectionalMenu {
                Text(labels("Associer à une fiche AniList"))
            } actions: { close in
                ForEach(model.matches) { result in
                    Button(result.name) { close(); model.assign(result, to: show) }
                        .buttonStyle(ControlStyle())
                }
            }
        }
    }

    func row(_ episode: Episode) -> some View {
        let status = model.progress(episode)
        let focused = model.libraryEpisodeFocus == episode.id
        let selected = model.episodeSelection.contains(episode.id)
        let title = episode.number.map {
            labels(model.librarySeason != nil ? "Épisode \($0)" : episode.display)
        } ?? episode.title
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
                        Label(labels("Vu"), systemImage: "checkmark")
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
            .buttonStyle(DirectionalPlainStyle(onFocus: { model.libraryEpisodeFocus = episode.id }))
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
                Button(labels("Mettre à la corbeille"), role: .destructive) { pendingTrash = [episode] }
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
            DirectionalTextField(title: "Titre affiché", text: $title)
            DirectionalTextField(title: "Nom pour la recherche", text: $query)
            DirectionalTextField(title: "Note sur 10", text: $rating)
            DirectionalTextField(title: "Lien Nautiljon", text: $link)
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
