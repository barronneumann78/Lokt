import Foundation

enum CoachContextKind: String, Codable {
    case planning = "planning"
    case draftEditing = "draft_editing"
    case activeWorkout = "active_workout"
}

struct CoachChatContextPayload: Codable {
    var kind: String
    var activeWorkout: CoachActiveWorkoutPayload?
}

struct CoachActiveWorkoutPayload: Codable {
    var routineName: String
    var exercises: [String]
    var nextExercise: String?
}

struct CoachChatResult {
    var action: AIWorkoutCoachAction
    var assistantReply: String
    var changeSummary: String?
    var routine: AIGeneratedRoutineDraft?
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

    func sendMessage(
        _ message: String,
        contextKind: CoachContextKind,
        currentDraft: AIGeneratedRoutineDraft?,
        activeWorkout: CoachWorkoutSnapshot?,
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
                        routineName: $0.routineName,
                        exercises: $0.exercises,
                        nextExercise: $0.nextExercise
                    )
                }
            ),
            preferences: preferences
        )

        let decoded = try await sendRequest(body: payload)
        let sourcePrompt = currentDraft?.sourcePrompt ?? trimmedMessage
        let routineDraft = decoded.routine.flatMap {
            try? draftBuilder.makeDraftForSupplementaryBlock(from: $0, sourcePrompt: sourcePrompt, model: decoded.model)
        }

        return CoachChatResult(
            action: decoded.action,
            assistantReply: nonEmptyText(decoded.reply)
                ?? "I’m with you. Keep talking me through what you want.",
            changeSummary: nonEmptyText(decoded.changeSummary),
            routine: routineDraft
        )
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
                "I could not reach the coach backend. Make sure your server is running and the backend URL in Settings is correct. \(AIBackendConfiguration.localTestingHint)"
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
    var preferences: AIUserPreferencesPayload
}

private struct CoachChatResponseEnvelope: Codable {
    var reply: String?
    var action: AIWorkoutCoachAction
    var changeSummary: String?
    var routine: AIWorkoutRoutinePayload?
    var requestId: String?
    var model: String?
}

private struct CoachChatErrorEnvelope: Codable {
    var error: String
}
