import Foundation

enum RoutineLibrary {
    @MainActor
    static func addExercise(
        named exerciseName: String,
        toRoutineID routineID: UUID,
        preferredSetCount: Int = 3,
        in store: WorkoutStore
    ) -> AddExerciseResult {
        guard var routine = store.routine(withID: routineID) else {
            return AddExerciseResult(message: "That routine could not be found.", didMutate: false)
        }

        if routine.exercises.contains(exerciseName) {
            return AddExerciseResult(message: "\(exerciseName) is already in \(routine.name).", didMutate: false)
        }

        routine.exercises.append(exerciseName)
        routine.preferredSetCounts[exerciseName] = max(1, preferredSetCount)
        store.upsertRoutine(routine)

        return AddExerciseResult(message: "Added to \(routine.name).", didMutate: true)
    }

    @MainActor
    static func createRoutine(
        from exerciseName: String,
        preferredSetCount: Int = 3,
        in store: WorkoutStore
    ) -> Routine {
        let routine = Routine(
            name: exerciseName,
            exercises: [exerciseName],
            preferredSetCounts: [exerciseName: max(1, preferredSetCount)]
        )

        store.addRoutine(routine)
        return routine
    }

    @MainActor
    static func addExercises(
        from draft: AIGeneratedRoutineDraft,
        toRoutineID routineID: UUID,
        in store: WorkoutStore
    ) -> AddExerciseResult {
        guard var routine = store.routine(withID: routineID) else {
            return AddExerciseResult(message: "That routine could not be found.", didMutate: false)
        }

        let incomingExercises = draft.exercises
            .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !incomingExercises.isEmpty else {
            return AddExerciseResult(message: "There were no exercises to add.", didMutate: false)
        }

        var addedCount = 0

        for exercise in draft.exercises {
            let name = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }

            if routine.exercises.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                continue
            }

            routine.exercises.append(name)
            routine.preferredSetCounts[name] = max(1, exercise.sets)
            addedCount += 1
        }

        guard addedCount > 0 else {
            return AddExerciseResult(message: "Those exercises are already in \(routine.name).", didMutate: false)
        }

        store.upsertRoutine(routine)

        return AddExerciseResult(
            message: addedCount == 1
                ? "Added 1 exercise to \(routine.name)."
                : "Added \(addedCount) exercises to \(routine.name).",
            didMutate: true
        )
    }

    @MainActor
    static func createRoutine(from draft: AIGeneratedRoutineDraft, in store: WorkoutStore) -> Routine? {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let exercises = draft.exercises
            .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !title.isEmpty, !exercises.isEmpty else { return nil }

        let preferredSetCounts = draft.exercises.reduce(into: [String: Int]()) { counts, exercise in
            let name = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            counts[name] = max(1, exercise.sets)
        }

        let routine = Routine(
            name: title,
            exercises: exercises,
            preferredSetCounts: preferredSetCounts
        )

        store.addRoutine(routine)
        return routine
    }
}

struct AddExerciseResult {
    var message: String
    var didMutate: Bool
}
