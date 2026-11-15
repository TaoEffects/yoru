import SwiftUI

struct HomeView: View {
    @Environment(\.yoruTheme) private var theme
    @ObservedObject var model: Model

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 27) {
                hero
                if let offer = model.suggestedSeason { SeasonOfferCard(offer: offer) { model.findSeason(offer) } }
                DiscoveredView(model: model)
                if !model.series.isEmpty { libraryShelf }
            }
            .frame(maxWidth: 1490)
            .padding(.horizontal, 30).padding(.top, 23).padding(.bottom, 32)
            .frame(maxWidth: .infinity)
        }
        .background(theme.background)
    }

    private var hero: some View {
        let resume = model.continuing
        let needsLibrary = model.libraryReady && model.series.isEmpty
        let feature = needsLibrary ? nil : model.recommendations.first
        let progress = resume.map(model.progress)
        return GeometryReader { geometry in
            HStack {
                VStack(alignment: .leading, spacing: 11) {
                    if !needsLibrary {
                        Text(resume == nil ? "À découvrir" : "Reprendre")
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
                            else if let feature { model.findRecommendation(feature) }
                            else { model.tab = .library }
                        } label: {
                            Label(resume != nil ? "Reprendre la lecture" : feature == nil ? "Ouvrir la bibliothèque" : "Voir les versions",
                                  systemImage: resume != nil ? "play.fill" : feature == nil ? "square.grid.2x2" : "arrow.up.right")
                        }.buttonStyle(ControlStyle(accent: true))
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
    @ObservedObject var model: Model
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: model.recommendations.contains(where: { $0.reason != nil }) ? "Pour toi" : "À découvrir", compact: compact)
            if model.recommendations.isEmpty {
                if model.recommending { ProgressView().controlSize(.small) }
                else { Button("Afficher des suggestions") { Task { await model.discover() } }.buttonStyle(ControlStyle()) }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: compact ? 170 : 138), spacing: compact ? 10 : 15)],
                          alignment: .leading, spacing: 16) {
                    ForEach(Array(model.recommendations.prefix(compact ? 8 : 12))) { item in
                        Button { model.findRecommendation(item) } label: {
                            if compact { compactCard(item) }
                            else { poster(item) }
                        }
                        .buttonStyle(.plain)
                        .modifier(RecommendationHover(compact: compact))
                        .help("Chercher les versions de " + item.entry.name)
                        .contextMenu {
                            Button("Ajouter à regarder") { model.plan(item.entry.name, catalogID: item.entry.id) }
                        }
                    }
                }
            }
        }
    }

    private func poster(_ item: Discovery) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Rectangle().fill(theme.card)
                .aspectRatio(0.72, contentMode: .fit)
                .overlay { WideArtwork(url: item.entry.coverImage?.large) }
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(theme.divider).allowsHitTesting(false))
            Text(item.entry.title.english ?? item.entry.name)
                .font(YoruTypography.text(15, strong: true)).lineLimit(2, reservesSpace: true)
            if let reason = item.reason {
                Text(reason).font(YoruTypography.text(13)).foregroundStyle(theme.mutedText).lineLimit(1)
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

struct SeasonOfferCard: View {
    let offer: SeasonOffer
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            CoverArt(url: offer.cover, width: 42, height: 58, radius: 7)
            VStack(alignment: .leading, spacing: 4) {
                Text(offer.announced ? "Saison \(offer.next) annoncée" : "Préparer la saison \(offer.next)")
                    .font(YoruTypography.text(17, strong: true))
                Text(offer.title).font(.callout).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 4)
            if !offer.announced {
                Button(action: action) { Label("Voir les versions", systemImage: "arrow.down.to.line") }
                    .buttonStyle(ControlStyle(accent: true))
            }
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading).modifier(HoverCard())
    }
}
