// Logic check: in-progress workout persistence (activeWorkoutV1).
// - State round-trip: encode/decode with mixed checked/unchecked/legacy-nil
//   sets preserves numbers and completion flags exactly.
// - Legacy decode: a blob without `activeSeconds` still decodes, and the
//   smart estimate falls back to lastInteraction − start.
// - Activity accumulation: interaction deltas add up, idle gaps beyond the
//   30-minute cutoff (and clock rollbacks) count zero.
// - Smart duration default: active span rounded UP to 5 min, never zero,
//   never above wall-clock elapsed — the forgotten-overnight workout defaults
//   to ~its real 45 minutes, not 25 hours and not 0.
// - Thresholds: duration fix strictly beyond 3h, staleness strictly beyond 12h.
// - Routine-deleted discard: resumableRoutine returns nil so callers clear.
// - Store save/load/clear round-trips through a real UserDefaults suite.
// - Session-added exercises (mid-workout Add Exercise): names + order survive
//   the round-trip; blobs without the field still decode (nil).
// Compiles against the REAL Models.swift + ActiveWorkoutState.swift.
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

// MARK: - Fixed dates / IDs (deterministic — never Date())

let iso = ISO8601DateFormatter()
iso.timeZone = TimeZone(identifier: "UTC")

let t0 = iso.date(from: "2026-09-01T09:00:00Z")!   // workout start
func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

let routineID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
let otherRoutineID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

func makeState(
    activeSeconds: TimeInterval?,
    lastInteractionOffset: TimeInterval,
    logs: [String: [WorkoutSet]] = [:]
) -> ActiveWorkoutState {
    ActiveWorkoutState(
        routineID: routineID,
        routineName: "Push Day",
        startedAt: t0,
        lastInteractionAt: at(lastInteractionOffset),
        activeSeconds: activeSeconds,
        logs: logs,
        preferredSetCounts: ["Bench Press": 3]
    )
}

// MARK: - 1. Round-trip with mixed set-completion flags

let mixedLogs: [String: [WorkoutSet]] = [
    "Bench Press": [
        WorkoutSet(weight: "135", reps: "8", completed: true),
        WorkoutSet(weight: "140", reps: "6", completed: false),
        WorkoutSet(weight: "145", reps: "4", completed: nil)   // legacy shape
    ],
    "Overhead Press": [
        WorkoutSet(weight: "", reps: "", completed: false)
    ]
]

let original = makeState(activeSeconds: 1234.5, lastInteractionOffset: 1500, logs: mixedLogs)
let encoded = try! JSONEncoder().encode(original)
let decoded = try! JSONDecoder().decode(ActiveWorkoutState.self, from: encoded)

check("round-trip: state equal after encode/decode", decoded == original)
check("round-trip: checked set stays checked", decoded.logs["Bench Press"]?[0].completed == true)
check("round-trip: unchecked set stays unchecked", decoded.logs["Bench Press"]?[1].completed == false)
check("round-trip: legacy nil flag stays nil", decoded.logs["Bench Press"]?[2].completed == nil)
check("round-trip: isCompleted semantics hold (true/false/nil→true)",
      decoded.logs["Bench Press"]?[0].isCompleted == true &&
      decoded.logs["Bench Press"]?[1].isCompleted == false &&
      decoded.logs["Bench Press"]?[2].isCompleted == true)
check("round-trip: numbers survive", decoded.logs["Bench Press"]?[1].weight == "140" && decoded.logs["Bench Press"]?[1].reps == "6")
check("round-trip: preferred set counts survive", decoded.preferredSetCounts["Bench Press"] == 3)
check("round-trip: start/lastInteraction dates survive",
      decoded.startedAt == t0 && decoded.lastInteractionAt == at(1500))

// MARK: - 2. Legacy decode (blob saved without activeSeconds)

var legacyDict = try! JSONSerialization.jsonObject(with: encoded) as! [String: Any]
legacyDict.removeValue(forKey: "activeSeconds")
let legacyData = try! JSONSerialization.data(withJSONObject: legacyDict)
let legacyState = try! JSONDecoder().decode(ActiveWorkoutState.self, from: legacyData)

check("legacy decode: blob without activeSeconds decodes", legacyState.routineID == routineID)
check("legacy decode: activeSeconds defaults to nil", legacyState.activeSeconds == nil)
check("legacy decode: estimate falls back to lastInteraction − start (1500s = 25 min, exact multiple kept)",
      legacyState.smartDurationSeconds(now: at(20_000)) == 1500)

