import Foundation

enum CoachContextKind: String, Codable {
    case planning = "planning"
    case draftEditing = "draft_editing"
    case routineEditing = "routine_editing"
    case activeWorkout = "active_workout"
}

struct CoachChatContextPayload: Codable {
    var kind: String
    var activeWorkout: CoachActiveWorkoutPayload?
}

struct CoachActiveWorkoutPayload: Codable {
    var routineID: String?
    var routineName: String
    var exercises: [String]
    var nextExercise: String?
    /// M4 safety branch: post-workout check-in summary the coach must address.
    var checkInNote: String?
}

/// Compact snapshot of one saved routine for the coach's context window.
struct CoachSavedRoutinePayload: Codable {
    var id: String
    var name: String
    var exercises: [CoachSavedRoutineExercisePayload]
}

struct CoachSavedRoutineExercisePayload: Codable {
    var name: String
    var sets: Int?
    var reps: String?
}

struct CoachChatResult {
    var action: AIWorkoutCoachAction
    var assistantReply: String
    var changeSummary: String?
    var routine: AIGeneratedRoutineDraft?
    /// Set when the backend built this draft as an edit of a specific saved
    /// routine, so the view can seed the save-in-place lineage. Describes the
    /// FIRST draft only.
    var editedRoutineID: UUID?
    /// Every draft this reply carries, in the coach's order: `[routine]` in
    /// the usual single case, two to five when the user clearly asked for
    /// more than one (backend `routines`, Coach tab only). Empty when the
    /// reply carries no draft. `drafts.first` is the same instance as `routine`.
    var drafts: [AIGeneratedRoutineDraft] = []
}

enum CoachChatError: LocalizedError {
    case invalidMessage
    case invalidResponse
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidMessage:
            return "Say a little more so Lokt has something useful to work with."
        case .invalidResponse:
            return "Lokt replied, but the coach response format was not usable."
        case .requestFailed(let message):
            return message
        }
    }
}

struct CoachChatService {
    private let draftBuilder = AIWorkoutGeneratorClient()

    /// Payload caps for the saved-routine snapshot: the 20 most recent routines
    /// ride along, the 12 most recent with per-exercise set/rep targets, older
    /// ones as exercise names only, at most 20 exercise names each.
    private static let maxSavedRoutines = 20
    private static let maxDetailedRoutines = 12
    private static let maxExercisesPerRoutine = 20

    func sendMessage(
        _ message: String,
        contextKind: CoachContextKind,
        currentDraft: AIGeneratedRoutineDraft?,
        activeWorkout: CoachRoutineSnapshot?,
        savedRoutines: [Routine],
        conversation: [AIWorkoutConversationMessage]
    ) async throws -> CoachChatResult {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedMessage.count >= 4 else {
            throw CoachChatError.invalidMessage
        }

        let preferences = AIUserPreferencesPayload(preferences: AIUserPreferencesStore.load())
        let payload = CoachChatRequest(
            message: trimmedMessage,
            conversation: conversation.aiPayload,
            currentRoutine: currentDraft?.routinePayload,
            context: CoachChatContextPayload(
                kind: contextKind.rawValue,
                activeWorkout: activeWorkout.map {
                    CoachActiveWorkoutPayload(
                        routineID: $0.routineID?.uuidString,
                        routineName: $0.routineName,
                        exercises: $0.exercises,
                        nextExercise: $0.nextExercise,
                        checkInNote: $0.checkInNote
                    )
                }
            ),
            savedRoutines: Self.savedRoutinesPayload(from: savedRoutines),
            preferences: preferences,
            memory: UserMemoryStore.current()
        )

        let decoded = try await sendRequest(body: payload)
        let sourcePrompt = currentDraft?.sourcePrompt ?? trimmedMessage
        func makeDraft(_ routine: AIWorkoutRoutinePayload) -> AIGeneratedRoutineDraft? {
            try? draftBuilder.makeDraftForSupplementaryBlock(from: routine, sourcePrompt: sourcePrompt, model: decoded.model)
        }

        // A multi-draft reply lists every draft in `routines` (routines[0] is
        // `routine`). Building from the list keeps one id per draft; anything
        // short of two usable drafts takes the single path exactly as before.
        let listedDrafts = (decoded.routines ?? []).compactMap(makeDraft)
        let routineDraft = listedDrafts.count >= 2 ? listedDrafts.first : decoded.routine.flatMap(makeDraft)
        let drafts = listedDrafts.count >= 2 ? listedDrafts : (routineDraft.map { [$0] } ?? [])

        return CoachChatResult(
            action: decoded.action,
            assistantReply: nonEmptyText(decoded.reply)
                ?? "I’m with you. Keep talking me through what you want.",
            changeSummary: nonEmptyText(decoded.changeSummary),
            routine: routineDraft,
            editedRoutineID: nonEmptyText(decoded.editedRoutineID).flatMap(UUID.init(uuidString:)),
            drafts: drafts
        )
    }

