import SwiftUI
import AppKit
import OpenGL.GL3
import Combine

struct Track: Identifiable, Equatable {
    var id: Int
    var kind: String
    var language: String
    var title: String
    var label: String { [language.uppercased(), title].filter { !$0.isEmpty }.joined(separator: " · ").nonEmpty ?? "Piste \(id)" }
    var shortLanguage: String {
        switch language.lowercased().split(separator: "-").first.map(String.init) {
        case "fre", "fra", "fr": return "fr"
        case "jpn", "ja", "jp": return "ja"
        case "eng", "en": return "en"
        default:
            if language.isEmpty {
                if title.match(#"(?i)\b(français|french|vostfr)\b"#) != nil { return "fr" }
                if title.match(#"(?i)\b(japanese|japonais)\b|日本語"#) != nil { return "ja" }
                if title.match(#"(?i)\b(english|anglais)\b"#) != nil { return "en" }
            }
            return language.lowercased()
        }
    }
}

struct SkipSegment: Equatable {
    var kind: String
    var start: Double
    var end: Double
    var label: String { kind == "op" ? "Passer l’intro" : "Passer le générique" }
}

private func openGLProc(_: UnsafeMutableRawPointer?, _ name: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? {
    guard let name, let bundle = CFBundleGetBundleWithIdentifier("com.apple.opengl" as CFString) else { return nil }
    return CFBundleGetFunctionPointerForName(bundle, String(cString: name) as CFString)
}

private final class GLRenderer {
    let context: CGLContextObj
    let format: CGLPixelFormatObj
    let lock = NSRecursiveLock()
    private var renderer: OpaquePointer?
    private var frames = 0
    var renderedFrames: Int {
        lock.lock()
        defer { lock.unlock() }
        return frames
    }
    var error: String?

    init?(engine: OpaquePointer?) {
        let attributes: [CGLPixelFormatAttribute] = [
            kCGLPFAOpenGLProfile, CGLPixelFormatAttribute(kCGLOGLPVersion_3_2_Core.rawValue),
            kCGLPFAAccelerated, CGLPixelFormatAttribute(0)
        ]
        var pixelFormat: CGLPixelFormatObj?
        var screens: GLint = 0
        guard CGLChoosePixelFormat(attributes, &pixelFormat, &screens) == kCGLNoError,
              let pixelFormat else { return nil }
        var newContext: CGLContextObj?
        guard CGLCreateContext(pixelFormat, nil, &newContext) == kCGLNoError,
              let newContext else { CGLReleasePixelFormat(pixelFormat); return nil }
        context = newContext
        format = pixelFormat
        guard let engine else { error = "Moteur vidéo indisponible."; return }
        let previous = CGLGetCurrentContext()
        CGLSetCurrentContext(context)
        defer { CGLSetCurrentContext(previous) }
        var gl = mpv_opengl_init_params(get_proc_address: openGLProc, get_proc_address_ctx: nil)
        let status = "opengl".withCString { api in
            withUnsafeMutablePointer(to: &gl) { gl in
                var params = [
                    mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: UnsafeMutableRawPointer(mutating: api)),
                    mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, data: gl),
                    mpv_render_param()
                ]
                return mpv_render_context_create(&renderer, engine, &params)
            }
        }
        if status < 0 { error = "Rendu vidéo indisponible · " + String(cString: mpv_error_string(status)) }
    }

    func hasFrame() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let renderer else { return false }
        return mpv_render_context_update(renderer) & 1 != 0
    }

    func draw() {
        lock.lock()
        defer { lock.unlock() }
        var framebuffer: GLint = 0
        var viewport = [GLint](repeating: 0, count: 4)
        glGetIntegerv(GLenum(GL_DRAW_FRAMEBUFFER_BINDING), &framebuffer)
        glGetIntegerv(GLenum(GL_VIEWPORT), &viewport)
        guard viewport[2] > 0, viewport[3] > 0 else { return }
        glClearColor(0, 0, 0, 1)
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
        if let renderer {
            var target = mpv_opengl_fbo(fbo: framebuffer, w: viewport[2], h: viewport[3], internal_format: 0)
            var flip: Int32 = 1
            var block: Int32 = 0
            withUnsafeMutablePointer(to: &target) { target in
                withUnsafeMutablePointer(to: &flip) { flip in
                    withUnsafeMutablePointer(to: &block) { block in
                        var params = [
                            mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: target),
                            mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: flip),
                            mpv_render_param(type: MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME, data: block),
                            mpv_render_param()
                        ]
                        if mpv_render_context_render(renderer, &params) == 0 { frames += 1 }
                    }
                }
            }
            mpv_render_context_report_swap(renderer)
        }
        glFlush()
    }
    func releaseRenderer() {
        lock.lock()
        defer { lock.unlock() }
        let previous = CGLGetCurrentContext()
        CGLSetCurrentContext(context)
        if let renderer { mpv_render_context_free(renderer) }
        renderer = nil
        CGLSetCurrentContext(previous)
    }
    deinit {
        releaseRenderer()
        CGLReleaseContext(context)
        CGLReleasePixelFormat(format)
    }
}

