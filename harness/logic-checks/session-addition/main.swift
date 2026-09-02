// Logic check: mid-workout "Add Exercise" (session-scoped additions).
// - Add mutation: appended to the END of the session order, seeded with 3
//   explicitly-unchecked sets, existing state untouched, name trimmed.
// - No-duplicate guard: exact, case-insensitive, and empty names all refuse
//   (nil outcome = zero mutation).
// - Session scoping: routineStrippingSessionAdded removes ONLY the additions
//   (names + set counts) so mid-workout routine writes never leak them.
// - Keep-at-finish upsert: SAME routine id, additions appended in session
//   order with their in-session set counts, never duplicating.
// Compiles against the REAL Models.swift + SessionAdditionLogic.swift.
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

let routineID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
let baseOrder = ["Bench Press", "Incline Dumbbell Press"]
let baseCounts = ["Bench Press": 4, "Incline Dumbbell Press": 3]
let baseLogs: [String: [WorkoutSet]] = [
    "Bench Press": [
        WorkoutSet(weight: "135", reps: "8", completed: true),
        WorkoutSet(weight: "140", reps: "6", completed: false)
    ]
]

// MARK: - 1. Add mutation (ordering, seeding, untouched neighbors)

check("default seeded set count is 3 (matches the review flow)",
      SessionAdditionLogic.defaultSetCount == 3)

let added = SessionAdditionLogic.addingExercise(
    named: "Face Pull",
    toOrder: baseOrder,
    sessionAdded: [],
    preferredSetCounts: baseCounts,
    logs: baseLogs
)

check("add: outcome produced for a new exercise", added != nil)
check("add: appended to the END of the session order",
      added?.order == ["Bench Press", "Incline Dumbbell Press", "Face Pull"])
check("add: tracked as session-added", added?.sessionAdded == ["Face Pull"])
check("add: seeded with 3 sets", added?.logs["Face Pull"]?.count == 3)
check("add: seeded sets are empty", added?.logs["Face Pull"]?.allSatisfy { $0.weight.isEmpty && $0.reps.isEmpty } == true)
check("add: seeded sets carry explicit completed == false (never legacy nil)",
      added?.logs["Face Pull"]?.allSatisfy { $0.completed == false } == true)
check("add: seeded sets do NOT count as completed",
      added?.logs["Face Pull"]?.allSatisfy { !$0.isCompleted } == true)
check("add: preferred set count recorded as 3", added?.preferredSetCounts["Face Pull"] == 3)
check("add: existing order untouched", Array(added?.order.prefix(2) ?? []) == baseOrder)
check("add: existing logs untouched", added?.logs["Bench Press"] == baseLogs["Bench Press"])
check("add: existing set counts untouched", added?.preferredSetCounts["Bench Press"] == 4)

// Sequential adds keep add order.
let secondAdd = SessionAdditionLogic.addingExercise(
    named: "Cable Lateral Raise",
    toOrder: added!.order,
    sessionAdded: added!.sessionAdded,
    preferredSetCounts: added!.preferredSetCounts,
    logs: added!.logs
)
check("add: second addition lands after the first",
      secondAdd?.order == ["Bench Press", "Incline Dumbbell Press", "Face Pull", "Cable Lateral Raise"])
check("add: session-added list keeps add order",
      secondAdd?.sessionAdded == ["Face Pull", "Cable Lateral Raise"])

// Name hygiene + clamping.
let trimmed = SessionAdditionLogic.addingExercise(
    named: "  Chest Dip  ",
    toOrder: baseOrder, sessionAdded: [], preferredSetCounts: baseCounts, logs: baseLogs
)
check("add: name is trimmed", trimmed?.order.last == "Chest Dip" && trimmed?.sessionAdded == ["Chest Dip"])

let clamped = SessionAdditionLogic.addingExercise(
    named: "Chest Dip",
    toOrder: baseOrder, sessionAdded: [], preferredSetCounts: baseCounts, logs: baseLogs,
    setCount: 0
)
check("add: set count clamps to at least 1", clamped?.logs["Chest Dip"]?.count == 1)

// Stale logs entry (from an earlier removal) pads rather than resurrects extra sets.
let staleLogs = baseLogs.merging(["Chest Dip": [WorkoutSet(weight: "50", reps: "10", completed: true)]]) { a, _ in a }
let readd = SessionAdditionLogic.addingExercise(
    named: "Chest Dip",
    toOrder: baseOrder, sessionAdded: [], preferredSetCounts: baseCounts, logs: staleLogs
)
check("add: stale log entry padded to 3, existing set kept",
      readd?.logs["Chest Dip"]?.count == 3 && readd?.logs["Chest Dip"]?.first?.weight == "50")

// MARK: - 2. No-duplicate guard

check("guard: exact duplicate refuses",
      SessionAdditionLogic.addingExercise(
          named: "Bench Press",
          toOrder: baseOrder, sessionAdded: [], preferredSetCounts: baseCounts, logs: baseLogs) == nil)
check("guard: case-insensitive duplicate refuses",
      SessionAdditionLogic.addingExercise(
          named: "bench press",
          toOrder: baseOrder, sessionAdded: [], preferredSetCounts: baseCounts, logs: baseLogs) == nil)
