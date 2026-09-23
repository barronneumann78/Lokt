import Foundation

enum AIWorkoutGenerationError: LocalizedError {
    case invalidPrompt
    case invalidBackendURL
    case invalidResponse
    case emptyRoutine
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidPrompt:
            return "Write a little more detail so the AI has something useful to build from."
        case .invalidBackendURL:
            return "Lokt’s AI service is unavailable right now. Check your connection and try again."
        case .invalidResponse:
            return "The backend responded, but the routine format was not usable."
        case .emptyRoutine:
            return "The AI did not return any exercises. Try a clearer prompt."
        case .requestFailed(let message):
            return message
        }
    }
}

enum AIBackendConfiguration {
    static let defaultBaseURLString = "https://lokt-production.up.railway.app"
    static let productionBaseURL = URL(string: defaultBaseURLString)!
    /// TestFlight always talks to the shipped Railway backend. The app never
    /// accepts a user-provided server address.
    static let connectionHelp = "Check your internet connection and try again."

    /// Header carrying the shared app token on every backend call.
    static let appTokenHeaderField = "x-app-token"

    /// The shared app token from the gitignored `AIBackendSecrets.swift`
    /// (copy `AIBackendSecrets.swift.example` to create it). Nil or blank
    /// means no header is sent.
    static var appToken: String? {
        guard let token = AIBackendSecrets.appToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else { return nil }
        return token
    }

}

struct AIBackendRequestResult {
    let data: Data
    let response: URLResponse
    let baseURL: URL
}

func sendAIBackendRequest(
    path: String,
    method: String = "POST",
    timeout: TimeInterval = 60,
    contentType: String = "application/json",
    body: Data? = nil
) async throws -> AIBackendRequestResult {
    let baseURL = AIBackendConfiguration.productionBaseURL
    let endpoint = baseURL.appending(path: path)
    var request = URLRequest(url: endpoint)
    request.httpMethod = method
    request.timeoutInterval = timeout

    if !contentType.isEmpty {
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
    }

    if let appToken = AIBackendConfiguration.appToken {
        request.setValue(appToken, forHTTPHeaderField: AIBackendConfiguration.appTokenHeaderField)
    }

    request.httpBody = body
    let (data, response) = try await URLSession.shared.data(for: request)
    return AIBackendRequestResult(data: data, response: response, baseURL: baseURL)
}

struct AIWorkoutGeneratorClient {
    func generateRoutine(from prompt: String) async throws -> AIGeneratedRoutineDraft {
        let trimmedPrompt = try validatedPrompt(prompt)
        let preferences = AIUserPreferencesPayload(preferences: AIUserPreferencesStore.load())
        let decoded = try await sendGeneratorRequest(
            path: "api/ai/workout-generator",
            body: AIWorkoutGeneratorRequest(
                prompt: trimmedPrompt,
                preferences: preferences,
                memory: UserMemoryStore.current()
            )
        )

        guard let routinePayload = decoded.routine else {
            throw AIWorkoutGenerationError.invalidResponse
        }

        return try makeDraft(from: routinePayload, sourcePrompt: trimmedPrompt, model: decoded.model)
    }

