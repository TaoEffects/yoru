# Yoru

Un lecteur vidéo et une bibliothèque d’animés pour macOS. Yoru lit notamment les fichiers MKV, MP4 et WebM, reprend au dernier passage regardé et regroupe les épisodes par saison.

## Télécharger

Télécharge **Yoru-macOS-universal.zip** dans les [releases](https://github.com/TaoEffects/yoru/releases/latest). Décompresse l’archive, puis place **Yoru Public.app** dans Applications. Le même téléchargement contient les versions Intel et Apple Silicon pour macOS Ventura (13) et versions ultérieures.

Le lecteur vidéo et le moteur BitTorrent sont inclus. Cette édition est signée localement et n’est pas notariée par Apple. Selon la version de macOS, l’ouverture peut demander une autorisation dans Réglages Système. [Aide macOS sur l’ouverture d’une app téléchargée](https://support.apple.com/fr-fr/guide/mac-help/mh40616/mac)

## Commencer

1. Glisse une vidéo sur Yoru, ou utilise **⌘O**.
2. Pour voir tes séries, ouvre **Bibliothèque** et choisis le dossier qui contient tes vidéos.
3. Pour télécharger, ouvre un fichier `.torrent`, cherche un titre ou lance le téléchargement depuis une recommandation. Yoru peut choisir un pack complet ou les épisodes disponibles d’une série en cours parmi les sources activées. Tu peux aussi choisir une version à la main. Les vidéos terminées apparaissent dans la bibliothèque et le torrent sort de la liste des transferts.

- **Espace** met en pause et **F** bascule en plein écran. La barre de navigation flotte au-dessus de la vidéo et se révèle près du bord supérieur en plein écran. Fais défiler la barre à la molette ou au trackpad pour changer d’onglet.
- Survole la barre du lecteur pour voir l’horodatage et, avec FFmpeg, une image de la scène. Les intros et génériques reconnus sont indiqués sur la barre.
- Un clic gauche sur les sous-titres fait défiler JP, FR et Aucun. Un clic droit ouvre les autres pistes et les réglages de décalage.
- Dans une saison, glisse sur les vignettes ou utilise **Maj + clic** pour changer le statut de plusieurs épisodes en une fois.
- La fiche d’une série reprend le dernier épisode entamé dans la saison choisie. **Corbeille** déplace les vidéos sélectionnées après confirmation.

L’interface est en français. Le Liquid Glass natif est disponible à partir de macOS 26. Les vignettes vidéo utilisent FFmpeg s’il est installé. Les recherches de sous-titres en ligne utilisent tes propres accès Jimaku ou OpenSubtitles, configurables dans les réglages.

## Personnaliser

- **Apparence** propose sept thèmes, les libellés en minuscules, les fonds floutés, l’interface légère, le titre du lecteur en police Yoru ou en japonais quand il est disponible, et la position de la navigation en mode fenêtre et son masquage avec les commandes.
- **Lecture** règle l’ajustement initial de la fenêtre en 16:9, le délai de masquage des commandes, le saut de l’intro et l’enchaînement au générique. Les boutons d’avance et de recul sont facultatifs et leur durée est réglable.
- **Sous-titres** permet de choisir la langue préférée et d’inclure l’anglais dans le cycle du bouton.
- **Bibliothèque** permet de masquer les recommandations. **Téléchargements** permet de désactiver le choix automatique des versions et de personnaliser les sources et le minimum de seeders.

## Données et services

Chaque installation publique utilise son propre historique et ses propres réglages. Elle démarre dans `~/Movies/Yoru Public`. Les données de progression restent dans `~/Library/Application Support/Yoru Public`. Les identifiants de services sont dans le Trousseau macOS.

Tu peux importer tes exports CSV **Vus** et **À voir** dans **Réglages → Nautiljon**. Les titres vus sont écartés des suggestions. Les titres à voir qui ont une fiche correspondante s’affichent dans **À voir**. **Voir plus** ouvre la liste importée avec une recherche. Réimporte les fichiers après une mise à jour sur Nautiljon.

Yoru utilise AniList pour les fiches et les recommandations, AniSkip pour certains repères et Nyaa pour les recherches de torrents. Les sous-titres en ligne ne sont recherchés qu’avec les accès configurés. Les téléchargements manuels et la lecture locale sont accessibles depuis l’application.

## Compiler

Sur un Mac avec Xcode 26 ou plus récent sélectionné en ligne de commande, installe *cmake*, *ninja* et *pkg-config*. Depuis la racine du dépôt, exécute les trois scripts dans cet ordre.

```sh
./prepare-mpv.sh
./prepare-torrent.sh
./build.sh
```

L’app est créée dans `build/Yoru Public.app`. Le montage des moteurs et les textes de licence sont décrits dans [THIRD-PARTY.md](THIRD-PARTY.md).
