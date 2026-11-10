#!/usr/bin/env python3
"""Validate every generated KidLearn Chinese bank against the catalog."""
import argparse
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PLUGIN = ROOT
CATALOG = json.loads((PLUGIN / "data" / "catalog.json").read_text(encoding="utf-8"))
PINYIN_RE = re.compile(r"^[a-zāáǎàēéěèīíǐìōóǒòūúǔùǖǘǚǜüńňǹḿ\s']+$")
VALID_TYPES = {
    "pinyin_to_char", "char_to_pinyin", "measure_word", "synonym", "antonym",
    "sentence_choice", "word_choice", "accumulation", "reading",
    "math_number", "math_choice",
}

errors = []
warnings = []
seen_ids = set()
seen_stems = defaultdict(set)

try:
    from pypinyin import pinyin, Style
except Exception:  # pragma: no cover - optional development dependency
    pinyin = None


def pinyin_readings(char):
    if pinyin is None:
        return None
    return {item[0] for item in pinyin(char, style=Style.TONE, heteronym=True)}


def err(msg):
    errors.append(msg)


def warn(msg):
    warnings.append(msg)


def check_bank(grade, semester, path, units):
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("schema_version") != 1:
        err(f"{path.name}: schema_version must be 1")
    if data.get("subject") != "chinese":
        err(f"{path.name}: subject must be chinese")
    if data.get("grade") != grade:
        err(f"{path.name}: grade must be {grade}")
    if data.get("semester") != semester:
        err(f"{path.name}: semester must be {semester}")
    if data.get("textbook") != "统编版":
        err(f"{path.name}: textbook must be 统编版")
    questions = data.get("questions")
    if not isinstance(questions, list):
        err(f"{path.name}: questions missing")
        return
    unit_ids = {u["id"] for u in units}
    per_unit = Counter()
    diff = Counter()
    types = Counter()
    for i, q in enumerate(questions):
        where = f"{path.name}[{i}] {q.get('id', '?')}"
        qid = q.get("id")
        if not isinstance(qid, str) or not qid:
            err(f"{where}: missing id")
        elif qid in seen_ids:
            err(f"{where}: duplicate id")
        else:
            seen_ids.add(qid)
        unit = q.get("unit")
        if unit not in unit_ids:
            err(f"{where}: unknown unit {unit!r}")
            continue
        per_unit[unit] += 1
        qtype = q.get("type")
        if qtype not in VALID_TYPES:
            err(f"{where}: invalid type {qtype!r}")
        types[qtype] += 1
        difficulty = q.get("difficulty")
        if difficulty not in (1, 2, 3):
            err(f"{where}: difficulty must be 1..3")
        else:
            diff[difficulty] += 1
        stem = q.get("stem")
        if not isinstance(stem, str) or not stem.strip():
            err(f"{where}: missing stem")
        else:
            norm = re.sub(r"\s+", "", stem)
            if norm in seen_stems[(grade, semester, unit)]:
                err(f"{where}: duplicate stem in unit")
            seen_stems[(grade, semester, unit)].add(norm)
        explain = q.get("explain")
        if not isinstance(explain, str) or len(explain.strip()) < 4:
            err(f"{where}: missing/short explain")
        options = q.get("options")
        if not isinstance(options, list) or len(options) != 4:
            err(f"{where}: need four options")
        else:
            if len(set(options)) != 4:
                err(f"{where}: duplicate options")
            if any(not isinstance(o, str) or not o.strip() for o in options):
                err(f"{where}: empty option")
            answer = q.get("answer")
            if not isinstance(answer, int) or not (1 <= answer <= 4):
                err(f"{where}: answer must be 1..4")
        if qtype in ("pinyin_to_char", "char_to_pinyin"):
            if qtype == "char_to_pinyin":
                for o in options or []:
                    if not PINYIN_RE.match(o):
                        err(f"{where}: invalid pinyin option {o!r}")
            m = re.search(r"“([^”]+)”", stem or "")
            if not m:
                warn(f"{where}: pinyin question has no quoted target")
            elif pinyin is not None:
                quoted = m.group(1)
                if qtype == "pinyin_to_char":
                    target_char = options[q["answer"] - 1]
                    readings = None
                    hint = re.search(r"提示：可以组成“([^”]+)”", stem or "")
                    if hint:
                        word = hint.group(1)
                        idx = word.find(target_char)
                        if idx >= 0:
                            phrase = pinyin(word, style=Style.TONE)
                            if idx < len(phrase):
                                readings = {phrase[idx][0]}
                    if readings is None:
                        readings = pinyin_readings(target_char)
                    if readings is not None and quoted not in readings:
                        err(f"{where}: “{target_char}” readings {readings} do not include {quoted}")
                else:
                    word_match = re.search(r"在“([^”]+)”中，“([^”]+)”", stem or "")
                    target_char = word_match.group(2) if word_match else quoted
                    correct_pinyin = options[q["answer"] - 1]
                    readings = None
                    if word_match:
                        word = word_match.group(1)
                        idx = word.find(target_char)
                        if idx >= 0:
                            phrase = pinyin(word, style=Style.TONE)
                            if idx < len(phrase):
                                readings = {phrase[idx][0]}
                    if readings is None:
                        readings = pinyin_readings(target_char)
                    if readings is not None and correct_pinyin not in readings:
                        err(f"{where}: “{target_char}” readings {readings} do not include {correct_pinyin}")
        if qtype == "reading" and not q.get("passage"):
            err(f"{where}: reading question missing passage")
    for unit in unit_ids:
        if per_unit[unit] != 20:
            err(f"{path.name}: unit {unit} has {per_unit[unit]} questions, expected 20")
    expected = {1: 8, 2: 8, 3: 4}
    for unit in unit_ids:
        unit_diff = Counter()
        for q in questions:
            if q.get("unit") == unit:
                unit_diff[q.get("difficulty")] += 1
        if dict(unit_diff) != expected:
            err(f"{path.name}: unit {unit} difficulty {dict(unit_diff)}, expected {expected}")
    print(f"{path.name}: {len(questions)} questions")
    print("  difficulty:", dict(sorted(diff.items())))
    print("  types:", dict(sorted(types.items())))
    print("  units:", dict(sorted(per_unit.items())))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--all", action="store_true", help="validate every grade/semester (default)")
    args = ap.parse_args()
    grades = CATALOG["subjects"]["chinese"]["editions"]["tongbian"]["grades"]
    for grade_key in sorted(grades, key=int):
        for semester in ("upper", "lower"):
            grade_data = grades[grade_key][semester]
            path = PLUGIN / "data" / grade_data["file"]
            check_bank(int(grade_key), semester, path, grade_data["units"])
    print()
    if warnings:
        print(f"WARNINGS ({len(warnings)}):")
        for w in warnings[:30]:
            print(" -", w)
        if len(warnings) > 30:
            print(f" ... and {len(warnings) - 30} more")
    if errors:
        print(f"ERRORS ({len(errors)}):")
        for e in errors[:100]:
            print(" -", e)
        if len(errors) > 100:
            print(f" ... and {len(errors) - 100} more")
        sys.exit(1)
    print("BANK VALIDATION OK")


if __name__ == "__main__":
    main()
