import Foundation
import AppKit
import SwiftUI

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var normalized: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: #"[^\p{L}\p{N}]"#, with: "", options: .regularExpression)
    }
    func match(_ pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let result = regex.firstMatch(in: self, range: NSRange(startIndex..., in: self)) else { return nil }
        return (0..<result.numberOfRanges).map { Range(result.range(at: $0), in: self).map { String(self[$0]) } ?? "" }
    }
    func replacingPattern(_ pattern: String, with text: String = "") -> String {
        replacingOccurrences(of: pattern, with: text, options: .regularExpression)
    }
}

struct ReleaseName {
    let title: String
    let group: String?
    let season: Int?
    let episode: Int?

    init(_ name: String) {
        let prefix = name.match(#"^\[([^\]]+)\]\s*"#)
        group = prefix?[1]
        let stem = prefix.map { String(name.dropFirst($0[0].count)) } ?? name
        let base = stem.replacingPattern(#"(?i)(?:\.(?:mkv|mp4|avi|webm|mov|m4v|ts|srt|ass|ssa))$"#)
        if let match = base.match(#"(?i)^(.+?)[ ._–-]+(?:S(\d{1,2})[ ._-]*)?(?:E|EP\.?\s*|Episode\s+)(\d{1,4})(?:v\d+)?\b"#) {
            title = Self.clean(match[1]); season = Int(match[2]); episode = Int(match[3])
        } else if let match = base.match(#"(?i)^(.+?)[ ._–-]+(\d{1,2})x(\d{1,4})\b"#) {
            title = Self.clean(match[1]); season = Int(match[2]); episode = Int(match[3])
        } else if let match = base.match(#"(?i)^(.+?)\s+[–-]\s*(\d{1,4})(?:v\d+)?(?:\b|$)"#) {
            let header = Self.clean(match[1])
            season = SeasonNumber.first(in: header)
            title = header; episode = Int(match[2])
        } else if let match = base.match(#"(?i)^(.+?)[ ._-]+S(\d{1,2})\b"#) {
            title = Self.clean(match[1]); season = Int(match[2]); episode = nil
        } else {
            title = Self.clean(base); season = nil; episode = nil
        }
    }

    static func clean(_ raw: String) -> String {
        raw.replacingPattern(#"\[[^\]]*\]"#)
            .replacingPattern(#"(?i)\s*\([^)]*(?:1080p|720p|HEVC|AV1|x26[45]|Blu.ray)[^)]*\)"#)
            .replacingPattern(#"(?i)[. _-]+(?:2160p|1080p|720p|480p|WEB[- .]?DL|BluRay|HEVC|AV1)\b.*$"#)
            .replacingOccurrences(of: "_", with: " ")
            .replacingPattern(#"(?<=\w)\.(?=\w)"#, with: " ")
            .replacingPattern(#"^[\s-]+|[\s-]+$"#)
            .replacingPattern(#"\s+"#, with: " ")
    }
}

struct Episode: Identifiable, Equatable, Sendable {
    var id: String { url.path }
    var url: URL
    var title: String
    var showID: String
    var season: Int?
    var number: Int?
    var absolute: String { season.map { "Saison \($0) · " } ?? "" }
    var display: String { number.map { "\(absolute)Épisode \($0)" } ?? title }
    var progressID: String {
        guard let number else { return id }
        return "\(showID)/\(season ?? 0)/\(number)"
    }
}

struct Series: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var query: String
    var episodes: [Episode]
    var downloadOnly = false
}

struct Progress: Codable, Equatable {
    var seconds: Double = 0
    var duration: Double = 0
    var watched = false
    var updated = Date.distantPast
    var fraction: Double { duration > 0 ? min(1, max(0, seconds / duration)) : 0 }
}

struct ShowPreference: Codable {
    var title = ""
    var query = ""
    var subtitle = ""
    var rating: Double?
    var watchlist = false
    var aniListID: Int?
    var nautiljonURL: String?
}

struct LocalState: Codable {
    var history: [String: Progress] = [:]
    var shows: [String: ShowPreference] = [:]
    var subtitleDelays: [String: Double] = [:]
    var synchronizedSubtitles: [String: String]?
    var downloadFolders: [String: String]?
    var introPreferences: [String: IntroPreference]?
    var transferSeasons: [String: String]?
    var importedRatings: [String: Double] = [:]
    var nautiljonSeen: Set<String>?
    var nautiljonWatchlist: [NautiljonTitle]?
    var localSkips: [String: [SavedSegment]] = [:]
}

struct NautiljonTitle: Codable {
    var titles: [String]
    var date: String
    var priority: Int
    var rating: Double?
    var status: String
    var keys: Set<String> { Set(titles.map(\.normalized).filter { !$0.isEmpty }) }
}

struct SavedSegment: Codable {
    var kind: String
    var start: Double
    var end: Double
}

extension FileManager {
    static var support: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Yoru Public", isDirectory: true)
    }
}

enum Indexer {
    static let extensions = Set(["mkv", "mp4", "mov", "avi", "webm", "m4v", "ts", "m2ts", "wmv", "mpg", "flv"])
    static let musicVideos = #"(?i)(?:^|[\s\[\]_.-])(?:NCOP|NCED|creditless|sample|trailer)(?:[\d\s\[\]_.-]|$)"#

    static func scan(_ folder: URL, downloadFolders: [String: String] = [:], excluding activePaths: Set<String> = []) -> [Series] {
        let manager = FileManager.default
        guard let files = manager.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var entries: [String: Series] = [:]
        for case let url as URL in files {
            guard extensions.contains(url.pathExtension.lowercased()),
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  url.lastPathComponent.match(musicVideos) == nil else { continue }
            guard !activePaths.contains(where: { url.path == $0 || url.path.hasPrefix($0 + "/") }) else { continue }
            let info = ReleaseName(url.lastPathComponent)
            if info.episode == nil, url.lastPathComponent.match(#"(?i)(?:^|[ ._-])(?:OP|ED)\d+(?:v\d+)?(?=$|[ ._\[])"#) != nil { continue }
            let relative = url.path.dropFirst(folder.path.count).split(separator: "/").map(String.init)
            let containers = Array(relative.dropLast())
            let parent = containers.first.map(ReleaseName.init)
            let genericFolders = Set(["tv", "anime", "animes", "shows", "films", "movies", "yoru", "downloads"])
            let showFolder = parent.flatMap { genericFolders.contains($0.title.normalized) ? nil : $0 }
            let directorySeason = containers.compactMap {
                SeasonNumber.first(in: $0)
            }.last
            let downloadedShow = containers.first == "Yoru" && containers.count >= 2 ? containers[1] : nil
            let quickFolder = downloadedShow.flatMap { _ in containers.count >= 3 && containers[2].hasPrefix("Saison ")
                && SeasonNumber.first(in: containers[2]) != nil ? downloadedShow : nil }
            let label = showFolder?.title.replacingPattern(#"(?i)\s+(?:S|season\s+|saison\s+)\d{1,2}$"#) ?? quickFolder ?? info.title
            let alias = downloadedShow.flatMap { downloadFolders[$0] }
            let id = alias ?? label.normalized.nonEmpty ?? url.path
            let number = info.episode ?? (containers.isEmpty ? nil : url.deletingPathExtension().lastPathComponent.match(#"^\s*(\d{1,4})\s*$"#).flatMap { Int($0[1]) })
            let display = number != nil && Int(info.title) != nil ? label : info.title.nonEmpty ?? label
            let quickSeason = quickFolder == nil ? nil : SeasonNumber.first(in: containers[2])
            let episode = Episode(url: url, title: display, showID: id, season: quickSeason ?? info.season ?? directorySeason ?? showFolder?.season, number: number)
            if entries[id] == nil {
                entries[id] = Series(id: id, title: label, query: quickFolder ?? (info.episode == nil ? label : display), episodes: [], downloadOnly: containers.first == "Yoru")
            } else if containers.first != "Yoru", entries[id]?.downloadOnly == true {
                entries[id]?.title = label
                entries[id]?.query = info.episode == nil ? label : display
                entries[id]?.downloadOnly = false
            }
            entries[id]?.episodes.append(episode)
        }
        return entries.values.map { item in
            var item = item
            item.episodes.sort {
                if ($0.season ?? 0) != ($1.season ?? 0) { return ($0.season ?? 0) < ($1.season ?? 0) }
                if ($0.number ?? Int.max) != ($1.number ?? Int.max) { return ($0.number ?? Int.max) < ($1.number ?? Int.max) }
                return $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
            }
            return item
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    static func nautiljon(_ url: URL) throws -> [NautiljonTitle] {
        let csv = try String(contentsOf: url, encoding: .utf8).replacingOccurrences(of: "\u{FEFF}", with: "")
        let rows = csvRows(csv)
        let headings = rows.first?.map(\.normalized) ?? []
        guard let titleIndex = headings.firstIndex(of: "titre") else { throw Notice("La colonne Titre manque dans l’export Nautiljon.") }
        let noteIndex = headings.firstIndex(of: "manote") ?? headings.firstIndex(of: "note")
        return rows.dropFirst().compactMap { fields in
            func cell(_ column: String) -> String {
                guard let index = headings.firstIndex(of: column), fields.indices.contains(index) else { return "" }
                return fields[index].trimmed
            }
            guard fields.indices.contains(titleIndex) else { return nil }
            // Older three-column exports sometimes leave semicolons in titles unquoted.
            let legacy = headings == ["annee", "titre", "note"]
            let title = legacy && fields.count >= 3 ? fields[titleIndex..<(fields.count - 1)].joined(separator: ";") : fields[titleIndex]
            let titles = [title.trimmed, cell("titrealternatif"), cell("titreoriginal")].filter { !$0.isEmpty }
            guard !titles.isEmpty else { return nil }
            let rating = (legacy ? fields.indices.last : noteIndex).flatMap { index in
                fields.indices.contains(index) ? Double(fields[index].trimmed.replacingOccurrences(of: ",", with: ".")) : nil
            }.flatMap { (0...10).contains($0) ? $0 : nil }
            let date = cell("datedajout").split(separator: "/").reversed().map {
                $0.count == 1 ? "0" + $0 : String($0)
            }.joined()
            return NautiljonTitle(titles: titles, date: date, priority: Int(cell("priorite")) ?? 0,
                                  rating: rating, status: cell("statut").normalized)
        }
    }

    private static func csvRows(_ csv: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var value = ""
        var quoted = false
        var characters = csv.makeIterator()
        var next = characters.next()
        while let character = next {
            next = characters.next()
            if character == "\"" && (quoted || value.isEmpty) {
                if quoted, next == "\"" {
                    value.append(character)
                    next = characters.next()
                } else { quoted.toggle() }
            } else if !quoted, character == ";" {
                row.append(value)
                value = ""
            } else if !quoted, character.isNewline {
                if !row.isEmpty || !value.isEmpty { rows.append(row + [value]) }
                row = []
                value = ""
            } else { value.append(character) }
        }
        if !row.isEmpty || !value.isEmpty { rows.append(row + [value]) }
        return rows
    }
}
