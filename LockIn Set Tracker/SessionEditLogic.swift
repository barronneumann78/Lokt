import Foundation

/// Pure mutation logic behind `SessionEditView` (Home → RECENT correction
/// editor). UI-free on purpose so the compiled harness check
/// (`harness/logic-checks/session-edit`) verifies it against the real models.
enum SessionEditLogic {

    /// One more set for an exercise, seeded from the last set's numbers so the
    /// common correction ("did another set at the same weight") is two taps.
    /// Always unchecked — only an explicit checkmark completes a set.
    static func addingSet(to sets: [WorkoutSet]) -> [WorkoutSet] {
        let seed = sets.last
        return sets + [WorkoutSet(weight: seed?.weight ?? "", reps: seed?.reps ?? "", completed: false)]
    }

    static func deletingSet(at index: Int, from sets: [WorkoutSet]) -> [WorkoutSet] {
        guard sets.indices.contains(index) else { return sets }
        var updated = sets
        updated.remove(at: index)
        return updated
    }

    /// Same completion rules as the logger: unchecking always works (legacy
    /// nil-flag sets get an explicit `false`), checking requires numbers that
    /// parse (`AnalyticsMath.isMeaningfulSet`).
    static func togglingCompletion(at index: Int, in sets: [WorkoutSet]) -> [WorkoutSet] {
        guard sets.indices.contains(index) else { return sets }
        var updated = sets
        if updated[index].isCompleted {
            updated[index].completed = false
        } else if AnalyticsMath.isMeaningfulSet(updated[index]) {
            updated[index].completed = true
        }
        return updated
    }

    /// Editor display order: the routine's exercise order while the session's
    /// routine still exists, extra logged exercises appended alphabetically.
    static func orderedExerciseNames(in logs: [String: [WorkoutSet]], routine: Routine?) -> [String] {
        var remaining = Set(logs.keys)
        var ordered: [String] = []
        for name in routine?.exercises ?? [] where remaining.remove(name) != nil {
            ordered.append(name)
        }
        return ordered + remaining.sorted()
    }

    /// Minutes shown in the duration field for a stored second count.
    static func durationMinutesText(forSeconds seconds: Int?) -> String {
        guard let seconds, seconds > 0 else { return "" }
        return "\(max(1, Int((Double(seconds) / 60).rounded())))"
    }

    /// Duration to store for the edited session. Empty or zero clears it; an
    /// unparseable entry keeps the original; a value matching what the field
    /// displayed keeps the original's exact seconds (no silent re-rounding);
    /// anything else stores whole minutes.
    static func resolvedDurationSeconds(original: Int?, minutesText: String) -> Int? {
        let trimmed = minutesText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        guard let minutes = Int(trimmed) else { return original }
        if minutes <= 0 { return nil }
        if durationMinutesText(forSeconds: original) == trimmed { return original }
        return minutes * 60
    }

    /// The edited session: same id, routine identity and check-in; new logs,
    /// date and duration. Exercises left with zero sets are dropped — deleting
    /// every set says "this exercise didn't happen".
    static func applyingEdits(
        to session: WorkoutSession,
        logs: [String: [WorkoutSet]],
        date: Date,
        durationMinutesText: String
    ) -> WorkoutSession {
        var edited = session
        edited.logs = logs.filter { !$0.value.isEmpty }
        edited.date = date
        edited.durationSeconds = resolvedDurationSeconds(
            original: session.durationSeconds,
            minutesText: durationMinutesText
        )
        return edited
    }
}
