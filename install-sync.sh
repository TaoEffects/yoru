#!/bin/zsh
set -eu
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
command -v uv >/dev/null || { print "Installe uv pour créer l’environnement du module."; exit 1; }
command -v ffmpeg >/dev/null || { print "Installe FFmpeg pour analyser les pistes audio."; exit 1; }
SYNC_DIR="$HOME/Library/Application Support/Yoru/sync"
uv venv --allow-existing --python 3.12 "$SYNC_DIR"
uv pip install --python "$SYNC_DIR/bin/python" 'ffsubsync==0.5.1'
"$SYNC_DIR/bin/ffsubsync" --version