// MARK: - 3. Activity accumulation (gap-capped)

let s0 = makeState(activeSeconds: 0, lastInteractionOffset: 0)
let s1 = s0.updatingActivity(now: at(120))
check("activity: small gap accumulates (0 + 120 = 120)", s1.activeSeconds == 120 && s1.lastInteractionAt == at(120))

let s2 = s1.updatingActivity(now: at(120 + 1800))
check("activity: exactly-30-min gap still counts (120 + 1800 = 1920)", s2.activeSeconds == 1920)

let s3 = s2.updatingActivity(now: at(1920 + 1801))
check("activity: gap beyond 30 min counts zero, interaction clock still moves",
      s3.activeSeconds == 1920 && s3.lastInteractionAt == at(3721))

let s4 = s3.updatingActivity(now: at(3600))   // clock rolled back
check("activity: negative gap counts zero", s4.activeSeconds == 1920 && s4.lastInteractionAt == at(3600))

// MARK: - 4. Smart duration default

check("estimate: exact 5-min multiple kept (2700 → 2700)",
      makeState(activeSeconds: 2700, lastInteractionOffset: 2700).smartDurationSeconds(now: at(20_000)) == 2700)
check("estimate: rounds UP, never below the active span (2710 → 3000)",
      makeState(activeSeconds: 2710, lastInteractionOffset: 2710).smartDurationSeconds(now: at(20_000)) == 3000)
check("estimate: floors at 5 min — never zero (30s → 300)",
      makeState(activeSeconds: 30, lastInteractionOffset: 30).smartDurationSeconds(now: at(20_000)) == 300)
check("estimate: capped at wall-clock elapsed (span 4000, elapsed 3500 → 3500)",
      makeState(activeSeconds: 4000, lastInteractionOffset: 3500).smartDurationSeconds(now: at(3500)) == 3500)

// The Hevy horror case: 45-min workout forgotten overnight, finished 25h later.
let forgotten = makeState(activeSeconds: nil, lastInteractionOffset: 2700)
check("estimate: forgotten workout defaults to its ~45 min, not 25h, not 0",
      forgotten.smartDurationSeconds(now: at(25 * 3600)) == 2700)

// Resume-then-finish: reopening yesterday's workout bumps the interaction
// clock but must NOT absorb the overnight gap into the estimate.
let resumed = makeState(activeSeconds: 2700, lastInteractionOffset: 2700)
    .updatingActivity(now: at(90_000))
check("estimate: resumed stale workout keeps yesterday's span (2700)",
      resumed.smartDurationSeconds(now: at(90_060)) == 2700)
check("estimate: always a 5-min multiple", [
    makeState(activeSeconds: 2710, lastInteractionOffset: 2710).smartDurationSeconds(now: at(20_000)),
    makeState(activeSeconds: 30, lastInteractionOffset: 30).smartDurationSeconds(now: at(20_000)),
    forgotten.smartDurationSeconds(now: at(25 * 3600))
].allSatisfy { $0 % 300 == 0 })

// MARK: - 5. Thresholds

let threshold = makeState(activeSeconds: 600, lastInteractionOffset: 0)
check("duration fix: 2h59m elapsed → no fix", !threshold.needsDurationFix(now: at(3 * 3600 - 60)))
check("duration fix: exactly 3h → no fix (strict >)", !threshold.needsDurationFix(now: at(3 * 3600)))
check("duration fix: 3h01s → fix", threshold.needsDurationFix(now: at(3 * 3600 + 1)))

check("stale: 11h59m since interaction → fresh", !threshold.isStale(now: at(12 * 3600 - 60)))
check("stale: exactly 12h → fresh (strict >)", !threshold.isStale(now: at(12 * 3600)))
check("stale: 12h01s → stale", threshold.isStale(now: at(12 * 3600 + 1)))
check("stale workout always trips the duration fix (12h > 3h)",
      threshold.needsDurationFix(now: at(12 * 3600 + 1)))

// MARK: - 6. Routine-deleted discard

let routines = [
    Routine(id: routineID, name: "Push Day", exercises: ["Bench Press"]),
    Routine(id: otherRoutineID, name: "Pull Day", exercises: ["Row"])
]
check("resume: routine found by id",
      ActiveWorkoutStore.resumableRoutine(for: original, in: routines)?.id == routineID)
check("resume: deleted routine → nil (caller clears the state)",
      ActiveWorkoutStore.resumableRoutine(for: original, in: [routines[1]]) == nil)
