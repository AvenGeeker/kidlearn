#!/usr/bin/env python3
"""Sync primary-school knowledge graphs and question banks from cn-math-taxonomy.

Reads topics.json / dependencies.json / questions.json from a local checkout of
https://github.com/xiaoyang111222/cn-math-taxonomy (CC BY-NC 4.0) and writes
generated, committed artifacts under data/knowledge/:

    data/knowledge/{math,chinese}/g{1..6}{u,l}.json   per-volume topics + questions
    data/knowledge/{math,chinese}_graph.json          nodes + prerequisite edges

Only primary-school nodes are synced (cnm_p* for math, cnc_p* for Chinese).
Questions that cannot work on a text-only e-ink UI are excluded:
  * questions or choices carrying an SVG `figure` (incl. hideChoiceText),
  * numeric questions with multiple answers (full-width comma separated),
  * numeric questions with a negative answer.

The output is deterministic for a given source commit.  Do not hand-edit the
generated files; re-run this script instead.  Use --check to detect drift.

Standard library only.
"""

import argparse
import collections
import json
import os
import re
import subprocess
import sys

SCHEMA_VERSION = 1
LICENSE = "CC BY-NC 4.0"
ATTRIBUTION = (
    "Data adapted from cn-math-taxonomy "
    "(https://github.com/xiaoyang111222/cn-math-taxonomy), licensed CC BY-NC 4.0."
)
GENERATED_BY = "tools/kidlearn/sync_taxonomy.py"

SUBJECTS = {
    "math": {"prefix": "cnm_p", "edition": "renjiao"},
    "chinese": {"prefix": "cnc_p", "edition": "tongbian"},
}
SEMESTER_MAP = {"上": "upper", "下": "lower"}
DIFFICULTY_MAP = {"basic": 1, "standard": 2, "challenge": 3, "advanced": 3}
CHAPTER_PREFIX_RE = re.compile(r"^[一二三四五六]年级[上下]册\s*")
INT_RE = re.compile(r"^\d+$")
DECIMAL_RE = re.compile(r"^\d+\.\d+$")
FRACTION_RE = re.compile(r"^(\d+)/(\d+)$")


def fail(msg):
    print("sync_taxonomy: " + msg, file=sys.stderr)
    sys.exit(1)


def load_json(path):
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def source_commit(source_dir):
    try:
        out = subprocess.run(
            ["git", "-C", source_dir, "rev-parse", "--short", "HEAD"],
            capture_output=True, text=True, check=True,
        )
        return out.stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return "unknown"


def exclusion_reason(q):
    """Return a reason string when a question cannot be used on e-ink, else None."""
    if q.get("figure") or any(c.get("figure") for c in q.get("choices", [])):
        return "figure"
    if q.get("type") == "numeric":
        answer = q.get("answer", "")
        if "，" in answer or "," in answer:
            return "multi-answer"
        if answer.startswith("-"):
            return "negative"
    return None


def normalize_question(q, topic, unit_id, subject, edition):
    """Convert a taxonomy question into the KidLearn question shape."""
    difficulty = DIFFICULTY_MAP.get(q.get("difficulty"))
    if difficulty is None:
        fail("question %s has unknown difficulty %r" % (q.get("id"), q.get("difficulty")))
    stem = q.get("prompt")
    explain = q.get("explanation")
    if not stem or not explain:
        fail("question %s missing prompt/explanation" % q.get("id"))

    out = {
        "id": q["id"],
        "topic": q["topicId"],
        "subject": subject,
        "grade": topic["grade"],
        "semester": SEMESTER_MAP[topic["semester"]],
        "edition": edition,
        "unit": unit_id,
        "unit_name": topic["name"],
        "type": "knowledge",
        "skill": topic["domain"],
        "difficulty": difficulty,
        "stem": stem,
        "explain": explain,
    }

    if q["type"] == "choice":
        choices = q.get("choices") or []
        keys = [c.get("key") for c in choices]
        if not 3 <= len(choices) <= 4 or keys != list("ABCD"[:len(choices)]):
            fail("question %s has invalid choices" % q["id"])
        texts = [c.get("text") for c in choices]
        if any(not t for t in texts) or len(set(texts)) != len(texts):
            fail("question %s has empty/duplicate choice text" % q["id"])
        if q.get("answer") not in keys:
            fail("question %s answer not a choice key" % q["id"])
        out["answer_mode"] = "choice"
        out["options"] = texts
        out["answer"] = keys.index(q["answer"]) + 1
    elif q["type"] == "numeric":
        answer = q.get("answer", "")
        out["answer_mode"] = "number"
        if INT_RE.match(answer):
            out["answer_format"] = "integer"
            out["answer"] = int(answer)
        elif DECIMAL_RE.match(answer):
            out["answer_format"] = "decimal"
            out["answer"] = float(answer)
        elif FRACTION_RE.match(answer):
            num, den = FRACTION_RE.match(answer).groups()
            if int(den) == 0:
                fail("question %s has zero denominator" % q["id"])
            out["answer_format"] = "fraction"
            out["answer"] = "%s/%s" % (num, den)
        else:
            fail("question %s has unsupported numeric answer %r" % (q["id"], answer))
    else:
        fail("question %s has unsupported type %r" % (q["id"], q.get("type")))
    return out


