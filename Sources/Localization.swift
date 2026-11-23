import Foundation
import SwiftUI

enum YoruLanguage: String, CaseIterable, Identifiable {
    case system, fr, en, ja, es, ko
    var id: String { rawValue }
    var name: String {
        switch self {
        case .system: return L.tr("Système")
        case .fr: return "Français"
        case .en: return "English"
        case .ja: return "日本語"
        case .es: return "Español"
        case .ko: return "한국어"
        }
    }
}

enum L {
    static var code: String {
        let selected = UserDefaults.standard.string(forKey: "interfaceLanguage") ?? "system"
        if ["fr", "en", "ja", "es", "ko"].contains(selected) { return selected }
        let preferred = Locale.preferredLanguages.first ?? "en"
        return ["fr", "en", "ja", "es", "ko"].first { preferred.hasPrefix($0) } ?? "en"
    }

    private final class Catalog: NSObject {
        let strings: [String: String]
        let templates: [(NSRegularExpression, String, [String])]
        init(code: String) {
            let url = Bundle.main.url(forResource: code, withExtension: "json", subdirectory: "Localizations")
            let values = url.flatMap { try? Data(contentsOf: $0) }.flatMap {
                try? JSONDecoder().decode([String: String].self, from: $0)
            } ?? [:]
            strings = values
            templates = values.keys.filter { $0.contains("__YORU") }.sorted { $0.count > $1.count }.compactMap { source in
                let tokens = source.components(separatedBy: "__YORU").dropFirst().compactMap {
                    $0.components(separatedBy: "__").first.map { "__YORU" + $0 + "__" }
                }
                var pattern = NSRegularExpression.escapedPattern(for: source)
                for token in tokens { pattern = pattern.replacingOccurrences(of: NSRegularExpression.escapedPattern(for: token), with: "(.+?)") }
                guard let regex = try? NSRegularExpression(pattern: "^" + pattern + "$", options: [.dotMatchesLineSeparators]) else { return nil }
                return (regex, values[source] ?? source, tokens)
            }
        }
    }
    private static let cache = NSCache<NSString, Catalog>()

    static func tr(_ source: String) -> String {
        let language = code
        guard language != "fr" else { return source }
        let key = language as NSString
        let catalog: Catalog
        if let saved = cache.object(forKey: key) { catalog = saved }
        else { catalog = Catalog(code: language); cache.setObject(catalog, forKey: key) }
        if let value = catalog.strings[source] { return value }
        let range = NSRange(source.startIndex..., in: source)
        for (regex, translated, tokens) in catalog.templates {
            guard let match = regex.firstMatch(in: source, range: range) else { continue }
            var result = translated
            for (index, token) in tokens.enumerated() {
                if let part = Range(match.range(at: index + 1), in: source) {
                    result = result.replacingOccurrences(of: token, with: String(source[part]))
                }
            }
            return result
        }
        return source
    }
}

struct LanguageChoice: View {
    @AppStorage("interfaceLanguage") private var language = "system"
    var body: some View {
        Picker(L.tr("Langue"), selection: $language) {
            ForEach(YoruLanguage.allCases) { item in Text(item.name).tag(item.rawValue) }
        }
        .pickerStyle(.menu)
        .font(YoruTypography.text(17, strong: true))
        .padding(10)
        .frame(maxWidth: 300)
        .accessibilityLabel(L.tr("Langue"))
    }
}
