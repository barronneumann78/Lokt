// Logic check: logger keyboard focus-advance (LoggerFocusModel).
// - Next walks weight → reps → next set's weight → next exercise's first
//   set, skipping NOTHING, honoring per-exercise set counts.
// - Returns nil exactly once: past the last reps cell of the last exercise
//   (where the keyboard's Next reads Done) — isFinalField agrees.
// - Unknown exercises (defensive edge) advance nowhere.
// - LoggerField coordinates round-trip (exercise / setIndex / kind).
// Compiles against the REAL LoggerFocusModel.swift.
import Foundation

// MARK: - Check plumbing

var failures = 0
func check(_ name: String, _ condition: Bool) {
    if condition {
        print("  PASS  \(name)")
    } else {
        print("  FAIL  \(name)")
        failures += 1
    }
}

// MARK: - Fixtures (deterministic)

let exercises = ["Bench Press", "Incline Dumbbell Press", "Face Pull"]
let counts = ["Bench Press": 2, "Incline Dumbbell Press": 3, "Face Pull": 1]
func setCount(_ exercise: String) -> Int { counts[exercise] ?? 1 }

func next(_ field: LoggerField) -> LoggerField? {
    LoggerFocusModel.nextField(after: field, exercises: exercises, setCount: setCount)
}

// MARK: - 1. Single steps

check("weight advances to reps of the SAME set",
      next(.weight("Bench Press", 0)) == .reps("Bench Press", 0))

check("mid-exercise reps advances to the NEXT set's weight",
      next(.reps("Bench Press", 0)) == .weight("Bench Press", 1))

check("last-set reps advances to the next exercise's first weight",
      next(.reps("Bench Press", 1)) == .weight("Incline Dumbbell Press", 0))

check("per-exercise set counts are honored (3-set exercise keeps advancing)",
      next(.reps("Incline Dumbbell Press", 1)) == .weight("Incline Dumbbell Press", 2))

check("single-set exercise: weight still goes to its reps first",
      next(.weight("Face Pull", 0)) == .reps("Face Pull", 0))

check("last reps of the LAST exercise advances nowhere (Next becomes Done)",
      next(.reps("Face Pull", 0)) == nil)

check("unknown exercise advances nowhere (defensive edge)",
      next(.reps("Ghost Curl", 0)) == nil)

// MARK: - 2. Full walk — every field visited exactly once, in order

var walk: [LoggerField] = []
var cursor: LoggerField? = .weight(exercises[0], 0)
while let field = cursor, walk.count < 64 {
    walk.append(field)
    cursor = next(field)
}

let expectedWalk: [LoggerField] = [
    .weight("Bench Press", 0), .reps("Bench Press", 0),
    .weight("Bench Press", 1), .reps("Bench Press", 1),
    .weight("Incline Dumbbell Press", 0), .reps("Incline Dumbbell Press", 0),
    .weight("Incline Dumbbell Press", 1), .reps("Incline Dumbbell Press", 1),
    .weight("Incline Dumbbell Press", 2), .reps("Incline Dumbbell Press", 2),
    .weight("Face Pull", 0), .reps("Face Pull", 0)
]

check("full walk covers every field of every set (\(expectedWalk.count) cells), skipping nothing",
      walk == expectedWalk)

check("full walk terminates (no cycle)", cursor == nil && walk.count == 12)

// MARK: - 3. isFinalField mirrors the advance

let finalFields = expectedWalk.filter {
    LoggerFocusModel.isFinalField($0, exercises: exercises, setCount: setCount)
}
check("isFinalField is true for exactly ONE cell", finalFields.count == 1)
check("…and that cell is the last reps of the last exercise",
      finalFields.first == .reps("Face Pull", 0))

// MARK: - 4. Coordinate accessors

let sample = LoggerField.reps("Bench Press", 1)
check("LoggerField exposes its exercise", sample.exercise == "Bench Press")
check("LoggerField exposes its set index", sample.setIndex == 1)
check("LoggerField exposes its cell kind", sample.kind == .reps &&
      LoggerField.weight("Bench Press", 1).kind == .weight)

// MARK: - Verdict

print(failures == 0 ? "ALL \(14) CHECKS PASSED" : "\(failures) CHECK(S) FAILED")
exit(failures == 0 ? 0 : 1)