def build_subject(source_dir, subject, commit):
    prefix = SUBJECTS[subject]["prefix"]
    edition = SUBJECTS[subject]["edition"]

    topics = [t for t in load_json(os.path.join(source_dir, "data", "topics.json"))
              if t["id"].startswith(prefix)]
    topic_ids = {t["id"] for t in topics}
    if len(topic_ids) != len(topics):
        fail("duplicate topic ids in " + subject)
    by_id = {t["id"]: t for t in topics}

    all_questions = load_json(os.path.join(source_dir, "data", "questions.json"))
    deps = [d for d in load_json(os.path.join(source_dir, "data", "dependencies.json"))
            if d["topicId"] in topic_ids and d["prerequisiteId"] in topic_ids]

    # Group topics by volume, then by chapter (unit) in first-appearance order.
    volumes = collections.OrderedDict()
    for t in topics:
        if t.get("external"):
            fail("external topic in primary set: " + t["id"])
        grade = t["grade"]
        semester = SEMESTER_MAP.get(t["semester"])
        if not isinstance(grade, int) or not 1 <= grade <= 6 or semester is None:
            fail("topic %s has invalid grade/semester" % t["id"])
        if not CHAPTER_PREFIX_RE.match(t.get("chapter", "")):
            fail("topic %s has unexpected chapter format %r" % (t["id"], t.get("chapter")))
        key = (grade, semester)
        vol = volumes.setdefault(key, {"units": collections.OrderedDict(), "topics": []})
        chapter = t["chapter"]
        if chapter not in vol["units"]:
            unit_id = "u%d" % (len(vol["units"]) + 1)
            vol["units"][chapter] = {
                "id": unit_id,
                "name": CHAPTER_PREFIX_RE.sub("", chapter, count=1),
            }
        vol["topics"].append(t)

    # Normalize questions, applying e-ink exclusions.
    kept, excluded = [], []
    seen_ids = set()
    for q in all_questions:
        if q.get("topicId") not in topic_ids:
            continue
        if q["id"] in seen_ids:
            fail("duplicate question id " + q["id"])
        seen_ids.add(q["id"])
        reason = exclusion_reason(q)
        if reason:
            excluded.append((q["id"], reason))
            continue
        topic = by_id[q["topicId"]]
        key = (topic["grade"], SEMESTER_MAP[topic["semester"]])
        unit_id = volumes[key]["units"][topic["chapter"]]["id"]
        kept.append(normalize_question(q, topic, unit_id, subject, edition))

    questions_by_topic = collections.Counter(q["topic"] for q in kept)
    for t in topics:
        if questions_by_topic[t["id"]] == 0:
            fail("topic %s has no usable questions after exclusion" % t["id"])

    meta = {
        "schema_version": SCHEMA_VERSION,
        "generated_by": GENERATED_BY,
        "source": {"repo": "cn-math-taxonomy", "commit": commit},
        "license": LICENSE,
        "attribution": ATTRIBUTION,
    }

    files = {}
    graph_nodes = []
    for (grade, semester), vol in sorted(volumes.items()):
        vol_topics = []
        for t in vol["topics"]:
            unit = vol["units"][t["chapter"]]
            node = {
                "id": t["id"],
                "name": t["name"],
                "grade": grade,
                "semester": semester,
                "unit": unit["id"],
                "unit_name": unit["name"],
                "domain": t["domain"],
            }
            graph_nodes.append(node)
            vol_topics.append({
                "id": t["id"],
                "name": t["name"],
                "domain": t["domain"],
                "kp_type": t.get("type", ""),
                "unit": unit["id"],
                "unit_name": unit["name"],
                "description": t.get("description", ""),
                "mastery_criteria": t.get("mastery_criteria", []),
                "example": {
                    "question": (t.get("diagnostic_question") or {}).get("question", ""),
                    "answer": (t.get("diagnostic_question") or {}).get("answer", ""),
                },
            })
        vol_questions = [q for q in kept
                         if q["grade"] == grade and q["semester"] == semester]
        payload = dict(meta)
        payload.update({
            "subject": subject,
            "grade": grade,
            "semester": semester,
            "units": list(vol["units"].values()),
            "topics": vol_topics,
            "questions": vol_questions,
        })
        suffix = "u" if semester == "upper" else "l"
        files["data/knowledge/%s/g%d%s.json" % (subject, grade, suffix)] = payload

    graph = dict(meta)
    graph.update({
        "subject": subject,
        "nodes": graph_nodes,
        "edges": [
            {"from": d["topicId"], "to": d["prerequisiteId"],
             "strength": d.get("strength", "hard"), "reason": d.get("reason", "")}
            for d in deps
        ],
    })
    files["data/knowledge/%s_graph.json" % subject] = graph

    stats = {
        "topics": len(topics),
        "questions": len(kept),
        "excluded": excluded,
        "edges": len(deps),
        "hard_edges": sum(1 for d in deps if d.get("strength") == "hard"),
    }
    return files, stats


