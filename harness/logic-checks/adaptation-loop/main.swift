// Logic check: M4 adaptation loop.
// - recordCheckIn semantics: progression-state transitions, pain flagging
//   (named exercise vs coarse fallback), needsRealCheckIn triggering, and
//   nudge-consumption on the next check-in.
// - WorkoutNudge.applied(to:): same routine id, same exercises, same order;
//   only set counts + progression targets move; unknown names ignored.
// - AdaptationMetrics counters (M5 instrumentation).
// - Legacy decode: sessions/routines/check-ins/progression saved before the
//   new fields still decode.
// Compiles against the REAL Models/WorkoutStore/WorkoutNudgeModels sources.
import Foundation

// MARK: - Stubs for app-only symbols WorkoutStore.swift references

enum UserMemoryStore {
    @discardableResult
    static func refresh(now: Date = Date(), defaults: UserDefaults = .standard) -> Bool { true }
}

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

// MARK: - Fixed dates / IDs

let iso = ISO8601DateFormatter()
iso.timeZone = TimeZone(identifier: "UTC")

let fixedDate = iso.date(from: "2026-08-30T12:00:00Z")!
let sessionDate1 = iso.date(from: "2026-08-27T17:30:00Z")!
let sessionDate2 = iso.date(from: "2026-08-29T17:30:00Z")!
let sessionDate3 = iso.date(from: "2026-08-31T17:30:00Z")!

let routineID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
let sessionID1 = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
let sessionID2 = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
let sessionID3 = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!

// MARK: - Fixture helpers

let suiteName = "adaptation-loop-logic-check"

