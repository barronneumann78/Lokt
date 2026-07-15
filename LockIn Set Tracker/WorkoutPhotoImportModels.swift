import Foundation

enum WorkoutPhotoImportStage {
    case input
    case processing
    case review
}

enum ImportedExerciseConfidence: String, Codable, Hashable {
    case high
    case medium
    case low

    var title: String {
        switch self {
        case .high:
            return "Matched"
        case .medium:
            return "Check match"
        case .low:
            return "Unclear"
        }
    }
}

enum ImportedExerciseMatchStatus: String, Hashable {
    case matched
    case uncertain
    case unmatched
}

struct ImportedExerciseMatchCandidate: Identifiable, Hashable, Codable {
    var name: String
    var score: Double

    var id: String { name }
}

struct ImportedExerciseDraft: Identifiable, Hashable, Codable {
    var id = UUID()
    var sourceText: String
    var exerciseName: String
    var matchedExerciseName: String?
    var matchCandidates: [ImportedExerciseMatchCandidate]
    var setCount: Int?
    var repText: String?
    var notes: String
    var restSeconds: Int?
    var intensityNotes: [String]
    var confidence: ImportedExerciseConfidence
    var isCustomExercise: Bool
    var customExercise: Exercise?

    var resolvedExerciseName: String {
        if isCustomExercise {
            return customExercise?.name ?? exerciseName
        }

        return matchedExerciseName ?? exerciseName
    }

    var matchStatus: ImportedExerciseMatchStatus {
        if isCustomExercise {
            return .unmatched
        }

        return confidence == .high ? .matched : .uncertain
    }

    var needsReview: Bool {
        isCustomExercise || confidence != .high || setCount == nil || repText == nil
    }

    var missingProgrammingDetails: String {
        var missing: [String] = []
        if setCount == nil {
            missing.append("sets are missing")
        }
        if repText == nil {
            missing.append("reps are missing")
        }
        return missing.joined(separator: " and ")
    }

    var warningText: String? {
        if isCustomExercise {
            let suggestions = matchCandidates.prefix(2).map(\.name)
            if suggestions.count == 2 {
                return "No strong library match yet. You may want \(suggestions[0]) or \(suggestions[1])."
            }

            return "No strong library match yet. Keep it as custom or swap it before saving."
        }

        guard confidence != .high else { return nil }
        let suggestions = matchCandidates.prefix(2).map(\.name)
        guard suggestions.count == 2 else {
            return "This match needs a quick review before saving."
        }

        return "This may be \(suggestions[0]) or \(suggestions[1]). Pick the one you want before saving."
    }

    var detailSummary: [String] {
        var values: [String] = []

        if let setCount {
            values.append("\(setCount) sets")
        } else {
            values.append("Sets not detected")
        }

        if let repText, !repText.isEmpty {
            values.append("\(repText) reps")
        } else {
            values.append("Reps not detected")
        }

        if let restSeconds {
            values.append(Self.restDescription(for: restSeconds))
        }

        values.append(contentsOf: intensityNotes)

        return values
    }

    static func restDescription(for seconds: Int) -> String {
        if seconds >= 60, seconds.isMultiple(of: 60) {
            return "\(seconds / 60) min rest"
        }

        return "\(seconds) sec rest"
    }
}

struct ImportedWorkoutDayDraft: Identifiable, Hashable, Codable {
    var id = UUID()
    var name: String
    var sourceHeading: String?
    var notes: [String]
    var exercises: [ImportedExerciseDraft]
}

struct ImportedWorkoutDraft: Identifiable, Hashable, Codable {
    var id = UUID()
    var sourceText: String
    var sourceKind: String
    var days: [ImportedWorkoutDayDraft]

    var allExercises: [ImportedExerciseDraft] {
        days.flatMap(\.exercises)
    }

    var totalExercises: Int {
        allExercises.count
    }

    var matchedExercises: [ImportedExerciseDraft] {
        allExercises.filter { $0.matchStatus == .matched }
    }

    var uncertainExercises: [ImportedExerciseDraft] {
        allExercises.filter { $0.matchStatus == .uncertain }
    }

    var unmatchedExercises: [ImportedExerciseDraft] {
        allExercises.filter { $0.matchStatus == .unmatched }
    }

    var readyExercises: [ImportedExerciseDraft] {
        allExercises.filter { !$0.needsReview }
    }
}

struct ImportedExerciseEditorTarget: Identifiable, Hashable {
    let dayIndex: Int
    let exerciseIndex: Int

    var id: String {
        "\(dayIndex)-\(exerciseIndex)"
    }
}
