import SwiftUI
import NaturalLanguage
import Translation

struct AnimePresentation: Identifiable {
    let id = UUID()
    let names: [String]
    let entry: Anime?
    var season: SeasonOffer? = nil
    var title: String { entry?.title.english ?? names.first ?? entry?.name ?? "Anime" }
}

struct AnimeProfileView: View {
    @Environment(\.miniPlaybackClearance) private var miniPlaybackClearance
    @ObservedObject var model: Model
    let presentation: AnimePresentation
    let navigationClearance: CGFloat
    @Environment(\.yoruTheme) private var theme
    @Environment(\.yoruLabels) private var labels
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("lightweight") private var lightweight = false
    @State private var loaded: Anime?
    @State private var loading = true
    @State private var loadFailed = false
    @State private var retry = 0
    @State private var episodes: [ProfileEpisodes.Episode] = []

    private var entry: Anime? { loaded ?? presentation.entry }
    private var title: String { entry?.title.english ?? entry?.title.romaji ?? presentation.title }
    private var cover: URL? { entry?.coverImage?.large ?? presentation.season?.cover }
    private var unavailable: Bool {
        presentation.season?.announced == true || entry?.status == "NOT_YET_RELEASED" || entry?.status == "CANCELLED"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Button { model.presentedAnime = nil } label: {
                    Label(labels("Retour"), systemImage: "chevron.left")
                }.buttonStyle(ControlStyle())

                hero

                if let entry { themes(entry) }

                if let french = VerifiedSynopsis.french(for: entry?.id ?? presentation.season?.catalogID) {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeading(title: "Synopsis", compact: true)
                        SynopsisText(text: french)
                    }
                    .frame(maxWidth: 810, alignment: .leading)
                } else if let synopsis = entry?.synopsis, !synopsis.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeading(title: "Synopsis", compact: true)
                        if #available(macOS 15, *) { FrenchSynopsis(original: synopsis).id(synopsis) }
                        else { OriginalSynopsis(original: synopsis, message: "Traduction disponible à partir de macOS 15") }
                    }
                    .frame(maxWidth: 810, alignment: .leading)
                } else if loading {
                    ProgressView(labels("Chargement de la fiche…")).controlSize(.regular)
                } else {
                    Text(labels("Synopsis indisponible")).font(YoruTypography.text(16))
                        .foregroundStyle(theme.mutedText)
                }

                if loadFailed {
                    Button(labels("Recharger la fiche")) { retry += 1 }.buttonStyle(ControlStyle())
                }

                if !episodes.isEmpty {
                    VStack(alignment: .leading, spacing: 11) {
                        SectionHeading(title: "Épisodes", compact: true)
                        ForEach(episodes) { episode in
                            let number = labels("Épisode \(episode.number)")
                            Text(episode.frenchTitle.map { "\(number) · \($0)" } ?? number)
                                .font(YoruTypography.text(17)).foregroundStyle(theme.mutedText)
                        }
                    }
                }
            }
            .frame(maxWidth: 1060, alignment: .leading)
            .padding(.horizontal, 30).padding(.top, navigationClearance + 20).padding(.bottom, 36 + miniPlaybackClearance)
            .frame(maxWidth: .infinity)
        }
        .background { ArtBackdrop(url: entry?.bannerImage ?? cover) }
        .task(id: retry) { await loadDetails() }
        .task(id: entry?.id) {
            guard let entry else { return }
            let list = await (try? ProfileEpisodes.list(for: entry)) ?? []
            if !Task.isCancelled { episodes = list }
        }
    }

    private func themes(_ entry: Anime) -> some View {
        let genres = entry.genres ?? []
        let topics = (entry.tags ?? []).filter {
            $0.isMediaSpoiler != true && $0.isGeneralSpoiler != true && ($0.rank ?? 0) >= 65
                && !genres.contains($0.name)
        }.sorted { ($0.rank ?? 0) > ($1.rank ?? 0) }.prefix(6)
        let names = genres + topics.map(\.name)
        return Group {
            if !names.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeading(title: "Thèmes", compact: true)
                    Text(names.joined(separator: "  ·  "))
                        .font(YoruTypography.text(16, strong: true)).foregroundStyle(theme.accent)
                        .lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 810, alignment: .leading)
            }
        }
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: 23) {
            CoverArt(url: cover, width: 116, height: 164, radius: 13)
            VStack(alignment: .leading, spacing: 13) {
                Text(title).font(YoruTypography.display(43))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let entry {
                    HStack(spacing: 14) {
                        if entry.isFilm {
                            Label(labels("Film"), systemImage: "film")
                        } else if entry.status == "RELEASING", let next = entry.nextAiringEpisode, next.episode > 1 {
                            Label(labels("\(next.episode - 1) épisodes diffusés"), systemImage: "rectangle.stack")
                        } else if let count = entry.episodes, count > 0 {
                            Label(count == 1 ? labels("1 épisode") : labels("\(count) épisodes"), systemImage: "rectangle.stack")
                        }
                        if let score = entry.averageScore {
                            Label("\(score) % · AniList", systemImage: "star")
                        }
                    }
                    .font(YoruTypography.text(16, strong: true)).foregroundStyle(.white.opacity(0.86))
                }
                HStack(spacing: 8) {
                    if unavailable {
                        Text(labels(entry?.status == "CANCELLED" ? "Annulé" : "À venir"))
                    } else {
                        Button {
                            model.downloadPresentedAnime(presentation, entry: entry)
                        } label: {
                            DownloadLabel(title: labels(model.addingTorrent ? "Préparation…" : "Télécharger"),
                                          busy: model.addingTorrent)
                        }
                        .buttonStyle(ControlStyle(accent: true))
                        .disabled(model.addingTorrent)
                        .help(labels(downloadTitle))
                        .accessibilityLabel(labels(downloadTitle))
                        if entry != nil || presentation.season != nil {
                            Button {
                                model.presentedAnime = nil
                                if let season = presentation.season { model.findSeason(season) }
                                else if let entry { model.findRecommendation(Discovery(entry: entry, reason: nil)) }
                            } label: {
                                Label(labels("Versions"), systemImage: "list.bullet")
                            }
                            .buttonStyle(ControlStyle())
                            .disabled(model.addingTorrent)
                            .help(labels("Choisir une version"))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 22).padding(.vertical, 23)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .background {
            GeometryReader { geometry in
                ZStack(alignment: .trailing) {
                    Color(red: 0.105, green: 0.047, blue: 0.082)
                    WideArtwork(url: entry?.bannerImage ?? cover)
                        .frame(width: geometry.size.width * 0.72)
                        .mask(LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing))
                    LinearGradient(colors: [.black.opacity(0.48), .black.opacity(0.25)], startPoint: .leading, endPoint: .trailing)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 23))
        .overlay(RoundedRectangle(cornerRadius: 23).strokeBorder(.white.opacity(0.17)).allowsHitTesting(false))
    }

    private var downloadTitle: String {
        if model.addingTorrent { return "Préparation…" }
        if entry?.isFilm == true { return "Télécharger le film" }
        if entry?.status == "RELEASING" { return "Télécharger les épisodes disponibles" }
        return presentation.season != nil ? "Télécharger la saison" : "Télécharger"
    }

    private func loadDetails() async {
        loading = true
        loadFailed = false
        defer { loading = false }
        if presentation.entry?.description != nil, presentation.entry?.tags != nil { return }
        do {
            let result: Anime?
            if let id = presentation.entry?.id ?? presentation.season?.catalogID {
                result = try await details(title: presentation.title, id: id).first
            } else {
                let keys = Set(presentation.names.map(\.normalized))
                var exact: Anime?
                for name in presentation.names.prefix(2) where exact == nil && !Task.isCancelled {
                    let candidates = try await details(title: name)
                    exact = candidates.first { !$0.titleKeys.isDisjoint(with: keys) }
                }
                result = exact
            }
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion || lightweight ? nil : YoruMotion.pageChange) { loaded = result }
        } catch {
            if !Task.isCancelled { loadFailed = true }
        }
    }

    private func details(title: String, id: Int? = nil) async throws -> [Anime] {
        do { return try await Catalog.lookup(title, id: id, details: true) }
        catch let status as HTTP.Status where status.code == 429 && (1...12).contains(status.retryAfter ?? 0) {
            let delay = status.retryAfter ?? 1
            try await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
            return try await Catalog.lookup(title, id: id, details: true)
        }
    }
}

struct DownloadLabel: View {
    let title: String
    var busy = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("lightweight") private var lightweight = false
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                if busy {
                    ProgressView().controlSize(.small).transition(.opacity)
                } else {
                    Image(systemName: "arrow.down.to.line")
                        .offset(y: hovered && !reduceMotion && !lightweight ? 2 : 0)
                        .transition(.opacity)
                }
            }.frame(width: 19, height: 19).accessibilityHidden(true)
            Text(title).lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
        .onHover { hovered = $0 }
        .animation(reduceMotion || lightweight ? nil : YoruMotion.focus, value: hovered)
        .animation(reduceMotion || lightweight ? nil : YoruMotion.pageChange, value: busy)
    }
}

