#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
root="${MPV_DEPS:-$PWD/mpv-deps}"
version=v0.41.4
repository=178meorg/libmpv-macos-build
mkdir -p "$root"

for arch in arm64 x86_64; do
  bundle="libmpv-$version-macos-$arch"
  archive="$root/$bundle.tar.gz"
  if [[ "$arch" == arm64 ]]; then
    checksum=584210a193e8925a7a2fcb6bb89bbcaa450937caf9601c1304a8d34698da3765
  else
    checksum=1e924be7be2870d62cabed33a75f4416647002c0b0e75eb9dce0f301c8a5d83b
  fi
  if [[ ! -f "$archive" ]]; then
    curl --fail --location --retry 3 "https://github.com/$repository/releases/download/$version/$bundle.tar.gz" -o "$archive.part"
    mv "$archive.part" "$archive"
  fi
  print -r -- "$checksum  $archive" | shasum -a 256 -c
  if [[ ! -f "$root/$bundle/lib/libmpv.2.dylib" ]]; then
    tar -xzf "$archive" -C "$root"
  fi
done
