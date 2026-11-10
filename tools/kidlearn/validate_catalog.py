#!/usr/bin/env python3
"""Validate the KidLearn catalog and its mapping to math generators."""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PLUGIN = ROOT
CATALOG = json.loads((PLUGIN / "data" / "catalog.json").read_text(encoding="utf-8"))
MATHGEN = (PLUGIN / "core" / "mathgen.lua").read_text(encoding="utf-8")

errors = []


def err(msg):
    errors.append(msg)


def lua_skill_keys():
    match = re.search(r"local skill_generators = \{(.*?)\n\}", MATHGEN, re.S)
    if not match:
        return set()
    return set(re.findall(r"^\s{4}([a-z_][a-z0-9_]*) =", match.group(1), re.M))


def main():
    if CATALOG.get("schema_version") != 2:
        err("catalog schema_version must be 2")
    if CATALOG.get("system") != "6-3":
        err("catalog system must be 6-3")
    provinces = CATALOG.get("provinces", [])
    if len(provinces) < 32:
        err(f"expected at least 32 province entries, got {len(provinces)}")
    province_ids = set()
    for province in provinces:
        pid = province.get("id")
        if not pid or pid in province_ids:
            err(f"duplicate/empty province id: {pid}")
        province_ids.add(pid)
        if not province.get("name"):
            err(f"province {pid} missing name")
        if not province.get("default_math"):
            err(f"province {pid} missing default_math")

    expected_editions = {
        "chinese": {"tongbian"},
        "math": {"renjiao", "beishida", "sujiao", "qingdao", "hujiao"},
    }
    known_skills = lua_skill_keys()
    if not known_skills:
        err("could not read skill_generators from mathgen.lua")

    for subject, expected in expected_editions.items():
        subject_data = CATALOG["subjects"].get(subject)
        if not subject_data:
            err(f"missing subject {subject}")
            continue
        editions = subject_data.get("editions", {})
        if set(editions) != expected:
            err(f"{subject} editions {sorted(editions)} != {sorted(expected)}")
        for edition_id, edition in editions.items():
            grades = edition.get("grades", {})
            if set(grades) != {"1", "2", "3", "4", "5", "6"}:
                err(f"{subject}/{edition_id}: grades must be 1..6")
            for grade, semesters in grades.items():
                if set(semesters) != {"upper", "lower"}:
                    err(f"{subject}/{edition_id}/g{grade}: missing semester")
                for semester, data in semesters.items():
                    units = data.get("units", [])
                    if not units:
                        err(f"{subject}/{edition_id}/g{grade}/{semester}: no units")
                    seen = set()
                    for unit in units:
                        uid = unit.get("id")
                        if not uid or uid in seen:
                            err(f"{subject}/{edition_id}/g{grade}/{semester}: bad unit id {uid}")
                        seen.add(uid)
                        if not unit.get("name"):
                            err(f"{subject}/{edition_id}/g{grade}/{semester}/{uid}: missing name")
                        if subject == "math":
                            skills = unit.get("skills", [])
                            if not skills:
                                err(f"math/{edition_id}/g{grade}/{semester}/{uid}: no skills")
                            for skill in skills:
                                if skill not in known_skills:
                                    err(f"math/{edition_id}/g{grade}/{semester}/{uid}: unknown skill {skill}")
                        if subject == "chinese" and not data.get("file"):
                            err(f"chinese/{edition_id}/g{grade}/{semester}: missing file")

    if errors:
        print(f"CATALOG ERRORS ({len(errors)}):")
        for item in errors[:100]:
            print(" -", item)
        sys.exit(1)
    print(f"CATALOG VALIDATION OK ({len(provinces)} provinces, {len(known_skills)} math skills)")


if __name__ == "__main__":
    main()
