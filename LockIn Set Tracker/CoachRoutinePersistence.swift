import Foundation

/// The one persistence path for a Coach draft. Keeping this separate from the
/// view makes the saved-lineage promise executable: a revised draft updates
/// its original routine instead of creating a duplicate.
enum CoachRoutinePersistence {
    enum Result {
        case added(Routine)
        case updated(Routine)
    }

    /// Persists a reviewed Coach draft. When its saved lineage still exists,
    /// retain that routine's identity and durable context; otherwise append a
    /// new routine just like a first-time save.
    @MainActor
    static func save(
        _ draft: AIGeneratedRoutineDraft,
        replacing routineID: UUID?,
        in store: WorkoutStore
    ) -> Result? {
        guard let generated = AIWorkoutRoutineSaver.makeRoutine(from: draft) else {
            return nil
        }

        if let routineID,
           let existing = store.routine(withID: routineID) {
            var updated = Routine(
                id: existing.id,
                name: generated.name,
                exercises: generated.exercises,
                preferredSetCounts: generated.preferredSetCounts,
                historyNames: existing.allKnownNames + [generated.name],
                importContext: existing.importContext
            )
            updated.progression = existing.progression
            store.upsertRoutine(updated)
            return .updated(updated)
        }

        store.addRoutine(generated)
        return .added(generated)
    }
}
