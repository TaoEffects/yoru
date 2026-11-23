import AppKit
import GameController
import SwiftUI

enum NavigationDirection: Equatable {
    case left, right, up, down

    init?(keyCode: UInt16) {
        switch keyCode {
        case 123: self = .left
        case 124: self = .right
        case 125: self = .down
        case 126: self = .up
        default: return nil
        }
    }

    init?(x: Float, y: Float) {
        guard max(abs(x), abs(y)) > 0.55 else { return nil }
        if abs(x) > abs(y) { self = x > 0 ? .right : .left }
        else { self = y > 0 ? .up : .down }
    }

    var vertical: Bool { self == .up || self == .down }
    var sign: CGFloat { self == .up || self == .right ? 1 : -1 }

    struct Match: Comparable {
        let alignment: Int
        let distance: CGFloat

        static func < (lhs: Match, rhs: Match) -> Bool {
            if lhs.alignment != rhs.alignment { return lhs.alignment < rhs.alignment }
            return lhs.distance < rhs.distance
        }
    }

    func match(from origin: CGRect, to candidate: CGRect, enteringScroll: Bool = false) -> Match? {
        let forward = (vertical ? candidate.midY - origin.midY : candidate.midX - origin.midX) * sign
        let halfLengths = (vertical ? origin.height + candidate.height : origin.width + candidate.width) / 2
        let edgeGap = forward - halfLengths
        let shorterLength = vertical ? min(origin.height, candidate.height) : min(origin.width, candidate.width)
        guard forward > 5, edgeGap >= -shorterLength * 0.22 - 2 else { return nil }

        let sideways = abs(vertical ? candidate.midX - origin.midX : candidate.midY - origin.midY)
        let overlap = vertical ? min(origin.maxX, candidate.maxX) - max(origin.minX, candidate.minX)
            : min(origin.maxY, candidate.maxY) - max(origin.minY, candidate.minY)
        let narrower = vertical ? min(origin.width, candidate.width) : min(origin.height, candidate.height)
        let aligned = overlap >= narrower * 0.25
        let diagonal = sideways <= forward
        guard aligned || diagonal || enteringScroll else { return nil }
        return Match(alignment: aligned ? 0 : diagonal ? 1 : 2,
                     distance: max(0, edgeGap) + sideways * (aligned ? 0.35 : 1.4))
    }
}

enum NavigationInput {
    case move(NavigationDirection), activate, back, playPause
}

final class DirectionalNavigation {
    private let targets = NSHashTable<FocusAnchor>.weakObjects()
    private weak var focused: FocusAnchor?
    private weak var pointed: FocusAnchor?
    private var pendingScroll: DispatchWorkItem?
    private var pendingDirection: NavigationDirection?

    func register(_ target: FocusAnchor) { targets.add(target) }
    var hasFocus: Bool { focused?.window != nil }

    func hasOverlay(in window: NSWindow) -> Bool {
        available(in: window).contains { $0.navigationLayer > 0 && $0.isVisible }
    }

    private func available(in window: NSWindow) -> [FocusAnchor] {
        let options = targets.allObjects.filter { $0.window != nil && $0.enabled && !$0.isHiddenOrHasHiddenAncestor && !$0.bounds.isEmpty }
        let local = options.filter { $0.window === window }
        let layer = local.filter(\.isVisible).map(\.navigationLayer).max() ?? 0
        // An AppKit popover can have its own window while key events still arrive on its sheet.
        let overlay = options.filter {
            $0.window !== window && $0.window?.isVisible == true && $0.navigationLayer > layer
                && $0.back != nil && $0.isVisible
        }.max { $0.navigationLayer < $1.navigationLayer }
        if let overlay {
            return options.filter { $0.window === overlay.window && $0.navigationLayer == overlay.navigationLayer }
        }
        return local.filter { $0.navigationLayer == layer }
    }

