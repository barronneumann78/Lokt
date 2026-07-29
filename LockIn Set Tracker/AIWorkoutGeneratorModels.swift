import Foundation

enum AIWorkoutGenerationStage {
    case prompt
    case generating
    case review
}

enum AIWorkoutConversationRole: String, Codable, Hashable {
    case user
    case assistant
}

enum AIWorkoutCoachAction: String, Codable, Hashable {
    case replyOnly = "reply_only"
    case suggestion = "suggestion"
    case createdDraft = "created_draft"
    case updatedDraft = "updated_draft"

    var changedDraft: Bool {
        self == .createdDraft || self == .updatedDraft
    }
}

struct AIWorkoutConversationMessage: Identifiable, Hashable, Codable {
    var id = UUID()
    var role: AIWorkoutConversationRole
    var text: String

    init(role: AIWorkoutConversationRole, text: String) {
        self.role = role
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func user(_ text: String) -> AIWorkoutConversationMessage {
        AIWorkoutConversationMessage(role: .user, text: text)
    }

    static func assistant(_ text: String) -> AIWorkoutConversationMessage {
        AIWorkoutConversationMessage(role: .assistant, text: text)
    }
}

struct AIWorkoutConversationMessagePayload: Codable {
    var role: String
    var text: String
}

extension Array where Element == AIWorkoutConversationMessage {
    var aiPayload: [AIWorkoutConversationMessagePayload] {
        compactMap { message in
            let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }

            return AIWorkoutConversationMessagePayload(
                role: message.role.rawValue,
                text: text
            )
        }
    }
}

struct AIGeneratedExercise: Identifiable, Hashable, Codable {
    var id = UUID()
    var name: String
    var sets: Int
    var reps: String
    var notes: String?
    /// One short AI sentence on why this exercise is in the plan. Optional so
    /// photo/voice-import drafts and older cached payloads still decode.
    var reasoning: String?
    /// One short practical tip on how to execute this exercise in this workout
    /// (form, setup, tempo, or rest). Optional so older drafts still decode.
    var tip: String?
}

struct AIGeneratedRoutineDraft: Identifiable, Hashable, Codable {
    var id = UUID()
    var title: String
    var summary: String
    var rationale: String
    var routineNotes: [String]
    var exercises: [AIGeneratedExercise]
    var sourcePrompt: String
    var model: String?

    var totalSets: Int {
        exercises.reduce(0) { $0 + max(1, $1.sets) }
    }
}

struct AIWorkoutRoutinePayload: Codable {
    var title: String
    var summary: String
    var rationale: String
    var routineNotes: [String]
    var exercises: [AIWorkoutExercisePayload]
}

struct AIWorkoutExercisePayload: Codable {
    var name: String
    var sets: Int
    var reps: String
    var notes: String
    /// Optional so responses from older backends (or cached payloads) decode.
    var reasoning: String?
    /// Optional so responses from older backends (or cached payloads) decode.
    var tip: String?
}

extension AIGeneratedRoutineDraft {
    /// 1–2 sentence overview for the review header: the backend-constrained
    /// summary when present, otherwise the first two sentences of the rationale.
    var briefOverview: String? {
        let source = [summary, rationale]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }

        guard let source else { return nil }

        var sentences: [String] = []
        source.enumerateSubstrings(in: source.startIndex..., options: .bySentences) { substring, _, _, stop in
            let sentence = substring?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !sentence.isEmpty {
                sentences.append(sentence)
            }
            if sentences.count >= 2 {
                stop = true
            }
        }

        let overview = sentences.joined(separator: " ")
        return overview.isEmpty ? source : overview
    }

    var routinePayload: AIWorkoutRoutinePayload {
        AIWorkoutRoutinePayload(
            title: title,
            summary: summary,
            rationale: rationale,
            routineNotes: routineNotes,
            exercises: exercises.map {
                AIWorkoutExercisePayload(
                    name: $0.name,
                    sets: $0.sets,
                    reps: $0.reps,
                    notes: $0.notes ?? "",
                    reasoning: $0.reasoning,
                    tip: $0.tip
                )
            }
        )
    }
}
