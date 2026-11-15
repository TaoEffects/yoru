#!/bin/zsh
set -eu
cd "${0:A:h}"
APP="${1:-$PWD/build/Yoru Public.app}"
APP="${APP:a}"
MPV="${MPV_DEPS:-$PWD/mpv-deps}"
MPV_VERSION=v0.41.4
FRAMEWORKS="$APP/Contents/Frameworks"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
DEPS="${TORRENT_DEPS:-$PWD/torrent-deps}"
if [[ ! -f "$DEPS/lt-arm64/libtorrent-rasterbar.a" || ! -f "$DEPS/lt-x86_64/libtorrent-rasterbar.a" ]]; then
  print "Lance d’abord ./prepare-torrent.sh pour compiler le moteur BitTorrent."
  exit 1
fi
if [[ ! -f "$MPV/libmpv-$MPV_VERSION-macos-arm64/lib/libmpv.2.dylib" || ! -f "$MPV/libmpv-$MPV_VERSION-macos-x86_64/lib/libmpv.2.dylib" ]]; then
  print "Lance d’abord ./prepare-mpv.sh pour télécharger le moteur vidéo."
  exit 1
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$FRAMEWORKS" obj
cp Info.plist "$APP/Contents/"
cp retime.py "$APP/Contents/Resources/"
cp -R Resources/Fonts "$APP/Contents/Resources/"

arm_libraries="$MPV/libmpv-$MPV_VERSION-macos-arm64/lib"
intel_libraries="$MPV/libmpv-$MPV_VERSION-macos-x86_64/lib"
for library in "$arm_libraries"/*.dylib; do
  name="${library:t}"
  if [[ -L "$library" ]]; then
    target="$(readlink "$library")"
    [[ "$target" == "$(readlink "$intel_libraries/$name")" ]]
    ln -sfn "$target" "$FRAMEWORKS/$name"
  else
    xcrun lipo -create "$library" "$intel_libraries/$name" -output "$FRAMEWORKS/$name"
    codesign --force --sign - "$FRAMEWORKS/$name"
  fi
done

for architecture in arm64 x86_64; do
  xcrun clang++ -std=c++20 -fobjc-arc -O2 -arch "$architecture" -isysroot "$SDK" -mmacosx-version-min=13.0 \
    "-ffile-prefix-map=$PWD=." "-ffile-prefix-map=$DEPS=third_party" \
    -DBOOST_ASIO_ENABLE_CANCELIO -DBOOST_ASIO_HAS_STD_CHRONO -DBOOST_ASIO_NO_DEPRECATED -DBOOST_EXCEPTION_DISABLE \
    -DOPENSSL_NO_SSL2 -DTORRENT_SSL_PEERS -DTORRENT_USE_LIBCRYPTO -DTORRENT_USE_OPENSSL -D_FILE_OFFSET_BITS=64 \
    -I"$DEPS/libtorrent-2.0.11/include" -isystem "$DEPS/ssl-$architecture/include" -isystem "$DEPS/boost_1_88_0" \
    -c Sources/Native/TorrentBridge.mm -o "obj/TorrentBridge-$architecture.o"
  xcrun swiftc -swift-version 5 -O -suppress-warnings \
    -target "${architecture}-apple-macosx13.0" -sdk "$SDK" \
    -file-prefix-map "$PWD=." \
    -import-objc-header Sources/MPV/Bridge.h \
    -L "$FRAMEWORKS" -lmpv.2 -Xlinker -rpath -Xlinker "@executable_path/../Frameworks" \
    -framework OpenGL -framework SystemConfiguration -lc++ Sources/*.swift "obj/TorrentBridge-$architecture.o" \
    "$DEPS/lt-$architecture/libtorrent-rasterbar.a" "$DEPS/ssl-$architecture/lib/libssl.a" "$DEPS/ssl-$architecture/lib/libcrypto.a" -o "obj/Yoru-$architecture"
done
xcrun lipo -create obj/Yoru-arm64 obj/Yoru-x86_64 -output "$APP/Contents/MacOS/Yoru"
if [[ -f icon.icns ]]; then cp icon.icns "$APP/Contents/Resources/Yoru.icns"; fi
mkdir -p "$APP/Contents/Resources/Licences"
mkdir -p "$APP/Contents/Resources/Licences/libmpv"
cp -R "$MPV/libmpv-$MPV_VERSION-macos-arm64/licenses/." "$APP/Contents/Resources/Licences/libmpv/"
cp Licences/* "$APP/Contents/Resources/Licences/libmpv/"
cp THIRD-PARTY.md "$APP/Contents/Resources/Licences/"
cp "$DEPS/libtorrent-2.0.11/COPYING" "$APP/Contents/Resources/Licences/libtorrent.txt"
cp "$DEPS/boost_1_88_0/LICENSE_1_0.txt" "$APP/Contents/Resources/Licences/Boost.txt"
cp "$DEPS/openssl-openssl-3.5.4/LICENSE.txt" "$APP/Contents/Resources/Licences/OpenSSL.txt"
codesign --force --sign - "$APP"
