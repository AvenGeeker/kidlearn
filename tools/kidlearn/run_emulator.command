#!/bin/bash
set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
KOREADER_DIR="${KOREADER_DIR:-$HOME/GitHub/koreader}"
PLUGIN_LINK="$KOREADER_DIR/plugins/kidlearn.koplugin"

if [[ ! -x "$KOREADER_DIR/kodev" ]]; then
    echo "KOReader checkout not found: $KOREADER_DIR" >&2
    echo "Set KOREADER_DIR to the KOReader source checkout." >&2
    exit 1
fi

if [[ -e "$PLUGIN_LINK" && ! -L "$PLUGIN_LINK" ]]; then
    echo "Refusing to replace non-symlink: $PLUGIN_LINK" >&2
    exit 1
fi

mkdir -p "$KOREADER_DIR/plugins"
ln -sfn "$ROOT" "$PLUGIN_LINK"
cd "$KOREADER_DIR"

export KIDLEARN_AUTOSTART=1
export PATH="/opt/homebrew/opt/coreutils/libexec/gnubin:/opt/homebrew/opt/make/libexec/gnubin:/opt/homebrew/opt/gnu-getopt/bin:/opt/homebrew/opt/findutils/libexec/gnubin:/usr/local/opt/coreutils/libexec/gnubin:/usr/local/opt/make/libexec/gnubin:/usr/local/opt/gnu-getopt/bin:/usr/local/opt/findutils/libexec/gnubin:$PATH"

BASH_BIN="${BASH_BIN:-/usr/local/bin/bash}"
[[ -x "$BASH_BIN" ]] || BASH_BIN="/opt/homebrew/bin/bash"
[[ -x "$BASH_BIN" ]] || BASH_BIN="/bin/bash"

echo "Starting KOReader emulator (600x800)..."
echo "Plugin: $PLUGIN_LINK"
echo "Close this Terminal window to stop it."
exec "$BASH_BIN" ./kodev run -b -W 600 -H 800 -D 167
