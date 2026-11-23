import SwiftUI

struct HomeView: View {
    @Environment(\.miniPlaybackClearance) private var miniPlaybackClearance
    @Environment(\.yoruTheme) private var theme
    @Environment(\.yoruLabels) private var labels
    @AppStorage("showRecommendations") private var showRecommendations = true
    @ObservedObject var model: Model
    let navigationClearance: CGFloat

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 27) {
                hero
                if model.allowsDownloads, let offer = model.suggestedSeason { SeasonOfferCard(offer: offer, model: model, opensProfile: true) }
                DiscoveredView(model: model)
                if !model.series.isEmpty { libraryShelf }
            }
            .frame(maxWidth: 1490)
            .padding(.horizontal, 30).padding(.top, 23 + navigationClearance).padding(.bottom, 32 + miniPlaybackClearance)
            .frame(maxWidth: .infinity)
        }
    }

    private var hero: some View {
        let resume = model.continuing
        let feature = showRecommendations && model.allowsDownloads ? model.nautiljonRecommendations.first ?? model.recommendations.first : nil
        let progress = resume.map(model.progress)
        let title = resume?.title ?? feature?.entry.title.english ?? feature?.entry.name ?? "Ta bibliothèque"
        return GeometryReader { geometry in
            HStack {
                VStack(alignment: .leading, spacing: 11) {
                    Text(labels(resume == nil ? "À découvrir" : "Reprendre"))
                        .font(YoruTypography.text(14, strong: true)).foregroundStyle(heroAccent)
                    Text(title)
                        .font(YoruTypography.display(geometry.size.width > 1050 ? 54 : 46))
                        .lineLimit(3).minimumScaleFactor(0.72)
                        .accessibilityAddTraits(.isHeader)
                        .help(title)
                    if let resume, let progress {
                        HStack(spacing: 7) {
                            if resume.number != nil {
                                Text(resume.display)
                                Circle().fill(.white.opacity(0.52)).frame(width: 3, height: 3)
                            }
                            Text(formatTime(progress.seconds) + " / " + formatTime(progress.duration))
                                .monospacedDigit()
                        }.font(YoruTypography.text(14)).foregroundStyle(.white.opacity(0.8))
                        ProgressLine(fraction: progress.fraction, tint: heroAccent, track: .white.opacity(0.24))
                            .frame(maxWidth: 220, alignment: .leading)
                            .padding(.bottom, 4)
                    } else if let reason = feature?.reason {
                        Text(reason).font(.callout).foregroundStyle(.white.opacity(0.76)).lineLimit(2)
                    }
                    Button {
                        if let resume { model.play(resume) }
                        else if let feature { model.present(feature) }
                        else { model.tab = .library }
                    } label: {
                        Label(labels(resume != nil ? "Reprendre la lecture" : feature == nil ? "Ouvrir la bibliothèque" : "Voir la fiche"),
                              systemImage: resume != nil ? "play.fill" : feature == nil ? "square.grid.2x2" : "arrow.right")
                    }.buttonStyle(ControlStyle(accent: true))
                }.frame(width: geometry.size.width * (geometry.size.width < 850 ? 0.68 : 0.58), alignment: .leading)
                Spacer(minLength: 0)
            }
            .padding(.leading, geometry.size.width > 1000 ? 34 : 26)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.vertical, 19)
        }
        .frame(height: progress == nil ? 310 : 334)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .environment(\.yoruTheme, .nuit)
        .background {
            GeometryReader { geometry in
                ZStack(alignment: .trailing) {
                    Color(red: 0.076, green: 0.092, blue: 0.083)
                    WideArtwork(url: resume == nil ? (feature?.entry.bannerImage ?? feature?.entry.coverImage?.large) : nil,
                                episode: resume, seconds: progress?.seconds)
                        .frame(width: geometry.size.width * 0.78)
                        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.22)],
                                             startPoint: .leading, endPoint: .trailing))
                    LinearGradient(stops: [
                        .init(color: Color(red: 0.06, green: 0.078, blue: 0.066), location: 0),
                        .init(color: Color(red: 0.06, green: 0.078, blue: 0.066).opacity(0.91), location: 0.30),
                        .init(color: Color(red: 0.06, green: 0.078, blue: 0.066).opacity(0.52), location: 0.61),
                        .init(color: .black.opacity(0.09), location: 1)
                    ], startPoint: .leading, endPoint: .trailing)
                    LinearGradient(colors: [.clear, .black.opacity(0.26)], startPoint: .center, endPoint: .bottom)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 23))
        .overlay(RoundedRectangle(cornerRadius: 23).strokeBorder(.white.opacity(0.1)).allowsHitTesting(false))
    }

    private var heroAccent: Color { YoruTheme.nuit.accent }

    private var libraryShelf: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeading(title: "Dans ta bibliothèque")
                Spacer()
                Button { model.tab = .library } label: {
                    Label("Voir tout", systemImage: "arrow.right")
                }.buttonStyle(ControlStyle())
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 199), spacing: 11)], spacing: 10) {
                ForEach(Array(model.series.prefix(8))) { item in
                    Button { model.select(item.id); model.tab = .library } label: {
                        HStack(spacing: 10) {
                            AnimeCover(title: item.query, id: model.state.shows[item.id]?.aniListID, preview: item.episodes.first, width: 37, height: 52)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title).font(YoruTypography.text(15, strong: true)).lineLimit(2)
                                if !item.episodes.isEmpty {
                                    Text(item.episodes.count == 1 ? (item.episodes[0].number == nil ? "Vidéo" : "1 épisode") : "\(item.episodes.count) épisodes")
                                        .font(YoruTypography.text(13)).foregroundStyle(theme.mutedText)
                                }
                            }
                            Spacer(minLength: 0)
                        }.padding(8).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(DirectionalPlainStyle()).modifier(HoverCard())
                }
            }
        }
    }
}

