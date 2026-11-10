#!/usr/bin/env python3
"""Export parent-friendly Markdown review sheets for every Chinese bank."""
import argparse
import json
import random
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PLUGIN = ROOT
OUT = ROOT / "install" / "kidlearn" / "review"
CATALOG = json.loads((PLUGIN / "data" / "catalog.json").read_text(encoding="utf-8"))
GRADE_LABEL = {1: "一年级", 2: "二年级", 3: "三年级", 4: "四年级", 5: "五年级", 6: "六年级"}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--all", action="store_true", help="export every question")
    ap.add_argument("--per-unit", type=int, default=5)
    args = ap.parse_args()

    grades = CATALOG["subjects"]["chinese"]["editions"]["tongbian"]["grades"]
    OUT.mkdir(parents=True, exist_ok=True)
    for grade_key in sorted(grades, key=int):
        grade = int(grade_key)
        for semester in ("upper", "lower"):
            grade_data = grades[grade_key][semester]
            data = json.loads((PLUGIN / "data" / grade_data["file"]).read_text(encoding="utf-8"))
            by_unit = defaultdict(list)
            for q in data["questions"]:
                by_unit[q["unit"]].append(q)
            rng = random.Random(f"review-{grade}-{semester}")
            label = "上" if semester == "upper" else "下"
            lines = [
                f"# 小小学习家 · {GRADE_LABEL[grade]}{label}册语文抽查",
                "",
                "请重点核对：题目是否只有唯一正确答案、拼音声调是否正确、解析是否适合本年级。",
                "发现错误时修改 `tools/kidlearn/build_bank.py`，重新生成并运行校验。",
                "",
            ]
            for unit in grade_data["units"]:
                questions = by_unit[unit["id"]]
                chosen = questions if args.all else rng.sample(questions, min(args.per_unit, len(questions)))
                lines.append(f"## {unit['name']}（{unit.get('topics', '')}）")
                lines.append("")
                for q in chosen:
                    lines.append(f"- [ ] `{q['id']}` **{q['stem']}**")
                    for i, option in enumerate(q["options"]):
                        mark = " ✅" if i + 1 == q["answer"] else ""
                        lines.append(f"  - {chr(65 + i)}. {option}{mark}")
                    if q.get("passage"):
                        lines.append(f"  - 短文：{q['passage']}")
                    lines.append(f"  - 解析：{q['explain']}")
                    lines.append("")
            path = OUT / f"chinese_g{grade}_{semester}_review.md"
            path.write_text("\n".join(lines), encoding="utf-8")
            print(f"wrote {path}")


if __name__ == "__main__":
    main()
