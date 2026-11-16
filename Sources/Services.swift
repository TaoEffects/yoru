import Foundation
import CryptoKit
import Security

struct Notice: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

enum Vault {
    static func get(_ key: String) -> String {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword, kSecAttrService: "io.github.taoeffects.yoru",
            kSecAttrAccount: key, kSecReturnData: true
        ] as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    static func set(_ key: String, _ value: String) {
        let query = [kSecClass: kSecClassGenericPassword, kSecAttrService: "io.github.taoeffects.yoru", kSecAttrAccount: key] as CFDictionary
        SecItemDelete(query)
        guard !value.isEmpty else { return }
        SecItemAdd([
            kSecClass: kSecClassGenericPassword, kSecAttrService: "io.github.taoeffects.yoru",
            kSecAttrAccount: key, kSecValueData: Data(value.utf8)
        ] as CFDictionary, nil)
    }
}

enum HTTP {
    struct Status: LocalizedError {
        let host: String
        let code: Int
        let retryAfter: Int?
        var errorDescription: String? { "\(host) indisponible (HTTP \(code))." }
    }

    static func endpoint(_ url: String, _ query: [String: String] = [:]) -> URL {
        var components = URLComponents(string: url)!
        if !query.isEmpty { components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        return components.url!
    }

    static func data(_ url: URL, headers: [String: String] = [:], body: Data? = nil, session: URLSession = .shared, limit: Int = 4_000_000) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Yoru v0.1", forHTTPHeaderField: "User-Agent")
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        if let body { request.httpMethod = "POST"; request.httpBody = body }
        let (data, response) = try await session.data(for: request)
        let status = response as? HTTPURLResponse
        let code = status?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            let delay = status?.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            throw Status(host: url.host ?? "Service", code: code, retryAfter: delay)
        }
        guard data.count <= limit else { throw Notice("Réponse trop volumineuse.") }
        return data
    }

    static func json(_ data: Data) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Notice("Réponse inattendue.") }
        return value
    }
}

