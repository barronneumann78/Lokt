import Foundation

/// A plain-language training baseline selected during onboarding. The raw
/// values are intentionally stable because this value is persisted and sent to
/// the AI backend as part of the user's preference profile.
enum TrainingExperience: String, Codable, CaseIterable, Hashable, Identifiable {
    case newToTraining = "new_to_training"
    case returningToTraining = "returning_to_training"
    case trainingConsistently = "training_consistently"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newToTraining:
            return "New to training"
        case .returningToTraining:
            return "Getting back into it"
        case .trainingConsistently:
            return "Training consistently"
        }
    }

    var subtitle: String {
        switch self {
        case .newToTraining:
            return "I am new to structured strength workouts."
        case .returningToTraining:
            return "I have trained before but have had time away."
        case .trainingConsistently:
            return "I have been training regularly for at least six months."
        }
    }
}

/// Broad areas the user wants a plan to work around. These are preference
/// flags, not diagnoses; a free-form note remains available for needed detail.
enum InjuryFlag: String, Codable, CaseIterable, Hashable, Identifiable {
    case shoulder
    case elbowWrist = "elbow_wrist"
    case lowerBack = "lower_back"
    case hip
    case knee
    case ankleFoot = "ankle_foot"
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shoulder:
            return "Shoulder"
        case .elbowWrist:
            return "Elbow or wrist"
        case .lowerBack:
            return "Low back"
        case .hip:
            return "Hip"
        case .knee:
            return "Knee"
        case .ankleFoot:
            return "Ankle or foot"
        case .other:
            return "Another area"
        }
    }
}

struct AIUserPreferences: Codable, Hashable {
    var preferredEquipment: [String]
    var dislikedExercises: [String]
    var primaryGoal: String
    var limitations: String
    var trainingStyle: String
    var defaultTimeLimitMinutes: Int?
    /// Optional fields preserve decoding of preferences saved before the
    /// safety-aware onboarding shipped.
    var trainingExperience: TrainingExperience? = nil
    var age: Int? = nil
    var injuryFlags: [InjuryFlag]? = nil

    static let empty = AIUserPreferences(
        preferredEquipment: [],
        dislikedExercises: [],
        primaryGoal: "",
        limitations: "",
        trainingStyle: "",
        defaultTimeLimitMinutes: nil,
        trainingExperience: nil,
        age: nil,
        injuryFlags: nil
    )

    var isEmpty: Bool {
        preferredEquipment.isEmpty &&
        dislikedExercises.isEmpty &&
        primaryGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        limitations.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        trainingStyle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        defaultTimeLimitMinutes == nil &&
        trainingExperience == nil &&
        age == nil &&
        (injuryFlags?.isEmpty ?? true)
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

        if let trainingExperience {
            lines.append("Training experience: \(trainingExperience.title)")
        }

        if let age {
            lines.append("Age: \(age)")
        }

        let injuryFlags = injuryFlags ?? []
        if !injuryFlags.isEmpty {
            lines.append("Areas to work around: \(injuryFlags.map(\.title).joined(separator: ", "))")
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
    var trainingExperience: String?
    var age: Int?
    var injuryFlags: [String]

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
        trainingExperience = preferences.trainingExperience?.rawValue
        age = preferences.age
        injuryFlags = (preferences.injuryFlags ?? []).map(\.rawValue)
    }
}

extension AIUserPreferences {
    static func fromForm(
        preferredEquipmentText: String,
        dislikedExercisesText: String,
        primaryGoal: String,
        limitations: String,
        trainingStyle: String,
        defaultTimeLimitText: String,
        trainingExperience: TrainingExperience? = nil,
        age: Int? = nil,
        injuryFlags: [InjuryFlag] = []
    ) -> AIUserPreferences {
        AIUserPreferences(
            preferredEquipment: preferredEquipmentText.commaSeparatedValues,
            dislikedExercises: dislikedExercisesText.commaSeparatedValues,
            primaryGoal: primaryGoal.trimmingCharacters(in: .whitespacesAndNewlines),
            limitations: limitations.trimmingCharacters(in: .whitespacesAndNewlines),
            trainingStyle: trainingStyle.trimmingCharacters(in: .whitespacesAndNewlines),
            defaultTimeLimitMinutes: Int(defaultTimeLimitText.trimmingCharacters(in: .whitespacesAndNewlines)),
            trainingExperience: trainingExperience,
            age: age,
            injuryFlags: injuryFlags
        )
    }

    static func validAge(from text: String) -> Int? {
        guard let age = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              (13...120).contains(age) else {
            return nil
        }

        return age
    }
}

private extension String {
    var commaSeparatedValues: [String] {
        split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
