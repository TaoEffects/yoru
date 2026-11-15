import Foundation

struct NyaaSource: Identifiable {
    let id: String
    let label: String
    let sample: String
    var url: URL { URL(string: id == "trusted" ? "https://nyaa.si/?f=2" : "https://nyaa.si/user/" + id)! }

    static let defaults = "trusted"
    static let catalog: [NyaaSource] = [
        .init(id: "trusted", label: "Publications vérifiées", sample: "Résultats marqués comme vérifiés sur Nyaa"),
        .init(id: "Judas", label: "Judas", sample: "Ranma 1/2 (2024) · S03E07 · HEVC"),
        .init(id: "NekoTrix", label: "Trix", sample: "Blue Box · S02E06 · Ao no Hako · AV1"),
        .init(id: "Ironclad", label: "Ironclad", sample: "Gundam GQuuuuuuX · S01 · AV1"),
        .init(id: "DKB0512", label: "DKB", sample: "Magic Repo Man · S01E07 · HEVC"),
        .init(id: "AkihitoSubsWeeklies", label: "ASW", sample: "Ace of Diamond Act II S2 - 19 · HEVC"),
        .init(id: "sff", label: "Anime Time", sample: "Magical Explorer · S01E08 · HEVC"),
        .init(id: "Ember_Encodes", label: "EMBER", sample: "Frieren · S02E09 · HEVC"),
        .init(id: "animencodes", label: "Cleo", sample: "Shangri-La Frontier 2nd Season · HEVC"),
        .init(id: "neoborn", label: "neoDESU", sample: "SPY × FAMILY · Season 1–3 + Movie"),
        .init(id: "Erai-raws", label: "Erai-raws", sample: "Ao Ashi Season 2 - 07 · MultiSub"),
        .init(id: "SubsPlease", label: "SubsPlease", sample: "Ao Ashi S2 - 07 · 1080p")
    ]

    static func account(_ value: String) -> String? {
        let key = value.trimmed
        if let match = catalog.first(where: { $0.id.normalized == key.normalized || $0.label.normalized == key.normalized }) { return match.id }
        return key.match(#"^[A-Za-z0-9_-]{1,32}$"#) != nil ? key : nil
    }

    static func accounts(_ input: String) -> [String] {
        var seen: Set<String> = []
        return input.split(separator: ",").compactMap { account(String($0)) }.filter {
            seen.insert($0.lowercased()).inserted
        }
    }
}

enum SeasonNumber {
    static func first(in name: String) -> Int? {
        for regex in [#"(?i)\b(?:season\s*|saison\s*|s)(\d{1,2})(?=\b|e\d)"#,
                      #"(?i)\b(\d{1,2})(?:st|nd|rd|th)\s+season\b"#] {
            if let value = name.match(regex).flatMap({ Int($0[1]) }) { return value }
        }
        return nil
    }

    static func base(_ name: String) -> String {
        name.replacingPattern(#"(?i)[ ._-]+(?:(?:season|saison)\s*\d{1,2}|s\d{1,2}|\d{1,2}(?:st|nd|rd|th)\s+season)(?:\s+(?:part|cour)\s*\d+)?$"#).trimmed
    }

    static func suffix(_ number: Int) -> String {
        let endings = [1: "st", 2: "nd", 3: "rd"]
        let ending = (11...13).contains(number % 100) ? "th" : endings[number % 10, default: "th"]
        return String(number) + ending + " Season"
    }
}