    @discardableResult
    func move(_ direction: NavigationDirection, in window: NSWindow) -> Bool {
        if pendingDirection == direction { return true }
        cancelPendingScroll()
        let options = available(in: window)
        let previous = focused ?? pointed
        guard let current = previous, options.contains(current), current.isVisible else {
            let local = previous?.enclosingScrollView.map { scroll in options.filter { $0.enclosingScrollView === scroll } }
            guard let first = initialTarget(local ?? []) ?? initialTarget(options) else { return false }
            setFocus(first)
            return true
        }
        if current.adjust?(direction) == true { return true }

        let next = adjacent(to: current, in: options, direction: direction)
        if direction.vertical, let scroll = current.enclosingScrollView, next?.enclosingScrollView !== scroll,
           current.revealMore(in: direction) {
            setFocus(current, scroll: false)
            pendingDirection = direction
            let retry = DispatchWorkItem { [weak self, weak current, weak window] in
                guard let self else { return }
                self.pendingScroll = nil
                self.pendingDirection = nil
                guard let current, let window, self.focused === current else { return }
                let candidates = self.available(in: window).filter { $0.enclosingScrollView === scroll }
                if let next = self.adjacent(to: current, in: candidates, direction: direction) { self.setFocus(next) }
            }
            pendingScroll = retry
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: retry)
        } else if let next {
            setFocus(next)
        } else if focused == nil {
            setFocus(current)
        }
        return true
    }

    private func adjacent(to current: FocusAnchor, in options: [FocusAnchor], direction: NavigationDirection) -> FocusAnchor? {
        let origin = current.windowFrame
        let scroll = current.enclosingScrollView
        return options.compactMap { target -> (FocusAnchor, NavigationDirection.Match)? in
            let targetScroll = target.enclosingScrollView
            guard target !== current, target.isVisible || (direction.vertical && scroll != nil && targetScroll === scroll),
                  let match = direction.match(from: origin, to: target.windowFrame,
                                              enteringScroll: direction == .down && scroll == nil && targetScroll != nil) else { return nil }
            return (target, match)
        }.min { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            return lhs.0.priority > rhs.0.priority
        }?.0
    }

    @discardableResult
    func activate(in window: NSWindow) -> Bool {
        if pendingScroll != nil { return true }
        let options = available(in: window)
        if let current = focused, options.contains(current), current.isVisible {
            current.action?()
            return true
        }
        guard let initial = initialTarget(options) else { return false }
        setFocus(initial)
        return true
    }

    func clear() {
        cancelPendingScroll()
        pointed = nil
        setFocus(nil)
    }

    func point(at location: CGPoint, in window: NSWindow) {
        clear()
        pointed = available(in: window).filter { $0.window === window && $0.isVisible && $0.windowFrame.contains(location) }
            .min { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }
    }

    private func cancelPendingScroll() {
        pendingScroll?.cancel()
        pendingScroll = nil
        pendingDirection = nil
    }

    func closeOverlay(in window: NSWindow) -> Bool {
        let options = available(in: window)
        guard let close = options.first(where: { $0.isVisible && $0.back != nil })?.back else { return false }
        clear()
        close()
        return true
    }

    private func initialTarget(_ options: [FocusAnchor]) -> FocusAnchor? {
        let visible = options.filter(\.isVisible)
        guard let priority = visible.map(\.priority).max() else { return nil }
        let preferred = visible.filter { $0.priority == priority }
        guard let top = preferred.map({ $0.windowFrame.midY }).max() else { return nil }
        return preferred.filter { $0.windowFrame.midY >= top - 12 }.min { $0.windowFrame.minX < $1.windowFrame.minX }
    }

    private func setFocus(_ target: FocusAnchor?, scroll: Bool = true) {
        pointed = nil
        guard focused !== target else { return }
        focused?.highlight?(false)
        focused = target
        guard let target else { return }
        target.highlight?(true)
        if scroll { target.scrollToFocus() }
    }
}

