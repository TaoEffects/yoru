# Composants tiers

## Moteur vidéo

Yoru charge libmpv et ses dépendances sous forme de bibliothèques dynamiques distinctes dans `Contents/Frameworks`. La préparation utilise les [archives du profil enhanced-lgpl v0.41.4](https://github.com/178meorg/libmpv-macos-build/releases/tag/v0.41.4). Les sommes de contrôle des deux archives sont dans `prepare-mpv.sh`.

Les [scripts et le manifeste de compilation](https://github.com/178meorg/libmpv-macos-build/tree/999253c50c059b58db61b4ec71fd9d87c0fb6070/third_party) permettent de reconstruire les bibliothèques. Pour reproduire le moteur, fixe `MPV_SOURCE_REF=d97d68da9576ac82c567ba6e8e9a71bbf9e05549` à la préparation. Les archives source exactes de [mpv](https://github.com/178meorg/mpv/archive/d97d68da9576ac82c567ba6e8e9a71bbf9e05549.tar.gz) et de [FFmpeg](https://ffmpeg.org/releases/ffmpeg-8.1.2.tar.xz) sont disponibles en téléchargement. Les notices sont incluses dans `Contents/Resources/Licences/libmpv`. Les en-têtes de l’API mpv fournis dans `Sources/MPV` portent leurs propres notices ISC.

Pour utiliser un moteur modifié compatible avec l’API, prépare des bibliothèques avec la même disposition et passe le dossier de préparation dans `MPV_DEPS` avant d’exécuter `build.sh`. Le script signe localement le résultat. Les licences libres des composants tiers s’appliquent à ces composants.

This software is based in part on the work of the FreeType Team. [FreeType 2.13.3](https://github.com/freetype/freetype/tree/VER-2-13-3) est utilisé sous la FreeType License. [Lua 5.2.4](https://www.lua.org/ftp/lua-5.2.4.tar.gz) est distribué sous licence MIT.

## BitTorrent et polices

- [libtorrent 2.0.11](https://github.com/arvidn/libtorrent/tree/v2.0.11), [Boost 1.88.0](https://www.boost.org/releases/1.88.0/) et [OpenSSL 3.5.4](https://github.com/openssl/openssl/tree/openssl-3.5.4) sont utilisés par le moteur BitTorrent. Leurs notices sont dans `Contents/Resources/Licences`.
- [Bricolage Grotesque](https://github.com/ateliertriay/bricolage) et [Instrument Serif](https://github.com/Instrument/instrument-serif) sont distribuées sous la SIL Open Font License. Leurs notices sont dans `Resources/Fonts`.
