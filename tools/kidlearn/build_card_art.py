#!/usr/bin/env python3
"""Post-process and validate KidLearn card art (generated artifacts).

Raw AI-generated illustrations are staged outside version control (e.g.
install/card_art_raw/<id>.png). This script converts them into e-ink friendly
grayscale 480x480 PNG assets under data/cards/. The committed PNGs are
generated artifacts: never hand-edit them; regenerate with this script.

Usage:
  python3 tools/kidlearn/build_card_art.py --raw install/card_art_raw
  python3 tools/kidlearn/build_card_art.py --raw install/card_art_raw --colors 8 --smooth 3
  python3 tools/kidlearn/build_card_art.py --raw install/card_art_raw --ids ss06 sss04 --colors 8 --smooth 3
  python3 tools/kidlearn/build_card_art.py --check
  python3 tools/kidlearn/build_card_art.py --check --allow-missing

Requires Pillow (build-time only; the plugin runtime has no new dependency).
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent.parent.parent
ART_DIR = ROOT / "data" / "cards"
SIZE = 480
MAX_FILE_BYTES = 80 * 1024
MAX_TOTAL_BYTES = 3 * 1024 * 1024
RAW_SUFFIXES = (".png", ".jpg", ".jpeg", ".webp")


def expected_ids() -> list[str]:
    """Card ids come from the Lua pool (single source of truth) plus back."""
    text = (ROOT / "core" / "cards.lua").read_text(encoding="utf-8")
    ids = re.findall(r'\{ id = "(\w+)", tier =', text)
    if not ids:
        sys.exit("no pool cards parsed from core/cards.lua")
    if len(ids) != len(set(ids)):
        sys.exit("duplicate card ids in core/cards.lua")
    return ids + ["back"]


def is_grayscale(img: Image.Image) -> bool:
    if img.mode in ("L", "LA", "1"):
        return True
    if img.mode == "P":
        palette = img.getpalette()
        if palette is None:
            return False
        return all(palette[i] == palette[i + 1] == palette[i + 2]
                   for i in range(0, len(palette), 3))
    return False


def save_grayscale(img: Image.Image, dest: Path,
                   max_colors: int | None = None,
                   smooth: int | None = None) -> bool:
    gray = img.convert("L")
    if gray.size != (SIZE, SIZE):
        gray = gray.resize((SIZE, SIZE), Image.LANCZOS)
    if smooth:
        # A light median filter simplifies band boundaries so quantized
        # PNGs stay small; 3 keeps line art crisp, larger values blur it.
        gray = gray.filter(ImageFilter.MedianFilter(smooth))
    # Prefer full 8-bit grayscale for the smoothest shading; step down the
    # palette depth only as needed to fit the per-file budget. E-ink renders
    # ~16 gray levels, so even the lower depths look correct on device.
    # max_colors caps the starting depth, useful when the total 3MB budget
    # is tight and new cards must stay small.
    depths = (64, 32, 16, 12, 8)
    if max_colors is None:
        gray.save(dest, optimize=True)
        if dest.stat().st_size <= MAX_FILE_BYTES:
            return True
    else:
        depths = tuple(c for c in depths if c <= max_colors) or (8,)
    for colors in depths:
        # No dithering: flat gray bands read cleanly on e-ink (~16 levels)
        # and keep PNGs small enough for the shared 3MB total budget.
        gray.quantize(colors=colors, dither=Image.Dither.NONE).save(dest, optimize=True)
        if dest.stat().st_size <= MAX_FILE_BYTES:
            return True
    return False


def build(raw_dir: Path, only_ids: list[str] | None = None,
          max_colors: int | None = None, smooth: int | None = None) -> None:
    if not raw_dir.is_dir():
        sys.exit(f"raw directory not found: {raw_dir}")
    ART_DIR.mkdir(parents=True, exist_ok=True)
    ids = expected_ids()
    if only_ids:
        unknown = [c for c in only_ids if c not in ids]
        if unknown:
            sys.exit(f"unknown card ids: {', '.join(unknown)}")
        ids = [c for c in ids if c in only_ids]
    missing, oversized = [], []
    for cid in ids:
        raw = next((raw_dir / f"{cid}{s}" for s in RAW_SUFFIXES
                    if (raw_dir / f"{cid}{s}").is_file()), None)
        if raw is None:
            missing.append(cid)
            continue
        dest = ART_DIR / f"{cid}.png"
        with Image.open(raw) as img:
            ok = save_grayscale(img, dest, max_colors=max_colors, smooth=smooth)
        if not ok:
            oversized.append(cid)
        print(f"{cid}: {dest.stat().st_size} bytes")
    if missing:
        sys.exit(f"missing raw art for: {', '.join(missing)}")
    if oversized:
        sys.exit(f"oversized after quantization: {', '.join(oversized)}")
    check()


def check(allow_missing: bool = False) -> None:
    problems = []
    missing = []
    total = 0
    for cid in expected_ids():
        path = ART_DIR / f"{cid}.png"
        if not path.is_file():
            missing.append(cid)
            if not allow_missing:
                problems.append(f"{cid}.png: missing")
            continue
        size = path.stat().st_size
        total += size
        if size > MAX_FILE_BYTES:
            problems.append(f"{cid}.png: {size} bytes > {MAX_FILE_BYTES}")
        with Image.open(path) as img:
            if img.size != (SIZE, SIZE):
                problems.append(f"{cid}.png: size {img.size} != {(SIZE, SIZE)}")
            if not is_grayscale(img):
                problems.append(f"{cid}.png: mode {img.mode} is not grayscale")
    if total > MAX_TOTAL_BYTES:
        problems.append(f"total {total} bytes > {MAX_TOTAL_BYTES}")
    if problems:
        print("\n".join(problems))
        sys.exit(1)
    present = len(expected_ids()) - len(missing)
    if missing:
        print(f"card art pending (text-only in UI): {', '.join(missing)}")
    print(f"card art OK: {present} files, {total} bytes total")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--raw", type=Path, help="directory holding raw generated art")
    parser.add_argument("--check", action="store_true", help="validate committed art only")
    parser.add_argument("--ids", nargs="*", default=None,
                        help="with --raw, only build these card ids")
    parser.add_argument("--allow-missing", action="store_true",
                        help="with --check, tolerate cards whose art is not generated yet")
    parser.add_argument("--colors", type=int, default=None,
                        help="with --raw, cap palette depth (64/32/16/12/8) to fit the total budget")
    parser.add_argument("--smooth", type=int, default=None,
                        help="with --raw, median filter size (3 recommended) before quantizing")
    args = parser.parse_args()
    if args.check:
        check(allow_missing=args.allow_missing)
    elif args.raw:
        build(args.raw, only_ids=args.ids, max_colors=args.colors, smooth=args.smooth)
    else:
        parser.error("pass --raw DIR to build or --check to validate")


if __name__ == "__main__":
    main()