struct DiscoveredView: View {
    @Environment(\.yoruTheme) private var theme
    @Environment(\.yoruLabels) private var labels
    @ObservedObject var model: Model
    @AppStorage("showRecommendations") private var showRecommendations = true
    @State private var shelfWidth: CGFloat = 0
    var compact = false

    private struct ShelfWidth: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
    }

    var body: some View {
        if showRecommendations && model.allowsDownloads {
            VStack(alignment: .leading, spacing: 12) {
                if model.state.nautiljonWatchlist?.isEmpty == false {
                    HStack {
                        SectionHeading(title: "À voir", compact: compact)
                        Spacer()
                        Button { model.watchlistOpen = true } label: {
                            Label(labels("Voir plus"), systemImage: "arrow.right")
                        }.buttonStyle(ControlStyle())
                    }
                    let columns = max(1, Int((shelfWidth + columnSpacing) / (cardWidth + columnSpacing)))
                    cards(model.nautiljonRecommendations, limit: columns * 2)
                        .padding(.bottom, 10)
                }
                SectionHeading(title: model.recommendations.contains(where: { $0.reason != nil }) ? "Pour toi" : "À découvrir", compact: compact)
                if model.recommendations.isEmpty {
                    if model.recommending { ProgressView().controlSize(.small) }
                    else { Button(labels("Afficher des suggestions")) { Task { await model.discover() } }.buttonStyle(ControlStyle()) }
                } else {
                    cards(model.recommendations, limit: compact ? 6 : 12)
                }
            }
            .background {
                GeometryReader { geometry in Color.clear.preference(key: ShelfWidth.self, value: geometry.size.width) }
            }
            .onPreferenceChange(ShelfWidth.self) { shelfWidth = $0 }
        }
    }

    private var cardWidth: CGFloat { compact ? 240 : 166 }
    private var columnSpacing: CGFloat { compact ? 10 : 15 }

    private func cards(_ items: [Discovery], limit: Int) -> some View {
        let showReason = items.contains { $0.reason != nil && $0.reason != "Nautiljon" }
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: cardWidth), spacing: columnSpacing, alignment: .topLeading)],
                  alignment: .leading, spacing: 17) {
            ForEach(Array(items.prefix(limit))) { item in
                Group {
                    if compact { compactCard(item) }
                    else {
                        let title = item.entry.title.english ?? item.entry.name
                        Button { model.present(item) } label: {
                            DiscoveryPoster(title: title, url: item.entry.coverImage?.large,
                                            reason: showReason ? item.reason ?? "" : nil)
                        }
                        .buttonStyle(DirectionalPlainStyle(radius: 12))
                        .accessibilityLabel(labels("Voir la fiche") + " · " + title)
                        .help(title)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .modifier(RecommendationHover(compact: compact))
                .contextMenu {
                    Button(labels("Choisir une version")) { model.findRecommendation(item) }
                    Button(labels("Ajouter à regarder")) { model.plan(item.entry.name, catalogID: item.entry.id) }
                }
            }
        }
    }

    private func compactCard(_ item: Discovery) -> some View {
        let entry = item.entry
        let fullTitle = entry.title.english ?? entry.name
        let parts = fullTitle.split(separator: ":", maxSplits: 1).map { String($0).trimmed }
        let subtitle = parts.count == 2 && (entry.isFilm || fullTitle.count > 45) ? parts[1] : nil
        let season = [entry.title.english, entry.title.romaji].compactMap { $0 }.lazy.compactMap(SeasonNumber.first).first
        let mainTitle = subtitle == nil ? fullTitle : parts[0]
        let title = season == nil ? mainTitle : SeasonNumber.base(mainTitle)
        let romaji = entry.title.romaji.map { name in
            let base = subtitle == nil ? name : String(name.prefix(while: { $0 != ":" })).trimmed
            return season == nil ? base : SeasonNumber.base(base)
        }
        let shorterTitle = romaji.flatMap { !$0.isEmpty && $0.count + 8 < title.count ? $0 : nil }
        let format = entry.isFilm ? "Film" : season.map { "Saison \($0)" }
            ?? (entry.status == "RELEASING" ? "En cours" : "Série")
        let detail = [labels(format), subtitle].compactMap { $0 }.joined(separator: " · ")

        return VStack(alignment: .leading, spacing: 10) {
            Button { model.present(item) } label: {
                HStack(spacing: 10) {
                    CoverArt(url: entry.coverImage?.large, width: 42, height: 59, radius: 7)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(shorterTitle ?? title)
                            .font(YoruTypography.text(15, strong: true)).lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(detail).font(YoruTypography.text(13)).foregroundStyle(theme.mutedText).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 62)
                .contentShape(Rectangle())
            }
            .buttonStyle(DirectionalPlainStyle(radius: 8))
            .accessibilityLabel(labels("Voir la fiche") + " · " + fullTitle)
            .help(fullTitle)

            if ["NOT_YET_RELEASED", "CANCELLED"].contains(entry.status ?? "") {
                Text(labels(entry.status == "CANCELLED" ? "Annulé" : "À venir"))
                    .font(YoruTypography.text(15, strong: true)).foregroundStyle(theme.mutedText)
                    .frame(maxWidth: .infinity, minHeight: 42)
            } else {
                let action = labels(downloadLabel(item))
                Button { model.downloadRecommendation(item) } label: {
                    DownloadLabel(title: labels("Télécharger")).frame(maxWidth: .infinity)
                }
                .buttonStyle(ControlStyle(horizontalPadding: 12))
                .disabled(model.addingTorrent)
                .help(action)
                .accessibilityLabel(action + " · " + fullTitle)
            }
        }
        .padding(11)
    }
}