    func reviseRoutine(
        _ routine: AIGeneratedRoutineDraft,
        editPrompt: String,
        conversation: [AIWorkoutConversationMessage] = []
    ) async throws -> AIWorkoutRevisionResult {
        let trimmedPrompt = try validatedPrompt(editPrompt)
        let preferences = AIUserPreferencesPayload(preferences: AIUserPreferencesStore.load())
        let decoded = try await sendRevisionRequest(
            path: "api/ai/workout-generator/revise",
            body: AIWorkoutGeneratorRevisionRequest(
                editPrompt: trimmedPrompt,
                currentRoutine: routine.routinePayload,
                conversation: conversation.aiPayload,
                preferences: preferences,
                memory: UserMemoryStore.current()
            )
        )

        let revisedRoutine = decoded.routine.flatMap {
            try? makeDraft(from: $0, sourcePrompt: routine.sourcePrompt, model: decoded.model)
        }

        return AIWorkoutRevisionResult(
            action: decoded.action,
            routine: revisedRoutine ?? routine,
            assistantReply: decoded.reply?.trimmingCharacters(in: .whitespacesAndNewlines),
            changeSummary: decoded.changeSummary?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    func makeDraftForSupplementaryBlock(
        from routine: AIWorkoutRoutinePayload,
        sourcePrompt: String,
        model: String?
    ) throws -> AIGeneratedRoutineDraft {
        try makeDraft(from: routine, sourcePrompt: sourcePrompt, model: model)
    }

    private func validatedPrompt(_ prompt: String) throws -> String {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedPrompt.count >= 8 else {
            throw AIWorkoutGenerationError.invalidPrompt
        }
        return trimmedPrompt
    }

    private func sendGeneratorRequest<T: Encodable>(
        path: String,
        body: T
    ) async throws -> AIWorkoutGeneratorResponseEnvelope {
        let (data, response): (Data, URLResponse)

        do {
            let result = try await sendAIBackendRequest(
                path: path,
                timeout: 60,
                body: try JSONEncoder().encode(body)
            )
            (data, response) = (result.data, result.response)
        } catch {
            throw AIWorkoutGenerationError.requestFailed(
                "I could not reach Lokt’s AI service. \(AIBackendConfiguration.connectionHelp)"
            )
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIWorkoutGenerationError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let decodedError = try? JSONDecoder().decode(AIWorkoutGeneratorErrorEnvelope.self, from: data) {
                throw AIWorkoutGenerationError.requestFailed(decodedError.error)
            }

            throw AIWorkoutGenerationError.requestFailed(
                "The AI backend returned an error (\(httpResponse.statusCode))."
            )
        }

        guard let decoded = try? JSONDecoder().decode(AIWorkoutGeneratorResponseEnvelope.self, from: data) else {
            throw AIWorkoutGenerationError.invalidResponse
        }

        return decoded
    }

    private func sendRevisionRequest<T: Encodable>(
        path: String,
        body: T
    ) async throws -> AIWorkoutRevisionResponseEnvelope {
        let (data, response): (Data, URLResponse)

        do {
            let result = try await sendAIBackendRequest(
                path: path,
                timeout: 60,
                body: try JSONEncoder().encode(body)
            )
            (data, response) = (result.data, result.response)
        } catch {
            throw AIWorkoutGenerationError.requestFailed(
                "I could not reach Lokt’s AI service. \(AIBackendConfiguration.connectionHelp)"
            )
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIWorkoutGenerationError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let decodedError = try? JSONDecoder().decode(AIWorkoutGeneratorErrorEnvelope.self, from: data) {
                throw AIWorkoutGenerationError.requestFailed(decodedError.error)
            }

            throw AIWorkoutGenerationError.requestFailed(
                "The AI backend returned an error (\(httpResponse.statusCode))."
            )
        }

        guard let decoded = try? JSONDecoder().decode(AIWorkoutRevisionResponseEnvelope.self, from: data) else {
            throw AIWorkoutGenerationError.invalidResponse
        }

        return decoded
    }

    private func makeDraft(
        from routine: AIWorkoutRoutinePayload,
        sourcePrompt: String,
        model: String?
    ) throws -> AIGeneratedRoutineDraft {
        let exercises = routine.exercises.compactMap { exercise -> AIGeneratedExercise? in
            let name = sanitizedExerciseName(exercise.name)
            let reps = exercise.reps.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !reps.isEmpty else { return nil }

            let notes = exercise.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            let reasoning = exercise.reasoning?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let tip = exercise.tip?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            // Seed the editable count at the app default; the AI's honest
            // number rides along so the review card can offer it as "Rec N".
            return AIGeneratedExercise(
                name: name,
                sets: AIGeneratedExercise.defaultReviewSetCount,
                reps: reps,
                notes: notes.isEmpty ? nil : notes,
                reasoning: reasoning.isEmpty ? nil : reasoning,
                tip: tip.isEmpty ? nil : tip,
                recommendedSets: max(1, exercise.sets),
                catalogMatch: exercise.catalogMatch
            )
        }

        guard !exercises.isEmpty else {
            throw AIWorkoutGenerationError.emptyRoutine
        }

        let title = routine.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = routine.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let rationale = routine.rationale.trimmingCharacters(in: .whitespacesAndNewlines)

        return AIGeneratedRoutineDraft(
            title: title.isEmpty ? "AI Workout" : title,
            summary: summary,
            rationale: rationale,
            routineNotes: routine.routineNotes
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty },
            exercises: exercises,
            sourcePrompt: sourcePrompt,
            model: model
        )
    }

    private func sanitizedExerciseName(_ rawName: String) -> String {
        var name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)

        let patterns = [
            #"^\d+[\.\)]\s*"#,
            #"(?i)\s+\d+\s*sets?\s*x\s*[\d\-\–\s,to]+\s*reps?$"#,
            #"(?i)\s+\d+\s*sets?$"#,
            #"(?i)\s*x\s*[\d\-\–\s,to]+\s*reps?$"#
        ]

        for pattern in patterns {
            name = name.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return name
    }
}

/// Fetches a routine-level plain-language explanation from the backend's
/// `/api/ai/workout-generator/explain` endpoint.
struct AIRoutineExplainService {
    func plainExplanation(for draft: AIGeneratedRoutineDraft) async throws -> String {
        let payload = AIRoutineExplainRequest(
            routine: AIRoutineExplainRoutinePayload(
                title: draft.title,
                summary: draft.summary,
                exercises: draft.exercises.map {
                    AIRoutineExplainExercisePayload(
                        name: $0.name,
                        sets: $0.sets,
                        reps: $0.reps,
                        reasoning: $0.reasoning
                    )
                }
            ),
            preferences: AIUserPreferencesPayload(preferences: AIUserPreferencesStore.load())
        )

        let (data, response): (Data, URLResponse)

        do {
            let result = try await sendAIBackendRequest(
                path: "api/ai/workout-generator/explain",
                timeout: 60,
                body: try JSONEncoder().encode(payload)
            )
            (data, response) = (result.data, result.response)
        } catch {
            throw AIWorkoutGenerationError.requestFailed(
                "I could not reach Lokt’s AI service. \(AIBackendConfiguration.connectionHelp)"
            )
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIWorkoutGenerationError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let decodedError = try? JSONDecoder().decode(AIWorkoutGeneratorErrorEnvelope.self, from: data) {
                throw AIWorkoutGenerationError.requestFailed(decodedError.error)
            }

            throw AIWorkoutGenerationError.requestFailed(
                "The AI backend returned an error (\(httpResponse.statusCode))."
            )
        }

        guard let decoded = try? JSONDecoder().decode(AIRoutineExplainResponseEnvelope.self, from: data) else {
            throw AIWorkoutGenerationError.invalidResponse
        }

        let explanation = decoded.explanation.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !explanation.isEmpty else {
            throw AIWorkoutGenerationError.invalidResponse
        }

        return explanation
    }
}

private struct AIRoutineExplainRequest: Codable {
    var routine: AIRoutineExplainRoutinePayload
    var preferences: AIUserPreferencesPayload
}

private struct AIRoutineExplainRoutinePayload: Codable {
    var title: String
    var summary: String
    var exercises: [AIRoutineExplainExercisePayload]
}

private struct AIRoutineExplainExercisePayload: Codable {
    var name: String
    var sets: Int
    var reps: String
    var reasoning: String?
}

private struct AIRoutineExplainResponseEnvelope: Codable {
    var explanation: String
}

enum AIWorkoutRoutineSaver {
    /// Build a fresh `Routine` from a reviewed draft, or nil when the draft has
    /// no usable title or exercises (matching the historical silent no-op save).
    static func makeRoutine(from draft: AIGeneratedRoutineDraft) -> Routine? {
        let trimmedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let exercises = draft.exercises
            .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !trimmedTitle.isEmpty, !exercises.isEmpty else { return nil }

        let preferredSetCounts = draft.exercises.reduce(into: [String: Int]()) { counts, exercise in
            let trimmedName = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else { return }
            counts[trimmedName] = max(1, exercise.sets)
        }

        return Routine(
            name: trimmedTitle,
            exercises: exercises,
            preferredSetCounts: preferredSetCounts
        )
    }

