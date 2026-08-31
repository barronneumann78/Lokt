#!/usr/bin/env python3
"""Generate backend/exercise-catalog.json from the bundled exercise dataset.

The AI backend grounds generated exercise names in this slim catalog so the
model copies real library names verbatim instead of inventing its own. Per
entry it carries only what subset selection needs:

    {name, muscleGroup, equipment[, staple]}

`staple` marks the always-included backbone of common exercises: the canonical
targets of the app's alias table (the exercises people actually reference by
slang) plus the curated head of each muscle group in dataset order.

Deterministic: same inputs -> byte-identical output (entries sorted by
muscleGroup then name, one entry per line). harness/checks.sh regenerates to a
temp file and byte-compares, so a stale committed catalog fails the harness.

Usage:
    python3 harness/gen-exercise-catalog.py           # writes backend/exercise-catalog.json
    python3 harness/gen-exercise-catalog.py --out X   # writes X (drift sensor)
"""

import argparse
import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DATASET = REPO / "LockIn Set Tracker" / "exercises.json"
ALIASES = REPO / "LockIn Set Tracker" / "ExerciseAliases.swift"
DEFAULT_OUT = REPO / "backend" / "exercise-catalog.json"

# How many dataset-order entries per muscle group join the staple backbone.
# The head of each group is curated (classics first) before the legacy
# alphabetical block starts, so a small prefix captures the group's staples.
CURATED_HEAD_PER_GROUP = 5


def alias_target_names(swift_source: str) -> set[str]:
    """Canonical names on the right-hand side of the ExerciseAliases table."""
    targets: set[str] = set()
    # Lines look like:  "pec deck": "Machine Chest Fly",
    # Values may contain escaped quotes ("Bicep Curls \"21s\"").
    pattern = re.compile(r'^\s*"(?:[^"\\]|\\.)+":\s*"((?:[^"\\]|\\.)+)",?\s*(?://.*)?$')
    for line in swift_source.splitlines():
        match = pattern.match(line)
        if match:
            targets.add(match.group(1).replace('\\"', '"'))
    return targets


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    args = parser.parse_args()

    library = json.loads(DATASET.read_text(encoding="utf-8"))
    staple_names = {name.lower() for name in alias_target_names(ALIASES.read_text(encoding="utf-8"))}

    # Curated head of each muscle group, in dataset order.
    per_group_seen: dict[str, int] = {}
    head_names: set[str] = set()
    for exercise in library:
        group = exercise["muscleGroup"]
        count = per_group_seen.get(group, 0)
        if count < CURATED_HEAD_PER_GROUP:
            head_names.add(exercise["name"].lower())
            per_group_seen[group] = count + 1

    # Dedupe by case-insensitive name; first dataset occurrence wins (the 29
    # legacy duplicate-name groups are grandfathered in the dataset itself).
    entries: list[dict] = []
    seen: set[str] = set()
    for exercise in library:
        key = exercise["name"].lower()
        if key in seen:
            continue
        seen.add(key)
        entry = {
            "name": exercise["name"],
            "muscleGroup": exercise["muscleGroup"],
            "equipment": exercise["equipment"],
        }
        if key in staple_names or key in head_names:
            entry["staple"] = True
        entries.append(entry)

    entries.sort(key=lambda entry: (entry["muscleGroup"], entry["name"].lower()))

    body = ",\n".join(json.dumps(entry, ensure_ascii=False, separators=(", ", ": ")) for entry in entries)
    args.out.write_text("[\n" + body + "\n]\n", encoding="utf-8")

    staples = sum(1 for entry in entries if entry.get("staple"))
    print(f"wrote {args.out} — {len(entries)} entries ({staples} staples)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
