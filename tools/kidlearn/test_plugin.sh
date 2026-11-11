#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
KOREADER_DIR="${KOREADER_DIR:-$HOME/GitHub/koreader}"
PLUGIN_LINK="$KOREADER_DIR/plugins/kidlearn.koplugin"
SPEC_DIR="$KOREADER_DIR/spec/unit"

if [[ ! -x "$KOREADER_DIR/kodev" ]]; then
    echo "KOReader checkout not found: $KOREADER_DIR" >&2
    echo "Set KOREADER_DIR to the KOReader source checkout." >&2
    exit 1
fi

if [[ ! -d "$SPEC_DIR" ]]; then
    echo "missing KOReader spec directory: $SPEC_DIR" >&2
    exit 1
fi

if [[ -e "$PLUGIN_LINK" && ! -L "$PLUGIN_LINK" ]]; then
    echo "Refusing to replace non-symlink: $PLUGIN_LINK" >&2
    exit 1
fi

mkdir -p "$KOREADER_DIR/plugins"
ln -sfn "$ROOT" "$PLUGIN_LINK"

for spec in "$ROOT"/spec/unit/kidlearn_*.lua; do
    target="$SPEC_DIR/$(basename "$spec")"
    if [[ -e "$target" && ! -L "$target" ]]; then
        echo "Refusing to replace non-symlink: $target" >&2
        exit 1
    fi
    ln -sfn "$spec" "$target"
done

cd "$KOREADER_DIR"
export PATH="/opt/homebrew/opt/coreutils/libexec/gnubin:/opt/homebrew/opt/make/libexec/gnubin:/opt/homebrew/opt/gnu-getopt/bin:/opt/homebrew/opt/findutils/libexec/gnubin:/usr/local/opt/coreutils/libexec/gnubin:/usr/local/opt/make/libexec/gnubin:/usr/local/opt/gnu-getopt/bin:/usr/local/opt/findutils/libexec/gnubin:$PATH"

BASH_BIN="${BASH_BIN:-/usr/local/bin/bash}"
[[ -x "$BASH_BIN" ]] || BASH_BIN="/opt/homebrew/bin/bash"
[[ -x "$BASH_BIN" ]] || BASH_BIN="/bin/bash"

if [[ $# -eq 0 ]]; then
    set -- kidlearn_bank kidlearn_catalog kidlearn_mathgen kidlearn_progress kidlearn_session kidlearn_ui kidlearn_ai kidlearn_knowledge kidlearn_diagnose
fi

KODEV_FLAGS=()
if [[ "${KODEV_REUSE_BUILD:-0}" == "1" ]]; then
    KODEV_FLAGS+=(-b)
fi

exec "$BASH_BIN" ./kodev test "${KODEV_FLAGS[@]}" front "$@"