private struct DiscoveryPoster: View {
    @Environment(\.yoruTheme) private var theme
    let title: String
    let url: URL?
    var reason: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 11).fill(theme.card)
                .aspectRatio(0.72, contentMode: .fit)
                .overlay {
                    Image(systemName: "play.rectangle")
                        .font(.system(size: 28, weight: .medium)).foregroundStyle(theme.accent.opacity(0.52))
                        .accessibilityHidden(true)
                    WideArtwork(url: url)
                }
                .clipShape(RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(theme.divider).allowsHitTesting(false))
            Text(title).font(YoruTypography.text(16, strong: true)).lineLimit(2, reservesSpace: true)
            if let reason {
                Text(reason).font(YoruTypography.text(13)).foregroundStyle(theme.mutedText)
                    .lineLimit(1, reservesSpace: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct RecommendationHover: ViewModifier {
    let compact: Bool
    @Environment(\.yoruTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("lightweight") private var lightweight = false
    @State private var hovered = false

    func body(content: Content) -> some View {
        if compact {
            content.modifier(HoverCard())
        } else {
            content
                .foregroundStyle(hovered ? theme.accent : theme.primary)
                .offset(y: hovered && !reduceMotion && !lightweight ? -4 : 0)
                .onHover { hovered = $0 }
                .animation(reduceMotion || lightweight ? nil : YoruMotion.selection, value: hovered)
        }
    }
}

struct WatchlistGallery: View {
    @Environment(\.miniPlaybackClearance) private var miniPlaybackClearance
    @ObservedObject var model: Model
    let navigationClearance: CGFloat
    @Environment(\.yoruTheme) private var theme
    @Environment(\.yoruLabels) private var labels
    @State private var query = ""
    @StateObject private var artwork = WatchlistArtwork()

    var body: some View {
        let entries = model.nautiljonWatchlist
        let needle = query.trimmed
        let visible = entries.enumerated().filter { _, row in
            needle.isEmpty || row.titles.contains { $0.localizedStandardContains(needle) }
        }
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Button { model.watchlistOpen = false } label: {
                    Label(labels("Retour"), systemImage: "chevron.left")
                }.buttonStyle(ControlStyle())
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 24) {
                        heading(count: visible.count).fixedSize()
                        Spacer(minLength: 12)
                        search.frame(minWidth: 260, maxWidth: 430)
                    }
                    VStack(alignment: .leading, spacing: 15) {
                        heading(count: visible.count)
                        search
                    }
                }
                if visible.isEmpty {
                    Text(labels("Aucun résultat")).font(YoruTypography.text(17)).foregroundStyle(theme.mutedText)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 157, maximum: 230), spacing: 19, alignment: .topLeading)],
                              alignment: .leading, spacing: 21) {
                        ForEach(visible, id: \.offset) { _, row in card(row) }
                    }
                }
            }
            .frame(maxWidth: 1490, alignment: .leading)
            .padding(.horizontal, 30).padding(.top, navigationClearance + 23).padding(.bottom, (artwork.failed ? 78 : 32) + miniPlaybackClearance)
            .frame(maxWidth: .infinity)
        }
        .overlay(alignment: .bottomTrailing) {
            if artwork.failed {
                Button { artwork.retry() } label: {
                    Label(labels("Recharger les affiches"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(ControlStyle(accent: true))
                .padding(22)
                .padding(.bottom, miniPlaybackClearance)
            }
        }
        .onDisappear { artwork.stop() }
    }

    private var search: some View {
        SearchField(title: "Rechercher un anime", value: $query, icon: "magnifyingglass")
    }

    private func heading(count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            SectionHeading(title: "À voir")
            Text(labels(count == 1 ? "1 titre" : "\(count) titres"))
                .font(YoruTypography.text(16, strong: true)).foregroundStyle(theme.mutedText)
        }
    }

    private func card(_ row: NautiljonTitle) -> some View {
        let suggestion = model.nautiljonRecommendations.first { !$0.entry.titleKeys.isDisjoint(with: row.keys) }?.entry
        let entry = suggestion ?? artwork.entries[row.titles]
        let title = row.titles.first ?? entry?.name ?? "Anime"
        return Button { model.openWatchlistTitle(row, entry: entry) } label: {
            DiscoveryPoster(title: title, url: entry?.coverImage?.large)
        }
        .buttonStyle(DirectionalPlainStyle(radius: 12))
        .modifier(RecommendationHover(compact: false))
        .accessibilityLabel(labels("Voir la fiche") + " · " + title)
        .help(title)
        .onAppear { if suggestion == nil { artwork.show(row) } }
        .onDisappear { artwork.hide(row) }
    }
}

