#!/usr/bin/env bash
# Render the KidLearn UI walkthrough in the KOReader emulator runtime and
# write fresh 600x800 screenshots into docs/screenshots/.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
KOREADER_DIR="${KOREADER_DIR:-$HOME/GitHub/koreader}"
SPEC_LINK="$KOREADER_DIR/spec/unit/kidlearn_screenshot_spec.lua"

if [[ ! -x "$KOREADER_DIR/kodev" ]]; then
  echo "KOReader checkout not found: $KOREADER_DIR" >&2
  exit 1
fi

ln -sfn "$ROOT/tools/kidlearn/screenshot_walkthrough.lua" "$SPEC_LINK"
trap 'rm -f "$SPEC_LINK"' EXIT

cd "$KOREADER_DIR"
export PATH="/opt/homebrew/opt/coreutils/libexec/gnubin:/opt/homebrew/opt/make/libexec/gnubin:/opt/homebrew/opt/gnu-getopt/bin:/opt/homebrew/opt/findutils/libexec/gnubin:/usr/local/opt/coreutils/libexec/gnubin:/usr/local/opt/make/libexec/gnubin:/usr/local/opt/gnu-getopt/bin:/usr/local/opt/findutils/libexec/gnubin:$PATH"
BASH_BIN="${BASH_BIN:-/usr/local/bin/bash}"
[[ -x "$BASH_BIN" ]] || BASH_BIN="/opt/homebrew/bin/bash"
[[ -x "$BASH_BIN" ]] || BASH_BIN="/bin/bash"

exec "$BASH_BIN" ./kodev test -b front kidlearn_screenshot
