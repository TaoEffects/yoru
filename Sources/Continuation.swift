import Foundation

struct SeasonOffer: Equatable {
    var showID: String
    var current: Int
    var next: Int
    var finale: Int
    var title: String
    var cover: URL?
    var catalogID: Int
    var announced: Bool
    var key: String { showID + "|" + String(next) }

    func isNearFinale(_ number: Int?) -> Bool {
        number.map { (max(1, finale - 1)...finale).contains($0) } ?? false
    }
}

enum SeasonCatalog {
    private static let television = Set(["TV", "TV_SHORT", "ONA"])

    static func resolve(_ show: Series, season: Int, catalogID: Int?) async throws -> SeasonOffer? {
        let base = SeasonNumber.base(show.query)
        let titles = Set([base, SeasonNumber.base(show.title)].map(\.normalized).filter { !$0.isEmpty })
        guard !base.isEmpty, (1...98).contains(season) else { return nil }
        let number = season + 1
        func matches(_ item: Anime) -> Bool {
            guard let format = item.format, television.contains(format) else { return false }
            return [item.title.romaji, item.title.english, item.title.native].compactMap { $0 }.contains { title in
                let matchingBase = titles.contains { title.normalized.hasPrefix($0) }
                return matchingBase && (SeasonNumber.first(in: title) ?? 1) == season
            }
        }
        var current: Anime?
        if let catalogID, let entry = try await Catalog.lookup(base, id: catalogID).first {
            if matches(entry) || (season == 1 && [entry.title.romaji, entry.title.english].compactMap({ $0 }).allSatisfy({ SeasonNumber.first(in: $0) == nil })) {
                current = entry
            }
        }
        if current == nil {
            let query = season == 1 ? base : base + " " + SeasonNumber.suffix(season)
            current = try await Catalog.lookup(query).filter(matches).sorted {
                let lhs = $0.title.english?.normalized == (base + " Season " + String(season)).normalized
                let rhs = $1.title.english?.normalized == (base + " Season " + String(season)).normalized
                return lhs && !rhs
            }.first
        }
        guard let current, let count = current.episodes, count > 1 else { return nil }
        // A movie, special or another cour of the same season does not advance the numbered season.
        let sequel = current.relations?.edges.first { edge in
            edge.relationType == "SEQUEL" && edge.node.type == "ANIME" &&
                edge.node.format.map(television.contains) == true &&
                [edge.node.title.romaji, edge.node.title.english].compactMap { $0 }.contains { SeasonNumber.first(in: $0) == number }
        }?.node
        guard let sequel, let title = sequel.title.english ?? sequel.title.romaji ?? sequel.title.native,
              sequel.status != "CANCELLED" else { return nil }
        return SeasonOffer(showID: show.id, current: season, next: number, finale: count, title: title,
                           cover: sequel.coverImage?.large, catalogID: sequel.id, announced: sequel.status == "NOT_YET_RELEASED")
    }
}
