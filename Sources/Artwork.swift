import SwiftUI
import AppKit
import CryptoKit

struct Discovery: Identifiable, Equatable {
    let entry: Anime
    let reason: String?
    var id: Int { entry.id }
}

actor ArtworkCatalog {
    static let shared = ArtworkCatalog()
    private var cache: [String: Anime] = [:]
    private var absent: Set<String> = []
    private var pending: [String: Task<(Anime?, Bool), Never>] = [:]

    func season(_ number: Int, title: String, id: Int? = nil) async -> Anime? {
        guard number > 1 else { return await match(title, id: id) }
        let query = title + " Season " + String(number)
        if let item = await match(query) { return item }
        let key = query.normalized + "|variants"
        if let cached = cache[key] { return cached }
        if absent.contains(key) { return nil }
        let results = try? await Catalog.lookup(query)
        let base = title.normalized
        let candidates = [base + String(number) + "ndseason", base + String(number) + "rdseason",
                          base + String(number) + "thseason", base + String(number)]
        let found = results?.first { entry in
            [entry.title.romaji, entry.title.english, entry.title.native]
                .compactMap { $0?.normalized }.contains { candidates.contains($0) }
        }
        if let found { cache[key] = found }
        else if results != nil { absent.insert(key) }
        return found
    }

    func match(_ title: String, id: Int? = nil) async -> Anime? {
        let key = id.map(String.init) ?? title.normalized
        guard !key.isEmpty else { return nil }
        if let cached = cache[key] { return cached }
        if absent.contains(key) { return nil }
        if let task = pending[key] { return await task.value.0 }
        let task = Task {
            guard let firstPass = try? await Catalog.lookup(title, id: id) else { return (nil as Anime?, false) }
            if let id { return (firstPass.first(where: { $0.id == id }), true) }
            func titles(_ item: Anime) -> [String] {
                Array(item.titleKeys)
            }
            if let exact = firstPass.first(where: { titles($0).contains(key) }) { return (exact, true) }
            let prefix = firstPass.filter { item in
                key.count >= 8 && titles(item).contains { $0.hasPrefix(key) }
            }
            return (prefix.count == 1 ? prefix.first : nil, true)
        }
        pending[key] = task
        let (value, completed) = await task.value
        pending[key] = nil
        if let value { cache[key] = value }
        else if completed { absent.insert(key) }
        return value
    }
}

enum FrameImage {
    static let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 2
        return queue
    }()

    private static let scrubQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    private final class RequestState: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        var isCancelled: Bool { lock.withLock { cancelled } }
        func cancel() { lock.withLock { cancelled = true } }
    }

    static func image(_ episode: Episode, featureTime: Int? = nil, scrubTime: Int? = nil) async -> NSImage? {
        let request = RequestState()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                (scrubTime == nil ? queue : scrubQueue).addOperation {
                    continuation.resume(returning: request.isCancelled ? nil : render(episode, featureTime: featureTime, scrubTime: scrubTime))
                }
            }
        } onCancel: { request.cancel() }
    }

    private static func render(_ episode: Episode, featureTime: Int?, scrubTime: Int?) -> NSImage? {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let folder = base.appendingPathComponent(scrubTime == nil ? "io.github.taoeffects.yoru/Frames" : "io.github.taoeffects.yoru/Timeline")
        let key = SubtitleService.version(episode) + (scrubTime.map { "-\($0)" } ?? featureTime.map { "-hero-\($0)" } ?? "")
        let target = folder.appendingPathComponent(key + ".jpg")
        if let image = NSImage(contentsOf: target) { return image }
        guard let tool = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return nil }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let temporary = folder.appendingPathComponent(UUID().uuidString + ".jpg")
            defer { try? FileManager.default.removeItem(at: temporary) }
            let moments = scrubTime.map { [String($0)] } ?? featureTime.map { [String($0), "8"] } ?? ["145", "8"]
            let width = scrubTime == nil ? (featureTime == nil ? 360 : 1040) : 320
            for second in moments {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: tool)
                process.arguments = ["-nostdin", "-v", "error", "-ss", second, "-i", episode.url.path,
                                     "-an", "-sn", "-map", "0:v:0", "-frames:v", "1", "-vf", "scale=\(width):-2",
                                     "-threads", "1", "-q:v", "5", "-y", temporary.path]
                process.standardError = FileHandle.nullDevice
                process.standardOutput = FileHandle.nullDevice
                try process.run()
                process.waitUntilExit()
                if let bytes = try? Data(contentsOf: temporary), let image = NSImage(data: bytes) {
                    try? bytes.write(to: target, options: .atomic)
                    return image
                }
            }
        } catch { return nil }
        return nil
    }
}

let canvas = Color(red: 0.972, green: 0.950, blue: 0.918)
let muted = Color(red: 0.34, green: 0.30, blue: 0.36)
let accentInk = Color(red: 0.35, green: 0.23, blue: 0.58)
let lilac = Color(red: 0.58, green: 0.49, blue: 0.89)

