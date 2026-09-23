import Foundation

enum SupplementaryWorkoutError: LocalizedError {
    case invalidPrompt
    case invalidBackendURL
    case invalidResponse
    case emptyRoutine
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidPrompt:
            return "Give Lokt a little more direction so it can build a useful add-on block."
        case .invalidBackendURL:
            return "Lokt’s AI service is unavailable right now. Check your connection and try again."
        case .invalidResponse:
            return "The backend responded, but the add-on block format was not usable."
        case .emptyRoutine:
            return "The add-on came back empty. Try a clearer request."
        case .requestFailed(let message):
            return message
        }
    }
}

struct SupplementaryWorkoutClient {
    func generateBlock(from prompt: String) async throws -> AIGeneratedRoutineDraft {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedPrompt.count >= 8 else {
            throw SupplementaryWorkoutError.invalidPrompt
        }

        let (data, response): (Data, URLResponse)

        do {
            let preferences = AIUserPreferencesPayload(preferences: AIUserPreferencesStore.load())
            let result = try await sendAIBackendRequest(
                path: "api/ai/workout-addon",
                timeout: 60,
                body: try JSONEncoder().encode(
                    SupplementaryWorkoutRequest(
                        prompt: trimmedPrompt,
                        preferences: preferences
                    )
                )
            )
            (data, response) = (result.data, result.response)
        } catch {
            throw SupplementaryWorkoutError.requestFailed(
                "I could not reach Lokt’s AI service. \(AIBackendConfiguration.connectionHelp)"
            )
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupplementaryWorkoutError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let decodedError = try? JSONDecoder().decode(SupplementaryWorkoutErrorEnvelope.self, from: data) {
                throw SupplementaryWorkoutError.requestFailed(decodedError.error)
            }

            throw SupplementaryWorkoutError.requestFailed("The AI backend returned an error (\(httpResponse.statusCode)).")
        }

        guard let decoded = try? JSONDecoder().decode(SupplementaryWorkoutResponseEnvelope.self, from: data) else {
            throw SupplementaryWorkoutError.invalidResponse
        }

        let generatorClient = AIWorkoutGeneratorClient()
        return try generatorClient.makeDraftForSupplementaryBlock(
            from: decoded.routine,
            sourcePrompt: trimmedPrompt,
            model: decoded.model
        )
    }
}

private struct SupplementaryWorkoutRequest: Codable {
    var prompt: String
    var preferences: AIUserPreferencesPayload
}

private struct SupplementaryWorkoutResponseEnvelope: Codable {
    var routine: AIWorkoutRoutinePayload
    var requestId: String?
    var model: String?
}

private struct SupplementaryWorkoutErrorEnvelope: Codable {
    var error: String
}