check("resume: empty library → nil",
      ActiveWorkoutStore.resumableRoutine(for: original, in: []) == nil)

// MARK: - 7. Meaningful-content gate (untouched logger never claims the slot)

check("content: empty logs → not meaningful", !ActiveWorkoutStore.hasMeaningfulContent([:]))
check("content: blank sets → not meaningful",
      !ActiveWorkoutStore.hasMeaningfulContent(["A": [WorkoutSet(weight: "", reps: "", completed: false)]]))
check("content: whitespace-only → not meaningful",
      !ActiveWorkoutStore.hasMeaningfulContent(["A": [WorkoutSet(weight: "  ", reps: " ", completed: false)]]))
check("content: legacy nil flag with blank numbers → not meaningful",
      !ActiveWorkoutStore.hasMeaningfulContent(["A": [WorkoutSet(weight: "", reps: "", completed: nil)]]))
check("content: a weight makes it meaningful",
      ActiveWorkoutStore.hasMeaningfulContent(["A": [WorkoutSet(weight: "135", reps: "", completed: false)]]))
check("content: reps alone make it meaningful",
      ActiveWorkoutStore.hasMeaningfulContent(["A": [WorkoutSet(weight: "", reps: "8", completed: false)]]))
check("content: an explicit checkmark makes it meaningful",
      ActiveWorkoutStore.hasMeaningfulContent(["A": [WorkoutSet(weight: "", reps: "", completed: true)]]))

// MARK: - 8. Store round-trip through real UserDefaults

let suiteName = "active-workout-logic-check"
let defaults = UserDefaults(suiteName: suiteName)!
defaults.removePersistentDomain(forName: suiteName)

check("store: key is activeWorkoutV1", ActiveWorkoutStore.key == "activeWorkoutV1")
check("store: empty slot loads nil", ActiveWorkoutStore.load(defaults: defaults) == nil)

ActiveWorkoutStore.save(original, defaults: defaults)
check("store: save → load round-trips", ActiveWorkoutStore.load(defaults: defaults) == original)

ActiveWorkoutStore.clear(defaults: defaults)
check("store: clear empties the slot", ActiveWorkoutStore.load(defaults: defaults) == nil)

defaults.removePersistentDomain(forName: suiteName)

// MARK: - 9. Session-added exercises (mid-workout Add Exercise) round-trip

var withAdded = makeState(activeSeconds: 900, lastInteractionOffset: 900, logs: mixedLogs)
withAdded.sessionAddedExercises = ["Cable Lateral Raise", "Face Pull"]
withAdded.preferredSetCounts["Cable Lateral Raise"] = 3
let addedEncoded = try! JSONEncoder().encode(withAdded)
let addedDecoded = try! JSONDecoder().decode(ActiveWorkoutState.self, from: addedEncoded)

check("session-added: state equal after encode/decode", addedDecoded == withAdded)
check("session-added: names survive in add order",
      addedDecoded.sessionAddedExercises == ["Cable Lateral Raise", "Face Pull"])
check("session-added: seeded set count survives",
      addedDecoded.preferredSetCounts["Cable Lateral Raise"] == 3)
check("session-added: state without additions decodes nil field",
      decoded.sessionAddedExercises == nil)

// A blob with the field explicitly stripped (legacy build's save) still decodes.
var addedDict = try! JSONSerialization.jsonObject(with: addedEncoded) as! [String: Any]
addedDict.removeValue(forKey: "sessionAddedExercises")
let strippedData = try! JSONSerialization.data(withJSONObject: addedDict)
let strippedState = try! JSONDecoder().decode(ActiveWorkoutState.self, from: strippedData)
check("session-added: legacy blob without the field decodes, field nil",
      strippedState.sessionAddedExercises == nil && strippedState.routineID == routineID)

// UserDefaults round-trip keeps the added names (quit-and-resume path).
let addedSuite = "active-workout-logic-check-added"
let addedDefaults = UserDefaults(suiteName: addedSuite)!
addedDefaults.removePersistentDomain(forName: addedSuite)
ActiveWorkoutStore.save(withAdded, defaults: addedDefaults)
check("session-added: UserDefaults save → load keeps additions",
      ActiveWorkoutStore.load(defaults: addedDefaults) == withAdded)
addedDefaults.removePersistentDomain(forName: addedSuite)

// MARK: - Summary

if failures == 0 {
    print("ALL ACTIVE-WORKOUT CHECKS PASSED")
    exit(0)
} else {
    print("\(failures) ACTIVE-WORKOUT CHECK(S) FAILED")
    exit(1)
}