struct CoverArt: View {
    var url: URL?
    var width: CGFloat
    var height: CGFloat
    var radius: CGFloat = 10
    var icon = "play.rectangle"
    @Environment(\.yoruTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("lightweight") private var lightweight = false
    var body: some View {
        ZStack {
            Rectangle().fill(theme.card)
            Image(systemName: icon).foregroundStyle(theme.accent.opacity(0.66)).font(.system(size: min(36, height * 0.3), weight: .medium))
            if let url {
                AsyncImage(url: url, transaction: Transaction(animation: reduceMotion || lightweight ? nil : .easeOut(duration: 0.22))) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill().transition(.opacity)
                    }
                }
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: radius))
        .accessibilityHidden(true)
    }
}

struct AnimeCover: View {
    let title: String
    var id: Int?
    var url: URL?
    var preview: Episode?
    var width: CGFloat
    var height: CGFloat
    @State private var resolved: URL?
    @State private var fallback: NSImage?
    var body: some View {
        ZStack {
            CoverArt(url: url ?? resolved, width: width, height: height)
            if let fallback, url == nil, resolved == nil {
                Image(nsImage: fallback).resizable().scaledToFill()
                    .frame(width: width, height: height).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 9)).transition(.opacity)
            }
        }.task(id: title + String(id ?? 0)) {
                resolved = nil
                fallback = nil
                guard url == nil else { return }
                let match = await ArtworkCatalog.shared.match(title, id: id)
                guard !Task.isCancelled else { return }
                resolved = match?.coverImage?.large
                if resolved == nil, let preview {
                    let image = await FrameImage.image(preview)
                    if !Task.isCancelled { withAnimation(.easeOut(duration: 0.2)) { fallback = image } }
                }
            }
    }
}

struct EpisodeStill: View {
    let episode: Episode
    var width: CGFloat = 91
    var height: CGFloat = 53
    @State private var image: NSImage?
    @AppStorage("lightweight") private var lightweight = false
    var body: some View {
        ZStack {
            CoverArt(width: width, height: height, icon: "film")
            if let image {
                Image(nsImage: image).resizable().scaledToFill().transition(.opacity)
            }
        }
        .frame(width: width, height: height).clipShape(RoundedRectangle(cornerRadius: 9))
        .animation(lightweight ? nil : .easeOut(duration: 0.22), value: image != nil)
        .accessibilityHidden(true)
        .task(id: episode.id) {
            image = nil
            guard !lightweight else { return }
            let result = await FrameImage.image(episode)
            if !Task.isCancelled { image = result }
        }
    }
}

struct ArtBackdrop: View {
    var url: URL?
    @Environment(\.yoruTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("lightweight") private var lightweight = false
    @AppStorage("showArtworkBlur") private var showArtworkBlur = true
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                theme.background
                RadialGradient(colors: [theme.glow.opacity(0.31), theme.background.opacity(0.97)], center: .topTrailing, startRadius: 20, endRadius: max(450, geometry.size.width * 0.84))
                if let glow = theme.secondaryGlow, !lightweight, showArtworkBlur {
                    RadialGradient(colors: [glow.opacity(0.33), .clear], center: .bottomLeading,
                                   startRadius: 26, endRadius: max(290, geometry.size.width * 0.65))
                }
                if let url, !lightweight, showArtworkBlur {
                    AsyncImage(url: url, transaction: Transaction(animation: reduceMotion ? nil : .easeInOut(duration: 0.26))) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                                .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                                .blur(radius: 28).scaleEffect(1.13).opacity(0.56)
                                .transition(.opacity)
                        }
                    }.id(url)
                    LinearGradient(colors: [theme.background.opacity(theme.colorScheme == .dark ? 0.65 : 0.24), theme.background.opacity(0.88)],
                                   startPoint: .topTrailing, endPoint: .bottomLeading)
                }
            }.clipped()
        }
        .animation(reduceMotion || lightweight ? nil : .easeOut(duration: 0.28), value: theme)
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct WideArtwork: View {
    var url: URL?
    var episode: Episode?
    var seconds: Double?
    @State private var frame: NSImage?
    @AppStorage("lightweight") private var lightweight = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var sampleTime: Int { max(8, Int((seconds ?? 145) / 120) * 120) }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let url, frame == nil {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image { image.resizable().scaledToFill() }
                    }
                }
                if let frame { Image(nsImage: frame).resizable().scaledToFill().transition(.opacity) }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .task(id: (episode?.id ?? "") + "|" + String(sampleTime) + "|" + String(lightweight)) {
            frame = nil
            guard !lightweight, let episode else { return }
            let image = await FrameImage.image(episode, featureTime: sampleTime)
            if !Task.isCancelled {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.24)) { frame = image }
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct HoverCard: ViewModifier {
    @Environment(\.yoruTheme) private var theme
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("lightweight") private var lightweight = false
    func body(content: Content) -> some View {
        content
            .background(hovered ? theme.tint : theme.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(hovered ? theme.accent.opacity(0.30) : theme.divider)
                .allowsHitTesting(false))
            .onHover { hovered = $0 }
            .animation(reduceMotion || lightweight ? nil : .easeOut(duration: 0.14), value: hovered)
    }
}