struct Anime: Decodable, Identifiable, Equatable {
    struct Title: Decodable, Equatable { var romaji: String?; var english: String?; var native: String? }
    struct Cover: Decodable, Equatable { var large: URL?; var color: String? }
    struct Next: Decodable, Equatable { var episode: Int; var airingAt: Double }
    struct Tag: Decodable, Equatable {
        var name: String
        var rank: Int?
        var isMediaSpoiler: Bool?
        var isGeneralSpoiler: Bool?
    }
    struct Relations: Decodable, Equatable {
        struct Edge: Decodable, Equatable {
            struct Node: Decodable, Equatable { var id: Int; var title: Title; var type: String; var coverImage: Cover?; var format: String?; var status: String? }
            var relationType: String
            var node: Node
        }
        var edges: [Edge]
    }
    var id: Int
    var idMal: Int?
    var format: String?
    var status: String?
    var countryOfOrigin: String?
    var synonyms: [String]?
    var coverImage: Cover?
    var bannerImage: URL?
    var title: Title
    var episodes: Int?
    var description: String?
    var averageScore: Int?
    var genres: [String]?
    var tags: [Tag]?
    var nextAiringEpisode: Next?
    var relations: Relations?
    var name: String { title.romaji ?? title.english ?? title.native ?? "Anime \(id)" }
    var isFilm: Bool { format == "MOVIE" }
    var synopsis: String? {
        description?
            .replacingPattern(#"(?i)<br\s*/?>\s*"#, with: "\n")
            .replacingPattern(#"(?i)</p\s*>"#, with: "\n\n")
            .replacingPattern(#"<[^>]+>"#)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#039;", with: "’")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmed
    }
    var titleKeys: Set<String> {
        let names = [title.romaji, title.english, title.native].compactMap { $0 } + (synonyms ?? [])
        return Set(names.map(\.normalized).filter { !$0.isEmpty })
    }
}

enum Catalog {
    private static let profileFields = "id format status idMal episodes title { romaji english native } synonyms coverImage { large color } bannerImage nextAiringEpisode { episode airingAt }"
    private static let summaryFields = "description(asHtml: true) averageScore"
    private static let detailFields = "genres tags { name rank isMediaSpoiler isGeneralSpoiler }"
    private struct Envelope: Decodable {
        struct Result: Decodable {
            struct Page: Decodable { var media: [Anime] }
            var Page: Page?
            var Media: Anime?
        }
        var data: Result?
    }

    static func lookup(_ title: String, id: Int? = nil, details: Bool = false) async throws -> [Anime] {
        let fields = "id idMal format status countryOfOrigin synonyms title { romaji english native } coverImage { large color } bannerImage episodes nextAiringEpisode { episode airingAt } relations { edges { relationType node { id title { romaji english native } type format status coverImage { large color } } } }"
            + (details ? " \(summaryFields) \(detailFields)" : "")
        let query = id == nil
            ? "query($query: String!) { Page(perPage: 6) { media(search: $query, type: ANIME) { \(fields) } } }"
            : "query($id: Int!) { Media(id: $id, type: ANIME) { \(fields) } }"
        let variables: [String: Any] = id.map { ["id": $0] } ?? ["query": title]
        let body = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])
        let response = try await HTTP.data(URL(string: "https://graphql.anilist.co")!, headers: ["Content-Type": "application/json"], body: body)
        guard let result = try JSONDecoder().decode(Envelope.self, from: response).data else {
            throw Notice("AniList n’a pas renvoyé de fiche lisible.")
        }
        return result.Page?.media ?? result.Media.map { [$0] } ?? []
    }

    static func matchWatchlist(_ rows: [NautiljonTitle], details: Bool = false) async throws -> [Anime?] {
        let entries = try await lookupWatchlist(rows.map { $0.titles.first ?? "" }, details: details)
        var matches = zip(rows, entries).map { row, candidates in
            candidates.first { !$0.titleKeys.isDisjoint(with: row.keys) }
        }
        for titleIndex in 1..<(max(1, rows.map(\.titles.count).max() ?? 1)) {
            let alternatives = rows.indices.filter { matches[$0] == nil && rows[$0].titles.indices.contains(titleIndex) }
            guard !alternatives.isEmpty else { continue }
            try Task.checkCancellation()
            let candidates = try await lookupWatchlist(alternatives.map { rows[$0].titles[titleIndex] }, details: details)
            for (index, entries) in zip(alternatives, candidates) {
                matches[index] = entries.first { !$0.titleKeys.isDisjoint(with: rows[index].keys) }
            }
        }
        return matches
    }

    private static func lookupWatchlist(_ names: [String], details: Bool) async throws -> [[Anime]] {
        guard !names.isEmpty else { return [] }
        let indices = Array(names.indices)
        let declarations = indices.map { "$name\($0): String!" }.joined(separator: ", ")
        let fields = details ? "\(profileFields) \(summaryFields) \(detailFields)" : profileFields
        let selections = indices.map { "entry\($0): Page(perPage: 4) { media(search: $name\($0), type: ANIME) { \(fields) } }" }
        let variables = Dictionary(uniqueKeysWithValues: indices.map { ("name\($0)", names[$0]) })
        let body = try JSONSerialization.data(withJSONObject: [
            "query": "query(\(declarations)) { \(selections.joined(separator: " ")) }", "variables": variables
        ])
        let data = try await HTTP.data(URL(string: "https://graphql.anilist.co")!,
                                       headers: ["Content-Type": "application/json"], body: body)
        struct Batch: Decodable { var data: [String: Envelope.Result.Page]? }
        let result = try JSONDecoder().decode(Batch.self, from: data)
        guard let entries = result.data else { throw Notice("AniList n’a pas renvoyé de fiches lisibles.") }
        return indices.map { entries["entry\($0)"]?.media ?? [] }
    }

    static func discover(basedOn id: Int?) async throws -> [Anime] {
        let fields = profileFields + " " + summaryFields
        let query: String
        let variables: [String: Any]
        if let id {
            query = "query($id: Int!) { Media(id: $id, type: ANIME) { recommendations(perPage: 10, sort: RATING_DESC) { nodes { mediaRecommendation { \(fields) } } } } }"
            variables = ["id": id]
        } else {
            query = "{ Page(perPage: 12) { media(type: ANIME, sort: TRENDING_DESC, isAdult: false) { \(fields) } } }"
            variables = [:]
        }
        let body = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])
        let data = try await HTTP.data(URL(string: "https://graphql.anilist.co")!, headers: ["Content-Type": "application/json"], body: body)
        struct Result: Decodable {
            struct Payload: Decodable {
                struct Media: Decodable {
                    struct Recommendations: Decodable {
                        struct Node: Decodable { let mediaRecommendation: Anime? }
                        let nodes: [Node?]
                    }
                    let recommendations: Recommendations
                }
                struct Page: Decodable { let media: [Anime] }
                let Media: Media?
                let Page: Page?
            }
            let data: Payload?
        }
        let result = try JSONDecoder().decode(Result.self, from: data).data
        return result?.Page?.media ?? result?.Media?.recommendations.nodes.compactMap { $0?.mediaRecommendation } ?? []
    }

    static func skip(malID: Int, episode: Int, duration: Double) async throws -> [SkipSegment] {
        var url = URLComponents(string: "https://api.aniskip.com/v2/skip-times/\(malID)/\(episode)")!
        url.queryItems = [URLQueryItem(name: "episodeLength", value: "0")] + ["op", "ed"].map { URLQueryItem(name: "types", value: $0) }
        struct Response: Decodable {
            struct Entry: Decodable {
                struct Interval: Decodable { var startTime: Double; var endTime: Double }
                var interval: Interval; var episodeLength: Double; var skipType: String
            }
            var results: [Entry]?
        }
        let data = try await HTTP.data(url.url!)
        return (try JSONDecoder().decode(Response.self, from: data).results ?? []).compactMap { entry in
            let segment = entry.interval
            guard abs(entry.episodeLength - duration) < 2, segment.startTime >= 0,
                  segment.endTime <= duration, (8...300).contains(segment.endTime - segment.startTime) else { return nil }
            return SkipSegment(kind: entry.skipType, start: segment.startTime, end: segment.endTime)
        }
    }
}