private final class VideoLayer: CAOpenGLLayer {
    let backend: GLRenderer?
    init(backend: GLRenderer) {
        self.backend = backend
        super.init()
        isAsynchronous = false
        needsDisplayOnBoundsChange = true
        backgroundColor = NSColor.black.cgColor
    }
    override init(layer: Any) { backend = (layer as? VideoLayer)?.backend; super.init(layer: layer) }
    required init?(coder: NSCoder) { nil }
    override func copyCGLPixelFormat(forDisplayMask mask: UInt32) -> CGLPixelFormatObj {
        guard let backend else { return super.copyCGLPixelFormat(forDisplayMask: mask) }
        return CGLRetainPixelFormat(backend.format)
    }
    override func copyCGLContext(forPixelFormat pixelFormat: CGLPixelFormatObj) -> CGLContextObj {
        guard let backend else { return super.copyCGLContext(forPixelFormat: pixelFormat) }
        return CGLRetainContext(backend.context)
    }
    override func draw(inCGLContext context: CGLContextObj, pixelFormat: CGLPixelFormatObj, forLayerTime time: CFTimeInterval, displayTime: UnsafePointer<CVTimeStamp>?) {
        backend?.draw()
    }
}

final class VideoSurface: NSView {
    private let backend: GLRenderer?
    var error: String? { backend?.error ?? (backend == nil ? "Impossible de créer le contexte vidéo." : nil) }
    var renderedFrames: Int { backend?.renderedFrames ?? 0 }
    init(engine: OpaquePointer?) {
        backend = GLRenderer(engine: engine)
        super.init(frame: .zero)
        if let backend { layer = VideoLayer(backend: backend); wantsLayer = true }
    }
    required init?(coder: NSCoder) { nil }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updateScale(); layer?.setNeedsDisplay() }
    override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); updateScale() }
    override func setFrameSize(_ newSize: NSSize) {
        let changed = frame.size != newSize
        super.setFrameSize(newSize)
        if changed { layer?.setNeedsDisplay() }
    }
    private func updateScale() { layer?.contentsScale = window?.backingScaleFactor ?? 1 }
    func frameIfNeeded() {
        if window != nil, backend?.hasFrame() == true { layer?.setNeedsDisplay() }
    }
    func releaseRenderer() { backend?.releaseRenderer() }
}

struct VideoView: NSViewRepresentable {
    let player: Player
    func makeCoordinator() -> PictureInPicture { player.pictureInPicture }
    func makeNSView(context: Context) -> VideoHostView { VideoHostView() }
    func updateNSView(_ host: VideoHostView, context: Context) { context.coordinator.attachInlineHost(host) }
    static func dismantleNSView(_ host: VideoHostView, coordinator: PictureInPicture) { coordinator.detachInlineHost(host) }
}