private enum VerifiedSynopsis {
    static func french(for id: Int?) -> String? {
        switch id {
        case 139498:
            // Crunchyroll France, Scarlet Bond.
            return "Dans le royaume de Raja, à l’ouest de Tempest, la reine Towa s’affaiblit en protégeant son peuple d’une mystérieuse malédiction. Hiiro, un ogre à qui elle a sauvé la vie, part demander l’aide de Limule. Leur rencontre les entraîne au cœur d’un complot qui menace le royaume."
        case 182206:
            // Crunchyroll France, Les larmes de la mer azur.
            return "Après le festival de Tempest, l’impératrice Elmecia invite Limule et ses compagnons à se reposer sur une île de Salion. Le séjour prend une autre tournure lorsqu’ils rencontrent Yura, une jeune femme mystérieuse venue chercher de l’aide."
        default: return nil
        }
    }
}

private struct SynopsisText: View {
    let text: String

    var body: some View {
        Text(text).font(YoruTypography.text(18)).lineSpacing(6)
            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
    }
}

private struct OriginalSynopsis: View {
    let original: String
    let message: String
    @Environment(\.yoruLabels) private var labels
    @Environment(\.yoruTheme) private var theme
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if expanded { SynopsisText(text: original) }
            else { Text(labels(message)).foregroundStyle(theme.mutedText) }
            Button(labels(expanded ? "Masquer l’original" : "Lire l’original")) { expanded.toggle() }
                .buttonStyle(ControlStyle())
        }
    }
}

