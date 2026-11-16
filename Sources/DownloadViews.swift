import SwiftUI

struct DownloadView: View {
    @Environment(\.miniPlaybackClearance) private var miniPlaybackClearance
    @Environment(\.yoruTheme) private var theme
    @Environment(\.yoruLabels) private var labels
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("lightweight") private var lightweight = false
    @ObservedObject var model: Model
    var inPlayer = false
    @State private var showFilters = false
    @State private var expandedVersions: Set<EpisodeGroup> = []

    private struct EpisodeGroup: Hashable, Comparable {
        let title: String
        let season: Int?
        let episode: Int

        static func < (lhs: Self, rhs: Self) -> Bool {
            (lhs.season ?? Int.max, lhs.episode, lhs.title) < (rhs.season ?? Int.max, rhs.episode, rhs.title)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header.padding(inPlayer ? 12 : 22)
            Divider()
            if let entry = model.inspected {
                inspector(entry)
            } else if model.downloadPane == .search {
                search
            } else {
                transfers
            }
        }
        .foregroundStyle(theme.primary)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.bottom, miniPlaybackClearance)
        .task { await model.checkTransfers(force: true) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                SectionHeading(title: "Téléchargements", compact: inPlayer)
                Spacer()
                Button { model.chooseTorrent() } label: {
                    if inPlayer { Image(systemName: "plus") }
                    else { Label(labels("Ouvrir un .torrent"), systemImage: "plus") }
                }.buttonStyle(ControlStyle()).disabled(model.addingTorrent)
                    .help("Ouvrir un fichier .torrent").accessibilityLabel("Ouvrir un fichier .torrent")
                if inPlayer {
                    Button { model.closePlayerDownloads() } label: { Image(systemName: "xmark") }
                        .buttonStyle(ControlStyle()).accessibilityLabel("Fermer les téléchargements")
                }
            }
            GlassGroup {
              HStack(spacing: 8) {
                ForEach(Model.DownloadPane.allCases, id: \.self) { pane in
                    let count = model.activeTransfers.count
                    let title = pane == .transfers && count > 0 ? "\(pane.rawValue) · \(count)" : pane.rawValue
                    Button(labels(title)) { model.selectDownloadPane(pane) }
                        .buttonStyle(ControlStyle(selected: model.downloadPane == pane && model.inspected == nil))
                        .disabled(model.addingTorrent)
                }
              }
            }
        }
    }

    private var search: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SearchField(title: "Titre de l’animé", value: $model.search, icon: "magnifyingglass")
                        .onSubmit(model.searchTorrents)
                    Button { model.searchTorrents() } label: {
                        if inPlayer { Image(systemName: "magnifyingglass") }
                        else { Label(labels("Rechercher"), systemImage: "magnifyingglass") }
                    }.buttonStyle(ControlStyle(accent: true))
                        .disabled(model.searching || model.search.trimmed.isEmpty)
                        .accessibilityLabel("Rechercher")
                }
                DirectionalDisclosure(expanded: $showFilters, title: labels("Filtres")) {
                    ViewThatFits(in: .horizontal) {
                        HStack { scope; numbers }
                        VStack(alignment: .leading, spacing: 8) { scope; numbers }
                    }.padding(.top, 7)
                }.onAppear { showFilters = model.packs != nil || !model.seasonNumber.isEmpty || !model.episodeNumber.isEmpty }
            }.padding(inPlayer ? 12 : 22)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 9) {
                    if model.searching {
                        ProgressView("Recherche sur Nyaa…").controlSize(.small).padding(.top, 8)
                    } else if model.torrentResults.isEmpty && model.downloadMessage.isEmpty {
                        if !inPlayer { DiscoveredView(model: model, compact: true) }
                        else { status("Cherche un animé ou ouvre un fichier .torrent avec le bouton +.") }
                    }
                    if !model.downloadMessage.isEmpty { status(model.downloadMessage) }
                    if !model.torrentResults.isEmpty {
                        let packs = model.torrentResults.filter(\.isPack).sorted {
                            ($0.seasons.min() ?? Int.max) < ($1.seasons.min() ?? Int.max)
                        }
                        let others = model.torrentResults.filter { !$0.isPack && $0.episode == nil }
                        episodeResults
                        results("Packs de saison", rows: packs)
                        results("Autres vidéos", rows: others)
                    }
                }.padding(inPlayer ? 10 : 22)
            }
        }
    }

    @ViewBuilder private var episodeResults: some View {
        let entries = model.torrentResults.compactMap { row in
            row.episode.map { (EpisodeGroup(title: SeasonNumber.base(row.artworkTitle).normalized, season: row.season, episode: $0), row) }
        }
        let groups = Dictionary(grouping: entries, by: { $0.0 })
        if !groups.isEmpty {
            section("Épisodes", count: groups.count)
            ForEach(groups.keys.sorted(), id: \.self) { group in
                let rows = (groups[group] ?? []).map { $0.1 }
                if let first = rows.first {
                    VStack(alignment: .leading, spacing: 6) {
                        resultRow(first, heading: labels("Épisode \(group.episode)"), details: "", episode: true)
                        if rows.count > 1 {
                            DirectionalDisclosure(expanded: Binding(get: { expandedVersions.contains(group) }, set: { value in
                                if value { expandedVersions.insert(group) } else { expandedVersions.remove(group) }
                            }), title: labels("Autres versions · \(rows.count - 1)")) {
                                ForEach(rows.dropFirst()) { row in resultRow(row, heading: row.artworkTitle, details: "") }
                            }.padding(.horizontal, 12).padding(.bottom, 7)
                        }
                    }
                    .background(theme.card, in: RoundedRectangle(cornerRadius: 15))
                    .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(theme.divider).allowsHitTesting(false))
                }
            }
        }
    }

    private var scope: some View {
        HStack(spacing: 5) {
            Button(labels("Tout")) { changeScope(nil) }.buttonStyle(ControlStyle(selected: model.packs == nil))
            Button(labels("Épisodes")) { changeScope(false) }.buttonStyle(ControlStyle(selected: model.packs == false))
            Button(labels("Packs")) { changeScope(true) }.buttonStyle(ControlStyle(selected: model.packs == true))
        }
    }

    private var numbers: some View {
        HStack(spacing: 7) {
            SearchField(title: "Saisons (1, 2…)", value: $model.seasonNumber).frame(width: 144)
                .onSubmit(model.searchTorrents)
            if model.packs != true {
                SearchField(title: "Épisode", value: $model.episodeNumber).frame(width: 102)
                    .onSubmit(model.searchTorrents)
            }
        }
    }

    private func changeScope(_ value: Bool?) {
        model.packs = value
        if !model.search.trimmed.isEmpty { model.searchTorrents() }
    }

    @ViewBuilder private func results(_ title: String, rows: [TorrentResult]) -> some View {
        if !rows.isEmpty {
            section(title, count: rows.count)
            ForEach(rows) { row in
                resultRow(row, heading: row.artworkTitle, details: row.scopeLabel)
            }
        }
    }

    private func resultRow(_ row: TorrentResult, heading: String, details: String, episode: Bool = false) -> some View {
        Button { model.inspect(row) } label: {
            HStack(spacing: 10) {
                if !inPlayer { AnimeCover(title: row.artworkTitle, width: 40, height: 56) }
                VStack(alignment: .leading, spacing: 3) {
                    Text(heading.nonEmpty ?? row.title).font(YoruTypography.display(inPlayer ? 19 : 23)).lineLimit(2)
                    let subtitle = episode ? [row.artworkTitle, row.season.map { labels("Saison \($0)") } ?? ""] : [labels(details)]
                    Text((subtitle + [row.group, row.french ? "FR" : ""]).filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(YoruTypography.text(15)).foregroundStyle(theme.mutedText).lineLimit(2)
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(row.size).font(YoruTypography.text(15, strong: true))
                    Text("\(row.seeds) seeders").font(YoruTypography.text(13)).foregroundStyle(theme.mutedText)
                }.monospacedDigit()
                Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(theme.mutedText)
            }.padding(inPlayer ? 9 : 11).contentShape(Rectangle())
        }.buttonStyle(DirectionalPlainStyle()).modifier(HoverCard()).help(row.title)
            .disabled(model.addingTorrent)
    }

    private var transfers: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if !model.availableDownloads.isEmpty {
                        SectionHeading(title: "Prêts à regarder", count: model.availableDownloads.count, compact: inPlayer)
                        ForEach(model.availableDownloads) { download in
                            completedRow(download)
                                .transition(.offset(y: reduceMotion || lightweight ? 0 : 10).combined(with: .opacity))
                        }
                    }
                    HStack {
                        section("En cours", count: model.activeTransfers.count)
                        Spacer()
                        Button { Task { await model.checkTransfers(force: true) } } label: { Image(systemName: "arrow.clockwise") }
                            .buttonStyle(ControlStyle()).accessibilityLabel("Actualiser les transferts")
                    }
                    if !model.downloadMessage.isEmpty { status(model.downloadMessage) }
                    if !model.transferStatus.isEmpty {
                        status(model.transferStatus)
                    } else if model.activeTransfers.isEmpty {
                        status("Aucun téléchargement en cours.")
                    }
                    ForEach(model.activeTransfers) { transfer in transferRow(transfer).id(transfer.id) }
                }.padding(inPlayer ? 12 : 22)
            }
            .animation(reduceMotion || lightweight ? nil : YoruMotion.reveal, value: model.availableDownloads.map(\.id))
            .onChange(of: model.transfers.map(\.id)) { _ in
                if let id = model.focusedTransfer { proxy.scrollTo(id) }
            }
        }
    }

    private func completedRow(_ download: AvailableDownload) -> some View {
        let name = ReleaseName(download.title)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(name.title.nonEmpty ?? download.title)
                    .font(YoruTypography.text(16, strong: true)).lineLimit(2)
                let episode = download.videos.count == 1
                    ? ReleaseName(download.videos[0].lastPathComponent).episode ?? name.episode : nil
                Text(episode.map { "Épisode \($0)" } ?? (download.videos.count == 1 ? "1 vidéo" : "\(download.videos.count) vidéos"))
                    .font(YoruTypography.text(14)).foregroundStyle(theme.mutedText)
            }
            Spacer(minLength: 2)
            Button { model.openCompletedDownload(download) } label: {
                Label(model.openingDownload == download.id ? "Ouverture…" : "Regarder", systemImage: "play.fill")
            }.buttonStyle(ControlStyle(accent: true))
                .disabled(model.openingDownload != nil)
                .accessibilityLabel("Regarder " + (name.title.nonEmpty ?? download.title))
        }.padding(12).modifier(HoverCard()).help(download.title)
    }

    private func transferRow(_ transfer: Transfer) -> some View {
        let display = ReleaseName(transfer.name)
        let season = display.season ?? SeasonNumber.first(in: transfer.name)
        let details = [season.map { "Saison \($0)" }, display.episode.map { "Épisode \($0)" }]
            .compactMap { $0 }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(display.title.nonEmpty ?? transfer.name).font(YoruTypography.text(16, strong: true)).lineLimit(2)
                    if !details.isEmpty { Text(details).font(.system(size: 13)).foregroundStyle(theme.mutedText) }
                }
                Spacer(minLength: 6)
                if !transfer.finished {
                    Text(transfer.fraction.formatted(.percent.precision(.fractionLength(0))))
                        .font(YoruTypography.text(18, strong: true)).monospacedDigit()
                }
            }
            if !transfer.finished {
                ProgressLine(fraction: transfer.fraction, tint: theme.accent, track: theme.divider, height: 5)
            }
            HStack(spacing: 8) {
                Text([transfer.label, transfer.speed, transfer.remainingTime].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 13)).foregroundStyle(theme.mutedText)
                Spacer(minLength: 5)
                if !transfer.finished, transfer.state != "error" {
                    Button(transfer.onHold ? "Reprendre" : "Pause") { model.transferAction(transfer) }.buttonStyle(ControlStyle())
                }
            }
        }.padding(11).modifier(HoverCard()).help(transfer.name)
    }

    private func inspector(_ entry: TorrentResult) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Button { model.inspected = nil; model.downloadMessage = "" } label: { Label("Retour", systemImage: "chevron.left") }
                .buttonStyle(ControlStyle()).disabled(model.addingTorrent)
            Text(entry.artworkTitle.nonEmpty ?? entry.title)
                .font(YoruTypography.display(inPlayer ? 30 : 39))
                .lineLimit(2).accessibilityAddTraits(.isHeader)
            if !entry.torrent.isFileURL {
                Text(entry.scopeLabel + " · " + entry.group).font(.system(size: 13)).foregroundStyle(theme.mutedText)
            }
            if let preview = model.preview {
                let videos = Set(preview.files.filter(\.isVideo).map(\.id))
                let all = Set(preview.files.map(\.id))
                let bytes = ByteCountFormatter.string(fromByteCount: preview.bytes(selected: model.chosenFiles), countStyle: .file)
                let count = model.chosenFiles.count
                let summary = Text("\(count) \(count == 1 ? "fichier" : "fichiers") · \(bytes)")
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(theme.mutedText)
                let actions = HStack(spacing: 6) {
                    if videos != all {
                        Button("Vidéos") { model.chosenFiles = videos }.buttonStyle(ControlStyle())
                            .accessibilityLabel("Sélectionner les vidéos")
                    }
                    Button("Tout") { model.chosenFiles = all }.buttonStyle(ControlStyle())
                        .accessibilityLabel("Sélectionner tous les fichiers")
                    Button("Vider") { model.chosenFiles = [] }.buttonStyle(ControlStyle())
                        .accessibilityLabel("Tout désélectionner")
                }.fixedSize().disabled(model.addingTorrent)
                ViewThatFits(in: .horizontal) {
                    HStack { actions; Spacer(minLength: 12); summary.fixedSize() }
                    VStack(alignment: .leading, spacing: 7) { actions; summary }
                }
                TorrentFilePicker(files: preview.files.sorted {
                    ($0.isVideo ? 0 : 1, $0.season ?? 0, $0.episode ?? Int.max, $0.id)
                        < ($1.isVideo ? 0 : 1, $1.season ?? 0, $1.episode ?? Int.max, $1.id)
                }, selection: $model.chosenFiles, locked: model.addingTorrent)
                    .accessibilityHint("Clique ou fais glisser pour choisir les fichiers.")
            } else if model.preparingPreview {
                ProgressView("Lecture du torrent…").controlSize(.small)
                Spacer()
            } else { Spacer() }
            if !model.downloadMessage.isEmpty { status(model.downloadMessage) }
            Divider()
            HStack {
                Spacer()
                Button { model.addTorrent() } label: {
                    DownloadLabel(title: labels(model.addingTorrent ? "Préparation…" : "Télécharger"), busy: model.addingTorrent)
                }
                    .buttonStyle(ControlStyle(accent: true))
                    .disabled(model.preview?.files.contains(where: { $0.isVideo && model.chosenFiles.contains($0.id) }) != true || model.addingTorrent)
            }
        }.padding(inPlayer ? 12 : 22)
            .frame(maxWidth: 960, maxHeight: .infinity, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func section(_ title: String, count: Int) -> some View {
        HStack {
            Text(labels(title)).font(YoruTypography.display(inPlayer ? 19 : 23))
            Text(String(count)).font(.caption.weight(.medium)).foregroundStyle(theme.mutedText).monospacedDigit()
        }.padding(.top, 4)
    }

    private func status(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(theme.mutedText).fixedSize(horizontal: false, vertical: true)
    }
}