private struct DirectionalNavigationKey: EnvironmentKey {
    static let defaultValue: DirectionalNavigation? = nil
}
private struct DirectionalLayerKey: EnvironmentKey {
    static let defaultValue = 0
}
private struct DirectionalBackKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    var directionalNavigation: DirectionalNavigation? {
        get { self[DirectionalNavigationKey.self] }
        set { self[DirectionalNavigationKey.self] = newValue }
    }
    var directionalLayer: Int {
        get { self[DirectionalLayerKey.self] }
        set { self[DirectionalLayerKey.self] = newValue }
    }
    var directionalBack: (() -> Void)? {
        get { self[DirectionalBackKey.self] }
        set { self[DirectionalBackKey.self] = newValue }
    }
}

final class FocusAnchor: NSView {
    weak var navigator: DirectionalNavigation?
    var action: (() -> Void)?
    var highlight: ((Bool) -> Void)?
    var adjust: ((NavigationDirection) -> Bool)?
    var back: (() -> Void)?
    var enabled = true
    var priority = 0
    var navigationLayer = 0

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { navigator?.register(self) }
    }

    var windowFrame: CGRect { convert(bounds, to: nil) }

    var isVisible: Bool {
        guard let content = window?.contentView else { return false }
        let intersection = convert(visibleRect, to: nil).intersection(content.convert(content.bounds, to: nil))
        return !intersection.isNull && intersection.width >= min(12, bounds.width) &&
            intersection.height >= min(12, bounds.height)
    }

    func scrollToFocus() {
        if let scroll = enclosingScrollView {
            let rect = convert(bounds, to: scroll.contentView)
            let inset = NSSize(width: 10, height: 13)
            if !scroll.contentView.bounds.insetBy(dx: inset.width, dy: inset.height).contains(rect) {
                scrollToVisible(bounds.insetBy(dx: -inset.width, dy: -inset.height))
            }
        }
    }

    func revealMore(in direction: NavigationDirection) -> Bool {
        guard let scroll = enclosingScrollView else { return false }
        let clip = scroll.contentView
        let old = clip.bounds
        let delta = direction.sign * (clip.isFlipped ? -1 : 1) * old.height * 0.42
        let next = clip.constrainBoundsRect(old.offsetBy(dx: 0, dy: delta)).origin
        guard abs(next.y - old.minY) > 1 else { return false }
        clip.scroll(to: next)
        scroll.reflectScrolledClipView(clip)
        return true
    }
}

private struct FocusRegistration: NSViewRepresentable {
    let navigator: DirectionalNavigation
    var enabled: Bool
    var priority: Int
    var layer: Int
    let action: () -> Void
    let highlight: (Bool) -> Void
    let adjust: ((NavigationDirection) -> Bool)?
    let back: (() -> Void)?

    func makeNSView(context: Context) -> FocusAnchor { FocusAnchor() }

    func updateNSView(_ view: FocusAnchor, context: Context) {
        view.navigator = navigator
        view.action = action
        view.highlight = highlight
        view.adjust = adjust
        view.back = back
        view.enabled = enabled
        view.priority = priority
        view.navigationLayer = layer
        navigator.register(view)
    }
}

