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
            return "The AI backend URL is invalid. Update it in Settings before generating a workout."
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
    static let userDefaultsKey = "aiBackendBaseURL"
    static let defaultBaseURLString = "http://127.0.0.1:8788"
    private static let fallbackLocalBaseURLStrings = [
        "http://127.0.0.1:8787",
        "http://localhost:8788",
        "http://localhost:8787"
    ]

    static var currentBaseURLString: String {
        let storedValue = UserDefaults.standard.string(forKey: userDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let storedValue, !storedValue.isEmpty {
            return storedValue
        }

        return defaultBaseURLString
    }

    static var currentBaseURL: URL? {
        URL(string: currentBaseURLString)
    }

    static var candidateBaseURLs: [URL] {
        let configured = currentBaseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldTryLocalFallbacks = configured.isEmpty || isLocalTestingURLString(configured)
        let candidates = [configured] + (shouldTryLocalFallbacks ? [defaultBaseURLString] + fallbackLocalBaseURLStrings : [])

        var seen = Set<String>()

        return candidates.compactMap { candidate in
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let url = URL(string: trimmed) else { return nil }

            let key = url.absoluteString.lowercased()
            guard seen.insert(key).inserted else { return nil }
            return url
        }
    }

    static var localTestingHint: String {
        "For local simulator testing, make sure the backend is running on 127.0.0.1:8788 or 127.0.0.1:8787."
    }

    static func persistWorkingBaseURL(_ url: URL) {
        UserDefaults.standard.set(url.absoluteString, forKey: userDefaultsKey)
    }

    static func isLocalTestingURL(_ url: URL) -> Bool {
        guard let host = url.host(percentEncoded: false)?.lowercased() else { return false }
        return host == "127.0.0.1" || host == "localhost"
    }

    private static func isLocalTestingURLString(_ value: String) -> Bool {
        guard let url = URL(string: value) else { return false }
        return isLocalTestingURL(url)
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
    let baseURLs = AIBackendConfiguration.candidateBaseURLs
    guard !baseURLs.isEmpty else {
        throw URLError(.badURL)
    }

    var lastError: Error = URLError(.cannotFindHost)

    for baseURL in baseURLs {
        let endpoint = baseURL.appending(path: path)
        var request = URLRequest(url: endpoint)
        request.httpMethod = method
        request.timeoutInterval = timeout

        if !contentType.isEmpty {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }

        request.httpBody = body

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            AIBackendConfiguration.persistWorkingBaseURL(baseURL)
            return AIBackendRequestResult(data: data, response: response, baseURL: baseURL)
        } catch {
            lastError = error

            if AIBackendConfiguration.isLocalTestingURL(baseURL),
               isRetryableAIBackendConnectionError(error) {
                continue
            }

            throw error
        }
    }

    throw lastError
}

func isRetryableAIBackendConnectionError(_ error: Error) -> Bool {
    guard let urlError = error as? URLError else { return false }

    switch urlError.code {
    case .timedOut,
         .cannotFindHost,
         .cannotConnectToHost,
         .dnsLookupFailed,
         .networkConnectionLost,
         .notConnectedToInternet,
         .resourceUnavailable:
        return true
    default:
        return false
    }
}

struct AIWorkoutGeneratorClient {
    func generateRoutine(from prompt: String) async throws -> AIGeneratedRoutineDraft {
        let trimmedPrompt = try validatedPrompt(prompt)
        let preferences = AIUserPreferencesPayload(preferences: AIUserPreferencesStore.load())
        let decoded = try await sendGeneratorRequest(
            path: "api/ai/workout-generator",
            body: AIWorkoutGeneratorRequest(prompt: trimmedPrompt, preferences: preferences)
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
                preferences: preferences
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
        guard !AIBackendConfiguration.candidateBaseURLs.isEmpty else {
            throw AIWorkoutGenerationError.invalidBackendURL
        }

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
                "I could not reach the AI backend. Make sure your server is running and the backend URL in Settings is correct. \(AIBackendConfiguration.localTestingHint)"
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
        guard !AIBackendConfiguration.candidateBaseURLs.isEmpty else {
            throw AIWorkoutGenerationError.invalidBackendURL
        }

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
                "I could not reach the AI backend. Make sure your server is running and the backend URL in Settings is correct. \(AIBackendConfiguration.localTestingHint)"
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

            return AIGeneratedExercise(
                name: name,
                sets: max(1, exercise.sets),
                reps: reps,
                notes: notes.isEmpty ? nil : notes
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

enum AIWorkoutRoutineSaver {
    static func save(_ draft: AIGeneratedRoutineDraft) {
        let trimmedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let exercises = draft.exercises
            .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !trimmedTitle.isEmpty, !exercises.isEmpty else { return }

        let preferredSetCounts = draft.exercises.reduce(into: [String: Int]()) { counts, exercise in
            let trimmedName = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else { return }
            counts[trimmedName] = max(1, exercise.sets)
        }

        var routines = loadRoutines()
        routines.append(
            Routine(
                name: trimmedTitle,
                exercises: exercises,
                preferredSetCounts: preferredSetCounts
            )
        )

        if let encoded = try? JSONEncoder().encode(routines) {
            UserDefaults.standard.set(encoded, forKey: "routines")
        }
    }

    private static func loadRoutines() -> [Routine] {
        guard let data = UserDefaults.standard.data(forKey: "routines"),
              let decoded = try? JSONDecoder().decode([Routine].self, from: data) else {
            return []
        }

        return decoded
    }
}

private struct AIWorkoutGeneratorRequest: Codable {
    var prompt: String
    var preferences: AIUserPreferencesPayload
}

private struct AIWorkoutGeneratorRevisionRequest: Codable {
    var editPrompt: String
    var currentRoutine: AIWorkoutRoutinePayload
    var conversation: [AIWorkoutConversationMessagePayload]
    var preferences: AIUserPreferencesPayload
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
