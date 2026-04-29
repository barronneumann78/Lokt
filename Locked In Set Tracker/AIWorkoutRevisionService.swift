import Foundation

enum ImportedWorkoutRevisionError: LocalizedError {
    case invalidPrompt
    case invalidBackendURL
    case invalidResponse
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidPrompt:
            return "Add a little more detail so the AI knows how to revise the workout."
        case .invalidBackendURL:
            return "The AI backend URL is invalid. Update it in Settings before revising a workout."
        case .invalidResponse:
            return "The backend responded, but the revised workout format was not usable."
        case .requestFailed(let message):
            return message
        }
    }
}

struct ImportedWorkoutRevisionService {
    private let client = ImportedWorkoutRevisionClient()
    private let builder = WorkoutPhotoImportPipeline()

    func revise(
        draft: ImportedWorkoutDraft,
        instruction: String,
        exercises: [Exercise],
        conversation: [AIWorkoutConversationMessage] = []
    ) async throws -> ImportedWorkoutRevisionResult {
        let extraction = try await client.revise(
            parsingResult: draft.parsingResult(),
            instruction: instruction,
            conversation: conversation
        )

        let revisedDraft: ImportedWorkoutDraft
        if let extractionPayload = extraction.extraction {
            revisedDraft = try builder.buildImportedWorkout(
                from: extractionPayload,
                sourceKind: draft.sourceKind,
                exercises: exercises
            )
        } else {
            revisedDraft = draft
        }

        return ImportedWorkoutRevisionResult(
            action: extraction.action,
            draft: revisedDraft,
            assistantReply: extraction.reply?.trimmingCharacters(in: .whitespacesAndNewlines),
            changeSummary: extraction.changeSummary?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

private struct ImportedWorkoutRevisionClient {
    func revise(
        parsingResult: AIWorkoutParsingResult,
        instruction: String,
        conversation: [AIWorkoutConversationMessage]
    ) async throws -> ImportedWorkoutRevisionResponseEnvelope {
        let trimmedInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedInstruction.count >= 8 else {
            throw ImportedWorkoutRevisionError.invalidPrompt
        }

        guard !AIBackendConfiguration.candidateBaseURLs.isEmpty else {
            throw ImportedWorkoutRevisionError.invalidBackendURL
        }

        let (data, response): (Data, URLResponse)

        do {
            let preferences = AIUserPreferencesPayload(preferences: AIUserPreferencesStore.load())
            let result = try await sendAIBackendRequest(
                path: "api/ai/workout-import/revise",
                timeout: 90,
                body: try JSONEncoder().encode(
                    ImportedWorkoutRevisionRequest(
                        editPrompt: trimmedInstruction,
                        currentDraft: parsingResult,
                        conversation: conversation.aiPayload,
                        preferences: preferences
                    )
                )
            )
            (data, response) = (result.data, result.response)
        } catch {
            throw ImportedWorkoutRevisionError.requestFailed(
                "I could not reach the AI backend. Make sure your server is running and the backend URL in Settings is correct. \(AIBackendConfiguration.localTestingHint)"
            )
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ImportedWorkoutRevisionError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let decodedError = try? JSONDecoder().decode(ImportedWorkoutRevisionErrorEnvelope.self, from: data) {
                throw ImportedWorkoutRevisionError.requestFailed(decodedError.error)
            }

            throw ImportedWorkoutRevisionError.requestFailed(
                "The AI backend returned an error (\(httpResponse.statusCode))."
            )
        }

        guard let decoded = try? JSONDecoder().decode(ImportedWorkoutRevisionResponseEnvelope.self, from: data) else {
            throw ImportedWorkoutRevisionError.invalidResponse
        }

        return decoded
    }
}

private struct ImportedWorkoutRevisionRequest: Codable {
    var editPrompt: String
    var currentDraft: AIWorkoutParsingResult
    var conversation: [AIWorkoutConversationMessagePayload]
    var preferences: AIUserPreferencesPayload
}

struct ImportedWorkoutRevisionResponseEnvelope: Codable {
    var extraction: PhotoWorkoutAIExtractionResult?
    var requestId: String?
    var model: String?
    var reply: String?
    var action: AIWorkoutCoachAction
    var changeSummary: String?
}

private struct ImportedWorkoutRevisionErrorEnvelope: Codable {
    var error: String
}

struct ImportedWorkoutRevisionResult {
    var action: AIWorkoutCoachAction
    var draft: ImportedWorkoutDraft
    var assistantReply: String?
    var changeSummary: String?
}