enum ProfileEpisodes {
    struct Episode: Identifiable {
        let number: Int
        let frenchTitle: String?
        var id: Int { number }
    }

    private struct Feed: Decodable {
        struct Mapping: Decodable { let anilistId: Int? }
        struct Entry: Decodable { let title: [String: String]? }
        let mappings: Mapping
        let episodes: [String: Entry]?
    }

    static func list(for anime: Anime) async throws -> [Episode] {
        guard !anime.isFilm, anime.status != "NOT_YET_RELEASED", anime.status != "CANCELLED" else { return [] }
        let url = HTTP.endpoint("https://api.ani.zip/mappings", ["anilist_id": String(anime.id)])
        let data = try await HTTP.data(url)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let feed = try decoder.decode(Feed.self, from: data)
        guard feed.mappings.anilistId == anime.id else { return [] }
        let aired = anime.status == "RELEASING" ? anime.nextAiringEpisode.map { $0.episode - 1 } : nil
        let upperLimit = aired ?? anime.episodes ?? Int.max
        return (feed.episodes ?? [:]).compactMap { key, episode -> Episode? in
            guard let number = Int(key), number > 0, number <= upperLimit else { return nil }
            let title = (episode.title?["fr"] ?? episode.title?["fr-FR"])?.trimmed.nonEmpty
            return Episode(number: number, frenchTitle: title)
        }.sorted { $0.number < $1.number }
    }
}

struct SubtitleCandidate: Identifiable, Equatable {
    var id: String
    var name: String
    var language: String
    var exact: Bool
    var url: URL?
    var openID: Int?
}

enum SubtitleService {
    static let types = Set(["srt", "ass", "ssa", "vtt"])
    private static let openBase = "https://api.opensubtitles.com/api/v1"

