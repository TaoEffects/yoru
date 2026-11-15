import SwiftUI

struct PlaybackTimeline: View {
    @ObservedObject var player: Player
    let episode: Episode?
    @Binding var seekValue: Double?
    var previewsEnabled: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("lightweight") private var lightweight = false
    @State private var hover: Double?
    private let inset: CGFloat = 8

    var body: some View {
        let duration = player.duration.isFinite ? max(0, player.duration) : 0
        let position = min(max(seekValue ?? player.position, 0), duration)
        let timeWidth: CGFloat = duration >= 3600 ? 63 : 45
        HStack(spacing: 11) {
            Text(formatTime(position)).frame(width: timeWidth, alignment: .leading)
            GeometryReader { geometry in
                let track = max(1, geometry.size.width - 2 * inset)
                let preview = previewsEnabled ? seekValue ?? hover : nil
                let center = geometry.size.height / 2
                ZStack {
                    ZStack(alignment: .topLeading) {
                        Capsule().fill(.white.opacity(0.23))
                            .frame(width: track, height: preview == nil ? 4 : 6)
                            .position(x: geometry.size.width / 2, y: center)
                        if duration > 0 {
                            let played = position / duration * track
                            if played > 0 {
                                Capsule().fill(mint)
                                    .frame(width: played, height: preview == nil ? 4 : 6)
                                    .position(x: inset + played / 2, y: center)
                            }
                            ForEach(Array(player.skips.enumerated()), id: \.offset) { _, segment in
                                let start = bound(segment.start, duration: duration)
                                let end = bound(segment.end, duration: duration)
                                if end > start {
                                    let width = max(2, (end - start) / duration * track)
                                    Capsule().fill(tint(segment))
                                        .frame(width: width, height: 5)
                                        .position(x: inset + (start + end) / (2 * duration) * track, y: center)
                                }
                            }
                            Circle().fill(.white)
                                .frame(width: preview == nil ? 8 : 12, height: preview == nil ? 8 : 12)
                                .shadow(color: .black.opacity(0.35), radius: 3)
                                .position(x: inset + played, y: center)
                        }
                    }.allowsHitTesting(false)
                    Slider(value: Binding(get: { position }, set: { seconds in
                        if seekValue != nil { seekValue = seconds }
                        else { player.seek(seconds) }
                    }), in: 0...max(duration, 1), onEditingChanged: { editing in
                        if editing { seekValue = player.position }
                        else if let value = seekValue { seekValue = nil; player.seek(value) }
                    })
                    .labelsHidden().opacity(0.012)
                    .disabled(duration == 0)
                    .accessibilityLabel("Position de lecture")
                    .accessibilityValue(formatTime(position) + " sur " + formatTime(duration))
                    .frame(height: geometry.size.height)
                    .contentShape(Rectangle())
                    if let preview, duration > 0 {
                        let width = min(188, geometry.size.width)
                        let pointer = inset + bound(preview, duration: duration) / duration * track
                        let x = min(geometry.size.width - width / 2, max(width / 2, pointer))
                        let marker = player.skips.first { $0.start <= preview && preview < $0.end }
                        let clearance: CGFloat = player.currentSkip == nil ? 0 : 53
                        TimelinePreview(episode: episode, seconds: preview, duration: duration, marker: marker,
                                        width: width, showFrame: !lightweight)
                            .frame(width: width).position(x: x, y: -width * 0.29 - 26 - clearance)
                            .transition(.opacity.combined(with: .offset(y: reduceMotion || lightweight ? 0 : 5)))
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point) where duration > 0 && previewsEnabled:
                        hover = time(at: point.x, track: track, duration: duration)
                    case .active, .ended: hover = nil
                    }
                }
                .simultaneousGesture(SpatialTapGesture().onEnded { tap in
                    if duration > 0 && previewsEnabled { hover = time(at: tap.location.x, track: track, duration: duration) }
                })
            }
            .frame(height: 23)
            .animation(reduceMotion || lightweight ? nil : .easeOut(duration: 0.17),
                       value: previewsEnabled && (seekValue != nil || hover != nil))
            Text(formatTime(duration)).frame(width: timeWidth, alignment: .trailing)
        }
        .font(YoruTypography.text(13, strong: true).monospacedDigit())
        .onChange(of: episode?.id) { _ in hover = nil; seekValue = nil }
        .onChange(of: previewsEnabled) { enabled in if !enabled { hover = nil } }
    }

    private func time(at x: CGFloat, track: CGFloat, duration: Double) -> Double {
        min(max((x - inset) / track, 0), 1) * duration
    }

    private func bound(_ seconds: Double, duration: Double) -> Double {
        seconds.isFinite ? min(max(seconds, 0), duration) : 0
    }

    private func tint(_ marker: SkipSegment) -> Color {
        marker.kind == "op" ? Color(red: 0.76, green: 0.87, blue: 0.54) : Color(red: 0.82, green: 0.70, blue: 0.99)
    }
}

private struct TimelinePreview: View {
    let episode: Episode?
    let seconds: Double
    let duration: Double
    let marker: SkipSegment?
    let width: CGFloat
    let showFrame: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var image: NSImage?
    @State private var displayedRequest: Request?

    private struct Request: Equatable {
        let id: String?
        let time: Int
    }

    var body: some View {
        let interval = max(5, Int(ceil(duration / 210)))
        let time = max(0, Int(min(seconds, max(0, duration - 0.2))) / interval * interval)
        let request = Request(id: showFrame ? episode?.id : nil, time: time)
        VStack(spacing: 0) {
            if showFrame {
                Rectangle().fill(.white.opacity(0.08)).frame(height: width * 0.53)
                    .overlay {
                        if displayedRequest == request, let image {
                            Image(nsImage: image).resizable().scaledToFill().transition(.opacity)
                        }
                    }.clipped()
            }
            HStack {
                Text(formatTime(seconds)).monospacedDigit()
                Spacer(minLength: 4)
                if let marker { Text(marker.kind == "op" ? "Intro" : "Ending").foregroundStyle(mint) }
            }
            .font(YoruTypography.text(14, strong: true))
            .foregroundStyle(.white).padding(.horizontal, 10).padding(.vertical, 7)
        }
        .clipShape(RoundedRectangle(cornerRadius: 17))
        .modifier(Glass(radius: 17, tint: .black.opacity(0.55), fallback: Color(red: 0.075, green: 0.086, blue: 0.084)))
        .shadow(color: .black.opacity(0.34), radius: 12, y: 4)
        .task(id: request) {
            guard showFrame, let episode else { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled else { return }
            let preview = await FrameImage.image(episode, scrubTime: time)
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                image = preview
                displayedRequest = request
            }
        }
    }
}
