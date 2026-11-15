# Yoru

Un lecteur vidéo et une bibliothèque d’animés pour macOS. Yoru lit notamment les fichiers MKV, MP4 et WebM, reprend au dernier passage regardé et regroupe les épisodes par saison.

## Télécharger

Télécharge **Yoru-macOS-universal.zip** dans les [releases](https://github.com/TaoEffects/yoru/releases/latest). Décompresse l’archive, puis place **Yoru Public.app** dans Applications. Le même téléchargement contient les versions Intel et Apple Silicon pour macOS Ventura (13) et versions ultérieures.

Le lecteur vidéo et le moteur BitTorrent sont inclus. Cette édition est signée localement et n’est pas notariée par Apple. Selon la version de macOS, l’ouverture peut demander une autorisation dans Réglages Système. [Aide macOS sur l’ouverture d’une app téléchargée](https://support.apple.com/fr-fr/guide/mac-help/mh40616/mac)

## Commencer

1. Glisse une vidéo sur Yoru, ou utilise **⌘O**.
2. Pour voir tes séries, ouvre **Bibliothèque** et choisis le dossier qui contient tes vidéos.
3. Pour les téléchargements, ouvre un fichier `.torrent` ou lance une recherche depuis l’onglet **Téléchargements**. Tu peux choisir les fichiers à récupérer, suivre le transfert et ouvrir les vidéos terminées avec **Regarder**. Le transfert est retiré à la fin du téléchargement.

- **Espace** met en pause et **F** bascule en plein écran.
- Survole la barre du lecteur pour voir l’horodatage et, avec FFmpeg, une image de la scène. Les intros et génériques reconnus sont indiqués sur la barre.
- Un clic gauche sur les sous-titres fait défiler JP, FR et Aucun. Un clic droit ouvre les autres pistes et les réglages de décalage.
- Dans une saison, glisse sur les vignettes ou utilise **Maj + clic** pour changer le statut de plusieurs épisodes en une fois.

L’interface est en français. Le Liquid Glass natif est disponible à partir de macOS 26. Les vignettes vidéo utilisent FFmpeg s’il est installé. Les recherches de sous-titres en ligne utilisent tes propres accès Jimaku ou OpenSubtitles, configurables dans les réglages.

## Données et services

Chaque installation publique utilise son propre historique et ses propres réglages. Elle démarre avec un dossier distinct, `~/Movies/Yoru Public`, et n’importe un CSV Nautiljon que si tu le choisis. Les données de progression restent dans `~/Library/Application Support/Yoru Public`. Les identifiants de services sont dans le Trousseau macOS.

Yoru utilise AniList pour les fiches et les recommandations, AniSkip pour certains repères et Nyaa pour les recherches de torrents. Les sous-titres en ligne ne sont recherchés qu’avec les accès configurés. Les téléchargements manuels et la lecture locale sont accessibles depuis l’application.

## Compiler

Sur un Mac avec Xcode 26 ou plus récent sélectionné en ligne de commande, installe *cmake*, *ninja* et *pkg-config*. Depuis la racine du dépôt, exécute les trois scripts dans cet ordre.

```sh
./prepare-mpv.sh
./prepare-torrent.sh
./build.sh
```

L’app est créée dans `build/Yoru Public.app`. Le montage des moteurs et les textes de licence sont décrits dans [THIRD-PARTY.md](THIRD-PARTY.md).