@MainActor private final class WatchlistArtwork: ObservableObject {
    @Published private(set) var entries: [[String]: Anime] = [:]
    @Published private(set) var failed = false
    private var absent: Set<[String]> = []
    private var visible: [NautiljonTitle] = []
    private var loader: Task<Void, Never>?

    func show(_ row: NautiljonTitle) {
        if !visible.contains(where: { $0.titles == row.titles }) { visible.append(row) }
        load()
    }

    func hide(_ row: NautiljonTitle) { visible.removeAll { $0.titles == row.titles } }

    func retry() { failed = false; load() }

    func stop() {
        loader?.cancel()
        loader = nil
        visible.removeAll()
    }

    private func load() {
        guard loader == nil, !failed else { return }
        loader = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 70_000_000)
            guard let self, !Task.isCancelled else { return }
            defer { if !Task.isCancelled { loader = nil } }
            while !Task.isCancelled {
                let pending = visible.lazy.filter { self.entries[$0.titles] == nil && !self.absent.contains($0.titles) }
                let batch = Array(pending.prefix(6))
                guard !batch.isEmpty else { return }
                do {
                    let matches = try await Catalog.matchWatchlist(batch)
                    try Task.checkCancellation()
                    var next = entries
                    for (row, match) in zip(batch, matches) {
                        if let match { next[row.titles] = match }
                        else { absent.insert(row.titles) }
                    }
                    entries = next
                } catch {
                    if !Task.isCancelled { failed = true }
                    return
                }
            }
        }
    }
}

struct SeasonOfferCard: View {
    let offer: SeasonOffer
    @ObservedObject var model: Model
    var opensProfile = false
    @Environment(\.yoruLabels) private var labels

    var body: some View {
        HStack(spacing: 14) {
            CoverArt(url: offer.cover, width: 42, height: 58, radius: 7)
            VStack(alignment: .leading, spacing: 4) {
                Text(labels(offer.announced ? "Saison \(offer.next) annoncée" : "Saison \(offer.next)"))
                    .font(YoruTypography.text(17, strong: true))
                Text(offer.title).font(.callout).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 4)
            if opensProfile {
                Button {
                    model.presentedAnime = AnimePresentation(names: [offer.title], entry: nil, season: offer)
                } label: {
                    Label(labels("Voir la saison"), systemImage: "arrow.right")
                }.buttonStyle(ControlStyle())
            } else if !offer.announced {
                Button { model.downloadSeason(offer) } label: {
                    DownloadLabel(title: labels("Télécharger la saison"))
                }.buttonStyle(ControlStyle(accent: true)).disabled(model.addingTorrent)
            }
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading).modifier(HoverCard())
    }
}

private func downloadLabel(_ item: Discovery) -> String {
    if item.entry.status == "RELEASING" { return "Télécharger les épisodes disponibles" }
    return item.entry.format == "MOVIE" ? "Télécharger le film" : "Télécharger la saison"
}