    /// Compact snapshot of the whole routine library. Every routine the user
    /// has saved is visible to the coach; the caps above only bound token cost.
    static func savedRoutinesPayload(from routines: [Routine]) -> [CoachSavedRoutinePayload] {
        let recent = Array(routines.suffix(maxSavedRoutines))
        let detailStartIndex = max(0, recent.count - maxDetailedRoutines)

        return recent.enumerated().map { index, routine in
            let includeTargets = index >= detailStartIndex
            let importedReps: [String: String]
            if includeTargets, let plans = routine.importContext?.exercisePlans {
                importedReps = plans.reduce(into: [:]) { partial, plan in
                    let name = (plan.matchedExerciseName ?? plan.exerciseName)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .lowercased()
                    if let reps = plan.targetReps?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !name.isEmpty, !reps.isEmpty, partial[name] == nil {
                        partial[name] = reps
                    }
                }
            } else {
                importedReps = [:]
            }

            let exercises = routine.exercises.prefix(maxExercisesPerRoutine).map { name in
                CoachSavedRoutineExercisePayload(
                    name: name,
                    sets: includeTargets ? routine.preferredSetCount(for: name) : nil,
                    reps: importedReps[name.lowercased()]
                )
            }

            return CoachSavedRoutinePayload(
                id: routine.id.uuidString,
                name: routine.name,
                exercises: Array(exercises)
            )
        }
    }

    private func sendRequest<T: Encodable>(body: T) async throws -> CoachChatResponseEnvelope {
        let data: Data
        let response: URLResponse

        do {
            let result = try await sendAIBackendRequest(
                path: "api/ai/coach/chat",
                timeout: 90,
                body: try JSONEncoder().encode(body)
            )
            data = result.data
            response = result.response
        } catch {
            throw CoachChatError.requestFailed(
                "I could not reach Lokt Coach. \(AIBackendConfiguration.connectionHelp)"
            )
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CoachChatError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let decodedError = try? JSONDecoder().decode(CoachChatErrorEnvelope.self, from: data) {
                throw CoachChatError.requestFailed(decodedError.error)
            }

            throw CoachChatError.requestFailed("The coach backend returned an error (\(httpResponse.statusCode)).")
        }

        guard let decoded = try? JSONDecoder().decode(CoachChatResponseEnvelope.self, from: data) else {
            throw CoachChatError.invalidResponse
        }

        return decoded
    }

    private func nonEmptyText(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct CoachChatRequest: Codable {
    var message: String
    var conversation: [AIWorkoutConversationMessagePayload]
    var currentRoutine: AIWorkoutRoutinePayload?
    var context: CoachChatContextPayload
    var savedRoutines: [CoachSavedRoutinePayload]
    var preferences: AIUserPreferencesPayload
    /// Tiered training-history digest (recent detail, weekly summaries,
    /// lifetime facts). nil when the user has no logged history yet.
    var memory: UserMemory?
}

private struct CoachChatResponseEnvelope: Codable {
    var reply: String?
    var action: AIWorkoutCoachAction
    var changeSummary: String?
    var routine: AIWorkoutRoutinePayload?
    var editedRoutineID: String?
    /// Full ordered draft list when the user asked for more than one workout;
    /// nil (or absent, from an older backend) otherwise.
    var routines: [AIWorkoutRoutinePayload]?
    var requestId: String?
    var model: String?
}

private struct CoachChatErrorEnvelope: Codable {
    var error: String
}
