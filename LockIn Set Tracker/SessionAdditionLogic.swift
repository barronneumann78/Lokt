import Foundation

/// Pure logic for the logger's mid-workout "Add Exercise" flow.
///
/// Additions are SESSION-SCOPED by default: they live in the logger's state
/// and the `activeWorkoutV1` snapshot, never in the saved routine — unless the
/// user explicitly keeps them at finish (review-before-save holds). Extracted
/// here (Foundation-only) so the compiled harness check asserts against the
/// shipping code.
enum SessionAdditionLogic {
    /// Seeded set count for an exercise added mid-workout — matches the
    /// review flow's default of 3.
    static let defaultSetCount = 3

    /// Everything an in-session add mutates, returned together so the logger
    /// applies it atomically.
    struct SessionAddOutcome {
        var order: [String]
        var sessionAdded: [String]
        var preferredSetCounts: [String: Int]
        var logs: [String: [WorkoutSet]]
    }

    /// Append `rawName` to the CURRENT session: end of the exercise order,
    /// seeded with `setCount` empty sets. Returns nil (no mutation) for an
    /// empty name or one already in the workout — case-insensitive, so tapping
    /// "bench press" never duplicates "Bench Press".
    static func addingExercise(
        named rawName: String,
        toOrder order: [String],
        sessionAdded: [String],
        preferredSetCounts: [String: Int],
        logs: [String: [WorkoutSet]],
        setCount: Int = defaultSetCount
    ) -> SessionAddOutcome? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              !order.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else {
            return nil
        }

        let count = max(1, setCount)
        var outcome = SessionAddOutcome(
            order: order,
            sessionAdded: sessionAdded,
            preferredSetCounts: preferredSetCounts,
            logs: logs
        )
        outcome.order.append(name)
        outcome.sessionAdded.append(name)
        outcome.preferredSetCounts[name] = count
        outcome.logs[name] = seededSets(existing: logs[name], count: count)
        return outcome
    }

    /// Pad (or trim) to `count`. Seeded sets carry an explicit
    /// `completed == false` — only the checkmark ever completes a set.
    static func seededSets(existing: [WorkoutSet]?, count: Int) -> [WorkoutSet] {
        var sets = existing ?? []
        let target = max(1, count)
        if sets.count < target {
            sets.append(contentsOf: Array(
                repeating: WorkoutSet(weight: "", reps: "", completed: false),
                count: target - sets.count
            ))
        } else if sets.count > target {
            sets = Array(sets.prefix(target))
        }
        return sets
    }

    /// The routine as it may be persisted MID-workout: session-added exercises
    /// stripped from the order and set counts, so reorder/set-count/swap
    /// writes never leak an addition into the saved routine before the user's
    /// explicit Keep at finish.
    static func routineStrippingSessionAdded(_ routine: Routine, sessionAdded: [String]) -> Routine {
        guard !sessionAdded.isEmpty else { return routine }

        var stripped = routine
        stripped.exercises.removeAll { name in
            sessionAdded.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
        }
        for name in sessionAdded {
            stripped.preferredSetCounts = stripped.preferredSetCounts.filter {
                $0.key.caseInsensitiveCompare(name) != .orderedSame
            }
        }
        return stripped
    }

    /// The Keep-at-finish upsert payload: `base` (SAME id — replace, never
    /// duplicate) with the session-added exercises appended in session order,
    /// carrying their in-session set counts.
    static func routineKeepingSessionAdded(
        _ base: Routine,
        sessionAdded: [String],
        preferredSetCounts: [String: Int]
    ) -> Routine {
        var kept = base
        for name in sessionAdded {
            guard !kept.exercises.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else {
                continue
            }
            kept.exercises.append(name)
            kept.preferredSetCounts[name] = max(1, preferredSetCounts[name] ?? defaultSetCount)
        }
        return kept
    }
}