@available(macOS 15, *)
private struct FrenchSynopsis: View {
    let original: String
    @Environment(\.yoruLabels) private var labels
    @State private var translated: String?
    @State private var message = "Synopsis français indisponible"
    @State private var working = true
    @State private var canTranslate = false
    @State private var configuration: TranslationSession.Configuration?
    private static let cache: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 100
        return cache
    }()
    private let french = Locale.Language(identifier: "fr")

    var body: some View {
        Group {
            if let translated { SynopsisText(text: translated) }
            else if working { ProgressView(labels("Traduction du synopsis…")) }
            else {
                VStack(alignment: .leading, spacing: 9) {
                    if canTranslate {
                        Button(labels("Traduire en français")) { translate() }
                            .buttonStyle(ControlStyle(accent: true))
                    }
                    OriginalSynopsis(original: original, message: message)
                }
            }
        }
        .task { await checkLanguages() }
        .translationTask(configuration) { session in
            do {
                let result = try await session.translate(original).targetText
                guard !Task.isCancelled else { return }
                Self.cache.setObject(result as NSString, forKey: original as NSString)
                translated = result
            } catch {
                message = "La traduction n’a pas abouti"
            }
            working = false
        }
    }

    private func checkLanguages() async {
        if let cached = Self.cache.object(forKey: original as NSString) {
            translated = cached as String
            working = false
            return
        }
        if NLLanguageRecognizer.dominantLanguage(for: original) == .french {
            translated = original
            working = false
            return
        }
        let status = try? await LanguageAvailability().status(for: original, to: french)
        if !Task.isCancelled {
            canTranslate = status == .installed || status == .supported
            if status == .installed { translate() }
            else {
                if status == .supported { message = "macOS peut télécharger la langue pour traduire le synopsis" }
                working = false
            }
        }
    }

    private func translate() {
        working = true
        if configuration == nil { configuration = .init(target: french) }
        else { configuration?.invalidate() }
    }
}
