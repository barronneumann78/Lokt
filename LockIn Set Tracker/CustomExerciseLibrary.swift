import Foundation

enum CustomExerciseLibrary {
    private static let storageKey = "customImportedExercises"

    static func loadExercises() -> [Exercise] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([Exercise].self, from: data) else {
            return []
        }

        return decoded
    }

    static func saveExercises(_ exercises: [Exercise]) {
        guard let encoded = try? JSONEncoder().encode(exercises) else { return }
        UserDefaults.standard.set(encoded, forKey: storageKey)
    }

    static func upsert(_ exercises: [Exercise]) {
        guard !exercises.isEmpty else { return }

        var stored = loadExercises()

        for exercise in exercises {
            if let index = stored.firstIndex(where: { $0.id == exercise.id || $0.name.caseInsensitiveCompare(exercise.name) == .orderedSame }) {
                stored[index] = exercise
            } else {
                stored.append(exercise)
            }
        }

        saveExercises(stored.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
    }
}
