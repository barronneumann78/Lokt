import Foundation

// MARK: - M4 adaptation loop — nudge wire models + pure application logic
//
// The backend's /api/ai/workout-nudge contract: the response mirrors the
// request's exercise list byte for byte (same names, same order) and carries
// only load/rep/set-count target deltas. Applying a nudge never changes a
// routine's identity, exercise list, or order — review-before-save holds
// because `applied(to:)` only runs from the user's explicit Apply tap.

struct WorkoutNudgeRequestExercise: Codable {
    var name: String
    /// Current preferred set count in the routine.
    var sets: Int?
    /// Current rep target, when the routine knows one.
    var repText: String?
    /// Most recent logged working weight, as the user typed it.
    var lastWeightText: String?
    /// Most recent logged reps for that set.
    var lastRepText: String?
}

struct WorkoutNudgeRequestRoutine: Codable {
    var name: String
    var exercises: [WorkoutNudgeRequestExercise]
}

struct WorkoutNudgeRequestCheckIn: Codable {
    /// Wire value: "too_easy" / "about_right" / "too_hard".
    var overall: String
    var hadPain: Bool
    var painNote: String?
    var painExercise: String?
}

extension CheckInOutcome {
    /// Snake-case wire value for the nudge endpoint.
    var nudgeWireValue: String {
        switch self {
        case .tooEasy: return "too_easy"
        case .aboutRight: return "about_right"
        case .tooHard: return "too_hard"
        }
    }
}

/// One exercise's next-session targets from the nudge. All-nil deltas mean
/// "no change" — the backend echoes every routine exercise either way.
struct WorkoutNudgeItem: Codable, Hashable {
    var name: String
    var suggestedWeightText: String?
    var repText: String?
    var setCount: Int?
    var whyNote: String?

    var hasChange: Bool {
        suggestedWeightText != nil || repText != nil || setCount != nil
    }
}

struct WorkoutNudge: Codable, Hashable {
    var overallNote: String?
    var exercises: [WorkoutNudgeItem]

    var changedItems: [WorkoutNudgeItem] {
        exercises.filter(\.hasChange)
    }

    var hasChanges: Bool {
        !changedItems.isEmpty
    }

    /// Pure application of this nudge to a routine: SAME id, SAME exercises,
    /// SAME order. Only `preferredSetCounts` and the per-exercise progression
    /// targets (`suggestedWeightText` / `suggestedRepText` / `nudgeNote`) move.
    /// Items naming an exercise the routine doesn't contain are ignored.
    func applied(to routine: Routine, at date: Date = Date()) -> Routine {
        var updated = routine
        var progression = updated.progression ?? [:]

        for item in exercises {
            guard item.hasChange,
                  updated.exercises.contains(item.name) else { continue }

            if let setCount = item.setCount {
                updated.preferredSetCounts[item.name] = min(max(setCount, 1), 10)
            }

            var state = progression[item.name] ?? ExerciseProgressionState()
            state.suggestedWeightText = item.suggestedWeightText
            state.suggestedRepText = item.repText
            state.nudgeNote = item.whyNote
            state.updatedAt = date
            progression[item.name] = state
        }

        updated.progression = progression
        return updated
    }
}

// MARK: - M5 instrumentation — local-only funnel counters
//
// BUILD_PLAN §M5's answered-vs-skipped experiment. One additive UserDefaults
// key, no UI; read the numbers when the experiment gets analyzed.

enum AdaptationMetrics {
    static let defaultsKey = "adaptationMetricsV1"

    enum Event: String, CaseIterable {
        case checkInShown
        case checkInAnswered
        case checkInSkipped
        case nudgeOffered
        case nudgeApplied
        case nudgeDismissed
    }

    static func increment(_ event: Event, defaults: UserDefaults = .standard) {
        var counts = self.counts(defaults: defaults)
        counts[event.rawValue, default: 0] += 1
        defaults.set(counts, forKey: defaultsKey)
    }

    static func counts(defaults: UserDefaults = .standard) -> [String: Int] {
        (defaults.dictionary(forKey: defaultsKey) as? [String: Int]) ?? [:]
    }
}
