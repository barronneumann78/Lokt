import Foundation

struct RoutineImportedExercisePlan: Codable, Hashable, Identifiable {
    var id = UUID()
    var exerciseName: String
    var sourceText: String
    var targetSets: Int?
    var targetReps: String?
    var restSeconds: Int?
    var notes: String?
    var intensityNotes: [String]
    var matchedExerciseName: String?
    var isCustomExercise: Bool
}

struct RoutineImportContext: Codable, Hashable {
    var sourceKind: String
    var importedAt: Date
    var originalText: String
    var dayName: String?
    var exercisePlans: [RoutineImportedExercisePlan]
}

struct Routine: Identifiable, Codable {
    var id = UUID()
    var name: String
    var exercises: [String]
    var preferredSetCounts: [String: Int]
    var historyNames: [String]?
    var importContext: RoutineImportContext?

    init(
        id: UUID = UUID(),
        name: String,
        exercises: [String],
        preferredSetCounts: [String: Int] = [:],
        historyNames: [String]? = nil,
        importContext: RoutineImportContext? = nil
    ) {
        self.id = id
        self.name = name
        self.exercises = exercises
        self.preferredSetCounts = preferredSetCounts
        self.historyNames = Routine.normalizedNames(historyNames ?? [name])
        self.importContext = importContext
    }

    func preferredSetCount(for exercise: String) -> Int {
        max(1, preferredSetCounts[exercise] ?? 3)
    }

    var allKnownNames: [String] {
        Routine.normalizedNames((historyNames ?? []) + [name])
    }

    private static func normalizedNames(_ names: [String]) -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []

        for name in names {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let key = trimmed.lowercased()
            if seen.insert(key).inserted {
                normalized.append(trimmed)
            }
        }

        return normalized
    }
}

struct WorkoutSet: Codable {
    var weight: String
    var reps: String
}

struct WorkoutSession: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var routineID: UUID?
    var routineName: String
    var logs: [String: [WorkoutSet]]

    init(
        id: UUID = UUID(),
        date: Date,
        routineID: UUID? = nil,
        routineName: String,
        logs: [String: [WorkoutSet]]
    ) {
        self.id = id
        self.date = date
        self.routineID = routineID
        self.routineName = routineName
        self.logs = logs
    }
}
