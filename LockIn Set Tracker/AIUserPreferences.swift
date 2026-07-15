import Foundation

struct AIUserPreferences: Codable, Hashable {
    var preferredEquipment: [String]
    var dislikedExercises: [String]
    var primaryGoal: String
    var limitations: String
    var trainingStyle: String
    var defaultTimeLimitMinutes: Int?

    static let empty = AIUserPreferences(
        preferredEquipment: [],
        dislikedExercises: [],
        primaryGoal: "",
        limitations: "",
        trainingStyle: "",
        defaultTimeLimitMinutes: nil
    )

    var isEmpty: Bool {
        preferredEquipment.isEmpty &&
        dislikedExercises.isEmpty &&
        primaryGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        limitations.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        trainingStyle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        defaultTimeLimitMinutes == nil
    }

    var summaryLines: [String] {
        var lines: [String] = []

        if !preferredEquipment.isEmpty {
            lines.append("Preferred equipment: \(preferredEquipment.joined(separator: ", "))")
        }

        if !dislikedExercises.isEmpty {
            lines.append("Avoid or minimize: \(dislikedExercises.joined(separator: ", "))")
        }

        let trimmedGoal = primaryGoal.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedGoal.isEmpty {
            lines.append("Primary goal: \(trimmedGoal)")
        }

        let trimmedLimitations = limitations.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedLimitations.isEmpty {
            lines.append("Limitations: \(trimmedLimitations)")
        }

        let trimmedTrainingStyle = trainingStyle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTrainingStyle.isEmpty {
            lines.append("Training style: \(trimmedTrainingStyle)")
        }

        if let defaultTimeLimitMinutes {
            lines.append("Default time limit: \(defaultTimeLimitMinutes) minutes")
        }

        return lines
    }
}

enum AIUserPreferencesStore {
    static let storageKey = "aiUserPreferences"

    static func load() -> AIUserPreferences {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(AIUserPreferences.self, from: data) else {
            return .empty
        }

        return decoded
    }

    static func save(_ preferences: AIUserPreferences) {
        guard let encoded = try? JSONEncoder().encode(preferences) else { return }
        UserDefaults.standard.set(encoded, forKey: storageKey)
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}

struct AIUserPreferencesPayload: Codable {
    var preferredEquipment: [String]
    var dislikedExercises: [String]
    var primaryGoal: String?
    var limitations: String?
    var trainingStyle: String?
    var defaultTimeLimitMinutes: Int?

    init(preferences: AIUserPreferences) {
        let trimmedGoal = preferences.primaryGoal.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLimitations = preferences.limitations.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedStyle = preferences.trainingStyle.trimmingCharacters(in: .whitespacesAndNewlines)

        preferredEquipment = preferences.preferredEquipment
        dislikedExercises = preferences.dislikedExercises
        primaryGoal = trimmedGoal.isEmpty ? nil : trimmedGoal
        limitations = trimmedLimitations.isEmpty ? nil : trimmedLimitations
        trainingStyle = trimmedStyle.isEmpty ? nil : trimmedStyle
        defaultTimeLimitMinutes = preferences.defaultTimeLimitMinutes
    }
}

extension AIUserPreferences {
    static func fromForm(
        preferredEquipmentText: String,
        dislikedExercisesText: String,
        primaryGoal: String,
        limitations: String,
        trainingStyle: String,
        defaultTimeLimitText: String
    ) -> AIUserPreferences {
        AIUserPreferences(
            preferredEquipment: preferredEquipmentText.commaSeparatedValues,
            dislikedExercises: dislikedExercisesText.commaSeparatedValues,
            primaryGoal: primaryGoal.trimmingCharacters(in: .whitespacesAndNewlines),
            limitations: limitations.trimmingCharacters(in: .whitespacesAndNewlines),
            trainingStyle: trainingStyle.trimmingCharacters(in: .whitespacesAndNewlines),
            defaultTimeLimitMinutes: Int(defaultTimeLimitText.trimmingCharacters(in: .whitespacesAndNewlines))
        )
    }
}

private extension String {
    var commaSeparatedValues: [String] {
        split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
