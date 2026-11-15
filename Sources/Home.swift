import SwiftUI

struct HomeView: View {
    @Environment(\.yoruTheme) private var theme
    @Environment(\.yoruLabels) private var labels
    @AppStorage("showRecommendations") private var showRecommendations = true
    @ObservedObject var model: Model

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 27) {
                hero
                if let offer = model.suggestedSeason { SeasonOfferCard(offer: offer, model: model) }
                DiscoveredView(model: model)
                if !model.series.isEmpty { libraryShelf }
            }
            .frame(maxWidth: 1490)
            .padding(.horizontal, 30).padding(.top, 23).padding(.bottom, 32)
            .frame(maxWidth: .infinity)
        }
        .background {
            if theme.secondaryGlow != nil { ArtBackdrop() }
            else { theme.background }
        }
    }

    private var hero: some View {
        let resume = model.continuing
        let needsLibrary = model.libraryReady && model.series.isEmpty && model.nautiljonRecommendations.isEmpty
        let feature = !needsLibrary && showRecommendations ? model.nautiljonRecommendations.first ?? model.recommendations.first : nil
        let progress = resume.map(model.progress)
        return GeometryReader { geometry in
            HStack {
                VStack(alignment: .leading, spacing: 11) {
                    if !needsLibrary {
                        Text(labels(resume == nil ? "À découvrir" : "Reprendre"))
                        .font(YoruTypography.text(14, strong: true)).foregroundStyle(heroAccent)
                    }
                    Text(resume?.title ?? feature?.entry.title.english ?? feature?.entry.name ?? "Ta bibliothèque")
                        .font(YoruTypography.display(geometry.size.width > 1050 ? 62 : 51))
                        .lineLimit(2).minimumScaleFactor(0.72)
                        .accessibilityAddTraits(.isHeader)
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
                    if needsLibrary {
                        ViewThatFits(in: .horizontal) {
                            HStack { libraryActions }
                            VStack(alignment: .leading) { libraryActions }
                        }
                    } else {
                        Button {
                            if let resume { model.play(resume) }
                            else if let feature { model.downloadRecommendation(feature) }
                            else { model.tab = .library }
                        } label: {
                            Label(labels(resume != nil ? "Reprendre la lecture" : feature.map(downloadLabel) ?? "Ouvrir la bibliothèque"),
                                  systemImage: resume != nil ? "play.fill" : feature == nil ? "square.grid.2x2" : "arrow.down.to.line")
                        }.buttonStyle(ControlStyle(accent: true))
                            .disabled(resume == nil && feature.map { model.addingTorrent || $0.entry.status == "NOT_YET_RELEASED" } == true)
                    }
                }.frame(width: geometry.size.width * 0.56, alignment: .leading)
                Spacer(minLength: 0)
            }
            .padding(.leading, geometry.size.width > 1000 ? 34 : 26)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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

    @ViewBuilder private var libraryActions: some View {
        Button { model.chooseFolder(thenOpenLibrary: true) } label: {
            Label("Choisir un dossier", systemImage: "folder")
        }.buttonStyle(ControlStyle(accent: true))
        Button { model.chooseVideos() } label: {
            Label("Ouvrir une vidéo", systemImage: "play.rectangle")
        }.buttonStyle(ControlStyle())
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
                    }.buttonStyle(.plain).modifier(HoverCard())
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
    @State private var watchlistOpen = false
    @State private var shelfWidth: CGFloat = 0
    var compact = false

    private struct ShelfWidth: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
    }

    var body: some View {
        if showRecommendations {
            VStack(alignment: .leading, spacing: 12) {
                if model.state.nautiljonWatchlist?.isEmpty == false {
                    HStack {
                        SectionHeading(title: "À voir", compact: compact)
                        Spacer()
                        Button { watchlistOpen = true } label: {
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
            .sheet(isPresented: $watchlistOpen) {
                WatchlistView(model: model, entries: model.nautiljonWatchlist)
            }
        }
    }

    private var cardWidth: CGFloat { compact ? 230 : 166 }
    private var columnSpacing: CGFloat { compact ? 10 : 15 }

    private func cards(_ items: [Discovery], limit: Int) -> some View {
        let showReason = items.contains { $0.reason != nil && $0.reason != "Nautiljon" }
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: cardWidth), spacing: columnSpacing, alignment: .topLeading)],
                  alignment: .leading, spacing: 17) {
            ForEach(Array(items.prefix(limit))) { item in
                VStack(alignment: .leading, spacing: 7) {
                    if compact { compactCard(item) }
                    else { poster(item, showReason: showReason) }
                    Button { model.downloadRecommendation(item) } label: {
                        Label(labels(downloadLabel(item)), systemImage: "arrow.down.to.line")
                            .lineLimit(2)
                            .frame(minHeight: 36, alignment: .leading)
                    }.buttonStyle(ControlStyle(horizontalPadding: 10)).disabled(model.addingTorrent)
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

    private func poster(_ item: Discovery, showReason: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Rectangle().fill(theme.card)
                .aspectRatio(0.72, contentMode: .fit)
                .overlay { WideArtwork(url: item.entry.coverImage?.large) }
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(theme.divider).allowsHitTesting(false))
            Text(item.entry.title.english ?? item.entry.name)
                .font(YoruTypography.text(15, strong: true)).lineLimit(2, reservesSpace: true)
            if showReason {
                Text(item.reason ?? "").font(YoruTypography.text(13)).foregroundStyle(theme.mutedText)
                    .lineLimit(1, reservesSpace: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func compactCard(_ item: Discovery) -> some View {
        HStack(spacing: 9) {
            CoverArt(url: item.entry.coverImage?.large, width: 42, height: 58, radius: 6)
            Text(item.entry.title.english ?? item.entry.name)
                .font(YoruTypography.text(14, strong: true)).lineLimit(2)
            Spacer(minLength: 0)
        }.padding(8).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
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

private struct WatchlistView: View {
    @ObservedObject var model: Model
    let entries: [NautiljonTitle]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.yoruTheme) private var theme
    @Environment(\.yoruLabels) private var labels
    @State private var query = ""

    var body: some View {
        let needle = query.trimmed
        let visible = needle.isEmpty ? entries : entries.filter {
            $0.titles.contains { $0.localizedStandardContains(needle) }
        }
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                SectionHeading(title: "À voir", count: entries.count)
                Spacer()
                Button(labels("Fermer")) { dismiss() }.buttonStyle(ControlStyle()).keyboardShortcut(.cancelAction)
            }
            SearchField(title: "Rechercher dans la liste", value: $query, icon: "magnifyingglass")
            if visible.isEmpty {
                Text(labels("Aucun résultat")).foregroundStyle(theme.mutedText)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(Array(visible.enumerated()), id: \.offset) { _, entry in
                            Button {
                                dismiss()
                                model.openWatchlistTitle(entry)
                            } label: {
                                HStack {
                                    Text(entry.titles.first ?? "").font(YoruTypography.text(18, strong: true)).lineLimit(2)
                                    Spacer()
                                    Image(systemName: "arrow.down.to.line").foregroundStyle(theme.accent)
                                }
                                .padding(.horizontal, 14).frame(minHeight: 51)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).modifier(HoverCard()).help("Voir les téléchargements")
                        }
                    }
                }
            }
        }
        .padding(22).frame(width: 665, height: 580)
        .background { ArtBackdrop() }
        .foregroundStyle(theme.primary)
    }
}

struct SeasonOfferCard: View {
    let offer: SeasonOffer
    @ObservedObject var model: Model
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
            if !offer.announced {
                Button { model.downloadSeason(offer) } label: {
                    Label(labels("Télécharger la saison"), systemImage: "arrow.down.to.line")
                }.buttonStyle(ControlStyle(accent: true)).disabled(model.addingTorrent)
            }
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading).modifier(HoverCard())
    }
}

private func downloadLabel(_ item: Discovery) -> String {
    if item.entry.status == "NOT_YET_RELEASED" { return "À venir" }
    if item.entry.status == "RELEASING" { return "Télécharger les épisodes disponibles" }
    return item.entry.format == "MOVIE" ? "Télécharger le film" : "Télécharger la saison"
}