    @MainActor
    static func save(_ draft: AIGeneratedRoutineDraft, to store: WorkoutStore) {
        guard let routine = makeRoutine(from: draft) else { return }
        store.addRoutine(routine)
    }
}

private struct AIWorkoutGeneratorRequest: Codable {
    var prompt: String
    var preferences: AIUserPreferencesPayload
    /// Tiered training-history digest; nil when there is no logged history.
    var memory: UserMemory?
}

private struct AIWorkoutGeneratorRevisionRequest: Codable {
    var editPrompt: String
    var currentRoutine: AIWorkoutRoutinePayload
    var conversation: [AIWorkoutConversationMessagePayload]
    var preferences: AIUserPreferencesPayload
    /// Tiered training-history digest; nil when there is no logged history.
    var memory: UserMemory?
}

private struct AIWorkoutGeneratorResponseEnvelope: Codable {
    var routine: AIWorkoutRoutinePayload?
    var requestId: String?
    var model: String?
}

private struct AIWorkoutRevisionResponseEnvelope: Codable {
    var routine: AIWorkoutRoutinePayload?
    var requestId: String?
    var model: String?
    var reply: String?
    var action: AIWorkoutCoachAction
    var changeSummary: String?
}

private struct AIWorkoutGeneratorErrorEnvelope: Codable {
    var error: String
}

struct AIWorkoutRevisionResult {
    var action: AIWorkoutCoachAction
    var routine: AIGeneratedRoutineDraft
    var assistantReply: String?
    var changeSummary: String?
}
