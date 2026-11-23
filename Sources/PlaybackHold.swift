import AppKit
import SwiftUI

enum SpeedBoostInput: Hashable {
    case keyboard, pointer
}

final class PlaybackPress {
    private var timer: Timer?
    private var activated = false
    private var finish: (() -> Void)?
    private(set) var isPressed = false

    func begin(held: @escaping () -> Void, released: @escaping () -> Void) {
        guard !isPressed else { return }
        isPressed = true
        activated = false
        finish = released
        let timer = Timer(timeInterval: 0.35, repeats: false) { [weak self] _ in
            guard let self, isPressed else { return }
            activated = true
            held()
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    @discardableResult func release() -> Bool {
        let wasHeld = activated
        cancel()
        return wasHeld
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        let finished = activated ? finish : nil
        isPressed = false
        activated = false
        finish = nil
        finished?()
    }

    deinit { timer?.invalidate() }
}

struct PlaybackSurfaceInput: NSViewRepresentable {
    let player: Player
    let mediaID: String
    let enabled: Bool
    let click: () -> Void
    let doubleClick: () -> Void

    final class Surface: NSView {
        weak var player: Player?
        var click: (() -> Void)?
        var doubleClick: (() -> Void)?
        var mediaID = "" {
            didSet { if mediaID != oldValue { cancel() } }
        }
        var enabled = true {
            didSet { if !enabled { press.cancel() } }
        }
        private let press = PlaybackPress()
        private var origin = NSPoint.zero
        private var dragged = false
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            cancel()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            guard let window else { return }
            observers.append(NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: window, queue: .main
            ) { [weak self] _ in self?.cancel() })
            observers.append(NotificationCenter.default.addObserver(
                forName: NSApplication.willResignActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in self?.cancel() })
        }

        override func mouseDown(with event: NSEvent) {
            guard enabled else { return }
            origin = event.locationInWindow
            dragged = false
            press.begin { [weak self] in
                guard let self, enabled, window?.isKeyWindow == true else { return }
                player?.beginSpeedBoost(.pointer)
            } released: { [weak self] in
                self?.player?.endSpeedBoost(.pointer)
            }
        }

        override func mouseDragged(with event: NSEvent) {
            if hypot(event.locationInWindow.x - origin.x, event.locationInWindow.y - origin.y) > 20 {
                dragged = true
                press.cancel()
            }
        }

        override func mouseUp(with event: NSEvent) {
            guard press.isPressed else { return }
            let held = press.release()
            guard enabled, !held, !dragged else { return }
            if event.clickCount == 2 { doubleClick?() }
            else { click?() }
        }

        private func cancel() {
            press.cancel()
            player?.endSpeedBoost(.pointer)
        }

        deinit {
            press.cancel()
            observers.forEach(NotificationCenter.default.removeObserver)
        }
    }

    func makeNSView(context: Context) -> Surface { Surface() }

    func updateNSView(_ view: Surface, context: Context) {
        view.player = player
        view.mediaID = mediaID
        view.enabled = enabled
        view.click = click
        view.doubleClick = doubleClick
    }

    static func dismantleNSView(_ view: Surface, coordinator: ()) {
        view.enabled = false
        view.player?.endSpeedBoost(.pointer)
    }
}
