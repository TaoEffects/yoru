import AppKit
import Combine
import Darwin

final class VideoHostView: NSView {
    var didAttachToWindow: ((NSWindow) -> Void)?
    private weak var surface: VideoSurface?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { didAttachToWindow?(window) }
    }

    func show(_ surface: VideoSurface) {
        self.surface = surface
        if surface.superview !== self {
            surface.removeFromSuperview()
            surface.frame = bounds
            surface.autoresizingMask = [.width, .height]
            addSubview(surface)
        }
        surface.layer?.setNeedsDisplay()
    }

    override func layout() {
        super.layout()
        guard let surface, surface.superview === self, surface.frame != bounds else { return }
        surface.frame = bounds
    }
}

@MainActor final class PictureInPicture: NSObject, NSWindowDelegate {
    private weak var player: Player?
    private weak var inlineHost: VideoHostView?
    private weak var inlineWindow: NSWindow?
    private var native: SystemPictureInPicture?
    private var floating: FloatingPictureInPicture?
    private var floatingFrame: NSRect?
    private var restorePlaybackTab: (() -> Void)?
    private var playbackObservation: AnyCancellable?
    private var transitionCheck: Task<Void, Never>?
    private var closing = false

    init(player: Player) {
        self.player = player
    }

    func attachInlineHost(_ host: VideoHostView) {
        guard let player else { return }
        if inlineHost !== host {
            inlineHost = host
            host.didAttachToWindow = { [weak self, weak host] window in
                guard self?.inlineHost === host else { return }
                self?.inlineWindow = window
            }
        }
        if let window = host.window { inlineWindow = window }
        if !player.pictureInPictureActive, player.surface.superview !== host { host.show(player.surface) }
    }

    func detachInlineHost(_ host: VideoHostView) {
        guard inlineHost === host else { return }
        inlineHost = nil
        host.didAttachToWindow = nil
        if player?.surface.superview === host { player?.surface.removeFromSuperview() }
    }

    func start(title: String, restore: @escaping () -> Void) {
        guard let player, player.loaded, !player.pictureInPictureActive else { return }
        restorePlaybackTab = restore
        player.setPictureInPictureActive(true)
        player.subtitleClearance(0, animated: false)
        playbackObservation = player.$paused.removeDuplicates().sink { [weak self] paused in
            self?.native?.setPlaying(!paused)
            self?.floating?.setPlaying(!paused)
        }

        let aspectRatio = player.displayAspectRatio
        if let native = SystemPictureInPicture(delegate: self, title: title, aspectRatio: aspectRatio) {
            self.native = native
            native.host.show(player.surface)
            native.setPlaying(!player.paused)
            checkTransition(after: 1_100_000_000) { [weak self, weak native] in
                guard let self, let native, self.native === native, native.host.window == nil else { return }
                native.clearDelegate()
                native.dismiss()
                self.native = nil
                self.showFloatingWindow(title: title, aspectRatio: aspectRatio)
            }
            native.present()
        } else {
            showFloatingWindow(title: title, aspectRatio: aspectRatio)
        }
    }

    func stop(restore: Bool) {
        guard beginClosing(restore: restore) else { return }
        if let native {
            checkTransition(after: 950_000_000) { [weak self] in self?.finishClosing() }
            native.dismiss()
        } else {
            finishClosing()
        }
    }

    private func beginClosing(restore: Bool) -> Bool {
        guard player?.pictureInPictureActive == true, !closing else { return false }
        closing = true
        transitionCheck?.cancel()
        if restore {
            restorePlaybackTab?()
            if let inlineWindow {
                if inlineWindow.isMiniaturized { inlineWindow.deminiaturize(nil) }
                inlineWindow.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        if let host = inlineHost, let window = host.window {
            native?.replace(with: host, in: window)
        }
        return true
    }

    private func finishClosing() {
        guard let player, player.pictureInPictureActive else { return }
        transitionCheck?.cancel()
        transitionCheck = nil
        playbackObservation?.cancel()
        playbackObservation = nil
        native?.clearDelegate()
        if let floating {
            floatingFrame = floating.frame
            floating.delegate = nil
            floating.close()
        }
        if let inlineHost { inlineHost.show(player.surface) }
        else { player.surface.removeFromSuperview() }
        native = nil
        floating = nil
        restorePlaybackTab = nil
        closing = false
        player.setPictureInPictureActive(false)
        NotificationCenter.default.post(name: .yoruPlaybackActivity, object: nil)
    }

    private func checkTransition(after delay: UInt64, _ check: @escaping () -> Void) {
        transitionCheck?.cancel()
        transitionCheck = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delay)
            if !Task.isCancelled { check() }
        }
    }