final class Player: ObservableObject {
    let surface: VideoSurface
    private var engine: OpaquePointer?
    private var frames: Timer?
    private var clock: Timer?
    var didLoad: (() -> Void)?
    var didEnd: (() -> Void)?
    var save: (() -> Void)?
    private var requestedPosition = 0.0
    private var ready = false
    private var reportedEnd = false
    private var correctedDuration: Double?
    private let audioDevicesObservation: UInt64 = 1
    private var failedAudioOutput: String?
    private var speedBoostInputs: Set<SpeedBoostInput> = []
    private var speedBeforeBoost = 1.0
    private var pausedBeforeBoost = false
    @MainActor lazy var pictureInPicture = PictureInPicture(player: self)

    @Published var position = 0.0
    @Published var duration = 0.0
    @Published var paused = true
    @Published var volume = 80.0
    @Published var tracks: [Track] = []
    @Published var activeSubtitle: Int?
    @Published var activeAudio: Int?
    @Published private(set) var audioOutputs = [AudioOutput.system]
    @Published private(set) var preferredAudioOutput = UserDefaults.standard.string(forKey: "audioOutputDevice") ?? AudioOutput.system.id
    @Published private(set) var configuredAudioOutput = AudioOutput.system.id
    @Published var delay = 0.0
    @Published var skips: [SkipSegment] = []
    @Published var error = ""
    @Published var loaded = false
    @Published private(set) var speedBoosted = false
    @Published private(set) var pictureInPictureActive = false
    private var loop: ClosedRange<Double>?

