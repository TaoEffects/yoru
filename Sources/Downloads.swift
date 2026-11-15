import Foundation
import CryptoKit
import AppKit

struct TorrentResult: Identifiable, Equatable {
    var id: String
    var title: String
    var torrent: URL
    var seeds: Int
    var size: String
    var bytes: Double
    var trusted: Bool
    var group: String { ReleaseName(title).group ?? "" }
    var episode: Int? { isRange ? nil : ReleaseName(title).episode }
    private var isRange: Bool {
        if title.match(#"(?i)\b(?:S\d{1,2}[ ._-]*)?(?:E|EP\.?\s*|Episode\s+)\d{1,4}\s*[-–~]\s*(?:S\d{1,2}E|E)?\d{1,4}\b"#) != nil {
            return true
        }
        return title.match(#"(?i)[ ._-]\d{1,3}\s*[-–~]\s*\d{1,3}\b"#) != nil
    }
    var artworkTitle: String {
        ReleaseName(title).title
            .replacingPattern(#"(?i)\s*\(Season\s*\d+\).*$"#)
            .replacingPattern(#"(?i)\s+\d{1,3}[-–~]\d{1,3}.*$"#)
            .replacingPattern(#"(?i)\s*\([^)]*\)\s*$"#).trimmed
    }
    var season: Int? {
        ReleaseName(title).season ?? SeasonNumber.first(in: title)
    }
    var seasons: Set<Int> {
        if let range = title.match(#"(?i)\bS(?:eason\s*)?(\d{1,2})\s*(?:[-–~]|to)\s*S?(?:eason\s*)?(\d{1,2})\b"#),
           let first = Int(range[1]), let last = Int(range[2]), first <= last { return Set(first...last) }
        return season.map { [$0] } ?? []
    }
    var isPack: Bool {
        episode == nil && (isRange || season != nil || title.match(#"(?i)\b(batch|complete|collection|pack|saisons?)\b"#) != nil)
    }
    var scopeLabel: String {
        let numbers = seasons.sorted()
        let season = numbers.count == 1 ? "Saison \(numbers[0])" : numbers.isEmpty ? "" : "Saisons " + numbers.map(String.init).joined(separator: ", ")
        if let episode { return [season, "Épisode \(episode)"].filter { !$0.isEmpty }.joined(separator: " · ") }
        return [season, isPack ? "Pack" : "Vidéo"].filter { !$0.isEmpty }.joined(separator: " · ")
    }
    var french: Bool { title.match(#"(?i)\b(vostfr|french|vff|multi.?fr)\b"#) != nil }
}

private final class Feed: NSObject, XMLParserDelegate {
    var results: [TorrentResult] = []
    private var item: [String: String]?
    private var characters = ""
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if elementName == "item" { item = [:] }
        characters = ""
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { characters += string }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name != "item" { item?[name] = characters.trimmed; return }
        defer { item = nil }
        guard let item, let id = item["nyaa:infoHash"], id.match(#"^[a-fA-F0-9]{40}$"#) != nil,
              let title = item["title"], let link = item["link"], let url = URL(string: link),
              url.scheme == "https", url.host == "nyaa.si", url.path.match(#"^/download/\d+\.torrent$"#) != nil else { return }
        let size = item["nyaa:size"] ?? ""
        let quantity = Double(size.split(separator: " ").first ?? "") ?? 0
        let multiplier: Double = size.contains("TiB") ? pow(1024, 4) : size.contains("GiB") ? pow(1024, 3) : size.contains("MiB") ? pow(1024, 2) : 1024
        results.append(TorrentResult(id: id.lowercased(), title: title, torrent: url, seeds: Int(item["nyaa:seeders"] ?? "") ?? 0,
            size: size, bytes: quantity * multiplier, trusted: item["nyaa:trusted"] == "Yes"))
    }
}

struct TorrentFile: Identifiable {
    var id: Int
    var path: String
    var bytes: Int64
    var isVideo: Bool { Indexer.extensions.contains(URL(fileURLWithPath: path).pathExtension.lowercased()) }
    var episode: Int? { ReleaseName(URL(fileURLWithPath: path).lastPathComponent).episode }
    var season: Int? {
        if let value = ReleaseName(URL(fileURLWithPath: path).lastPathComponent).season { return value }
        return path.split(separator: "/").dropLast().reversed().compactMap {
            SeasonNumber.first(in: String($0))
        }.first
    }
}
struct TorrentPreview {
    var data: Data
    var files: [TorrentFile]

    func bytes(selected: Set<Int>? = nil) -> Int64 {
        files.reduce(Int64(0)) { sum, file in
            if let selected, !selected.contains(file.id) { return sum }
            let added = sum.addingReportingOverflow(file.bytes)
            return added.overflow ? Int64.max : added.partialValue
        }
    }
}

private struct Bencode {
    indirect enum Value {
        case bytes(Data), int(Int64), list([Value]), dictionary([String: Value])
        var string: String? { if case .bytes(let bytes) = self { return String(data: bytes, encoding: .utf8) }; return nil }
        var int: Int64? { if case .int(let value) = self { return value }; return nil }
        var list: [Value]? { if case .list(let value) = self { return value }; return nil }
        subscript(_ key: String) -> Value? { if case .dictionary(let values) = self { return values[key] }; return nil }
    }

    let bytes: [UInt8]
    var index = 0
    var infoRange: Range<Int>?
    let invalid = Notice("Métadonnées du torrent non valides.")

    mutating func read(_ depth: Int = 0) throws -> Value {
        guard depth < 40, index < bytes.count else { throw invalid }
        switch bytes[index] {
        case 100:
            index += 1
            var fields: [String: Value] = [:]
            while try !end() {
                guard let key = try read(depth + 1).string, fields[key] == nil else { throw invalid }
                let start = index
                fields[key] = try read(depth + 1)
                if depth == 0, key == "info" { infoRange = start..<index }
            }
            return .dictionary(fields)
        case 108:
            index += 1
            var items: [Value] = []
            while try !end() {
                guard items.count < 20000 else { throw invalid }
                items.append(try read(depth + 1))
            }
            return .list(items)
        case 105:
            index += 1
            let number = try token(until: 101)
            guard let value = Int64(number) else { throw invalid }
            return .int(value)
        case 48...57:
            let number = try token(until: 58)
            guard let size = Int(number), size >= 0, size <= bytes.count - index else { throw invalid }
            defer { index += size }
            return .bytes(Data(bytes[index..<index + size]))
        default: throw invalid
        }
    }

    private mutating func token(until marker: UInt8) throws -> String {
        let start = index
        while index < bytes.count, index - start <= 22, bytes[index] != marker { index += 1 }
        guard index < bytes.count, bytes[index] == marker else { throw invalid }
        defer { index += 1 }
        return String(decoding: bytes[start..<index], as: UTF8.self)
    }

    private mutating func end() throws -> Bool {
        guard index < bytes.count else { throw invalid }
        guard bytes[index] == 101 else { return false }
        index += 1
        return true
    }
}

enum TorrentSearch {
    static func search(_ query: String, groups: String, minimumSeeds: Int, packs: Bool?, episode: Int?, season: Int? = nil, seasons: Set<Int> = []) async throws -> [TorrentResult] {
        let accounts = Array(NyaaSource.accounts(groups).prefix(12))
        let requested = season.map { Set([$0]) } ?? seasons
        func feed(account: String) async throws -> [TorrentResult] {
            let verified = account.lowercased() == "trusted"
            var query = ["page": "rss", "q": query, "c": "1_0", "f": verified ? "2" : "0"]
            if !verified { query["u"] = account }
            let url = HTTP.endpoint("https://nyaa.si/", query)
            let data = try await HTTP.data(url)
            let feed = Feed()
            let parser = XMLParser(data: data)
            parser.shouldResolveExternalEntities = false
            parser.delegate = feed
            guard parser.parse() else { throw Notice("Nyaa n’a pas renvoyé de flux lisible.") }
            return feed.results.filter { !verified || $0.trusted }
        }
        let (rows, failures) = await withTaskGroup(of: Result<[TorrentResult], Error>.self) { tasks in
            func request(_ account: String) async -> Result<[TorrentResult], Error> {
                do { return .success(try await feed(account: account)) }
                catch { return .failure(error) }
            }
            var remaining = accounts.makeIterator()
            for _ in 0..<4 {
                if let account = remaining.next() { tasks.addTask { await request(account) } }
            }
            var rows: [TorrentResult] = []
            var failures: [Error] = []
            for await result in tasks {
                switch result {
                case .success(let entries): rows.append(contentsOf: entries)
                case .failure(let error): failures.append(error)
                }
                if let account = remaining.next(), !Task.isCancelled { tasks.addTask { await request(account) } }
            }
            return (rows, failures)
        }
        if !accounts.isEmpty, failures.count == min(12, accounts.count), let error = failures.first { throw error }
        var seen: Set<String> = []
        let values = rows.filter { row in
            guard row.seeds >= minimumSeeds, seen.insert(row.id).inserted else { return false }
            if !requested.isEmpty, row.seasons.isDisjoint(with: requested) { return false }
            if packs == true { return row.isPack }
            if let episode { return row.episode == episode }
            if packs == false { return row.episode != nil }
            return true
        }
        func score(_ item: TorrentResult) -> Double {
            Double(item.french ? 12 : 0) + (item.trusted ? 6 : 0) + 8 * log10(Double(item.seeds + 1)) - 3 * log2(max(1, item.bytes / 150_000_000))
        }
        let ranked = values.sorted {
            let lhs = score($0), rhs = score($1)
            return lhs == rhs ? $0.id < $1.id : lhs > rhs
        }
        if packs == nil, episode == nil {
            let batches = ranked.filter(\.isPack)
            let singles = ranked.filter { !$0.isPack }
            return Array(batches.prefix(18)) + Array(singles.prefix(max(32, 48 - batches.count)))
        }
        return Array(ranked.prefix(60))
    }

    static func preview(_ item: TorrentResult) async throws -> TorrentPreview {
        guard !item.torrent.isFileURL else { throw Notice("Le fichier torrent local n’est plus disponible.") }
        let data = try await HTTP.data(item.torrent)
        return try decode(data, expectedHash: item.id).preview
    }

    static func local(_ url: URL) throws -> (TorrentResult, TorrentPreview) {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let limit = 4_000_000
        guard let data = try file.read(upToCount: limit + 1), data.count <= limit else { throw Notice("Fichier torrent trop volumineux.") }
        let result = try decode(data, expectedHash: nil)
        let total = result.preview.bytes()
        let size = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
        return (TorrentResult(id: result.hash, title: result.name, torrent: url, seeds: 0, size: size, bytes: Double(total), trusted: false), result.preview)
    }

    private static func decode(_ data: Data, expectedHash: String?) throws -> (preview: TorrentPreview, hash: String, name: String) {
        var reader = Bencode(bytes: Array(data))
        let root = try reader.read()
        guard let info = root["info"], let range = reader.infoRange, reader.index == data.count else { throw reader.invalid }
        let hash = Insecure.SHA1.hash(data: Data(data[range])).map { String(format: "%02x", $0) }.joined()
        guard expectedHash == nil || hash == expectedHash else { throw Notice("L’empreinte du torrent diffère du résultat Nyaa.") }
        let scanned: [(String, Int64)]
        func safe(_ components: [String]) -> Bool {
            !components.isEmpty && components.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." && !($0.contains("/") || $0.contains("\\") || $0.contains("\0")) }
        }
        guard let rootName = (info["name.utf-8"] ?? info["name"])?.string, safe([rootName]) else { throw reader.invalid }
        if let list = info["files"]?.list {
            scanned = try list.map { record in
                guard let components = (record["path.utf-8"] ?? record["path"])?.list,
                      let count = record["length"]?.int, count >= 0, record["attr"]?.string?.contains("l") != true else { throw reader.invalid }
                let parts = components.compactMap(\.string)
                guard parts.count == components.count, safe(parts) else { throw reader.invalid }
                return (parts.joined(separator: "/"), count)
            }
        } else {
            guard let name = (info["name.utf-8"] ?? info["name"])?.string,
                  safe([name]), let length = info["length"]?.int, length >= 0 else { throw reader.invalid }
            scanned = [(name, length)]
        }
        let files = scanned.enumerated().map { TorrentFile(id: $0.offset, path: $0.element.0, bytes: $0.element.1) }
        let allowed = Indexer.extensions.union(SubtitleService.types).union(["txt", "nfo", "ttf", "otf", "jpg", "jpeg", "png", "webp"])
        let blocked = files.filter { !allowed.contains(URL(fileURLWithPath: $0.path).pathExtension.lowercased()) }
        guard blocked.isEmpty else { throw Notice("Ce torrent contient des fichiers inattendus : \(blocked.prefix(3).map(\.path).joined(separator: ", ")).") }
        guard files.contains(where: \.isVideo) else { throw Notice("Aucune vidéo trouvée dans ce torrent.") }
        return (TorrentPreview(data: data, files: files), hash, rootName)
    }
}

struct TransferredFile: Decodable {
    var name: String
    var priority: Int
    var progress: Double
}

struct AvailableDownload: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let videos: [URL]
    let finishedAt: Date
}

struct Transfer: Decodable, Identifiable, Equatable {
    var id: String { hash }
    var hash: String
    var name: String
    var progress: Double
    var state: String
    var dlspeed: Int64
    var amount_left: Int64
    var num_seeds: Int
    var content_path: String
    var save_path: String?
    var eta: Int?
    var details: String?
    var fraction: Double { min(1, max(0, progress)) }
    var onHold: Bool { state.contains("paused") || state.contains("stopped") }
    var speed: String? { dlspeed > 0 ? ByteCountFormatter.string(fromByteCount: dlspeed, countStyle: .file) + "/s" : nil }
    var remainingTime: String? {
        guard !onHold, dlspeed > 0, let eta, (1...86_400).contains(eta) else { return nil }
        return Duration.seconds(eta).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2))
    }
    var finished: Bool { progress >= 1 && amount_left == 0 }
    var label: String {
        if finished { return "Prêt à regarder" }
        if state.contains("stalled") { return "En attente de pairs" }
        if state.contains("paused") || state.contains("stopped") { return "En pause" }
        if state.contains("error") || state == "missingFiles" { return details ?? "Erreur" }
        if state.contains("checking") { return "Vérification" }
        return "Téléchargement"
    }
}