    private func showFloatingWindow(title: String, aspectRatio: CGSize) {
        guard let player else { return }
        let window = FloatingPictureInPicture(title: title, aspectRatio: aspectRatio,
                                               screen: inlineWindow?.screen ?? NSScreen.main,
                                               previousFrame: floatingFrame)
        window.delegate = self
        window.onToggle = { [weak player] in player?.toggle() }
        window.onRestore = { [weak self] in self?.stop(restore: true) }
        window.onClose = { [weak self, weak player] in
            player?.set("pause", "yes")
            self?.stop(restore: false)
        }
        window.setPlaying(!player.paused)
        floating = window
        window.host.show(player.surface)
        window.orderFrontRegardless()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === floating else { return true }
        floating?.onClose?()
        return false
    }

    @objc private func pipWillClose(_ controller: NSViewController) {
        guard native?.controller === controller, beginClosing(restore: true) else { return }
        checkTransition(after: 950_000_000) { [weak self] in self?.finishClosing() }
    }

    @objc private func pipDidClose(_ controller: NSViewController) {
        guard native?.controller === controller else { return }
        _ = beginClosing(restore: true)
        finishClosing()
    }

    @objc private func pipActionPlay(_ controller: NSViewController) {
        guard native?.controller === controller, player?.paused == true else { return }
        player?.set("pause", "no")
    }

    @objc private func pipActionPause(_ controller: NSViewController) {
        guard native?.controller === controller else { return }
        player?.set("pause", "yes")
    }

    @objc private func pipActionStop(_ controller: NSViewController) {
        guard native?.controller === controller, !closing else { return }
        player?.set("pause", "yes")
    }

    @objc(pipAction:skipInterval:) private func pipAction(_ controller: NSViewController, skipInterval: TimeInterval) {
        guard native?.controller === controller, let player else { return }
        player.seek(player.position + skipInterval)
    }
}

// AVKit on macOS only presents AVPlayer-backed video. Load the system host at runtime
// to make macOS PiP available for the frames and subtitles already rendered by mpv.
@MainActor private final class SystemPictureInPicture {
    private static let library = dlopen("/System/Library/PrivateFrameworks/PIP.framework/Versions/A/PIP", RTLD_LAZY | RTLD_LOCAL)
    private static let presentation = NSSelectorFromString("presentViewControllerAsPictureInPicture:")
    private static let delegate = NSSelectorFromString("setDelegate:")
    private static let playing = NSSelectorFromString("setPlaying:")
    private static let aspect = NSSelectorFromString("setAspectRatio:")
    let controller: NSViewController
    let host: VideoHostView
    private let content = NSViewController()

    init?(delegate: NSObject, title: String, aspectRatio: CGSize) {
        guard Self.library != nil, let controllerType = NSClassFromString("PIPViewController") as? NSObject.Type,
              let controller = controllerType.init() as? NSViewController,
              controller.responds(to: Self.presentation), controller.responds(to: Self.delegate),
              controller.responds(to: Self.playing), controller.responds(to: Self.aspect) else { return nil }
        self.controller = controller
        let frame = NSRect(origin: .zero, size: CGSize(width: 480, height: 480 * aspectRatio.height / aspectRatio.width))
        host = VideoHostView(frame: frame)
        content.view = Self.container(for: host)
        content.title = title
        controller.title = title
        controller.perform(Self.delegate, with: delegate)
        typealias SetAspect = @convention(c) (AnyObject, Selector, CGSize) -> Void
        unsafeBitCast(controller.method(for: Self.aspect), to: SetAspect.self)(controller, Self.aspect, aspectRatio)
    }

