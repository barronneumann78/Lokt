#!/usr/bin/env python3
"""Dataset lint for the bundled exercise library (run from repo root, or anywhere).

Permanent sensor added with the researched dataset expansion (2026-08). Rules:

  1. exercises.json parses as JSON and is a non-empty list.
  2. Every entry has the full schema (all required keys, metadata sub-keys).
  3. Enum-backed fields only use values the Swift decoder accepts
     (MuscleGroup / EquipmentType / MovementPattern / DifficultyLevel /
     PrimaryMuscleGroup) — an unknown value would fail decoding and silently
     EMPTY the whole library at runtime.
  4. ids are globally unique.
  5. Names are unique case-insensitively. Exception: a frozen baseline of 29
     duplicate-name groups that shipped before this lint existed (the runtime
     merge collapses them, first entry wins). The baseline may only SHRINK:
     any new duplicate, or growth of an existing group, fails. If you dedupe
     the dataset, delete the entries here too.
  6. Content floor for every entry: exactly 3 non-empty cues, 1-6 non-empty
     howTo steps, non-empty instructions/description/muscleGroup, and at least
     one non-empty metadata.primaryMuscles value (the muscle-role mapper and
     analytics consume it).
"""
import json
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATASET = os.path.join(REPO, "LockIn Set Tracker", "exercises.json")

VALID_MUSCLE_GROUP = {"Chest", "Back", "Shoulders", "Arms", "Legs", "Core",
                      "Cardio", "Full Body", "Mobility", "Other"}
VALID_EQUIPMENT = {"Dumbbell", "Barbell", "Machine", "Cable", "Kettlebell",
                   "Band", "Medicine Ball", "Bodyweight", "Other"}
VALID_PATTERN = {"Horizontal Push", "Vertical Push", "Horizontal Pull",
                 "Vertical Pull", "Squat", "Hinge", "Isolation"}
VALID_DIFFICULTY = {"Beginner", "Intermediate", "Advanced"}
VALID_PRIMARY_GROUP = {"Chest", "Back", "Shoulders", "Triceps", "Biceps",
                       "Legs", "Core"}

REQUIRED_KEYS = ["id", "name", "muscleGroup", "equipment", "movementPattern",
                 "primaryMuscleGroups", "difficulty", "instructions",
                 "metadata", "description", "howTo", "cues"]
REQUIRED_META_KEYS = ["primaryMuscles", "secondaryMuscles", "movementPattern",
                      "equipment", "difficulty", "mechanic", "forceType",
                      "laterality", "bodyRegion", "trainingGoal",
                      "exerciseType", "planeOfMotion", "tags"]

# Duplicate-name groups that predate this lint (lowercased name -> count).
# Frozen: may only shrink. First entry wins at runtime (ExerciseStore.merge).
GRANDFATHERED_DUPLICATE_NAMES = {
    "barbell curl": 2, "barbell deadlift": 2, "barbell squat": 2,
    "bent over barbell row": 2, "bodyweight walking lunge": 2,
    "close-grip ez bar curl": 2, "cross-body crunch": 2, "decline crunch": 2,
    "double kettlebell push press": 2, "dumbbell bench press": 2,
    "dumbbell floor press": 2, "ez-bar skullcrusher": 3,
    "flat bench lying leg raise": 2, "glute ham raise": 3, "hack squat": 3,
    "kneeling cable triceps extension": 2, "leg extensions": 2,
    "lying close-grip bar curl on high pulley": 2,
    "machine triceps extension": 3, "natural glute ham raise": 2,
    "otis-up": 2, "power snatch": 2, "push up to side plank": 2,
    "seated calf raise": 2, "sit-up": 2, "sled push": 2,
    "smith machine close-grip bench press": 2,
    "smith machine incline bench press": 2,
    "stiff-legged dumbbell deadlift": 2,
}