func freshDefaults() -> UserDefaults {
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

func makeRoutine() -> Routine {
    Routine(
        id: routineID,
        name: "Push Day",
        exercises: ["Bench Press", "Overhead Press", "Lateral Raise", "Triceps Pushdown"],
        preferredSetCounts: ["Bench Press": 4, "Overhead Press": 3]
    )
}

func makeLogs() -> [String: [WorkoutSet]] {
    [
        "Bench Press": [
            WorkoutSet(weight: "135", reps: "8", completed: true),
            WorkoutSet(weight: "140", reps: "6", completed: true),
            WorkoutSet(weight: "145", reps: "4", completed: false)
        ],
        "Overhead Press": [
            WorkoutSet(weight: "85", reps: "8", completed: true)
        ],
        "Lateral Raise": [
            WorkoutSet(weight: "15", reps: "12", completed: true)
        ],
        "Triceps Pushdown": [
            WorkoutSet(weight: "", reps: "", completed: false)
        ]
    ]
}

func seedStore(defaults: UserDefaults, routine: Routine, sessions: [WorkoutSession]) {
    let encoder = JSONEncoder()
    defaults.set(try! encoder.encode([routine]), forKey: "routines")
    defaults.set(try! encoder.encode(sessions), forKey: "workoutSessions")
}

func makeSession(id: UUID, date: Date) -> WorkoutSession {
    WorkoutSession(id: id, date: date, routineID: routineID, routineName: "Push Day", logs: makeLogs())
}

@MainActor
func runChecks() {

    // MARK: recordCheckIn — clean "too easy" check-in

    print("-- recordCheckIn: clean check-in --")
    do {
        let defaults = freshDefaults()
        seedStore(defaults: defaults, routine: makeRoutine(), sessions: [makeSession(id: sessionID1, date: sessionDate1)])
        let store = WorkoutStore(defaults: defaults)

        store.recordCheckIn(SessionCheckIn(overall: .tooEasy, recordedAt: fixedDate), forSessionID: sessionID1)

        let session = store.session(withID: sessionID1)
        check("check-in attached to the session", session?.checkIn?.overall == .tooEasy)
        check("check-in carries no pain", session?.checkIn?.hadPain == false)

        let progression = store.routine(withID: routineID)?.progression
        let bench = progression?["Bench Press"]
        check("progression created for logged exercises", progression?.count == 4)
        check("lastWeight is the LAST completed set (140, not the unchecked 145)", bench?.lastWeight == "140")
        check("lastReps follows the same set", bench?.lastReps == "6")
        check("outcome recorded on each exercise", bench?.lastOutcome == .tooEasy)
        check("too-easy leaves consecutiveTooHard at 0", bench?.consecutiveTooHard == 0)
        check("no pain flag on a clean check-in", bench?.painFlagged == false)
        check("needsRealCheckIn stays off", bench?.needsRealCheckIn == false)

        check("check-in on an unknown session id is a no-op", {
            store.recordCheckIn(SessionCheckIn(overall: .tooHard), forSessionID: UUID())
            return store.routine(withID: routineID)?.progression?["Bench Press"]?.lastOutcome == .tooEasy
        }())
    }

    // MARK: recordCheckIn — repeated too-hard trips needsRealCheckIn

    print("-- recordCheckIn: repeated too-hard --")
    do {
        let defaults = freshDefaults()
        seedStore(
            defaults: defaults,
            routine: makeRoutine(),
            sessions: [
                makeSession(id: sessionID1, date: sessionDate1),
                makeSession(id: sessionID2, date: sessionDate2),
                makeSession(id: sessionID3, date: sessionDate3)
            ]
        )
        let store = WorkoutStore(defaults: defaults)

        store.recordCheckIn(SessionCheckIn(overall: .tooHard), forSessionID: sessionID1)
        var bench = store.routine(withID: routineID)?.progression?["Bench Press"]
        check("first too-hard: consecutiveTooHard == 1", bench?.consecutiveTooHard == 1)
        check("first too-hard: needsRealCheckIn still off", bench?.needsRealCheckIn == false)

        store.recordCheckIn(SessionCheckIn(overall: .tooHard), forSessionID: sessionID2)
        bench = store.routine(withID: routineID)?.progression?["Bench Press"]
        check("second too-hard: consecutiveTooHard == 2", bench?.consecutiveTooHard == 2)
        check("second too-hard FIRES needsRealCheckIn", bench?.needsRealCheckIn == true)

        store.recordCheckIn(SessionCheckIn(overall: .aboutRight), forSessionID: sessionID3)
        bench = store.routine(withID: routineID)?.progression?["Bench Press"]
        check("about-right resets the streak", bench?.consecutiveTooHard == 0)
        check("reset streak clears needsRealCheckIn", bench?.needsRealCheckIn == false)
    }

    // MARK: recordCheckIn — pain flagging

    print("-- recordCheckIn: pain flagging --")
    do {
        let defaults = freshDefaults()
        seedStore(defaults: defaults, routine: makeRoutine(), sessions: [makeSession(id: sessionID1, date: sessionDate1)])
        let store = WorkoutStore(defaults: defaults)

        // Named exercise: exactly that one is flagged, regardless of outcome.
        store.recordCheckIn(
            SessionCheckIn(overall: .aboutRight, hadPain: true, painNote: "left shoulder", painExercise: "Lateral Raise"),
            forSessionID: sessionID1
        )
        let progression = store.routine(withID: routineID)?.progression
        check("named pain exercise gets the flag", progression?["Lateral Raise"]?.painFlagged == true)
        check("pain flag fires needsRealCheckIn", progression?["Lateral Raise"]?.needsRealCheckIn == true)
        check("other exercises stay unflagged (Bench)", progression?["Bench Press"]?.painFlagged == false)
        check("other exercises stay unflagged (OHP)", progression?["Overhead Press"]?.painFlagged == false)
    }
    do {
        let defaults = freshDefaults()
        seedStore(defaults: defaults, routine: makeRoutine(), sessions: [makeSession(id: sessionID1, date: sessionDate1)])
        let store = WorkoutStore(defaults: defaults)

        // No named exercise: coarse fallback — pain rides on too-hard outcomes.
        store.recordCheckIn(SessionCheckIn(overall: .tooHard, hadPain: true), forSessionID: sessionID1)
        let progression = store.routine(withID: routineID)?.progression
        check("coarse fallback flags too-hard exercises when pain reported", progression?["Bench Press"]?.painFlagged == true)
    }

    // MARK: recordCheckIn — consumes applied nudge targets

    print("-- recordCheckIn: nudge consumption --")
    do {
        let defaults = freshDefaults()
        var routine = makeRoutine()
        routine.progression = [
            "Bench Press": ExerciseProgressionState(
                lastWeight: "135",
                lastReps: "8",
                suggestedWeightText: "140 lb",
                suggestedRepText: "8",
                nudgeNote: "last one felt easy"
            )
        ]
        seedStore(defaults: defaults, routine: routine, sessions: [makeSession(id: sessionID1, date: sessionDate1)])
        let store = WorkoutStore(defaults: defaults)

        store.recordCheckIn(SessionCheckIn(overall: .aboutRight), forSessionID: sessionID1)
        let bench = store.routine(withID: routineID)?.progression?["Bench Press"]
        check("applied nudge weight cleared after the next check-in", bench?.suggestedWeightText == nil)
        check("applied nudge reps cleared after the next check-in", bench?.suggestedRepText == nil)
        check("nudge why-note cleared after the next check-in", bench?.nudgeNote == nil)
        check("history fields survive the consumption", bench?.lastWeight == "140")
    }

    // MARK: WorkoutNudge.applied(to:)

    print("-- nudge application --")
    do {
        var routine = makeRoutine()
        routine.progression = [
            "Bench Press": ExerciseProgressionState(lastWeight: "140", lastReps: "6", lastOutcome: .tooEasy)
        ]

        let nudge = WorkoutNudge(
            overallNote: "Small bump across the pressing work.",
            exercises: [
                WorkoutNudgeItem(name: "Bench Press", suggestedWeightText: "145 lb", repText: "6-8", setCount: 5, whyNote: "last one felt easy"),
                WorkoutNudgeItem(name: "Overhead Press", suggestedWeightText: nil, repText: nil, setCount: nil, whyNote: "steady"),
                WorkoutNudgeItem(name: "Lateral Raise", suggestedWeightText: nil, repText: nil, setCount: 12, whyNote: "room for a set"),
                WorkoutNudgeItem(name: "Not In Routine", suggestedWeightText: "999 lb", repText: "1", setCount: 3, whyNote: "bogus")
            ]
        )

        let applied = nudge.applied(to: routine, at: fixedDate)

        check("routine id unchanged", applied.id == routineID)
        check("exercise list identical and order preserved", applied.exercises == routine.exercises)
        check("routine name unchanged", applied.name == "Push Day")
        check("set count applied (Bench 4 → 5)", applied.preferredSetCounts["Bench Press"] == 5)
        check("out-of-range set count clamps to 10", applied.preferredSetCounts["Lateral Raise"] == 10)
        check("no-change exercise keeps its set count", applied.preferredSetCounts["Overhead Press"] == 3)

        let bench = applied.progression?["Bench Press"]
        check("weight target stored on progression", bench?.suggestedWeightText == "145 lb")
        check("rep target stored on progression", bench?.suggestedRepText == "6-8")
        check("why-note stored on progression", bench?.nudgeNote == "last one felt easy")
        check("existing history fields preserved on the applied exercise", bench?.lastWeight == "140" && bench?.lastOutcome == .tooEasy)
        check("no-change exercise gains no progression entry", applied.progression?["Overhead Press"] == nil)
        check("unknown exercise in the nudge is ignored", applied.progression?["Not In Routine"] == nil && applied.preferredSetCounts["Not In Routine"] == nil)

        check("changedItems filters all-nil entries", nudge.changedItems.map(\.name) == ["Bench Press", "Lateral Raise", "Not In Routine"])
        check("hasChanges true when any delta present", nudge.hasChanges)
        let quietNudge = WorkoutNudge(overallNote: nil, exercises: [
            WorkoutNudgeItem(name: "Bench Press", suggestedWeightText: nil, repText: nil, setCount: nil, whyNote: nil)
        ])
        check("hasChanges false for an all-null nudge", !quietNudge.hasChanges)
        check("all-null nudge applies as a no-op", quietNudge.applied(to: routine, at: fixedDate).preferredSetCounts == routine.preferredSetCounts)
    }

    // MARK: Wire values

    print("-- wire values --")
    check("tooEasy wire value", CheckInOutcome.tooEasy.nudgeWireValue == "too_easy")
    check("aboutRight wire value", CheckInOutcome.aboutRight.nudgeWireValue == "about_right")
    check("tooHard wire value", CheckInOutcome.tooHard.nudgeWireValue == "too_hard")

    // MARK: AdaptationMetrics counters

    print("-- counters --")
    do {
        let defaults = freshDefaults()
        check("fresh install has no counts", AdaptationMetrics.counts(defaults: defaults).isEmpty)

        AdaptationMetrics.increment(.checkInShown, defaults: defaults)
        AdaptationMetrics.increment(.checkInShown, defaults: defaults)
        AdaptationMetrics.increment(.checkInAnswered, defaults: defaults)
        AdaptationMetrics.increment(.nudgeOffered, defaults: defaults)
        AdaptationMetrics.increment(.nudgeApplied, defaults: defaults)

        let counts = AdaptationMetrics.counts(defaults: defaults)
        check("shown counted twice", counts["checkInShown"] == 2)
        check("answered counted once", counts["checkInAnswered"] == 1)
        check("offered counted once", counts["nudgeOffered"] == 1)
        check("applied counted once", counts["nudgeApplied"] == 1)
        check("unfired events absent", counts["checkInSkipped"] == nil && counts["nudgeDismissed"] == nil)
        check("counters survive a re-read", AdaptationMetrics.counts(defaults: defaults)["checkInShown"] == 2)
    }

    // MARK: Legacy decode — blobs saved before the new fields

    print("-- legacy decode --")
    do {
        let decoder = JSONDecoder()

        // Routine saved before the adaptation loop: no progression key.
        let legacyRoutine = """
        [{"id":"11111111-1111-1111-1111-111111111111","name":"Old Push","exercises":["Bench Press"],"preferredSetCounts":{}}]
        """.data(using: .utf8)!
        let routines = try? decoder.decode([Routine].self, from: legacyRoutine)
        check("pre-M4 routine decodes (no progression)", routines?.first?.progression == nil)

        // Session saved before check-ins/duration; sets without completed flag.
        let legacySession = """
        [{"id":"33333333-3333-3333-3333-333333333333","date":775000000,"routineName":"Old Push","logs":{"Bench Press":[{"weight":"135","reps":"8"}]}}]
        """.data(using: .utf8)!
        let sessions = try? decoder.decode([WorkoutSession].self, from: legacySession)
        check("pre-M4 session decodes (no checkIn)", sessions?.first?.checkIn == nil)
        check("legacy set without flag counts completed", sessions?.first?.logs["Bench Press"]?.first?.isCompleted == true)

        // Check-in recorded by M1 plumbing: no painExercise key.
        let legacyCheckIn = """
        {"overall":"tooHard","hadPain":true,"recordedAt":775000000}
        """.data(using: .utf8)!
        let checkIn = try? decoder.decode(SessionCheckIn.self, from: legacyCheckIn)
        check("pre-M4 check-in decodes (no painExercise)", checkIn?.painExercise == nil && checkIn?.overall == .tooHard)

        // Progression state persisted before nudge targets existed.
        let legacyState = """
        {"consecutiveTooHard":2,"painFlagged":false,"updatedAt":775000000}
        """.data(using: .utf8)!
        let state = try? decoder.decode(ExerciseProgressionState.self, from: legacyState)
        check("pre-M4 progression state decodes (no nudge fields)", state?.suggestedWeightText == nil && state?.nudgeNote == nil)
        check("decoded legacy state still computes needsRealCheckIn", state?.needsRealCheckIn == true)
    }
}

MainActor.assumeIsolated {
    runChecks()
}

print("==========================")
if failures == 0 {
    print("ALL CHECKS PASSED")
    exit(0)
} else {
    print("\(failures) CHECK(S) FAILED")
    exit(1)
}