private struct DirectionalTarget: ViewModifier {
    @Environment(\.directionalNavigation) private var navigator
    @Environment(\.directionalLayer) private var layer
    @Environment(\.directionalBack) private var back
    @Environment(\.yoruTheme) private var theme
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("lightweight") private var lightweight = false
    @AppStorage("animatePlaybackButtons") private var animateButtons = true
    @State private var focused = false
    @State private var keyPressed = false
    @State private var pressCount = 0
    let radius: CGFloat
    let priority: Int
    let action: () -> Void
    var adjust: ((NavigationDirection) -> Bool)? = nil
    var onBlur: (() -> Void)? = nil
    var onFocus: (() -> Void)? = nil
    var animatesButton = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .overlay {
                if focused && enabled {
                    ZStack {
                        shape.fill(theme.accent.opacity(0.10))
                        if !lightweight {
                            shape.strokeBorder(theme.accent.opacity(0.70), lineWidth: 6)
                                .blur(radius: 4).clipShape(shape)
                        }
                        shape.strokeBorder(theme.accent, lineWidth: 2)
                    }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .animation(animateButtons && !reduceMotion && !lightweight ? YoruMotion.focus : nil, value: focused)
            .modifier(GlassButtonMotion(pressed: keyPressed, radius: radius))
            .task(id: pressCount) {
                guard keyPressed else { return }
                try? await Task.sleep(nanoseconds: 85_000_000)
                if !Task.isCancelled { keyPressed = false }
            }
            .background {
                if let navigator {
                    FocusRegistration(navigator: navigator, enabled: enabled, priority: priority, layer: layer,
                                      action: {
                                          if animatesButton && animateButtons && !reduceMotion && !lightweight {
                                              keyPressed = true
                                              pressCount += 1
                                          }
                                          action()
                                      }, highlight: {
                                          focused = $0
                                          if $0 { onFocus?() } else { onBlur?() }
                                      }, adjust: adjust, back: back)
                }
            }
    }
}

extension View {
    func directionalTarget(radius: CGFloat = 14, priority: Int = 0, animatesButton: Bool = false, action: @escaping () -> Void) -> some View {
        modifier(DirectionalTarget(radius: radius, priority: priority, action: action, animatesButton: animatesButton))
    }

    func directionalValue(_ adjust: @escaping (CGFloat) -> Void) -> some View {
        modifier(DirectionalValueControl(adjust: adjust))
    }
}

private struct DirectionalValueControl: ViewModifier {
    @State private var editing = false
    @Environment(\.yoruTheme) private var theme
    let adjust: (CGFloat) -> Void

    func body(content: Content) -> some View {
        content
            .overlay {
                if editing {
                    Capsule().strokeBorder(theme.accent, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .allowsHitTesting(false)
                }
            }
            .modifier(DirectionalTarget(radius: 100, priority: 0, action: { editing.toggle() },
                adjust: { direction in
                    guard editing, !direction.vertical else { return false }
                    adjust(direction.sign)
                    return true
                }, onBlur: { editing = false }))
    }
}

struct DirectionalPlainStyle: PrimitiveButtonStyle {
    var radius: CGFloat = 15
    var priority = 0
    var onFocus: (() -> Void)? = nil

    func makeBody(configuration: Configuration) -> some View {
        Button(configuration)
            .buttonStyle(GlassPlainButtonStyle(radius: radius))
            .modifier(DirectionalTarget(radius: radius, priority: priority, action: configuration.trigger, onFocus: onFocus, animatesButton: true))
    }
}

private struct GlassPlainButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    let radius: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(enabled ? 1 : 0.47)
            .modifier(GlassButtonMotion(pressed: configuration.isPressed, radius: radius))
    }
}

final class ControllerInput {
    private var connected: [ObjectIdentifier: [GCControllerButtonInput]] = [:]
    private var observers: [NSObjectProtocol] = []
    private var repeatTask: Task<Void, Never>?
    private var direction: NavigationDirection?
    private var activePad: ObjectIdentifier?
    var receive: ((NavigationInput) -> Void)?