def main():
    problems = []

    try:
        with open(DATASET, encoding="utf-8") as f:
            data = json.load(f)
    except Exception as exc:  # noqa: BLE001 - any parse failure is the finding
        print(f"  FAIL  exercises.json unreadable/invalid: {exc}")
        return 1

    if not isinstance(data, list) or not data:
        print("  FAIL  exercises.json is not a non-empty list")
        return 1

    ids = {}
    name_counts = {}
    for i, e in enumerate(data):
        label = f"[{i}] {e.get('name') or e.get('id') or '?'}"

        missing = [k for k in REQUIRED_KEYS if k not in e]
        if missing:
            problems.append(f"{label}: missing keys {missing}")
            continue

        ids[e["id"]] = ids.get(e["id"], 0) + 1
        lname = e["name"].strip().lower()
        if not lname:
            problems.append(f"{label}: empty name")
        name_counts[lname] = name_counts.get(lname, 0) + 1

        if e["muscleGroup"] not in VALID_MUSCLE_GROUP:
            problems.append(f"{label}: bad muscleGroup {e['muscleGroup']!r}")
        if e["equipment"] not in VALID_EQUIPMENT:
            problems.append(f"{label}: bad equipment {e['equipment']!r}")
        if e["movementPattern"] not in VALID_PATTERN:
            problems.append(f"{label}: bad movementPattern {e['movementPattern']!r}")
        if e["difficulty"] not in VALID_DIFFICULTY:
            problems.append(f"{label}: bad difficulty {e['difficulty']!r}")
        bad_groups = [g for g in e["primaryMuscleGroups"] if g not in VALID_PRIMARY_GROUP]
        if bad_groups:
            problems.append(f"{label}: bad primaryMuscleGroups {bad_groups}")

        meta = e["metadata"]
        meta_missing = [k for k in REQUIRED_META_KEYS if k not in meta]
        if meta_missing:
            problems.append(f"{label}: metadata missing {meta_missing}")
            continue

        cues = e["cues"]
        if len(cues) != 3 or any(not str(c).strip() for c in cues):
            problems.append(f"{label}: needs exactly 3 non-empty cues (has {len(cues)})")
        how = e["howTo"]
        if not (1 <= len(how) <= 6) or any(not str(s).strip() for s in how):
            problems.append(f"{label}: howTo needs 1-6 non-empty steps (has {len(how)})")
        if not str(e["instructions"]).strip():
            problems.append(f"{label}: empty instructions")
        if not str(e["description"]).strip():
            problems.append(f"{label}: empty description")
        pm = meta["primaryMuscles"]
        if not pm or any(not str(m).strip() for m in pm):
            problems.append(f"{label}: metadata.primaryMuscles must be non-empty strings")

    for eid, count in sorted(ids.items()):
        if count > 1:
            problems.append(f"duplicate id {eid!r} x{count}")

    for lname, count in sorted(name_counts.items()):
        if count <= 1:
            continue
        allowed = GRANDFATHERED_DUPLICATE_NAMES.get(lname, 1)
        if count > allowed:
            problems.append(
                f"duplicate name {lname!r} x{count} (allowed {allowed}; "
                "new duplicates are banned - rename or drop the extra entry)")

    shrunk = [n for n, c in GRANDFATHERED_DUPLICATE_NAMES.items()
              if name_counts.get(n, 0) < c]
    if shrunk:
        problems.append(
            "grandfathered duplicate baseline is stale (dataset was deduped?) - "
            f"shrink GRANDFATHERED_DUPLICATE_NAMES for: {shrunk}")

    if problems:
        print(f"  FAIL  dataset lint: {len(problems)} problem(s) across {len(data)} entries")
        for p in problems[:20]:
            print(f"        {p}")
        if len(problems) > 20:
            print(f"        ... and {len(problems) - 20} more")
        return 1

    print(f"  PASS  dataset lint ({len(data)} entries: schema, enums, unique ids, "
          "names, cues/howTo/muscles floor)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
