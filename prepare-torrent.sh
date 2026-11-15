#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
base="${TORRENT_DEPS:-$PWD/torrent-deps}"
mkdir -p "$base"
cd "$base"
base="$PWD"
if ! command -v cmake >/dev/null || ! command -v ninja >/dev/null; then
  command -v uv >/dev/null || { print "Installe cmake et ninja, ou bien uv."; exit 1; }
  uv venv --allow-existing "$base/venv"
  uv pip install --python "$base/venv/bin/python" cmake ninja
  export PATH="$base/venv/bin:$PATH"
fi

download() {
  local url="$1" archive="$2"
  if [[ ! -f "$archive" ]]; then
    curl -fL --retry 3 "$url" -o "$archive.part"
    mv "$archive.part" "$archive"
  fi
}
if [[ ! -d boost_1_88_0/boost ]]; then
  download https://archives.boost.io/release/1.88.0/source/boost_1_88_0.tar.bz2 boost.tar.bz2
  tar -xjf boost.tar.bz2
fi
if [[ ! -d libtorrent-2.0.11 ]]; then
  download https://codeload.github.com/arvidn/libtorrent/tar.gz/refs/tags/v2.0.11 libtorrent.tar.gz
  tar -xzf libtorrent.tar.gz
fi
if [[ ! -f libtorrent-2.0.11/deps/try_signal/try_signal.cpp ]]; then
  download https://codeload.github.com/arvidn/try_signal/tar.gz/105cce59972f925a33aa6b1c3109e4cd3caf583d try_signal.tar.gz
  mkdir -p libtorrent-2.0.11/deps/try_signal
  tar -xzf try_signal.tar.gz -C libtorrent-2.0.11/deps/try_signal --strip-components 1
fi
if [[ ! -d openssl-openssl-3.5.4 ]]; then
  download https://codeload.github.com/openssl/openssl/tar.gz/refs/tags/openssl-3.5.4 ssl.tar.gz
  tar -xzf ssl.tar.gz
fi

for arch in arm64 x86_64; do
  if [[ ! -f "$base/ssl-$arch/lib/libssl.a" ]]; then
    mkdir -p "$base/ssl-$arch-build"
    (
      cd "$base/ssl-$arch-build"
      export MACOSX_DEPLOYMENT_TARGET=13.0
      "$base/openssl-openssl-3.5.4/Configure" "darwin64-$arch-cc" --prefix=/usr/local --openssldir=/etc/ssl no-shared no-tests no-apps
      make -j "$(sysctl -n hw.ncpu)" build_libs
      make DESTDIR="$base/ssl-$arch-stage" install_dev
      mv "$base/ssl-$arch-stage/usr/local" "$base/ssl-$arch"
    )
  fi
  cmake -S libtorrent-2.0.11 -B "lt-$arch" -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES="$arch" -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_CXX_FLAGS="-ffile-prefix-map=\"$base=third_party\"" \
    -DCMAKE_POLICY_DEFAULT_CMP0167=OLD -DBoost_NO_BOOST_CMAKE=ON -DBoost_INCLUDE_DIR="$base/boost_1_88_0" \
    -DOPENSSL_ROOT_DIR="$base/ssl-$arch" -DOPENSSL_USE_STATIC_LIBS=ON
  cmake --build "lt-$arch" --parallel "$(sysctl -n hw.ncpu)"
done
