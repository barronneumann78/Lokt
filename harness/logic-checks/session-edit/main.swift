// Logic check: session correction editor (Home → RECENT → SessionEditView).
// - SessionEditLogic: add/delete/toggle set semantics (checkmark rules match
//   the logger: unchecking always works, checking needs parseable numbers),
//   exercise ordering, duration round-trip, applyingEdits invariants
//   (id/routineID/routineName/checkIn preserved; zero-set exercises dropped).
// - WorkoutStore.updateSession: replace-by-id, never inserts, persists
//   legacy-compatible JSON under "workoutSessions", triggers the user-memory
//   refresh hook like every other session-writing path.
// Compiles against the REAL Models/WorkoutStore/AnalyticsModels/SessionEditLogic.
import Foundation

// MARK: - Stubs for app-only symbols the sources reference

enum MuscleGroup: String, Hashable {
    case chest, back, shoulders, arms, legs, core, other
}

struct Exercise {
    var name: String
    var muscleGroup: MuscleGroup
}

enum UserMemoryStore {
    static var refreshCount = 0
    @discardableResult
    static func refresh(now: Date = Date(), defaults: UserDefaults = .standard) -> Bool {
        refreshCount += 1
        return true
    }
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

let originalDate = iso.date(from: "2026-08-30T17:30:00Z")!
let editedDate = iso.date(from: "2026-08-29T09:15:00Z")!
let checkInDate = iso.date(from: "2026-08-30T18:20:00Z")!

let routineID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
let sessionID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
let strangerID = UUID(uuidString: "99999999-9999-9999-9999-999999999999")!

let suiteName = "session-edit-logic-check"

func freshDefaults() -> UserDefaults {
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

func makeSession() -> WorkoutSession {
    var session = WorkoutSession(
        id: sessionID,
        date: originalDate,
        routineID: routineID,
        routineName: "Push Day",
        logs: [
            "Bench Press": [
                WorkoutSet(weight: "135", reps: "8", completed: true),
                WorkoutSet(weight: "140", reps: "6", completed: true)
            ],
            "Overhead Press": [
                WorkoutSet(weight: "85", reps: "8", completed: nil) // legacy set
            ],
            "Lateral Raise": [
                WorkoutSet(weight: "15", reps: "12", completed: true)
            ]
        ],
        durationSeconds: 2730 // 45:30 → displays as "46"
    )
    session.checkIn = SessionCheckIn(overall: .aboutRight, recordedAt: checkInDate)
    return session
}

@MainActor
func runChecks() {

    // MARK: addingSet

    do {
        let seeded = SessionEditLogic.addingSet(to: [
            WorkoutSet(weight: "135", reps: "8", completed: true),
            WorkoutSet(weight: "140", reps: "6", completed: true)
        ])
        check("addingSet appends one set", seeded.count == 3)
        check("added set seeds last set's numbers", seeded[2].weight == "140" && seeded[2].reps == "6")
        check("added set starts unchecked (explicit false)", seeded[2].completed == false && !seeded[2].isCompleted)

        let fromEmpty = SessionEditLogic.addingSet(to: [])
        check("addingSet on empty exercise yields one blank unchecked set",
              fromEmpty.count == 1 && fromEmpty[0].weight == "" && fromEmpty[0].reps == "" && !fromEmpty[0].isCompleted)
    }

    // MARK: deletingSet

    do {
        let sets = [
            WorkoutSet(weight: "1", reps: "1", completed: true),
            WorkoutSet(weight: "2", reps: "2", completed: false),
            WorkoutSet(weight: "3", reps: "3", completed: true)
        ]
        let afterMiddle = SessionEditLogic.deletingSet(at: 1, from: sets)
        check("deletingSet removes the right index, order kept",
              afterMiddle.count == 2 && afterMiddle[0].weight == "1" && afterMiddle[1].weight == "3")
        check("deletingSet out of bounds is a no-op", SessionEditLogic.deletingSet(at: 5, from: sets).count == 3)
        check("deletingSet negative index is a no-op", SessionEditLogic.deletingSet(at: -1, from: sets).count == 3)
        check("deleting the only set leaves zero sets",
              SessionEditLogic.deletingSet(at: 0, from: [sets[0]]).isEmpty)
    }

    // MARK: togglingCompletion — checkmark rules match the logger

    do {
        let sets = [
            WorkoutSet(weight: "135", reps: "8", completed: true),   // checked
            WorkoutSet(weight: "85", reps: "8", completed: nil),     // legacy nil = completed
            WorkoutSet(weight: "155", reps: "5", completed: false),  // unchecked, meaningful
            WorkoutSet(weight: "", reps: "", completed: false),      // unchecked, blank
            WorkoutSet(weight: "bw", reps: "", completed: false),    // unchecked, unparseable
            WorkoutSet(weight: "", reps: "8", completed: false)      // reps-only still meaningful
        ]
        let unchecked = SessionEditLogic.togglingCompletion(at: 0, in: sets)
        check("toggling a checked set unchecks it", unchecked[0].completed == false && !unchecked[0].isCompleted)

        let legacyUnchecked = SessionEditLogic.togglingCompletion(at: 1, in: sets)
        check("toggling a legacy nil-flag set gives explicit false",
              legacyUnchecked[1].completed == false && !legacyUnchecked[1].isCompleted)

        let checked = SessionEditLogic.togglingCompletion(at: 2, in: sets)
        check("toggling an unchecked meaningful set checks it", checked[2].completed == true)

        let blank = SessionEditLogic.togglingCompletion(at: 3, in: sets)
        check("blank set cannot be checked", blank[3].completed == false)

        let unparseable = SessionEditLogic.togglingCompletion(at: 4, in: sets)
        check("unparseable set cannot be checked", unparseable[4].completed == false)

        let repsOnly = SessionEditLogic.togglingCompletion(at: 5, in: sets)
        check("reps-only set can be checked (isMeaningfulSet parity)", repsOnly[5].completed == true)

        check("toggling out of bounds is a no-op",
              SessionEditLogic.togglingCompletion(at: 9, in: sets).map(\.isCompleted) == sets.map(\.isCompleted))
    }

    // MARK: completion counting after edits — only isCompleted counts

    do {
        var sets = [
            WorkoutSet(weight: "100", reps: "10", completed: true),
            WorkoutSet(weight: "100", reps: "10", completed: true)
        ]
        sets = SessionEditLogic.addingSet(to: sets)               // +1 unchecked
        check("added set does not count until checked",
              sets.filter(\.isCompleted).count == 2 && AnalyticsMath.setVolume(sets[2]) == nil)

        sets = SessionEditLogic.togglingCompletion(at: 2, in: sets)
        check("checked added set counts (volume math sees it)",
              sets.filter(\.isCompleted).count == 3
              && sets.compactMap(AnalyticsMath.setVolume).reduce(0, +) == 3000)

        sets = SessionEditLogic.togglingCompletion(at: 0, in: sets)
        check("unchecked set stops counting everywhere",
              sets.filter(\.isCompleted).count == 2
              && !AnalyticsMath.isCountedSet(sets[0])
              && sets.compactMap(AnalyticsMath.setVolume).reduce(0, +) == 2000)
    }

    // MARK: orderedExerciseNames

    do {
        let logs: [String: [WorkoutSet]] = [
            "Lateral Raise": [], "Bench Press": [], "Overhead Press": [], "Face Pull": []
        ]
        let routine = Routine(
            id: routineID,
            name: "Push Day",
            exercises: ["Bench Press", "Overhead Press", "Lateral Raise", "Triceps Pushdown"]
        )
        check("routine order drives the editor, extras appended sorted",
              SessionEditLogic.orderedExerciseNames(in: logs, routine: routine)
              == ["Bench Press", "Overhead Press", "Lateral Raise", "Face Pull"])
        check("no routine → alphabetical",
              SessionEditLogic.orderedExerciseNames(in: logs, routine: nil)
              == ["Bench Press", "Face Pull", "Lateral Raise", "Overhead Press"])
    }

    // MARK: duration round-trip

    do {
        check("nil duration displays empty", SessionEditLogic.durationMinutesText(forSeconds: nil) == "")
        check("zero duration displays empty", SessionEditLogic.durationMinutesText(forSeconds: 0) == "")
        check("2730s displays as 46 min (rounded)", SessionEditLogic.durationMinutesText(forSeconds: 2730) == "46")
        check("2700s displays as 45 min", SessionEditLogic.durationMinutesText(forSeconds: 2700) == "45")
        check("tiny duration floors at 1 min", SessionEditLogic.durationMinutesText(forSeconds: 20) == "1")

        check("empty text clears duration",
              SessionEditLogic.resolvedDurationSeconds(original: 2730, minutesText: "") == nil)
        check("zero clears duration",
              SessionEditLogic.resolvedDurationSeconds(original: 2730, minutesText: "0") == nil)
        check("garbage keeps original seconds",
              SessionEditLogic.resolvedDurationSeconds(original: 2730, minutesText: "abc") == 2730)
        check("unchanged displayed value keeps exact original seconds",
              SessionEditLogic.resolvedDurationSeconds(original: 2730, minutesText: "46") == 2730)
        check("changed value stores whole minutes",
              SessionEditLogic.resolvedDurationSeconds(original: 2730, minutesText: "50") == 3000)
        check("duration added where there was none",
              SessionEditLogic.resolvedDurationSeconds(original: nil, minutesText: "12") == 720)
    }

    // MARK: applyingEdits — invariants

    do {
        let session = makeSession()
        var logs = session.logs
        logs["Bench Press"] = SessionEditLogic.addingSet(to: logs["Bench Press"]!)
        logs["Bench Press"] = SessionEditLogic.togglingCompletion(at: 2, in: logs["Bench Press"]!)
        logs["Lateral Raise"] = SessionEditLogic.deletingSet(at: 0, from: logs["Lateral Raise"]!)

        let edited = SessionEditLogic.applyingEdits(
            to: session, logs: logs, date: editedDate, durationMinutesText: "50"
        )
        check("id preserved", edited.id == sessionID)
        check("routineID preserved", edited.routineID == routineID)
        check("routineName preserved", edited.routineName == "Push Day")
        check("checkIn untouched by edits",
              edited.checkIn?.overall == .aboutRight && edited.checkIn?.recordedAt == checkInDate)
        check("date updated", edited.date == editedDate)
        check("duration updated", edited.durationSeconds == 3000)
        check("added+checked set landed",
              edited.logs["Bench Press"]?.count == 3 && edited.logs["Bench Press"]?[2].isCompleted == true)
        check("zero-set exercise dropped from the session", edited.logs["Lateral Raise"] == nil)
        check("untouched exercise (legacy set) kept verbatim",
              edited.logs["Overhead Press"]?.count == 1 && edited.logs["Overhead Press"]?[0].completed == nil)

        // No edits at all → nothing moves (duration text matches display).
        let identity = SessionEditLogic.applyingEdits(
            to: session, logs: session.logs, date: session.date,
            durationMinutesText: SessionEditLogic.durationMinutesText(forSeconds: session.durationSeconds)
        )
        check("no-op edit keeps exact duration seconds", identity.durationSeconds == 2730)
        check("no-op edit keeps all exercises", identity.logs.count == 3)
    }

    // MARK: WorkoutStore.updateSession — persistence round-trip

    do {
        let defaults = freshDefaults()
        let store = WorkoutStore(defaults: defaults)
        store.addSession(makeSession())

        let refreshesBefore = UserMemoryStore.refreshCount
        var logs = makeSession().logs
        logs["Bench Press"] = SessionEditLogic.addingSet(to: logs["Bench Press"]!)
        logs["Bench Press"] = SessionEditLogic.togglingCompletion(at: 2, in: logs["Bench Press"]!)
        logs["Lateral Raise"] = []
        let edited = SessionEditLogic.applyingEdits(
            to: makeSession(), logs: logs, date: editedDate, durationMinutesText: "50"
        )
        store.updateSession(edited)

        check("updateSession replaces in place (no duplicate)", store.sessions.count == 1)
        check("updateSession triggers user-memory refresh hook",
              UserMemoryStore.refreshCount == refreshesBefore + 1)

        // A second store instance = a fresh app launch reading the same key.
        let reloaded = WorkoutStore(defaults: defaults)
        let persisted = reloaded.session(withID: sessionID)
        check("edited session survives a reload", persisted != nil)
        check("persisted logs carry the correction",
              persisted?.logs["Bench Press"]?.count == 3
              && persisted?.logs["Bench Press"]?[2].isCompleted == true)
        check("persisted drop of the emptied exercise", persisted?.logs["Lateral Raise"] == nil)
        check("persisted date/duration", persisted?.date == editedDate && persisted?.durationSeconds == 3000)
        check("persisted checkIn intact", persisted?.checkIn?.overall == .aboutRight)

        // Legacy compatibility: the raw blob under "workoutSessions" decodes
        // with a plain JSONDecoder, exactly like the not-yet-migrated screens.
        let raw = defaults.data(forKey: "workoutSessions")
        let legacyDecoded = raw.flatMap { try? JSONDecoder().decode([WorkoutSession].self, from: $0) }
        check("raw blob decodes with a plain JSONDecoder (legacy paths keep working)",
              legacyDecoded?.count == 1 && legacyDecoded?[0].id == sessionID)

        // Unknown id: correcting a deleted session must not resurrect it.
        var stranger = makeSession()
        stranger.id = strangerID
        store.updateSession(stranger)
        check("updateSession never inserts unknown sessions", store.sessions.count == 1)

        defaults.removePersistentDomain(forName: suiteName)
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
