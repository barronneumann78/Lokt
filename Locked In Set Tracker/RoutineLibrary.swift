import Foundation

enum RoutineLibrary {
    static let storageKey = "routines"

    static func load() -> [Routine] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([Routine].self, from: data) else {
            return []
        }

        return decoded
    }

    static func save(_ routines: [Routine]) {
        guard let encoded = try? JSONEncoder().encode(routines) else { return }
        UserDefaults.standard.set(encoded, forKey: storageKey)
    }

    static func addExercise(named exerciseName: String, toRoutineID routineID: UUID, preferredSetCount: Int = 3) -> AddExerciseResult {
        var routines = load()
        guard let index = routines.firstIndex(where: { $0.id == routineID }) else {
            return AddExerciseResult(message: "That routine could not be found.", didMutate: false)
        }

        if routines[index].exercises.contains(exerciseName) {
            return AddExerciseResult(message: "\(exerciseName) is already in \(routines[index].name).", didMutate: false)
        }

        routines[index].exercises.append(exerciseName)
        routines[index].preferredSetCounts[exerciseName] = max(1, preferredSetCount)
        save(routines)

        return AddExerciseResult(message: "Added to \(routines[index].name).", didMutate: true)
    }

    static func createRoutine(from exerciseName: String, preferredSetCount: Int = 3) -> Routine {
        let routine = Routine(
            name: exerciseName,
            exercises: [exerciseName],
            preferredSetCounts: [exerciseName: max(1, preferredSetCount)]
        )

        var routines = load()
        routines.append(routine)
        save(routines)
        return routine
    }

    static func addExercises(from draft: AIGeneratedRoutineDraft, toRoutineID routineID: UUID) -> AddExerciseResult {
        var routines = load()
        guard let index = routines.firstIndex(where: { $0.id == routineID }) else {
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

            if routines[index].exercises.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                continue
            }

            routines[index].exercises.append(name)
            routines[index].preferredSetCounts[name] = max(1, exercise.sets)
            addedCount += 1
        }

        guard addedCount > 0 else {
            return AddExerciseResult(message: "Those exercises are already in \(routines[index].name).", didMutate: false)
        }

        save(routines)

        return AddExerciseResult(
            message: addedCount == 1
                ? "Added 1 exercise to \(routines[index].name)."
                : "Added \(addedCount) exercises to \(routines[index].name).",
            didMutate: true
        )
    }

    static func createRoutine(from draft: AIGeneratedRoutineDraft) -> Routine? {
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

        var routines = load()
        routines.append(routine)
        save(routines)
        return routine
    }
}

struct AddExerciseResult {
    var message: String
    var didMutate: Bool
}
