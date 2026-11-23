import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var model: Model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("preferredSubtitle") private var preferred = "fr"
    @AppStorage("theme") private var theme: YoruTheme = InterfaceDefaults.theme
    @AppStorage("lightweight") private var lightweight = false
    @AppStorage(YoruUsageMode.preferenceKey) private var usagePreference = ""
    @AppStorage("lowercaseInterface") private var lowercaseInterface = InterfaceDefaults.lowercase
    @AppStorage("playerTitleStyle") private var titleStyle: PlayerTitleStyle = .wordmark
    @AppStorage("showSeekButtons") private var showSeekButtons = false
    @AppStorage("playbackArrows") private var playbackArrows: PlaybackArrows = .hybrid
    @AppStorage("animatePlaybackButtons") private var animatePlaybackButtons = true
    @AppStorage("browsePlayback") private var browsePlayback: BrowsePlayback = .bubble
    @AppStorage("showAudioOutputButton") private var showAudioOutputButton = false
    @AppStorage("seekButtonSeconds") private var seekButtonSeconds = 10
    @AppStorage("playerControlsTimeout") private var controlsTimeout = 2
    @AppStorage("fitPlaybackOnFirstOpen") private var fitPlaybackOnFirstOpen = true
    @AppStorage("inlinePlayerNavigation") private var inlinePlayerNavigation = InterfaceDefaults.inlinePlayerNavigation
    @AppStorage("hidePlayerNavigationWithControls") private var hidePlayerNavigationWithControls = true
    @AppStorage("autoAdvanceAtEnding") private var autoAdvanceAtEnding = true
    @AppStorage("introBehavior") private var introBehavior: IntroBehavior = .adaptive
    @AppStorage("englishInSubtitleCycle") private var englishInSubtitleCycle = false
    @AppStorage("showRecommendations") private var showRecommendations = true
    @AppStorage("showArtworkBlur") private var showArtworkBlur = true
    @AppStorage("automaticDownloadSelection") private var automaticDownloadSelection = true
    @AppStorage("torrentGroups") private var groups = NyaaSource.defaults
    @AppStorage("minimumSeeds") private var seeds = 8

    @FocusState private var editingField: String?
    @State private var section = SectionID.appearance
    @State private var showServices = false
    @State private var showSources = false
    @State private var showAudioOutputs = false
    @State private var savedCredentials: Credentials?
    @State private var credentials = Credentials()
    @State private var credentialStatus: String?

    private var labels: InterfaceLabels { InterfaceLabels(lowercase: lowercaseInterface) }
    private var usage: YoruUsageMode { YoruUsageMode(rawValue: usagePreference) ?? .complete }

    private enum SectionID: String, CaseIterable, Identifiable {
        case appearance = "Apparence"
        case playback = "Lecture"
        case subtitles = "Sous-titres"
        case library = "Bibliothèque"
        case downloads = "Téléchargements"

        var id: Self { self }

        var icon: String {
            switch self {
            case .appearance: return "paintpalette"
            case .playback: return "play.rectangle"
            case .subtitles: return "captions.bubble"
            case .library: return "square.grid.2x2"
            case .downloads: return "arrow.down.to.line"
            }
        }
    }

    private struct Credentials: Equatable {
        var jimaku = ""
        var openKey = ""
        var openUser = ""
        var openPassword = ""

        var entries: [(String, String)] {
            [("jimaku", jimaku), ("open-key", openKey), ("open-user", openUser), ("open-password", openPassword)]
        }

        static func load() -> Self {
            Self(jimaku: Vault.get("jimaku"), openKey: Vault.get("open-key"),
                 openUser: Vault.get("open-user"), openPassword: Vault.get("open-password"))
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(labels(section.rawValue))
                        .font(YoruTypography.display(38))
                        .accessibilityAddTraits(.isHeader)

                    switch section {
                    case .appearance: appearance
                    case .playback: playback
                    case .subtitles: subtitles
                    case .library: library
                    case .downloads: downloads
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 30)
                .padding(.vertical, 27)
            }
            .id(section)
            .transition(.opacity)
            .accessibilityLabel(labels(section.rawValue))
        }
        .frame(width: 790, height: 590)
        .background {
            if theme.secondaryGlow != nil { ArtBackdrop() }
            else { theme.background }
        }
        .foregroundStyle(theme.primary)
        .font(YoruTypography.text(17))
        .environment(\.yoruTheme, theme)
        .environment(\.colorScheme, theme.colorScheme)
        .tint(theme.accent)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 17) {
            Text(labels("Réglages"))
                .font(YoruTypography.display(31))
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 10)

            VStack(spacing: 5) {
                ForEach(SectionID.allCases.filter { item in
                    (item != .downloads || usage.hasDownloads) && (item != .library || usage.hasLibrary)
                }) { item in
                    Button {
                        withAnimation(reduceMotion || lightweight ? nil : .easeInOut(duration: 0.17)) {
                            section = item
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: item.icon)
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(section == item ? theme.accent : theme.mutedText)
                                .frame(width: 22)
                                .accessibilityHidden(true)
                            Text(labels(item.rawValue))
                                .font(YoruTypography.text(17, strong: true))
                                .lineLimit(1)
                                .minimumScaleFactor(0.94)
                        }
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        .background(section == item ? theme.tint : .clear, in: RoundedRectangle(cornerRadius: 14))
                        .overlay {
                            if section == item {
                                RoundedRectangle(cornerRadius: 14).strokeBorder(theme.accent.opacity(0.25))
                                    .allowsHitTesting(false)
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(DirectionalPlainStyle())
                    .accessibilityAddTraits(section == item ? .isSelected : [])
                }
            }

            Spacer()

            Button { dismiss() } label: {
                Label(labels("Fermer"), systemImage: "xmark")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(ControlStyle())
            .keyboardShortcut(.cancelAction)
        }
        .padding(16)
        .padding(.vertical, 11)
        .frame(width: 232)
        .background(theme.card.opacity(0.71))
        .overlay(alignment: .trailing) {
            Rectangle().fill(theme.divider).frame(width: 1).allowsHitTesting(false)
        }
    }

    private var appearance: some View {
        VStack(spacing: 16) {
            LanguageChoice()
            SettingsGroup(title: labels("Mode d’utilisation")) {
                settingChoice("Accueil et fonctionnalités", selection: $usagePreference,
                              choices: YoruUsageMode.allCases.map { ($0.rawValue, $0.title) })
                Text(L.tr(usage.detail)).font(YoruTypography.text(16)).foregroundStyle(theme.mutedText)
            }
            SettingsGroup(title: labels("Thème")) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 106), spacing: 10)], spacing: 10) {
                    ForEach(YoruTheme.allCases) { item in
                        themePreview(item)
                    }
                }
            }

            SettingsGroup(title: labels("Interface")) {
                settingToggle("Fonds floutés", isOn: $showArtworkBlur)
                settingToggle("Libellés en minuscules", isOn: $lowercaseInterface)
                settingToggle("Interface légère", isOn: $lightweight)
            }
        }
    }

    private func themePreview(_ item: YoruTheme) -> some View {
        Button { theme = item } label: {
            VStack(alignment: .leading, spacing: 7) {
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.linearGradient(colors: [item.background, item.secondaryGlow ?? item.card],
                                             startPoint: .bottomLeading, endPoint: .topTrailing))
                    Capsule().fill(item.accent).frame(width: 28, height: 6)
                        .padding(8)
                }
                .frame(height: 36)

                Text(item.name)
                    .font(YoruTypography.text(16, strong: true))
                    .lineLimit(1)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme == item ? theme.tint : theme.background.opacity(0.70), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(theme == item ? theme.accent : theme.divider, lineWidth: theme == item ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(DirectionalPlainStyle())
        .accessibilityAddTraits(theme == item ? .isSelected : [])
    }

    private var playback: some View {
        VStack(spacing: 16) {
            SettingsGroup(title: labels("Audio")) {
                HStack(spacing: 12) {
                    Text(labels("Sortie audio"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityHidden(true)
                    AudioOutputControl(player: model.player, showingChoices: $showAudioOutputs)
                }
                .frame(minHeight: 46)
                settingToggle("Afficher le bouton de sortie audio dans le lecteur", isOn: $showAudioOutputButton)
            }

            SettingsGroup(title: labels("Fenêtre et commandes")) {
                settingChoice("Titre dans le lecteur", selection: $titleStyle,
                              choices: [(.wordmark, "Police Yoru"), (.japanese, "Japonais si disponible")])
                settingChoice("Position de la barre", selection: $inlinePlayerNavigation,
                              choices: [(true, "À côté des boutons macOS"), (false, "Sous les boutons macOS")])
                settingToggle("Masquer la barre avec les commandes", isOn: $hidePlayerNavigationWithControls)
                settingToggle("Ajuster la fenêtre à la première lecture", isOn: $fitPlaybackOnFirstOpen)
                settingChoice("Flèches du clavier", selection: $playbackArrows,
                              choices: PlaybackArrows.allCases.map { ($0, $0.title) })
                settingChoice("En dehors de l’onglet Lecture", selection: $browsePlayback,
                              choices: BrowsePlayback.allCases.map { ($0, $0.title) })
                settingChoice("Masquer les commandes", selection: $controlsTimeout,
                              choices: [(0, "Jamais")] + [2, 3, 5, 8].map { ($0, "Après \($0) s") })
                settingToggle("Animer les boutons de lecture", isOn: $animatePlaybackButtons)
                settingToggle("Afficher les boutons de saut", isOn: $showSeekButtons)
                if showSeekButtons {
                    settingChoice("Durée d’un saut", selection: $seekButtonSeconds,
                                  choices: [5, 10, 15, 30].map { ($0, "\($0) s") })
                }
            }

            SettingsGroup(title: labels("Intros et génériques")) {
                settingChoice("Sauter l’intro", selection: $introBehavior,
                              choices: IntroBehavior.allCases.map { ($0, $0.title) })
                settingToggle("Enchaîner au générique de fin", isOn: $autoAdvanceAtEnding)
            }
        }
    }

    private var subtitles: some View {
        VStack(spacing: 16) {
            SettingsGroup(title: labels("Pistes")) {
                settingChoice("Langue préférée", selection: $preferred,
                              choices: [("fr", "Français"), ("ja", "Japonais"), ("en", "Anglais"), ("off", "Aucun")])
                settingToggle("Inclure l’anglais dans le cycle", isOn: $englishInSubtitleCycle)
            }

            SettingsGroup(title: labels("Services en ligne")) {
                settingsDisclosure("Jimaku et OpenSubtitles", expanded: $showServices) {
                    VStack(alignment: .leading, spacing: 10) {
                        settingField("Clé Jimaku", value: $credentials.jimaku, secure: true)
                        settingField("Clé OpenSubtitles", value: $credentials.openKey, secure: true)
                        settingField("Identifiant OpenSubtitles", value: $credentials.openUser)
                        settingField("Mot de passe OpenSubtitles", value: $credentials.openPassword, secure: true)
                        HStack {
                            Button(labels("Enregistrer les identifiants")) { saveCredentials() }
                                .buttonStyle(ControlStyle(accent: true))
                                .disabled(savedCredentials == nil || savedCredentials == credentials)
                            if let credentialStatus {
                                Text(labels(credentialStatus)).font(YoruTypography.text(15))
                                    .foregroundStyle(theme.mutedText)
                            }
                        }
                    }
                }
                .onChange(of: showServices) { expanded in
                    if expanded, savedCredentials == nil {
                        let saved = Credentials.load()
                        credentials = saved
                        savedCredentials = saved
                    }
                }
                .onChange(of: credentials) { _ in credentialStatus = nil }
            }

            SettingsGroup(title: labels("Recalage automatique")) {
                let syncPath = FileManager.support.appendingPathComponent("sync/bin/ffsubsync").path
                Text(labels(FileManager.default.isExecutableFile(atPath: syncPath)
                            ? "Le recalage automatique est installé."
                            : "Lance install-sync.sh depuis le dossier du projet pour installer le recalage automatique."))
                    .font(YoruTypography.text(16))
                    .foregroundStyle(theme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var library: some View {
        VStack(spacing: 16) {
            SettingsGroup(title: labels("Dossier des vidéos")) {
                Text((model.folder.path as NSString).abbreviatingWithTildeInPath)
                    .font(YoruTypography.text(16))
                    .foregroundStyle(theme.mutedText)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
                Button(labels("Choisir le dossier…")) { model.chooseFolder() }
                    .buttonStyle(ControlStyle())
            }

            if usage.hasDownloads {
                SettingsGroup(title: "Nautiljon") {
                    Button(labels("Importer la liste « vus »…")) { importNautiljon(watchlist: false) }
                        .buttonStyle(ControlStyle())
                    Button(labels("Importer la liste « à voir »…")) { importNautiljon(watchlist: true) }
                        .buttonStyle(ControlStyle())
                }

                SettingsGroup(title: labels("Accueil")) {
                    settingToggle("Afficher les recommandations", isOn: $showRecommendations)
                }
            }
        }
    }

    private var downloads: some View {
        VStack(spacing: 16) {
            SettingsGroup(title: labels("Recherche")) {
                settingToggle("Choisir automatiquement les versions", isOn: $automaticDownloadSelection)
                HStack(spacing: 9) {
                    Text(labels("Minimum de seeders"))
                    Spacer()
                    seedButton(-1, icon: "minus", title: "Diminuer le minimum")
                        .disabled(seeds <= 1)
                    Text(seeds.formatted()).monospacedDigit()
                        .frame(minWidth: 30)
                        .accessibilityLabel("\(seeds) seeders")
                    seedButton(1, icon: "plus", title: "Augmenter le minimum")
                        .disabled(seeds >= 500)
                }
                .frame(minHeight: 46)
            }

            SettingsGroup(title: labels("Sources Nyaa")) {
                settingField("Comptes acceptés", value: $groups, hint: "Séparés par des virgules")
                settingsDisclosure("Sources repérées sur Nyaa", expanded: $showSources) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(NyaaSource.catalog) { source in
                            let enabled = NyaaSource.accounts(groups).contains { $0.caseInsensitiveCompare(source.id) == .orderedSame }
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Link(source.label, destination: source.url)
                                        .font(YoruTypography.text(17, strong: true))
                                    Text(source.sample)
                                        .font(YoruTypography.text(15))
                                        .foregroundStyle(theme.mutedText)
                                }
                                Spacer(minLength: 4)
                                Button(labels(enabled ? "Retirer" : "Ajouter")) {
                                    var accounts = NyaaSource.accounts(groups).filter { $0.caseInsensitiveCompare(source.id) != .orderedSame }
                                    if !enabled { accounts.append(source.id) }
                                    groups = accounts.joined(separator: ",")
                                }
                                .buttonStyle(ControlStyle(selected: enabled))
                                .accessibilityLabel(labels((enabled ? "Retirer " : "Ajouter ") + source.label))
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
            }
        }
    }

    private func settingToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Text(labels(title)).fixedSize(horizontal: false, vertical: true).accessibilityHidden(true)
            Spacer(minLength: 0)
            Toggle(labels(title), isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.large)
                .accessibilityLabel(labels(title))
                .directionalTarget(radius: 100) { isOn.wrappedValue.toggle() }
        }
        .frame(minHeight: 46)
    }

    private func settingChoice<Value: Hashable>(_ title: String, selection: Binding<Value>,
                                                choices: [(Value, String)]) -> some View {
        let current = choices.first { $0.0 == selection.wrappedValue }.map { labels($0.1) } ?? "—"
        return HStack(spacing: 12) {
            Text(labels(title))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)
            DirectionalMenu {
                Text(current)
            } actions: { close in
                ForEach(choices, id: \.0) { value, name in
                    Button {
                        selection.wrappedValue = value
                        close()
                    } label: {
                        if value == selection.wrappedValue { Label(labels(name), systemImage: "checkmark") }
                        else { Text(labels(name)) }
                    }
                    .buttonStyle(ControlStyle(selected: value == selection.wrappedValue))
                }
            }
            .accessibilityLabel(labels(title))
            .accessibilityValue(current)
        }
        .frame(minHeight: 46)
    }

    private func settingField(_ title: String, value: Binding<String>, secure: Bool = false, hint: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(labels(title)).fixedSize(horizontal: false, vertical: true).accessibilityHidden(true)
            Group {
                if secure {
                    SecureField(labels(title), text: value)
                } else {
                    TextField(labels(title), text: value, prompt: hint.map { Text(labels($0)) })
                }
            }
            .textFieldStyle(.plain)
            .focused($editingField, equals: title)
            .font(YoruTypography.text(16))
            .padding(.horizontal, 12)
            .frame(minHeight: 42)
            .background(theme.background.opacity(0.76), in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(theme.divider).allowsHitTesting(false))
            .directionalTarget(radius: 11) { editingField = title }
        }
    }

    private func settingsDisclosure<Content: View>(_ title: String, expanded: Binding<Bool>,
                                                   @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                expanded.wrappedValue.toggle()
            } label: {
                HStack {
                    Text(labels(title)).font(YoruTypography.text(17, strong: true))
                    Spacer()
                    Image(systemName: expanded.wrappedValue ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.mutedText)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(DirectionalPlainStyle())
            .accessibilityValue(labels(expanded.wrappedValue ? "Déployé" : "Replié"))
            if expanded.wrappedValue { content() }
        }
    }

    private func seedButton(_ delta: Int, icon: String, title: String) -> some View {
        Button {
            seeds = min(500, max(1, seeds + delta))
        } label: {
            Image(systemName: icon).frame(width: 14)
        }
        .buttonStyle(ControlStyle(horizontalPadding: 11))
        .accessibilityLabel(labels(title))
    }

    private func saveCredentials() {
        guard let saved = savedCredentials else { return }
        let draft = credentials
        for ((key, value), (_, previous)) in zip(draft.entries, saved.entries) where value != previous {
            Vault.set(key, value)
        }
        savedCredentials = Credentials.load()
        credentialStatus = savedCredentials == draft ? "Identifiants enregistrés." : "Impossible d’enregistrer tous les identifiants."
    }

    private func importNautiljon(watchlist: Bool) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let url = panel.url else { return }
        dismiss()
        if watchlist { model.importNautiljonWatchlist(url) }
        else { model.importRatings(url) }
    }
}

private struct SettingsGroup<Content: View>: View {
    @Environment(\.yoruTheme) private var theme
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(YoruTypography.display(22))
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 3)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.card.opacity(0.88), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(theme.divider).allowsHitTesting(false))
    }
}