check("guard: already-session-added name refuses (it is in the order)",
      SessionAdditionLogic.addingExercise(
          named: "FACE PULL",
          toOrder: added!.order, sessionAdded: added!.sessionAdded,
          preferredSetCounts: added!.preferredSetCounts, logs: added!.logs) == nil)
check("guard: empty name refuses",
      SessionAdditionLogic.addingExercise(
          named: "   ",
          toOrder: baseOrder, sessionAdded: [], preferredSetCounts: baseCounts, logs: baseLogs) == nil)

// MARK: - 3. Session scoping (strip before any mid-workout routine write)

var liveRoutine = Routine(
    id: routineID,
    name: "Push Day",
    exercises: ["Bench Press", "Incline Dumbbell Press", "Face Pull", "Cable Lateral Raise"],
    preferredSetCounts: [
        "Bench Press": 4, "Incline Dumbbell Press": 3,
        "Face Pull": 3, "Cable Lateral Raise": 3
    ]
)
let sessionAdded = ["Face Pull", "Cable Lateral Raise"]

let stripped = SessionAdditionLogic.routineStrippingSessionAdded(liveRoutine, sessionAdded: sessionAdded)
check("strip: session-added names removed from the order",
      stripped.exercises == ["Bench Press", "Incline Dumbbell Press"])
check("strip: session-added set counts removed",
      stripped.preferredSetCounts["Face Pull"] == nil && stripped.preferredSetCounts["Cable Lateral Raise"] == nil)
check("strip: routine's own exercises + counts intact",
      stripped.preferredSetCounts == ["Bench Press": 4, "Incline Dumbbell Press": 3])
check("strip: id and name preserved", stripped.id == routineID && stripped.name == "Push Day")
check("strip: empty session-added list is a no-op",
      SessionAdditionLogic.routineStrippingSessionAdded(liveRoutine, sessionAdded: []).exercises == liveRoutine.exercises)

// Case-insensitive strip (a swap could change casing).
let strippedCased = SessionAdditionLogic.routineStrippingSessionAdded(liveRoutine, sessionAdded: ["FACE PULL"])
check("strip: case-insensitive removal",
      !strippedCased.exercises.contains("Face Pull") && strippedCased.exercises.count == 3)

// Mid-workout reorder: additions stripped, the user's new order for the
// routine's own exercises survives.
liveRoutine.exercises = ["Face Pull", "Incline Dumbbell Press", "Cable Lateral Raise", "Bench Press"]
let strippedReordered = SessionAdditionLogic.routineStrippingSessionAdded(liveRoutine, sessionAdded: sessionAdded)
check("strip: reordered routine keeps its own order minus additions",
      strippedReordered.exercises == ["Incline Dumbbell Press", "Bench Press"])

// MARK: - 4. Keep-at-finish upsert (same id, appended, set counts)

let storedRoutine = Routine(
    id: routineID,
    name: "Push Day",
    exercises: ["Bench Press", "Incline Dumbbell Press"],
    preferredSetCounts: ["Bench Press": 4, "Incline Dumbbell Press": 3]
)
// User bumped Face Pull to 4 sets mid-session.
let sessionCounts = ["Bench Press": 4, "Incline Dumbbell Press": 3, "Face Pull": 4, "Cable Lateral Raise": 3]

let kept = SessionAdditionLogic.routineKeepingSessionAdded(
    storedRoutine,
    sessionAdded: sessionAdded,
    preferredSetCounts: sessionCounts
)
check("keep: SAME routine id (replace, never duplicate)", kept.id == routineID)
check("keep: additions appended in session order",
      kept.exercises == ["Bench Press", "Incline Dumbbell Press", "Face Pull", "Cable Lateral Raise"])
check("keep: in-session set counts carried (mid-session bump included)",
      kept.preferredSetCounts["Face Pull"] == 4 && kept.preferredSetCounts["Cable Lateral Raise"] == 3)
check("keep: routine's own set counts untouched",
      kept.preferredSetCounts["Bench Press"] == 4 && kept.preferredSetCounts["Incline Dumbbell Press"] == 3)
check("keep: routine name preserved", kept.name == "Push Day")

// Missing count falls back to the default seed.
let keptDefault = SessionAdditionLogic.routineKeepingSessionAdded(
    storedRoutine, sessionAdded: ["Face Pull"], preferredSetCounts: [:]
)
check("keep: missing set count falls back to 3", keptDefault.preferredSetCounts["Face Pull"] == 3)

// Already-present name (e.g. the routine absorbed it meanwhile) never doubles.
let keptDup = SessionAdditionLogic.routineKeepingSessionAdded(
    kept, sessionAdded: ["face pull"], preferredSetCounts: sessionCounts
)
check("keep: already-present name not duplicated (case-insensitive)",
      keptDup.exercises == kept.exercises)

// Strip → keep round-trip reconstructs the full session order.
let roundTrip = SessionAdditionLogic.routineKeepingSessionAdded(
    stripped, sessionAdded: sessionAdded, preferredSetCounts: sessionCounts
)
check("strip → keep reconstructs the session's full order",
      roundTrip.exercises == ["Bench Press", "Incline Dumbbell Press", "Face Pull", "Cable Lateral Raise"])

// MARK: - Summary

if failures == 0 {
    print("ALL SESSION-ADDITION CHECKS PASSED")
    exit(0)
} else {
    print("\(failures) SESSION-ADDITION CHECK(S) FAILED")
    exit(1)
}