    init() {
        let handle = mpv_create()
        engine = handle
        if let handle {
            for (key, value) in [
                "vo": "libmpv", "config": "no", "idle": "yes", "hwdec": "auto-safe",
                "volume": "80", "alang": "jpn,ja", "sid": "no", "audio-device": "auto",
                "audio-fallback-to-null": "yes",
                "sub-auto": "fuzzy", "load-scripts": "no", "ytdl": "no", "keep-open": "yes",
                "osd-level": "0", "input-default-bindings": "no"
            ] { mpv_set_option_string(handle, key, value) }
            if mpv_initialize(handle) < 0 { error = "Impossible de démarrer le moteur vidéo." }
        } else { error = "Moteur vidéo indisponible." }
        surface = VideoSurface(engine: handle)
        if let renderError = surface.error { error = renderError }
        if let handle {
            mpv_observe_property(handle, audioDevicesObservation, "audio-device-list", MPV_FORMAT_NONE)
            refreshAudioOutputs()
        }
        frames = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.surface.frameIfNeeded() }
        clock = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in self?.tick() }
        if let frames, let clock {
            RunLoop.main.add(frames, forMode: .common)
            RunLoop.main.add(clock, forMode: .common)
        }
    }

    deinit {
        frames?.invalidate()
        clock?.invalidate()
        surface.releaseRenderer()
        if let engine { mpv_terminate_destroy(engine) }
    }

    @discardableResult func command(_ arguments: [String]) -> Int32 {
        guard let engine else { return -1 }
        let storage = arguments.map { strdup($0) }
        defer { storage.forEach { free($0) } }
        var pointers = storage.map { $0.map { UnsafePointer<CChar>($0) } }
        pointers.append(nil)
        return pointers.withUnsafeMutableBufferPointer { mpv_command(engine, $0.baseAddress) }
    }

    private func property(_ name: String) -> String? {
        guard let engine, let raw = mpv_get_property_string(engine, name) else { return nil }
        defer { mpv_free(raw) }
        return String(cString: raw)
    }

    func set(_ name: String, _ value: String) {
        guard let engine else { return }
        mpv_set_property_string(engine, name, value)
    }

    func open(_ url: URL, resume: Double) {
        cancelSpeedBoost()
        requestedPosition = resume
        ready = false
        reportedEnd = false
        correctedDuration = nil
        loaded = false
        error = surface.error ?? ""
        tracks = []
        skips = []
        position = 0
        duration = 0
        activeSubtitle = nil
        delay = 0
        loop = nil
        set("sub-delay", "0")
        set("sid", "no")
        set("aid", "auto")
        if command(["loadfile", url.path, "replace"]) < 0 { error = "Impossible d’ouvrir cette vidéo." }
        set("pause", "no")
    }

    func seek(_ seconds: Double) {
        command(["seek", String(max(0, min(seconds, duration))), "absolute+exact"])
    }

    @MainActor func stop() {
        cancelSpeedBoost()
        stopPictureInPicture(restore: false)
        command(["stop"])
        ready = false
        loaded = false
        position = 0
        duration = 0
        skips = []
        tracks = []
        error = ""
    }

    @MainActor func startPictureInPicture(title: String, restore: @escaping () -> Void) {
        pictureInPicture.start(title: title, restore: restore)
    }

    @MainActor func stopPictureInPicture(restore: Bool = true) {
        if pictureInPictureActive { pictureInPicture.stop(restore: restore) }
    }

    func setPictureInPictureActive(_ active: Bool) {
        if active { cancelSpeedBoost() }
        pictureInPictureActive = active
    }

    var displayAspectRatio: CGSize {
        guard let width = property("dwidth").flatMap(Double.init), let height = property("dheight").flatMap(Double.init),
              width > 0, height > 0, (0.2...5).contains(width / height) else { return CGSize(width: 16, height: 9) }
        return CGSize(width: width, height: height)
    }
    func toggle() {
        cancelSpeedBoost()
        if reportedEnd { seek(0); reportedEnd = false; set("pause", "no"); return }
        set("pause", property("pause") == "yes" ? "no" : "yes")
    }

    func beginSpeedBoost(_ input: SpeedBoostInput) {
        guard ready, loaded, !reportedEnd, !pictureInPictureActive,
              property("eof-reached") != "yes", speedBoostInputs.insert(input).inserted else { return }
        guard !speedBoosted else { return }
        let speed = property("speed").flatMap(Double.init) ?? 1
        speedBeforeBoost = speed.isFinite && speed > 0 ? speed : 1
        pausedBeforeBoost = property("pause") == "yes"
        set("speed", "2")
        set("pause", "no")
        speedBoosted = true
    }

    func endSpeedBoost(_ input: SpeedBoostInput) {
        speedBoostInputs.remove(input)
        if speedBoostInputs.isEmpty { cancelSpeedBoost() }
    }

    func cancelSpeedBoost() {
        speedBoostInputs.removeAll()
        guard speedBoosted else { return }
        set("speed", String(speedBeforeBoost))
        if pausedBeforeBoost { set("pause", "yes") }
        speedBoosted = false
    }
    func setVolume(_ value: Double) { volume = max(0, min(100, value)); set("volume", String(volume)) }
    func subtitles(_ id: Int?) { activeSubtitle = id; set("sid", id.map(String.init) ?? "no") }
    func audio(_ id: Int) { set("aid", String(id)); activeAudio = id }
    func setDelay(_ value: Double) { delay = value; set("sub-delay", String(value)) }

    func chooseAudioOutput(_ output: AudioOutput) {
        guard audioOutputs.contains(where: { $0.id == output.id }) else { return }
        if preferredAudioOutput != output.id {
            preferredAudioOutput = output.id
            UserDefaults.standard.set(output.id, forKey: "audioOutputDevice")
        }
        failedAudioOutput = nil
        applyAudioOutput()
    }

    private func refreshAudioOutputs() {
        guard let count = property("audio-device-list/count").flatMap(Int.init), count > 0 else { return }
        var seen = Set<String>()
        var devices: [AudioOutput] = []
        for index in 0..<count {
            let path = "audio-device-list/\(index)"
            guard let id = property("\(path)/name"), id.hasPrefix("coreaudio/"), seen.insert(id).inserted,
                  let name = property("\(path)/description"), !name.isEmpty else { continue }
            devices.append(AudioOutput(id: id, name: name))
        }
        let outputs = [AudioOutput.system] + devices.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if outputs != audioOutputs { audioOutputs = outputs }
        if let failedAudioOutput, !seen.contains(failedAudioOutput) { self.failedAudioOutput = nil }
        applyAudioOutput()
    }

    private func applyAudioOutput() {
        guard let engine else { return }
        let requested = audioOutputs.contains { $0.id == preferredAudioOutput } && failedAudioOutput != preferredAudioOutput
            ? preferredAudioOutput : AudioOutput.system.id
        guard requested != configuredAudioOutput else { return }
        if mpv_set_property_string(engine, "audio-device", requested) >= 0 {
            configuredAudioOutput = requested
        }
    }

    func addSubtitle(_ url: URL, language: String? = nil) {
        if command(["sub-add", url.path, "select", language.map { $0.uppercased() } ?? "", language ?? ""]) < 0 {
            error = "Impossible de charger ces sous-titres."
        }
        refreshTracks()
    }

    var currentSkip: SkipSegment? { skips.first { $0.start <= position && position < $0.end - 0.35 } }
    func toggleLoop() {
        if loop != nil { loop = nil; return }
        let start = max(0, position - 2)
        let end = min(duration, position + 3)
        guard start < end else { return }
        loop = start...end
        seek(start)
        set("pause", "no")
    }

    private func refreshTracks() {
        let count = min(200, Int(property("track-list/count") ?? "") ?? 0)
        let latest: [Track] = (0..<max(0, count)).compactMap { index in
            let key = "track-list/\(index)"
            guard let type = property("\(key)/type"), type != "video",
                  let id = Int(property("\(key)/id") ?? "") else { return nil }
            return Track(id: id, kind: type, language: property("\(key)/lang") ?? "", title: property("\(key)/title") ?? "")
        }
        if latest != tracks { tracks = latest }
        let sid = Int(property("sid") ?? "")
        let aid = Int(property("aid") ?? "")
        if sid != activeSubtitle { activeSubtitle = sid }
        if aid != activeAudio { activeAudio = aid }
    }

    private func mediaDuration(_ declared: Double) -> Double {
        let count = min(200, Int(property("track-list/count") ?? "") ?? 0)
        var videoEnds: [Double] = []
        var audioEnds: [Double] = []
        for index in 0..<max(0, count) {
            let key = "track-list/\(index)"
            guard property(key + "/external") != "yes",
                  let type = property(key + "/type"), type == "video" || type == "audio",
                  type != "video" || property(key + "/image") != "yes" else { continue }
            let raw = property(key + "/metadata/by-key/DURATION")
            let parts = raw?.split(separator: ":").compactMap { Double($0) } ?? []
            let seconds = parts.count == 3 ? parts[0] * 3600 + parts[1] * 60 + parts[2]
                : Double(property(key + "/demux-duration") ?? "")
            guard let seconds, seconds.isFinite, seconds > 0 else { continue }
            if type == "video" { videoEnds.append(seconds) }
            else { audioEnds.append(seconds) }
        }
        guard let video = videoEnds.max() else { return declared }
        let audio = audioEnds.max() ?? video
        let real = max(video, audio)
        // Do not shorten an ordered edition or override clearly divergent track lengths.
        guard abs(audio - video) < 5, declared - real > 0.75, declared - real < 180 else { return declared }
        let chapters = min(300, Int(property("chapter-list/count") ?? "") ?? 0)
        if chapters > 0, let last = Double(property("chapter-list/\(chapters - 1)/time") ?? ""), last > real { return declared }
        return real
    }

    private var subtitlePosition = 100.0
    private var subtitleDestination = 100.0
    private var subtitleMotion: Task<Void, Never>?

    func subtitleClearance(_ height: CGFloat, animated: Bool = true) {
        let viewHeight = surface.bounds.height
        let shift = viewHeight > 0 ? Double(height / viewHeight) * 100 : 0
        let target = 100 - min(30, max(0, shift))
        guard abs(target - subtitleDestination) > 0.12 || (!animated && target != subtitlePosition) else { return }
        subtitleMotion?.cancel()
        subtitleDestination = target
        if !animated {
            subtitlePosition = target
            set("sub-pos", String(target))
            return
        }

        let start = subtitlePosition
        subtitleMotion = Task { @MainActor [weak self] in
            for step in 1...14 {
                try? await Task.sleep(nanoseconds: 16_000_000)
                guard !Task.isCancelled, let self else { return }
                let t = Double(step) / 14
                let eased = t * t * (3 - 2 * t)
                let value = start + (target - start) * eased
                if abs(value - self.subtitlePosition) > 0.035 || step == 14 {
                    self.subtitlePosition = value
                    self.set("sub-pos", String(value))
                }
            }
        }
    }

    private func readChapters() {
        let count = min(300, Int(property("chapter-list/count") ?? "") ?? 0)
        let chapters: [(String, Double)] = (0..<max(0, count)).compactMap { index in
            guard let timestamp = Double(property("chapter-list/\(index)/time") ?? "") else { return nil }
            return (property("chapter-list/\(index)/title")?.lowercased() ?? "", timestamp)
        }
        skips = chapters.enumerated().compactMap { index, chapter in
            let pattern = #"^(?:\d+[ .:-]+)?(?:opening|op\d*|intro(?:duction)?|ending|ed\d*|outro|(?:(?:end|closing) )?credits|générique (?:de début|de fin))(?:\b|$)"#
            guard chapter.0.range(of: pattern, options: .regularExpression) != nil else { return nil }
            let isEnding = chapter.0.range(of: #"\b(ending|ed\d*|outro|(?:(?:end|closing) )?credits|générique de fin)\b"#, options: .regularExpression) != nil
            let next = index + 1 < chapters.count ? chapters[index + 1].1 : duration
            let end = min(next, duration)
            guard !isEnding || !chapter.0.contains("credits") || chapter.1 >= duration * 0.6 else { return nil }
            guard end - chapter.1 >= 8, end - chapter.1 <= 300 else { return nil }
            return SkipSegment(kind: isEnding ? "ed" : "op", start: chapter.1, end: end)
        }
    }

    private func tick() {
        guard let engine else { return }
        while let event = mpv_wait_event(engine, 0), event.pointee.event_id != MPV_EVENT_NONE {
            switch event.pointee.event_id {
            case MPV_EVENT_FILE_LOADED:
                ready = true
                loaded = true
                let declared = Double(property("duration") ?? "") ?? 0
                duration = mediaDuration(declared)
                if duration < declared {
                    correctedDuration = duration
                    set("file-local-options/end", String(duration))
                }
                refreshTracks()
                readChapters()
                if requestedPosition > 3 { seek(requestedPosition) }
                didLoad?()
            case MPV_EVENT_END_FILE:
                cancelSpeedBoost()
                let result = event.pointee.data?.assumingMemoryBound(to: mpv_event_end_file.self).pointee
                if result?.reason == MPV_END_FILE_REASON_ERROR {
                    ready = false
                    error = "Lecture interrompue · \(String(cString: mpv_error_string(result?.error ?? -1)))"
                }
            case MPV_EVENT_AUDIO_RECONFIG:
                if configuredAudioOutput != AudioOutput.system.id, property("current-ao") == "null" {
                    failedAudioOutput = configuredAudioOutput
                    applyAudioOutput()
                }
            case MPV_EVENT_PROPERTY_CHANGE where event.pointee.reply_userdata == audioDevicesObservation:
                refreshAudioOutputs()
            default: break
            }
        }
        guard ready else { return }
        let time = Double(property("time-pos") ?? "").flatMap { $0.isFinite ? $0 : nil }
        if let time {
            let next = correctedDuration.map { min(time, $0) } ?? time
            if position != next { position = next }
        }
        let isPaused = property("pause") == "yes"
        if isPaused { cancelSpeedBoost() }
        if isPaused != paused { paused = isPaused; if paused { save?() } }
        if let loop, position >= loop.upperBound { seek(loop.lowerBound) }
        if property("eof-reached") == "yes" {
            cancelSpeedBoost()
            if !reportedEnd {
                reportedEnd = true
                if let time, time > 0, duration - time > 0.75 {
                    duration = time
                    skips = skips.compactMap { segment in
                        guard segment.start + 1 < time else { return nil }
                        return SkipSegment(kind: segment.kind, start: segment.start, end: min(segment.end, time))
                    }
                }
                paused = true
                didEnd?()
            }
        } else { reportedEnd = false }
    }
}