    private static func container(for host: VideoHostView) -> NSView {
        let container = NSView(frame: host.frame)
        container.autoresizingMask = [.width, .height]
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        host.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            host.topAnchor.constraint(equalTo: container.topAnchor),
            host.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    func present() { controller.perform(Self.presentation, with: content) }
    func dismiss() {
        if host.window != nil || controller.presentedViewControllers?.contains(where: { $0 === content }) == true {
            controller.dismiss(content)
        }
    }
    func clearDelegate() { controller.perform(Self.delegate, with: nil) }

    func setPlaying(_ playing: Bool) {
        typealias SetPlaying = @convention(c) (AnyObject, Selector, Bool) -> Void
        unsafeBitCast(controller.method(for: Self.playing), to: SetPlaying.self)(controller, Self.playing, playing)
    }

    func replace(with host: NSView, in window: NSWindow) {
        let setView = NSSelectorFromString("setReplacementView:")
        if controller.responds(to: setView) {
            controller.perform(setView, with: host)
        } else {
            let setWindow = NSSelectorFromString("setReplacementWindow:")
            let setRect = NSSelectorFromString("setReplacementRect:")
            guard controller.responds(to: setWindow), controller.responds(to: setRect) else { return }
            controller.perform(setWindow, with: window)
            typealias SetRect = @convention(c) (AnyObject, Selector, CGRect) -> Void
            let rect = host.convert(host.bounds, to: nil)
            unsafeBitCast(controller.method(for: setRect), to: SetRect.self)(controller, setRect, rect)
        }
    }
}

@MainActor private final class FloatingPictureInPicture: NSPanel {
    let host: VideoHostView
    var onToggle: (() -> Void)?
    var onRestore: (() -> Void)?
    var onClose: (() -> Void)?
    private let playButton = NSButton()

    init(title: String, aspectRatio: CGSize, screen: NSScreen?, previousFrame: NSRect?) {
        let width: CGFloat = 420
        let height = width * aspectRatio.height / aspectRatio.width
        let usable = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let initial = NSRect(x: usable.maxX - width - 20, y: usable.minY + 20, width: width, height: height)
        let frame = previousFrame.flatMap { usable.contains($0) ? $0 : nil } ?? initial
        host = VideoHostView(frame: NSRect(origin: .zero, size: frame.size))
        super.init(contentRect: frame, styleMask: [.borderless, .resizable, .nonactivatingPanel],
                   backing: .buffered, defer: false)

        self.title = title
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isFloatingPanel = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        minSize = NSSize(width: 225, height: 95)
        contentAspectRatio = aspectRatio

        let container = NSView(frame: host.frame)
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.masksToBounds = true
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)
        contentView = container

        let closeButton = NSButton()
        let restoreButton = NSButton()
        configure(closeButton, icon: "xmark", name: "Fermer la vidéo flottante", action: #selector(closePanel))
        configure(restoreButton, icon: "pip.exit", name: "Revenir au lecteur", action: #selector(restorePanel))
        configure(playButton, icon: "pause.fill", name: "Pause", action: #selector(togglePlayback))
        for button in [closeButton, playButton, restoreButton] { container.addSubview(button) }
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: container.topAnchor, constant: 9),
            closeButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 9),
            restoreButton.topAnchor.constraint(equalTo: container.topAnchor, constant: 9),
            restoreButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -9),
            playButton.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            playButton.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
    }

    func setPlaying(_ playing: Bool) {
        let name = playing ? "Pause" : "Reprendre"
        playButton.image = NSImage(systemSymbolName: playing ? "pause.fill" : "play.fill", accessibilityDescription: name)
        playButton.setAccessibilityLabel(name)
        playButton.toolTip = name
    }

    private func configure(_ button: NSButton, icon: String, name: String, action: Selector) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isBordered = false
        button.image = NSImage(systemSymbolName: icon, accessibilityDescription: name)
        button.imagePosition = .imageOnly
        button.contentTintColor = .white
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.68).cgColor
        button.layer?.cornerRadius = 17
        button.target = self
        button.action = action
        button.toolTip = name
        button.setAccessibilityLabel(name)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 34),
            button.heightAnchor.constraint(equalToConstant: 34)
        ])
    }

    @objc private func restorePanel() { onRestore?() }
    @objc private func togglePlayback() { onToggle?() }
    @objc private func closePanel() { onClose?() }
}