    static func candidates(_ episode: Episode, language: String, anime: Anime?) async throws -> [SubtitleCandidate] {
        if language == "ja", let anime, let number = episode.number {
            let key = Vault.get("jimaku")
            if !key.isEmpty {
                let options = try await jimaku(anime.id, number, key: key)
                if !options.isEmpty {
                    let videoName = episode.url.deletingPathExtension().lastPathComponent.normalized
                    return options.map { candidate in
                        var result = candidate
                        let subtitleName = URL(fileURLWithPath: candidate.name).deletingPathExtension().lastPathComponent
                            .replacingPattern(#"(?i)[. _-](ja|jpn|jp)(?:[. _-](sdh|cc))?$"#).normalized
                        result.exact = subtitleName == videoName
                        return result
                    }.sorted { $0.exact && !$1.exact }
                }
            }
        }
        let key = Vault.get("open-key")
        guard !key.isEmpty else { throw Notice("Ajoute une clé \(language == "ja" ? "Jimaku ou OpenSubtitles" : "OpenSubtitles") dans Réglages.") }
        struct Search: Decodable {
            struct Result: Decodable {
                struct Attributes: Decodable {
                    struct File: Decodable { var file_id: Int; var file_name: String }
                    var files: [File]; var moviehash_match: Bool?
                }
                var attributes: Attributes
            }
            var data: [Result]
        }
        let headers = ["Api-Key": key]
        func fetch(_ query: [String: String], exact: Bool) async throws -> [SubtitleCandidate] {
            let response = try await HTTP.data(HTTP.endpoint(openBase + "/subtitles", query), headers: headers)
            return try JSONDecoder().decode(Search.self, from: response).data.flatMap { result in
                result.attributes.files.map { file in
                    SubtitleCandidate(id: "os-\(file.file_id)", name: file.file_name, language: language,
                        exact: exact && result.attributes.moviehash_match == true, openID: file.file_id)
                }
            }
        }
        if let hash = try? movieHash(episode.url) {
            let exact = try await fetch(["moviehash": hash, "languages": language], exact: true).filter(\.exact)
            if !exact.isEmpty { return exact }
        }
        var query = ["query": anime?.title.english ?? episode.title, "languages": language]
        if let number = episode.number { query["episode_number"] = String(number) }
        if let season = episode.season { query["season_number"] = String(season) }
        return Array(try await fetch(query, exact: false).prefix(15))
    }

    private static func jimaku(_ anime: Int, _ episode: Int, key: String) async throws -> [SubtitleCandidate] {
        struct Entry: Decodable { var id: Int }
        struct File: Decodable { var name: String; var url: URL; var size: Int }
        let headers = ["Authorization": key]
        let matches = try await HTTP.data(HTTP.endpoint("https://jimaku.cc/api/entries/search", ["anilist_id": String(anime)]), headers: headers)
        let entries = try JSONDecoder().decode([Entry].self, from: matches)
        var candidates: [SubtitleCandidate] = []
        for entry in entries.prefix(3) {
            let response = try await HTTP.data(HTTP.endpoint("https://jimaku.cc/api/entries/\(entry.id)/files", ["episode": String(episode)]), headers: headers)
            candidates += try JSONDecoder().decode([File].self, from: response).filter {
                types.contains(URL(fileURLWithPath: $0.name).pathExtension.lowercased()) && $0.size < 4_000_000
            }.map { SubtitleCandidate(id: $0.url.absoluteString, name: $0.name, language: "ja", exact: false, url: $0.url) }
        }
        return Array(candidates.prefix(20))
    }

    static func fetch(_ candidate: SubtitleCandidate, for episode: Episode) async throws -> URL {
        let url: URL
        var headers: [String: String] = [:]
        if let directURL = candidate.url {
            url = directURL
            if url.host == "jimaku.cc" { headers["Authorization"] = Vault.get("jimaku") }
        } else if let id = candidate.openID {
            headers = ["Api-Key": Vault.get("open-key"), "Content-Type": "application/json"]
            let user = Vault.get("open-user")
            let password = Vault.get("open-password")
            if !user.isEmpty, !password.isEmpty {
                let body = try JSONSerialization.data(withJSONObject: ["username": user, "password": password])
                let login = try await HTTP.json(HTTP.data(URL(string: openBase + "/login")!, headers: headers, body: body))
                guard let token = login["token"] as? String else { throw Notice("Connexion OpenSubtitles refusée.") }
                headers["Authorization"] = "Bearer \(token)"
            }
            let body = try JSONSerialization.data(withJSONObject: ["file_id": id])
            let result = try await HTTP.json(HTTP.data(URL(string: openBase + "/download")!, headers: headers, body: body))
            guard let link = result["link"] as? String, let download = URL(string: link) else { throw Notice("Sous-titre indisponible.") }
            url = download
            headers = [:]
        } else { throw Notice("Sous-titre indisponible.") }
        guard url.scheme == "https" else { throw Notice("Lien de sous-titre invalide.") }
        let data = try await HTTP.data(url, headers: headers)
        let ext = URL(fileURLWithPath: candidate.name).pathExtension.lowercased()
        guard types.contains(ext), !data.isEmpty else { throw Notice("Format de sous-titre non pris en charge.") }
        let directory = cacheDirectory(episode)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = candidate.language + "-" + digest(candidate.id) + "." + ext
        let destination = directory.appendingPathComponent(name)
        try data.write(to: destination, options: .atomic)
        return destination
    }

    static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }
    static func version(_ episode: Episode) -> String {
        let attributes = try? FileManager.default.attributesOfItem(atPath: episode.url.path)
        return digest(episode.url.path + "|" + (attributes?[.size] as? NSNumber ?? 0).stringValue)
    }
    static func cacheDirectory(_ episode: Episode) -> URL { FileManager.support.appendingPathComponent("Sous-titres").appendingPathComponent(version(episode)) }

    private static func movieHash(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let size = try file.seekToEnd()
        let length = 65_536
        guard size >= UInt64(length * 2) else { throw Notice("Vidéo trop courte.") }
        var hash = size
        for offset in [0, size - UInt64(length)] {
            try file.seek(toOffset: offset)
            let data = try file.read(upToCount: length) ?? Data()
            guard data.count == length else { throw Notice("Empreinte vidéo indisponible.") }
            data.withUnsafeBytes { bytes in
                for i in stride(from: 0, to: length, by: 8) { hash &+= UInt64(littleEndian: bytes.loadUnaligned(fromByteOffset: i, as: UInt64.self)) }
            }
        }
        return String(format: "%016llx", hash)
    }
}