    func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] notice in
                if let controller = notice.object as? GCController { self?.attach(controller) }
            },
            center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] notice in
                guard let id = (notice.object as? GCController).map(ObjectIdentifier.init) else { return }
                self?.connected.removeValue(forKey: id)
                self?.endRepeat()
            },
            center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.endRepeat() }
        ]
        GCController.controllers().forEach(attach)
    }

    func stop() {
        endRepeat()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        connected.values.flatMap { $0 }.forEach { $0.pressedChangedHandler = nil }
        connected.removeAll()
    }

    private func attach(_ controller: GCController) {
        let id = ObjectIdentifier(controller)
        guard connected[id] == nil else { return }
        controller.handlerQueue = .main
        var buttons: [GCControllerButtonInput] = []
        if let gamepad = controller.extendedGamepad {
            bind(gamepad.dpad)
            bind(gamepad.leftThumbstick)
            buttons = [gamepad.buttonA, gamepad.buttonB, gamepad.buttonX, gamepad.buttonMenu]
            bind(gamepad.buttonA, .activate)
            bind(gamepad.buttonB, .back)
            bind(gamepad.buttonX, .playPause)
            bind(gamepad.buttonMenu, .playPause)
        } else if let remote = controller.microGamepad {
            let profile = controller.physicalInputProfile
            let directions = profile.dpads[GCInputDirectionalCardinalDpad] ?? remote.dpad
            let select = profile.buttons[GCInputDirectionalCenterButton] ?? remote.buttonA
            bind(directions)
            buttons = [select, remote.buttonMenu, remote.buttonX]
            bind(select, .activate)
            bind(remote.buttonMenu, .back)
            bind(remote.buttonX, .playPause)
        }
        connected[id] = buttons
    }

    private func bind(_ button: GCControllerButtonInput, _ input: NavigationInput) {
        button.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed, NSApp.isActive { self?.receive?(input) }
        }
    }

    private func bind(_ pad: GCControllerDirectionPad) {
        let id = ObjectIdentifier(pad)
        pad.valueChangedHandler = { [weak self] _, x, y in
            self?.move(NavigationDirection(x: x, y: y), from: id)
        }
    }

    private func move(_ next: NavigationDirection?, from pad: ObjectIdentifier) {
        guard NSApp.isActive else { return }
        if next == nil, activePad != pad { return }
        guard next != direction || pad != activePad else { return }
        endRepeat()
        guard let next else { return }
        direction = next
        activePad = pad
        receive?(.move(next))
        repeatTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 340_000_000)
            while !Task.isCancelled, NSApp.isActive {
                self?.receive?(.move(next))
                try? await Task.sleep(nanoseconds: 105_000_000)
            }
        }
    }

    private func endRepeat() {
        repeatTask?.cancel()
        repeatTask = nil
        activePad = nil
        direction = nil
    }

    deinit { stop() }
}

struct DirectionalMenu<Title: View, Actions: View>: View {
    @Environment(\.directionalLayer) private var layer
    @State private var isOpen = false
    @ViewBuilder let title: () -> Title
    @ViewBuilder let actions: (_ close: @escaping () -> Void) -> Actions

    var body: some View {
        Button { isOpen.toggle() } label: {
            HStack(spacing: 7) {
                title()
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(ControlStyle(horizontalPadding: 11))
        .popover(isPresented: $isOpen) {
            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    actions { isOpen = false }
                }
                .padding(12)
            }
            .frame(minWidth: 190, idealWidth: 310, maxWidth: 370, maxHeight: 320)
            .environment(\.directionalLayer, layer + 1)
            .environment(\.directionalBack, { isOpen = false })
        }
    }
}

struct DirectionalDisclosure<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("lightweight") private var lightweight = false
    @AppStorage("animatePlaybackButtons") private var animateButtons = true
    @Binding var expanded: Bool
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        let motion = animateButtons && !reduceMotion && !lightweight
        VStack(alignment: .leading, spacing: 8) {
            Button { expanded.toggle() } label: {
                HStack {
                    Text(title)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                }
                .frame(minHeight: 36)
                .contentShape(Rectangle())
            }
            .buttonStyle(DirectionalPlainStyle(radius: 10))
            .accessibilityValue(expanded ? "Déployé" : "Replié")
            if expanded { content.transition(motion ? YoruMotion.page : .identity) }
        }
        .animation(motion ? YoruMotion.pageChange : nil, value: expanded)
    }
}

struct DirectionalTextField: View {
    let title: String
    @Binding var text: String
    @FocusState private var editing: Bool

    var body: some View {
        TextField(title, text: $text)
            .focused($editing)
            .directionalTarget(radius: 9) { editing = true }
    }
}