def serialize(payload):
    return json.dumps(payload, ensure_ascii=False, indent=2) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--source", default=os.environ.get("CN_MATH_TAXONOMY_DIR"),
                        help="cn-math-taxonomy checkout (default: $CN_MATH_TAXONOMY_DIR or ~/GitHub/cn-math-taxonomy)")
    parser.add_argument("--subject", choices=["math", "chinese", "all"], default="all")
    parser.add_argument("--check", action="store_true",
                        help="compare generated output against committed files without writing")
    args = parser.parse_args()

    source_dir = os.path.expanduser(args.source or "~/GitHub/cn-math-taxonomy")
    if not os.path.isfile(os.path.join(source_dir, "data", "topics.json")):
        fail("source checkout not found: " + source_dir)
    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    commit = source_commit(source_dir)

    subjects = list(SUBJECTS) if args.subject == "all" else [args.subject]
    drift = []
    for subject in subjects:
        files, stats = build_subject(source_dir, subject, commit)
        print("[%s] topics=%d questions=%d edges=%d (hard=%d) excluded=%d"
              % (subject, stats["topics"], stats["questions"], stats["edges"],
                 stats["hard_edges"], len(stats["excluded"])))
        for qid, reason in stats["excluded"]:
            print("  excluded %s (%s)" % (qid, reason))
        for rel, payload in sorted(files.items()):
            text = serialize(payload)
            dest = os.path.join(root, rel)
            if args.check:
                current = None
                if os.path.isfile(dest):
                    with open(dest, "r", encoding="utf-8") as fh:
                        current = fh.read()
                if current != text:
                    drift.append(rel)
            else:
                os.makedirs(os.path.dirname(dest), exist_ok=True)
                with open(dest, "w", encoding="utf-8") as fh:
                    fh.write(text)
                print("  wrote %s" % rel)

    if args.check:
        if drift:
            print("drift detected in:\n  " + "\n  ".join(drift), file=sys.stderr)
            sys.exit(1)
        print("check OK: generated output matches committed files")
    else:
        print("done (source commit %s)" % commit)


if __name__ == "__main__":
    main()
