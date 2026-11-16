import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor final class Model: ObservableObject {
    enum Tab: String, CaseIterable { case home = "Accueil", library = "Bibliothèque", player = "Lecture", downloads = "Téléchargements" }
    enum LibraryFilter: String, CaseIterable, Identifiable {
        case all = "Tout", watching = "En cours", planned = "À voir"
        var id: Self { self }
    }
    let player = Player()
    let torrent = TorrentClient()
    @Published var tab = Tab.home
    @Published var presentedAnime: AnimePresentation?
    @Published var watchlistOpen = false
    @Published var series: [Series] = []
    @Published private(set) var libraryReady = false
    @Published var selected: String?
    @Published var filter = ""
    @Published var libraryFilter = LibraryFilter.all
    @Published var current: Episode?
    @Published var state = LocalState()
    @Published var settings = false
    @Published var message = ""
    @Published var importing = false
    @Published var anime: [String: Anime] = [:]
    @Published var matches: [Anime] = []
    @Published var metadataBusy = false
    @Published private(set) var requestedSubtitle = ""
    @Published var subtitleOptions: [SubtitleCandidate] = []
    @Published var subtitleStatus = ""
    @Published var workingSubtitles = false
    enum DownloadPane: String, CaseIterable { case search = "Chercher", transfers = "Transferts" }
    @Published var downloadPane = DownloadPane.search
    @Published var playerDownloadsOpen = false
    @Published var transfers: [Transfer] = []
    @Published private(set) var availableDownloads: [AvailableDownload] = []
    @Published private(set) var openingDownload: String?
    @Published var focusedTransfer: String?
    @Published var downloadMessage = ""
    private var checkingTransfers = false
    @Published var transferStatus = ""
    @Published var search = ""
    @Published var torrentResults: [TorrentResult] = []
    @Published var packs: Bool?
    @Published var recommendations: [Discovery] = []
    @Published private(set) var nautiljonRecommendations: [Discovery] = []
    private var nautiljonTask: Task<Void, Never>?
    private var nautiljonRecommendationExclusions: Set<String> = []
    @Published private(set) var seasonOffers: [String: SeasonOffer] = [:]
    private var checkingSeasons: Set<String> = []
    private var checkedSeasons: [String: Date] = [:]
    private var searchTask: Task<Void, Never>?
    private var searchGeneration = 0
    @Published var recommending = false
    @Published var librarySeason: Int?
    @Published private(set) var introCountdown: Int?
    @Published private(set) var introKept = false
    @Published private(set) var introUndo: SkipSegment?
    private var introSession = IntroSession()
    @Published var episodeNumber = ""
    @Published var seasonNumber = ""
    @Published var searching = false
    @Published var inspected: TorrentResult?
    @Published var preview: TorrentPreview?
    @Published var chosenFiles: Set<Int> = []
    @Published private(set) var quickDownloadStatus = ""
    @Published var addingTorrent = false
    @Published var preparingPreview = false
    @Published var modifyingSkip: String?
    @Published var markStart: Double?
    @Published var syncAnchor: Double?
    private var anchorDelay = 0.0
    @Published var playlistFocus: String?
    @Published var libraryEpisodeFocus: String?
    @Published var episodeSelection: Set<String> = []
    @Published private(set) var watchUndoCount = 0
    private var episodeSelectionAnchor: String?
    private struct WatchChange {
        let previous: Progress?
        let updated: Progress
    }
    private var watchUndo: [String: WatchChange] = [:]
    private var subtitleTask: Task<Void, Never>?
    private var skipTask: Task<Void, Never>?
    private var lastSave = Date.distantPast
    private var stagedFiles: [URL] = []
    private var subtitleFile: URL?
    private var activeTransferPaths: Set<String> = []
    private var downloadSeries: Series?
    private var requestedSeasons: Set<Int> = []
    private var requestedEpisode: Int?
    private var scanCount = 0
    private let selfTest = CommandLine.arguments.contains("--self-test")
    var allowsDownloads: Bool { selfTest || YoruUsageMode.current.hasDownloads }
    private var store: URL { FileManager.support.appendingPathComponent("Bibliothèque.json") }

    var folder: URL {
        if let path = UserDefaults.standard.string(forKey: "moviesFolder") {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies/Yoru Public", isDirectory: true)
    }
    var downloadFolder: URL { folder.appendingPathComponent("Yoru") }

    init() {
        if !selfTest { state = (try? Data(contentsOf: store)).flatMap { try? JSONDecoder().decode(LocalState.self, from: $0) } ?? LocalState() }
        player.didLoad = { [weak self] in self?.loaded() }
        player.didEnd = { [weak self] in self?.markFinished() }
        player.save = { [weak self] in self?.saveProgress() }
    }

    var displayed: [Series] {
        let query = filter.trimmed
        return series.filter { show in
            guard query.isEmpty || (show.title + " " + show.query).localizedCaseInsensitiveContains(query) else { return false }
            switch libraryFilter {
            case .all: return true
            case .watching:
                return show.episodes.contains { let status = progress($0); return !status.watched && status.seconds > 3 }
            case .planned: return state.shows[show.id]?.watchlist == true
            }
        }
    }
    var selectedSeries: Series? { displayed.first { $0.id == selected } }
    var seasonEpisodes: [Episode] {
        (selectedSeries?.episodes ?? []).filter { librarySeason == nil || $0.season == librarySeason }
    }

    func selectLibraryFilter(_ filter: LibraryFilter) {
        libraryFilter = filter
        if selectedSeries == nil { select(displayed.first?.id) }
    }

    func trashEpisodes(_ episodes: [Episode]) {
        let root = folder.resolvingSymlinksInPath().standardizedFileURL.path
        let prefix = root.hasSuffix("/") ? root : root + "/"
        let known = Set(series.flatMap(\.episodes).map(\.id))
        var failures: [String] = []
        for episode in episodes {
            let url = episode.url
            guard url.isFileURL, known.contains(episode.id),
                  url.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(prefix) else {
                failures.append(url.lastPathComponent)
                continue
            }
            if current?.id == episode.id {
                saveProgress()
                subtitleTask?.cancel()
                skipTask?.cancel()
                current = nil
                player.stop()
            }
            do { try FileManager.default.trashItem(at: url, resultingItemURL: nil) }
            catch { failures.append(url.lastPathComponent) }
        }
        let removed = Set(episodes.map(\.id))
        stagedFiles.removeAll { removed.contains($0.path) && !FileManager.default.fileExists(atPath: $0.path) }
        availableDownloads = playableDownloads(availableDownloads)
        clearEpisodeSelection()
        refresh()
        if !failures.isEmpty { message = "Corbeille inaccessible pour " + failures.joined(separator: ", ") }
    }

    func selectSeason(_ season: Int?) {
        clearEpisodeSelection()
        librarySeason = season
        libraryEpisodeFocus = seasonEpisodes.first?.id
    }

    func clearEpisodeSelection() {
        if !episodeSelection.isEmpty { episodeSelection = [] }
        episodeSelectionAnchor = nil
    }

    func episodeRange(from first: String, to last: String) -> Set<String> {
        let episodes = seasonEpisodes
        guard let start = episodes.firstIndex(where: { $0.id == first }),
              let end = episodes.firstIndex(where: { $0.id == last }) else { return [last] }
        return Set(episodes[min(start, end)...max(start, end)].map(\.id))
    }

    func selectEpisodeRange(through episode: Episode) {
        let anchor = episodeSelectionAnchor ?? libraryEpisodeFocus ?? episode.id
        episodeSelectionAnchor = anchor
        episodeSelection = episodeRange(from: anchor, to: episode.id)
        libraryEpisodeFocus = episode.id
    }

    func toggleEpisodeSelection(_ episode: Episode) {
        if episodeSelection.contains(episode.id) { episodeSelection.remove(episode.id) }
        else { episodeSelection.insert(episode.id) }
        episodeSelectionAnchor = episode.id
        libraryEpisodeFocus = episode.id
    }

    var playlist: [Episode] { series.first { $0.id == current?.showID }?.episodes ?? stagedFiles.map(makeEpisode) }
    private func adjacentEpisode(direction: Int) -> Episode? {
        guard let current else { return nil }
        let numbered = playlist.filter { $0.number != nil }
        if let number = current.number {
            let season = current.season ?? 1
            return (direction > 0 ? numbered : Array(numbered.reversed())).first { item in
                guard let candidate = item.number else { return false }
                let other = item.season ?? 1
                return direction > 0 ? (other, candidate) > (season, number) : (other, candidate) < (season, number)
            }
        }
        guard let index = playlist.firstIndex(of: current), playlist.indices.contains(index + direction) else { return nil }
        return playlist[index + direction]
    }

    var next: Episode? { adjacentEpisode(direction: 1) }
    var previous: Episode? { adjacentEpisode(direction: -1) }

    func startNextEpisode() {
        guard let next else { return }
        if player.currentSkip?.kind == "ed" || (player.duration > 0 && player.position >= 0.9 * player.duration) { markFinished() }
        play(next)
    }

    private var latestFollowedEpisode: Episode? {
        series.flatMap(\.episodes).filter { progress($0).watched || progress($0).seconds >= 30 }
            .max { progress($0).updated < progress($1).updated }
    }

    func seasonOffer(for episode: Episode) -> SeasonOffer? {
        let key = episode.showID + "|" + String(episode.season ?? 1)
        guard let offer = seasonOffers[key], offer.isNearFinale(episode.number),
              !series.contains(where: { show in
                  show.id == offer.showID && show.episodes.contains { $0.season == offer.next && $0.number == 1 }
              }),
              !transfers.contains(where: { !($0.state.contains("error") || $0.state == "missingFiles") && state.transferSeasons?[$0.id] == offer.key })
        else { return nil }
        return offer
    }

    var suggestedSeason: SeasonOffer? { (current ?? latestFollowedEpisode).flatMap(seasonOffer(for:)) }

    func checkFollowingSeason(_ episode: Episode? = nil) {
        guard allowsDownloads, !selfTest, let point = episode ?? latestFollowedEpisode, point.number != nil,
              let show = series.first(where: { $0.id == point.showID }) else { return }
        let season = point.season ?? 1
        let key = show.id + "|" + String(season)
        let latest = checkedSeasons[key] ?? .distantPast
        guard !checkingSeasons.contains(key), Date().timeIntervalSince(latest) > 30 * 60 else { return }
        checkingSeasons.insert(key)
        let catalogID = state.shows[show.id]?.aniListID
        Task {
            defer { checkingSeasons.remove(key) }
            do {
                seasonOffers[key] = try await SeasonCatalog.resolve(show, season: season, catalogID: catalogID)
                checkedSeasons[key] = Date()
            } catch { /* A later playback may retry catalogue errors. */ }
        }
    }

    func findSeason(_ offer: SeasonOffer, inPlayer: Bool = false) {
        guard !offer.announced, let show = series.first(where: { $0.id == offer.showID }) else { return }
        downloadSeries = show
        search = SeasonNumber.base(show.query)
        episodeNumber = ""
        seasonNumber = String(offer.next)
        packs = nil
        downloadPane = .search
        if inPlayer { playerDownloadsOpen = true }
        else { tab = .downloads }
        searchTorrents()
    }

    func downloadSeason(_ offer: SeasonOffer, inPlayer: Bool = false) {
        guard !offer.announced, let show = series.first(where: { $0.id == offer.showID }) else { return }
        startQuickDownload(query: show.query, id: offer.catalogID, season: offer.next, source: show, inPlayer: inPlayer) {
            self.findSeason(offer, inPlayer: inPlayer)
        }
    }

    var continuing: Episode? {
        resumeEpisode(in: series.flatMap(\.episodes))
    }

    func resumeEpisode(in episodes: [Episode]) -> Episode? {
        episodes.filter { let entry = progress($0); return !entry.watched && entry.seconds > 3 }
            .max { progress($0).updated < progress($1).updated }
    }

    func progress(_ episode: Episode) -> Progress { state.history[episode.progressID] ?? Progress() }
    func score(_ show: Series) -> Double? { state.shows[show.id]?.rating ?? state.importedRatings[show.query.normalized] ?? state.importedRatings[show.title.normalized] }

    func persist() {
        guard !selfTest else { return }
        do {
            try FileManager.default.createDirectory(at: FileManager.support, withIntermediateDirectories: true)
            try JSONEncoder().encode(state).write(to: store, options: .atomic)
        } catch { message = "Impossible d’enregistrer la bibliothèque : \(error.localizedDescription)" }
    }

    @discardableResult func refresh() -> Task<Void, Never> {
        scanCount += 1
        let generation = scanCount
        let root = folder
        let downloadFolders = state.downloadFolders ?? [:]
        let activePaths = activeTransferPaths
        return Task {
            let items = await Task.detached(priority: .utility) { Indexer.scan(root, downloadFolders: downloadFolders, excluding: activePaths) }.value
            guard scanCount == generation else { return }
            let existing = Set(items.map(\.id))
            let planned = state.shows.compactMap { id, preference -> Series? in
                guard !existing.contains(id), preference.watchlist, let title = preference.title.nonEmpty else { return nil }
                return Series(id: id, title: title, query: preference.query.nonEmpty ?? title, episodes: [])
            }
            series = (items + planned).map {
                var item = $0
                if let pref = state.shows[item.id] {
                    item.title = pref.title.nonEmpty ?? item.title
                    item.query = pref.query.nonEmpty ?? item.query
                }
                return item
            }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            if selectedSeries == nil { select(displayed.first?.id) }
            else if !seasonEpisodes.contains(where: { $0.id == libraryEpisodeFocus }) {
                if seasonEpisodes.isEmpty, let selectedSeries, !selectedSeries.episodes.isEmpty {
                    selectSeason(selectedSeries.episodes.compactMap(\.season).min())
                } else {
                    libraryEpisodeFocus = seasonEpisodes.first?.id
                }
            }
            let firstScan = !libraryReady
            libraryReady = true
            updateNautiljonRecommendationsIfNeeded()
            if firstScan, allowsDownloads {
                Task { await checkTransfers(force: true) }
            }
            checkFollowingSeason()
        }
    }

    func select(_ id: String?) {
        selected = id
        let episodes = selectedSeries?.episodes ?? []
        selectSeason(resumeEpisode(in: episodes)?.season ?? episodes.compactMap(\.season).min())
        matches = []
    }

    func updateShow(_ id: String, _ update: (inout ShowPreference) -> Void) {
        var settings = state.shows[id] ?? ShowPreference()
        update(&settings)
        state.shows[id] = settings
        persist()
    }

    func plan(_ title: String, catalogID: Int? = nil) {
        let title = title.trimmed
        guard !title.isEmpty else { return }
        let existing = series.first { $0.query.normalized == title.normalized || $0.title.normalized == title.normalized }
        updateShow(existing?.id ?? title.normalized) {
            $0.watchlist = true
            $0.title = existing?.title ?? title
            $0.query = existing?.query ?? title
            if let catalogID { $0.aniListID = catalogID }
        }
        refresh()
    }

    func importRatings(_ url: URL, announce: Bool = true) {
        do {
            let entries = try Indexer.nautiljon(url)
            let watched = entries.filter { !["encours", "pasvu", "nonvu", "avoir"].contains($0.status) }
            let titles = Set(watched.flatMap(\.keys))
            state.nautiljonSeen = titles
            state.importedRatings = [:]
            for entry in entries {
                if let rating = entry.rating {
                    for key in entry.keys { state.importedRatings[key] = rating }
                }
            }
            recommendations.removeAll { !$0.entry.titleKeys.isDisjoint(with: titles) }
            recommendationBasis = nil
            persist()
            if announce {
                loadNautiljonRecommendations()
                message = "\(watched.count) titres Nautiljon importés depuis « vus »."
                Task { await discover() }
            }
        } catch { message = error.localizedDescription }
    }

    func importNautiljonWatchlist(_ url: URL, announce: Bool = true) {
        do {
            let entries = try Indexer.nautiljon(url)
            state.nautiljonWatchlist = entries
            nautiljonRecommendations = []
            let planned = Set(entries.flatMap(\.keys))
            recommendations.removeAll { !$0.entry.titleKeys.isDisjoint(with: planned) }
            recommendationBasis = nil
            persist()
            if announce {
                loadNautiljonRecommendations()
                message = "\(entries.count) titres importés depuis « à voir »."
                Task { await discover() }
            }
        } catch { message = error.localizedDescription }
    }

    private func loadNautiljonRecommendations() {
        nautiljonTask?.cancel()
        let seen = nautiljonExcludedTitles
        nautiljonRecommendationExclusions = seen
        let candidates = (state.nautiljonWatchlist ?? []).filter { $0.keys.isDisjoint(with: seen) }.sorted {
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            return $0.date > $1.date
        }
        nautiljonRecommendations = nautiljonRecommendations.filter { $0.entry.titleKeys.isDisjoint(with: seen) }
        guard !candidates.isEmpty else { nautiljonRecommendations = []; return }
        nautiljonTask = Task {
            var excluded = seen
            var items: [Discovery] = []
            let queue = Array(candidates.prefix(36))
            for start in stride(from: 0, to: queue.count, by: 6) {
                let batch = Array(queue[start..<min(start + 6, queue.count)])
                guard let matches = try? await Catalog.matchWatchlist(batch, details: true), !Task.isCancelled else { break }
                for match in matches {
                    guard let anime = match, anime.status != "NOT_YET_RELEASED", anime.status != "CANCELLED",
                          anime.titleKeys.isDisjoint(with: excluded) else { continue }
                    excluded.formUnion(anime.titleKeys)
                    items.append(Discovery(entry: anime, reason: "Nautiljon"))
                }
                nautiljonRecommendations = Array(items.prefix(16))
                if items.count >= 16 { break }
            }
        }
    }

    private var nautiljonExcludedTitles: Set<String> {
        (state.nautiljonSeen ?? []).union(series.filter { !$0.episodes.isEmpty }.flatMap {
            [$0.title.normalized, $0.query.normalized]
        })
    }

    var nautiljonWatchlist: [NautiljonTitle] {
        let seen = state.nautiljonSeen ?? []
        return (state.nautiljonWatchlist ?? []).filter { $0.keys.isDisjoint(with: seen) }.sorted {
            ($0.titles.first ?? "").localizedStandardCompare($1.titles.first ?? "") == .orderedAscending
        }
    }

    func openWatchlistTitle(_ row: NautiljonTitle, entry: Anime?) {
        presentedAnime = AnimePresentation(names: row.titles, entry: entry)
    }

    func present(_ item: Discovery) {
        presentedAnime = AnimePresentation(names: [item.entry.name], entry: item.entry)
    }

    func downloadPresentedAnime(_ presentation: AnimePresentation, entry: Anime?) {
        if let season = presentation.season { downloadSeason(season) }
        else if let entry { downloadRecommendation(Discovery(entry: entry, reason: nil)) }
        else { searchRecommendation(title: presentation.title) }
    }

    private func updateNautiljonRecommendationsIfNeeded() {
        guard allowsDownloads, !(state.nautiljonWatchlist ?? []).isEmpty,
              nautiljonRecommendationExclusions != nautiljonExcludedTitles || nautiljonTask == nil else { return }
        loadNautiljonRecommendations()
    }

    func chooseFolder(thenOpenLibrary: Bool = false) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = FileManager.default.fileExists(atPath: folder.path) ? folder
            : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies", isDirectory: true)
        if panel.runModal() == .OK, let url = panel.url {
            UserDefaults.standard.set(url.path, forKey: "moviesFolder")
            if thenOpenLibrary { tab = .library }
            refresh()
        }
    }

    func chooseVideos() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.directoryURL = folder
        if panel.runModal() == .OK { openURLs(panel.urls) }
    }

    func chooseSubtitle() {
        let panel = NSOpenPanel()
        panel.directoryURL = current?.url.deletingLastPathComponent()
        if panel.runModal() == .OK, let url = panel.url, SubtitleService.types.contains(url.pathExtension.lowercased()) { loadSubtitle(url) }
    }

    private func makeEpisode(_ url: URL) -> Episode {
        let name = ReleaseName(url.lastPathComponent)
        return Episode(url: url, title: name.title, showID: "fichier:" + url.deletingLastPathComponent().path + "|" + name.title.normalized, season: name.season, number: name.episode)
    }

    func openURLs(_ urls: [URL]) {
        let items = urls.filter { $0.isFileURL && Indexer.extensions.contains($0.pathExtension.lowercased()) }
        guard let url = items.first else { return }
        stagedFiles = items
        play(series.flatMap(\.episodes).first { $0.url == url } ?? makeEpisode(url))
    }

    func play(_ episode: Episode, restart: Bool = false) {
        saveProgress()
        subtitleTask?.cancel()
        skipTask?.cancel()
        subtitleStatus = ""
        workingSubtitles = false
        subtitleOptions = []
        subtitleFile = nil
        modifyingSkip = nil
        markStart = nil
        syncAnchor = nil
        introSession = IntroSession()
        introKept = false
        introUndo = nil
        introCountdown = nil
        current = episode
        checkFollowingSeason(episode)
        playlistFocus = episode.id
        tab = .player
        let point = progress(episode)
        player.open(episode.url, resume: restart || point.watched ? 0 : point.seconds)
    }

    func saveProgress() {
        guard let current, player.loaded, player.duration > 0, player.position >= 0 else { return }
        let old = progress(current)
        state.history[current.progressID] = Progress(seconds: player.position, duration: player.duration, watched: old.watched, updated: Date())
        lastSave = Date()
        persist()
    }

    func markFinished() {
        guard let current else { return }
        var history = progress(current)
        history.watched = true
        history.duration = player.duration
        history.seconds = player.duration
        history.updated = Date()
        state.history[current.progressID] = history
        persist()
    }

    func toggleWatched(_ episode: Episode) {
        var item = progress(episode)
        item.watched.toggle()
        if !item.watched { item.seconds = 0 }
        item.updated = Date()
        state.history[episode.progressID] = item
        persist()
    }

    func markEpisodeSelection(watched: Bool) {
        let keys = Set(seasonEpisodes.filter { episodeSelection.contains($0.id) }.map(\.progressID))
        var history = state.history
        var changes: [String: WatchChange] = [:]
        let updated = Date()
        for key in keys {
            let previous = history[key]
            var item = previous ?? Progress()
            guard item.watched != watched else { continue }
            item.watched = watched
            if !watched { item.seconds = 0 }
            item.updated = updated
            changes[key] = WatchChange(previous: previous, updated: item)
            history[key] = item
        }
        clearEpisodeSelection()
        guard !changes.isEmpty else { return }
        state.history = history
        watchUndo = changes
        watchUndoCount = changes.count
        persist()
    }

    func undoEpisodeWatchChange() {
        var history = state.history
        for (key, change) in watchUndo where history[key] == change.updated {
            history[key] = change.previous
        }
        state.history = history
        watchUndo = [:]
        watchUndoCount = 0
        persist()
    }

    func timer() {
        if !player.paused, Date().timeIntervalSince(lastSave) > 10 { saveProgress() }
    }

    func introActivity() { introSession.lastActivity = ProcessInfo.processInfo.systemUptime }
    private var introKey: String? { current.map { $0.showID + "|" + String($0.season ?? 0) } }

    private func recordIntro(kept: Bool) {
        guard let key = introKey else { return }
        var stored = state.introPreferences ?? [:]
        var preference = stored[key] ?? IntroPreference()
        preference.record(current?.number, kept: kept)
        if stored[key] != preference { stored[key] = preference; state.introPreferences = stored; persist() }
    }

    func introTick() {
        guard !selfTest else { return }
        if let introUndo, player.position > introUndo.end + 8 { self.introUndo = nil }
        let behavior = UserDefaults.standard.string(forKey: "introBehavior").flatMap(IntroBehavior.init(rawValue:)) ?? .adaptive
        if behavior == .manual { introCountdown = nil; return }
        guard !introSession.resolved else { return }
        let segment = player.currentSkip
        let inside = segment?.kind == "op"
        if !inside, introSession.wasVisible, !player.paused,
           let opening = player.skips.first(where: { $0.kind == "op" }),
           (opening.end - 0.35 ... opening.end + 0.8).contains(player.position) {
            introSession.resolved = true
            recordIntro(kept: true)
        }
        if !inside || player.paused {
            if introCountdown != nil { introCountdown = nil }
            if player.paused { introActivity() }
            return
        }
        let mode = behavior == .countdown ? .countdown : introKey.flatMap { state.introPreferences?[$0]?.mode } ?? .countdown
        switch introSession.assess(mode: mode, uptime: ProcessInfo.processInfo.systemUptime, position: player.position, playing: !player.paused, inside: inside) {
        case .skip:
            if let segment { skipSegment(segment, manual: false) }
        case .countdown(let value):
            if introCountdown != value { introCountdown = value }
        case .none: break
        }
    }

    func skipSegment(_ segment: SkipSegment, manual: Bool = true) {
        if segment.kind == "op" {
            if manual { recordIntro(kept: false) }
            else { introUndo = segment }
            introSession.resolved = true
            if introCountdown != nil { introCountdown = nil }
        }
        player.seek(segment.end)
    }

    func undoIntro() {
        guard let introUndo else { return }
        self.introUndo = nil
        keepIntro()
        player.seek(introUndo.start)
    }

    func keepIntro() {
        introSession.resolved = true
        introKept = true
        introCountdown = nil
        recordIntro(kept: true)
    }

    private func loaded() {
        guard let current else { return }
        let storage = SubtitleService.version(current)
        let saved = state.localSkips[storage] ?? []
        for segment in saved {
            player.skips.removeAll { $0.kind == segment.kind }
            player.skips.append(SkipSegment(kind: segment.kind, start: segment.start, end: segment.end))
        }
        if selfTest { return }
        pickSubtitles(state.shows[current.showID]?.subtitle.nonEmpty ?? UserDefaults.standard.string(forKey: "preferredSubtitle") ?? "fr")
        findSkips(current)
    }

    func metadata(for show: Series) {
        metadataBusy = true
        matches = []
        Task {
            defer { metadataBusy = false }
            do {
                let candidates = try await Catalog.lookup(show.query, id: state.shows[show.id]?.aniListID)
                guard selected == show.id else { return }
                matches = candidates
                if let exact = exactMatch(candidates, title: show.query) ?? (state.shows[show.id]?.aniListID == nil ? nil : candidates.first) {
                    anime[show.id] = exact
                }
                if candidates.isEmpty { message = "Aucune fiche AniList trouvée." }
            } catch { message = error.localizedDescription }
        }
    }

    func assign(_ entry: Anime, to show: Series) {
        anime[show.id] = entry
        updateShow(show.id) { $0.aniListID = entry.id }
        matches = []
        if let current, current.showID == show.id { findSkips(current) }
    }

    private func exactMatch(_ candidates: [Anime], title: String) -> Anime? {
        let matches = candidates.filter { anime in
            [anime.title.romaji, anime.title.english, anime.title.native].compactMap { $0?.normalized }.contains(title.normalized)
        }
        return matches.count == 1 ? matches.first : nil
    }

    private func findSkips(_ episode: Episode) {
        guard let number = episode.number, player.duration > 0, Set(player.skips.map(\.kind)).count < 2 else { return }
        let duration = player.duration
        skipTask?.cancel()
        skipTask = Task {
            guard let entry = try? await animeFor(episode), let mal = entry.idMal,
                  let skip = try? await Catalog.skip(malID: mal, episode: number, duration: duration),
                  !Task.isCancelled, current == episode else { return }
            for segment in skip where !player.skips.contains(where: { $0.kind == segment.kind }) { player.skips.append(segment) }
        }
    }

    private func animeFor(_ episode: Episode) async throws -> Anime? {
        if let saved = anime[episode.showID] { return saved }
        let query = state.shows[episode.showID]?.query.nonEmpty ?? episode.title
        let id = state.shows[episode.showID]?.aniListID
        // A later season may share the base filename of season one.
        let seasonQuery = (episode.season ?? 0) > 1 && id == nil ? query + " Season \(episode.season!)" : query
        let results = try await Catalog.lookup(seasonQuery, id: id)
        return id == nil ? exactMatch(results, title: seasonQuery) : results.first
    }

    func japaneseTitle(for episode: Episode) async -> String? {
        let preference = state.shows[episode.showID]
        let query = preference?.query.nonEmpty ?? episode.title
        let base = SeasonNumber.base(query)
        let item: Anime?
        if let season = episode.season, season > 1 {
            item = await ArtworkCatalog.shared.season(season, title: base, id: preference?.aniListID)
        } else {
            item = await ArtworkCatalog.shared.match(query, id: preference?.aniListID)
        }
        guard let item, item.countryOfOrigin == "JP" else { return nil }
        return item.title.native?.nonEmpty
    }

    func saveSkip(_ kind: String) {
        guard let current, let start = markStart, player.position - start >= 2 else { return }
        let storage = SubtitleService.version(current)
        let segment = SavedSegment(kind: kind, start: start, end: player.position)
        state.localSkips[storage, default: []].removeAll { $0.kind == kind }
        state.localSkips[storage, default: []].append(segment)
        player.skips.removeAll { $0.kind == kind }
        player.skips.append(SkipSegment(kind: kind, start: start, end: player.position))
        markStart = nil
        modifyingSkip = nil
        persist()
    }

    private func languageTrack(_ language: String) -> Track? {
        let tracks = player.tracks.filter { $0.kind == "sub" && $0.shortLanguage == language }
        return tracks.first { $0.title.match(#"(?i)signs|songs|panneaux|forced|commentary|karaoke"#) == nil } ?? tracks.first
    }

    func cycleSubtitles() {
        let modes = UserDefaults.standard.bool(forKey: "englishInSubtitleCycle") ? ["ja", "fr", "en", "off"] : ["ja", "fr", "off"]
        if let index = modes.firstIndex(of: requestedSubtitle) {
            pickSubtitles(modes[(index + 1) % modes.count], remember: true)
        } else { pickSubtitles("ja", remember: true) }
    }

    func pickSubtitles(_ language: String, remember: Bool = false) {
        guard let current else { return }
        requestedSubtitle = language
        if remember { updateShow(current.showID) { $0.subtitle = language } }
        subtitleTask?.cancel()
        workingSubtitles = false
        subtitleOptions = []
        subtitleStatus = ""
        subtitleFile = nil
        syncAnchor = nil
        player.setDelay(0)
        if language == "off" { player.subtitles(nil); return }
        let version = SubtitleService.version(current)
        if let path = state.synchronizedSubtitles?[version + "|" + language], FileManager.default.fileExists(atPath: path) {
            loadSubtitle(URL(fileURLWithPath: path), language: language)
            return
        }
        if let track = languageTrack(language) { chooseTrack(track); return }
        let directory = SubtitleService.cacheDirectory(current)
        if let cached = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))?
            .first(where: { $0.lastPathComponent.hasPrefix(language + "-") && SubtitleService.types.contains($0.pathExtension.lowercased()) }) {
            loadSubtitle(cached, language: language)
            return
        }
        let hasOpenSubtitles = !Vault.get("open-key").isEmpty
        let hasJimaku = !Vault.get("jimaku").isEmpty
        let languages: [String]
        if language != "en", languageTrack("fr") == nil, languageTrack("ja") == nil {
            languages = [language, language == "fr" ? "ja" : "fr", "en"]
        } else { languages = [language] }
        let providers = languages.filter { hasOpenSubtitles || ($0 == "ja" && hasJimaku) }
        useEnglishFallback()
        guard !providers.isEmpty else { return }
        subtitleTask = Task {
            workingSubtitles = true
            subtitleStatus = "Recherche de sous-titres…"
            defer { if !Task.isCancelled { workingSubtitles = false } }
            do {
                var options: [SubtitleCandidate] = []
                var failure: Error?
                for wanted in providers {
                    if wanted != language && languageTrack(wanted) != nil { continue }
                    let entry = wanted == "ja" ? try? await animeFor(current) : nil
                    do {
                        options = try await SubtitleService.candidates(current, language: wanted, anime: entry)
                        if !options.isEmpty { break }
                    } catch { failure = error }
                }
                guard !Task.isCancelled, self.current == current else { return }
                if options.isEmpty, let failure { throw failure }
                if let best = options.first, best.exact {
                    let file = try await SubtitleService.fetch(best, for: current)
                    guard !Task.isCancelled, self.current == current else { return }
                    loadSubtitle(file, language: best.language)
                    subtitleStatus = "\(best.language.uppercased()) téléchargé · correspondance exacte"
                } else {
                    subtitleOptions = options
                    if options.isEmpty { useEnglishFallback() }
                    else { subtitleStatus = "Choisis le fichier qui correspond à ta version." }
                }
            } catch {
                guard !Task.isCancelled, self.current == current else { return }
                useEnglishFallback()
                subtitleStatus = error.localizedDescription
            }
        }
    }

    private func useEnglishFallback() {
        if let alternative = languageTrack("fr") ?? languageTrack("ja") {
            chooseTrack(alternative)
            subtitleStatus = "Piste choisie indisponible · " + alternative.shortLanguage.uppercased() + " chargé."
        } else if let english = languageTrack("en") {
            chooseTrack(english)
            subtitleStatus = "Sous-titres anglais disponibles."
        } else { subtitleStatus = "Piste absente. Tu peux ajouter un fichier ou régler les fournisseurs." }
    }

    func chooseTrack(_ track: Track) {
        subtitleFile = nil
        syncAnchor = nil
        player.subtitles(track.id)
        player.setDelay(current.flatMap { state.subtitleDelays[delayKey($0)] } ?? 0)
    }

    func chooseCandidate(_ candidate: SubtitleCandidate) {
        guard let current else { return }
        subtitleTask?.cancel()
        workingSubtitles = true
        subtitleTask = Task {
            defer { if !Task.isCancelled { workingSubtitles = false } }
            do {
                let url = try await SubtitleService.fetch(candidate, for: current)
                guard !Task.isCancelled, self.current == current else { return }
                subtitleOptions = []
                loadSubtitle(url, language: candidate.language)
                subtitleStatus = "Sous-titre chargé."
            } catch { if !Task.isCancelled { subtitleStatus = error.localizedDescription } }
        }
    }

    private func delayKey(_ episode: Episode) -> String {
        SubtitleService.version(episode) + "|" + (subtitleFile?.path ?? "piste-\(player.activeSubtitle ?? 0)")
    }

    func loadSubtitle(_ url: URL, language: String? = nil) {
        subtitleFile = url
        syncAnchor = nil
        player.addSubtitle(url, language: language)
        player.setDelay(current.flatMap { state.subtitleDelays[delayKey($0)] } ?? 0)
    }

    func changeDelay(_ value: Double) {
        guard let current else { return }
        player.setDelay(value)
        state.subtitleDelays[delayKey(current)] = value
        persist()
    }

    var canAlignTwoPoints: Bool { subtitleFile != nil }
    func syncPoint() {
        guard subtitleFile != nil else { return }
        if let first = syncAnchor {
            let second = player.position
            let offset = player.delay
            guard second - first >= 10 else { subtitleStatus = "Avance d’au moins dix secondes et recale une autre réplique."; return }
            let sourceStart = first - anchorDelay
            let sourceEnd = second - offset
            guard sourceEnd - sourceStart > 0 else { subtitleStatus = "Les deux repères sont trop proches."; return }
            let scale = (second - first) / (sourceEnd - sourceStart)
            guard (0.8...1.25).contains(scale) else { subtitleStatus = "La différence entre les deux repères est trop grande."; return }
            let intercept = first - scale * sourceStart
            synchronize(manual: (scale, intercept))
        } else {
            syncAnchor = player.position
            anchorDelay = player.delay
            subtitleStatus = "Premier point gardé. Avance, ajuste une autre réplique, puis applique."
        }
    }

    func autoSynchronize() { synchronize(manual: nil) }

    private func synchronize(manual: (scale: Double, offset: Double)?) {
        guard let current, let subtitleFile else { subtitleStatus = "Ajoute d’abord un sous-titre externe SRT ou ASS."; return }
        guard !workingSubtitles else { return }
        let folder = FileManager.support.appendingPathComponent("sync/bin")
        let tool = folder.appendingPathComponent(manual == nil ? "ffsubsync" : "python")
        guard FileManager.default.isExecutableFile(atPath: tool.path) else {
            subtitleStatus = "Le module de recalage n’est pas installé. Voir Réglages."
            return
        }
        let language = player.tracks.first { $0.kind == "sub" && $0.id == player.activeSubtitle }?.shortLanguage.nonEmpty
        workingSubtitles = true
        subtitleStatus = manual == nil ? "Analyse de l’audio…" : "Application des repères…"
        let target = SubtitleService.cacheDirectory(current).appendingPathComponent("recalé-" + UUID().uuidString + "." + subtitleFile.pathExtension)
        Task {
            let success = await Task.detached(priority: .utility) {
                do {
                    try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                    let process = Process()
                    process.executableURL = tool
                    if let manual, let script = Bundle.main.url(forResource: "retime", withExtension: "py") {
                        process.arguments = [script.path, subtitleFile.path, target.path, String(manual.scale), String(manual.offset)]
                    } else {
                        process.arguments = [current.url.path, "-i", subtitleFile.path, "-o", target.path, "--skip-sync-on-low-quality"]
                    }
                    var environment = ProcessInfo.processInfo.environment
                    environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
                    process.environment = environment
                    process.standardOutput = FileHandle.nullDevice
                    process.standardError = FileHandle.nullDevice
                    try process.run()
                    process.waitUntilExit()
                    return process.terminationStatus == 0 && FileManager.default.fileExists(atPath: target.path)
                } catch { return false }
            }.value
            guard self.current == current, self.subtitleFile == subtitleFile else { return }
            workingSubtitles = false
            if success {
                if let language {
                    var saved = state.synchronizedSubtitles ?? [:]
                    saved[SubtitleService.version(current) + "|" + language] = target.path
                    state.synchronizedSubtitles = saved
                    persist()
                }
                loadSubtitle(target, language: language)
                subtitleStatus = "Recalage appliqué. Vérifie sur quelques répliques."
            } else { subtitleStatus = "Le recalage n’a pas abouti. Essaie le réglage manuel." }
        }
    }

    private var recommendationBasis: String?
    func discover() async {
        guard allowsDownloads, libraryReady, !selfTest, !recommending else { return }
        let known = series.compactMap { show -> (Series, Double)? in
            let watched = show.episodes.filter { progress($0).watched }.count
            guard watched > 0 else { return nil }
            return (show, Double(watched) + (score(show) ?? 0) / 4)
        }.sorted { $0.1 > $1.1 }
        let rated = series.filter { (score($0) ?? 0) >= 7 }.sorted { (score($0) ?? 0) > (score($1) ?? 0) }
        let seeds = Array((known.map { $0.0 } + rated.filter { s in !known.contains { $0.0.id == s.id } }).prefix(3))
        let excluded = (state.nautiljonSeen ?? []).union((state.nautiljonWatchlist ?? []).flatMap(\.keys))
        let fingerprint = String(excluded.hashValue) + "|" + seeds.map { seed in
            seed.id + (known.contains { $0.0.id == seed.id } ? ":seen" : ":rated")
        }.joined(separator: "|")
        guard recommendationBasis != fingerprint else { return }
        recommending = true
        defer { recommending = false }
        var found: [Discovery] = []
        var seen = excluded.union(series.flatMap { [$0.title.normalized, $0.query.normalized] })
        func accept(_ anime: Anime) -> Bool {
            let keys = anime.titleKeys
            guard anime.status != "NOT_YET_RELEASED", anime.status != "CANCELLED", keys.isDisjoint(with: seen) else { return false }
            seen.formUnion(keys)
            return true
        }
        for seed in seeds {
            guard let match = await ArtworkCatalog.shared.match(seed.query, id: state.shows[seed.id]?.aniListID),
                  let choices = try? await Catalog.discover(basedOn: match.id) else { continue }
            for choice in choices where accept(choice) {
                found.append(Discovery(entry: choice, reason: (known.contains { $0.0.id == seed.id } ? "Après " : "Parce que tu as aimé ") + seed.title))
            }
        }
        if found.isEmpty, let choices = try? await Catalog.discover(basedOn: nil) {
            found = choices.filter(accept).map { Discovery(entry: $0, reason: nil) }
        }
        guard !Task.isCancelled else { return }
        let currentlySeen = (state.nautiljonSeen ?? []).union((state.nautiljonWatchlist ?? []).flatMap(\.keys))
        recommendations = Array(found.filter { $0.entry.titleKeys.isDisjoint(with: currentlySeen) }.prefix(12))
        if !found.isEmpty { recommendationBasis = fingerprint }
    }

    func findRecommendation(_ item: Discovery) {
        searchRecommendation(title: item.entry.name)
    }

    private func searchRecommendation(title: String) {
        presentedAnime = nil
        downloadSeries = nil
        search = title
        requestedEpisode = nil
        episodeNumber = ""; seasonNumber = ""; packs = nil
        downloadPane = .search
        tab = .downloads
        searchTorrents()
    }

    func downloadRecommendation(_ item: Discovery) {
        let source = series.first { !$0.episodes.isEmpty && item.entry.titleKeys.contains($0.query.normalized) }
        startQuickDownload(query: item.entry.name, id: item.entry.id, season: nil, source: source) {
            self.findRecommendation(item)
        }
    }

    func downloadLibrarySeason(_ show: Series) {
        let season = librarySeason ?? show.episodes.compactMap(\.season).min() ?? 1
        let id = season == 1 ? state.shows[show.id]?.aniListID : nil
        startQuickDownload(query: show.query, id: id, season: season, source: show) {
            self.downloadSeries = show
            self.search = SeasonNumber.base(show.query)
            self.episodeNumber = ""
            self.seasonNumber = String(season)
            self.packs = nil
            self.downloadPane = .search
            self.tab = .downloads
            self.searchTorrents()
        }
    }

    private func startQuickDownload(query: String, id: Int?, season: Int?, source: Series?, inPlayer: Bool = false,
                                    fallback: @escaping () -> Void) {
        guard !addingTorrent else { return }
        inspected = nil
        if UserDefaults.standard.object(forKey: "automaticDownloadSelection") as? Bool == false {
            fallback()
            return
        }
        addingTorrent = true
        quickDownloadStatus = "Recherche du téléchargement…"
        downloadMessage = ""
        let root = downloadFolder
        Task {
            defer { addingTorrent = false; quickDownloadStatus = "" }
            do {
                let entry: Anime?
                if let id {
                    entry = try await Catalog.lookup(query, id: id).first
                } else if let season {
                    entry = await ArtworkCatalog.shared.season(season, title: SeasonNumber.base(query))
                } else {
                    entry = await ArtworkCatalog.shared.match(query)
                }
                guard let entry else {
                    fallback()
                    downloadMessage = "La fiche de cet animé reste à identifier. Tu peux choisir une version."
                    return
                }
                guard entry.status == "FINISHED" || entry.status == "RELEASING" else {
                    throw Notice("Cet animé n’est pas encore disponible.")
                }
                let names = [entry.title.romaji, entry.title.english].compactMap { $0 }
                let number = season ?? names.lazy.compactMap(SeasonNumber.first).first ?? 1
                let name = source?.title ?? entry.name
                let showID = source?.id ?? name.normalized
                let transferScope = showID + "|" + String(number)
                await checkTransfers(force: true)
                if activeTransfers.contains(where: { !$0.state.contains("error") && state.transferSeasons?[$0.id] == transferScope }) {
                    presentedAnime = nil
                    downloadPane = .transfers
                    if inPlayer, tab == .player { playerDownloadsOpen = true }
                    else { tab = .downloads }
                    return
                }
                let base = SeasonNumber.base(source?.query ?? query)
                let matchKeys = Set((names + [base]).map { SeasonNumber.base($0).normalized })
                let airing = entry.status == "RELEASING"
                let film = entry.format == "MOVIE"
                let end = airing ? entry.nextAiringEpisode.map { $0.episode - 1 } : entry.episodes
                if end == 0 { throw Notice("Aucun épisode diffusé pour le moment.") }
                if !airing, !film, end == nil { throw Notice("Le nombre d’épisodes reste à vérifier.") }
                let existing = Set((source?.episodes ?? []).filter { ($0.season ?? 1) == number }.compactMap(\.number))
                let expected = Set((1...max(1, end ?? 1))).subtracting(existing)
                if !film, end != nil, expected.isEmpty {
                    throw Notice("Tous les épisodes disponibles sont déjà dans ta bibliothèque.")
                }
                let defaults = UserDefaults.standard
                let groups = defaults.string(forKey: "torrentGroups") ?? NyaaSource.defaults
                let seeds = defaults.object(forKey: "minimumSeeds") as? Int ?? 8
                let results = try await TorrentSearch.search(base, groups: groups, minimumSeeds: seeds,
                    packs: !airing && !film ? true : nil, episode: nil, resultLimit: 200)
                let matching = results.filter { row in
                    guard row.seasons.count <= 1, matchKeys.contains(SeasonNumber.base(row.matchingTitle).normalized) else { return false }
                    return (row.season ?? 1) == number
                }
                let knownTransfers = Set(activeTransfers.map(\.id))
                let rows = matching.filter { !knownTransfers.contains($0.id) }
                var selections: [(row: TorrentResult, preview: TorrentPreview, files: Set<Int>)] = []
                var missing = expected
                var selectedNumbers: Set<Int> = []
                for row in rows.filter({ film ? !$0.isPack : $0.isPack }).prefix(10) {
                    guard let preview = try? await TorrentSearch.preview(row) else { continue }
                    if film {
                        let videos = preview.files.filter { $0.isVideo && $0.path.match(Indexer.musicVideos) == nil }
                        if videos.count == 1 { selections.append((row, preview, [videos[0].id])); break }
                    } else {
                        let files = TorrentSearch.seasonFiles(preview, season: number, through: end)
                        let numbers = Set(files.keys).subtracting(existing)
                        if !numbers.isEmpty, (airing || numbers == missing) {
                            let new = numbers.subtracting(selectedNumbers)
                            if !new.isEmpty {
                                selections.append((row, preview, Set(new.compactMap { files[$0] })))
                                selectedNumbers.formUnion(new)
                                missing.subtract(new)
                            }
                            if !airing || (end != nil && missing.isEmpty) { break }
                        }
                    }
                }
                if airing, end == nil || !missing.isEmpty {
                    for row in rows {
                        guard let episode = row.episode, episode > 0, !existing.contains(episode), !selectedNumbers.contains(episode),
                              end.map({ episode <= $0 }) ?? true,
                              let preview = try? await TorrentSearch.preview(row) else { continue }
                        let files = TorrentSearch.seasonFiles(preview, season: number, through: end)
                        guard let file = files[episode] else { continue }
                        selections.append((row, preview, [file]))
                        selectedNumbers.insert(episode)
                    }
                }
                guard !selections.isEmpty else {
                    fallback()
                    downloadMessage = "Aucun pack ou épisode vérifié automatiquement. Tu peux choisir une version."
                    return
                }
                guard root == downloadFolder else { throw Notice("Le dossier de la bibliothèque a changé. Relance le téléchargement.") }
                let safeName = name.replacingOccurrences(of: "/", with: "／").trimmed
                guard !["", ".", ".."].contains(safeName) else { throw Notice("Le titre du dossier est invalide.") }
                let folder = root.appendingPathComponent(safeName, isDirectory: true)
                    .appendingPathComponent("Saison \(number)", isDirectory: true)
                var succeeded = 0
                var firstError: Error?
                for selection in selections {
                    do {
                        try await torrent.add(selection.row, preview: selection.preview, selected: selection.files, folder: folder)
                        succeeded += selection.files.count
                        focusedTransfer = selection.row.id
                        state.transferSeasons = (state.transferSeasons ?? [:]).merging([selection.row.id: transferScope]) { _, latest in latest }
                    } catch { if firstError == nil { firstError = error } }
                }
                if succeeded == 0 { throw firstError ?? Notice("Le téléchargement n’a pas démarré.") }
                state.downloadFolders = (state.downloadFolders ?? [:]).merging([safeName: showID]) { _, latest in latest }
                persist()
                presentedAnime = nil
                downloadPane = .transfers
                if inPlayer, tab == .player { playerDownloadsOpen = true }
                else if tab == .home || tab == .library { tab = .downloads }
                if let firstError { downloadMessage = "\(succeeded) fichier(s) lancé(s) · \(firstError.localizedDescription)" }
                else if airing, let end, !missing.subtracting(selectedNumbers).isEmpty {
                    downloadMessage = "\(succeeded) épisode(s) lancé(s) sur les \(end) déjà diffusés."
                }
                await checkTransfers(force: true)
            } catch {
                message = error.localizedDescription
            }
        }
    }

    func findDownloads(_ show: Series, episode: Episode? = nil) {
        downloadSeries = show
        search = show.query
        episodeNumber = episode?.number.map(String.init) ?? ""
        seasonNumber = episode?.season.map(String.init) ?? ""
        packs = episode == nil
        downloadPane = .search
        tab = .downloads
        searchTorrents()
    }

    var activeTransfers: [Transfer] { transfers.filter { !$0.finished } }

    func selectDownloadPane(_ pane: DownloadPane) {
        guard !addingTorrent else { return }
        downloadPane = pane
        inspected = nil
        downloadMessage = ""
        if pane == .transfers { Task { await checkTransfers(force: true) } }
    }

    func openPlayerDownloads() {
        guard allowsDownloads else { return }
        if playerDownloadsOpen { closePlayerDownloads(); return }
        playerDownloadsOpen = true
        downloadPane = activeTransfers.isEmpty && availableDownloads.isEmpty ? .search : .transfers
        if search.trimmed.isEmpty, let current {
            downloadSeries = series.first { $0.id == current.showID }
            search = SeasonNumber.base(downloadSeries?.query ?? current.title)
        }
        Task { await checkTransfers(force: true) }
    }

    func closePlayerDownloads() {
        guard playerDownloadsOpen else { return }
        playerDownloadsOpen = false
        if !addingTorrent { inspected = nil; downloadMessage = "" }
    }

    func chooseTorrent() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "torrent") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importTorrent(url)
    }

    func openFiles(_ urls: [URL]) {
        if allowsDownloads, let torrent = urls.first(where: { $0.isFileURL && $0.pathExtension.lowercased() == "torrent" }) {
            importTorrent(torrent)
        } else { openURLs(urls) }
    }

    func importTorrent(_ url: URL) {
        guard allowsDownloads, !addingTorrent else { return }
        if tab == .player { playerDownloadsOpen = true }
        else { tab = .downloads }
        downloadPane = .search
        downloadMessage = ""
        inspected = nil
        preview = nil
        chosenFiles = []
        do {
            let (item, payload) = try TorrentSearch.local(url)
            inspected = item
            preview = payload
            chosenFiles = Set(payload.files.filter(\.isVideo).map(\.id))
        } catch { downloadMessage = error.localizedDescription }
    }

    func openCompletedDownload(_ download: AvailableDownload) {
        guard openingDownload == nil else { return }
        openingDownload = download.id
        downloadMessage = ""
        Task {
            defer { openingDownload = nil }
            let videos = download.videos.filter { url in
                (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            }
            guard let first = videos.first else {
                downloadMessage = "Les vidéos de ce téléchargement ont été déplacées ou supprimées."
                return
            }
            if !series.contains(where: { $0.episodes.contains { $0.url.path == first.path } }) {
                await refresh().value
            }
            closePlayerDownloads()
            openURLs(videos)
        }
    }

    func searchTorrents() {
        guard !search.trimmed.isEmpty else { return }
        searchTask?.cancel()
        searchGeneration += 1
        let generation = searchGeneration
        searching = true
        downloadMessage = ""
        torrentResults = []
        let query = search.trimmed
        let packMode = packs
        let episode = packMode == true ? nil : Int(episodeNumber)
        let tokens = seasonNumber.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let seasons = Set(tokens.compactMap(Int.init))
        if (!episodeNumber.isEmpty && packMode != true && episode == nil) ||
           tokens.contains(where: { Int($0).map { !(1...99).contains($0) } ?? true }) {
            searching = false
            downloadMessage = "Saisis un numéro de saison ou d’épisode valide."
            return
        }
        requestedSeasons = seasons
        requestedEpisode = episode
        searchTask = Task {
            defer { if generation == searchGeneration { searching = false } }
            do {
                let defaults = UserDefaults.standard
                let rows = try await TorrentSearch.search(query, groups: defaults.string(forKey: "torrentGroups") ?? NyaaSource.defaults,
                    minimumSeeds: defaults.object(forKey: "minimumSeeds") as? Int ?? 8, packs: packMode, episode: episode, seasons: seasons)
                guard !Task.isCancelled, generation == searchGeneration else { return }
                torrentResults = rows
                if rows.isEmpty { downloadMessage = "Aucun résultat dans tes groupes avec ce seuil de seeders." }
            } catch { if !Task.isCancelled, generation == searchGeneration { downloadMessage = error.localizedDescription } }
        }
    }

    func inspect(_ item: TorrentResult) {
        downloadMessage = ""
        inspected = item
        preview = nil
        chosenFiles = []
        preparingPreview = true
        Task {
            do {
                let result = try await TorrentSearch.preview(item)
                guard inspected == item else { return }
                preview = result
                chosenFiles = Set(result.files.filter { file in
                    guard file.isVideo else { return false }
                    if let requestedEpisode, file.episode != requestedEpisode {
                        return result.files.filter(\.isVideo).count == 1 && file.episode == nil && item.episode == requestedEpisode
                    }
                    if !requestedSeasons.isEmpty, item.seasons.count > 1 {
                        return file.season.map { requestedSeasons.contains($0) } ?? false
                    }
                    return true
                }.map(\.id))
            } catch { if inspected == item { downloadMessage = error.localizedDescription } }
            if inspected == item { preparingPreview = false }
        }
    }

    func addTorrent() {
        guard let inspected, let preview, !chosenFiles.isEmpty, !addingTorrent else { return }
        let selected = chosenFiles
        let source = downloadSeries.map { $0.query.normalized == search.trimmed.normalized || SeasonNumber.base($0.query).normalized == search.trimmed.normalized } == true
            ? downloadSeries
            : series.first { $0.query.normalized == search.trimmed.normalized }
        let title = ReleaseName(inspected.title).title.replacingOccurrences(of: "/", with: "／").trimmed
        let safeName = [".", "..", ""].contains(title) ? inspected.id : title
        let folder = downloadFolder.appendingPathComponent(safeName, isDirectory: true)
        let onlySeason = !inspected.torrent.isFileURL && requestedSeasons.count == 1 ? requestedSeasons.first : nil
        let matchingShow = inspected.torrent.isFileURL ? nil : source
        addingTorrent = true
        downloadMessage = ""
        Task {
            defer { addingTorrent = false }
            do {
                try await torrent.add(inspected, preview: preview, selected: selected, folder: folder)
                if let source = matchingShow {
                    state.downloadFolders = (state.downloadFolders ?? [:]).merging([safeName: source.id]) { _, latest in latest }
                    if let season = onlySeason, preview.files.contains(where: { selected.contains($0.id) && $0.isVideo && $0.episode == 1 }) {
                        state.transferSeasons = (state.transferSeasons ?? [:]).merging([inspected.id: source.id + "|" + String(season)]) { _, latest in latest }
                    }
                    persist()
                }
                self.inspected = nil
                focusedTransfer = inspected.id
                downloadPane = .transfers
                await checkTransfers(force: true)
            } catch { downloadMessage = error.localizedDescription }
        }
    }

    func checkTransfers(force: Bool = false) async {
        guard !selfTest else { return }
        guard !checkingTransfers, (force || tab == .downloads || playerDownloadsOpen || !activeTransfers.isEmpty) else { return }
        checkingTransfers = true
        defer { checkingTransfers = false }
        do {
            let snapshot = try await torrent.transferSnapshot()
            if snapshot.active != transfers { transfers = snapshot.active }
            let playable = playableDownloads(snapshot.available)
            if playable != availableDownloads { availableDownloads = playable }
            transferStatus = ""
            let downloading = Set(transfers.filter { !$0.finished && !$0.content_path.isEmpty }.map(\.content_path))
            let needsRefresh = downloading != activeTransferPaths || snapshot.completed
            activeTransferPaths = downloading
            if needsRefresh { refresh() }
        } catch { transferStatus = error.localizedDescription }
    }

    private func playableDownloads(_ downloads: [AvailableDownload]) -> [AvailableDownload] {
        downloads.compactMap { download in
            let videos = download.videos.filter {
                (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            }
            guard !videos.isEmpty else { return nil }
            return AvailableDownload(id: download.id, title: download.title, videos: videos,
                                     finishedAt: download.finishedAt)
        }
    }

    func transferAction(_ transfer: Transfer) {
        Task {
            do {
                try await torrent.action(transfer.id, start: transfer.onHold)
                await checkTransfers(force: true)
            } catch { downloadMessage = error.localizedDescription }
        }
    }

}
