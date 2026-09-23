import Foundation

enum WorkoutNudgeError: LocalizedError {
    case invalidBackendURL
    case invalidResponse
    /// The backend refused to nudge (pain check-in — spine §6 safety branch).
    /// The app never asks in that case; this exists as defense in depth.
    case safetyRefused
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidBackendURL:
            return "Lokt’s AI service is unavailable right now. Check your connection and try again."
        case .invalidResponse:
            return "The backend responded, but the adjustment format was not usable."
        case .safetyRefused:
            return "This check-in needs a real conversation, not an auto-adjustment."
        case .requestFailed(let message):
            return message
        }
    }
}

/// Client for `/api/ai/workout-nudge`: sends the routine's current targets,
/// the fresh check-in, and the user-memory digest; gets back constrained
/// next-session target deltas (same exercises, same order — never a replan).
struct WorkoutNudgeService {

    func fetchNudge(for routine: Routine, checkIn: SessionCheckIn) async throws -> WorkoutNudge {
        let progression = routine.progression ?? [:]
        let importedReps = Self.importedRepTargets(for: routine)

        let exercises = routine.exercises.map { name in
            WorkoutNudgeRequestExercise(
                name: name,
                sets: routine.preferredSetCount(for: name),
                repText: importedReps[name.lowercased()],
                lastWeightText: progression[name]?.lastWeight,
                lastRepText: progression[name]?.lastReps
            )
        }

        let body = WorkoutNudgeRequest(
            routine: WorkoutNudgeRequestRoutine(name: routine.name, exercises: exercises),
            checkIn: WorkoutNudgeRequestCheckIn(
                overall: checkIn.overall.nudgeWireValue,
                hadPain: checkIn.hadPain,
                painNote: checkIn.painNote,
                painExercise: checkIn.painExercise
            ),
            preferences: AIUserPreferencesPayload(preferences: AIUserPreferencesStore.load()),
            memory: UserMemoryStore.current()
        )

        let (data, response): (Data, URLResponse)

        do {
            let result = try await sendAIBackendRequest(
                path: "api/ai/workout-nudge",
                timeout: 60,
                body: try JSONEncoder().encode(body)
            )
            (data, response) = (result.data, result.response)
        } catch {
            throw WorkoutNudgeError.requestFailed(
                "I could not reach Lokt’s AI service. \(AIBackendConfiguration.connectionHelp)"
            )
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WorkoutNudgeError.invalidResponse
        }

        if httpResponse.statusCode == 422 {
            throw WorkoutNudgeError.safetyRefused
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let decodedError = try? JSONDecoder().decode(WorkoutNudgeErrorEnvelope.self, from: data) {
                throw WorkoutNudgeError.requestFailed(decodedError.error)
            }

            throw WorkoutNudgeError.requestFailed(
                "The AI backend returned an error (\(httpResponse.statusCode))."
            )
        }

        guard let decoded = try? JSONDecoder().decode(WorkoutNudgeResponseEnvelope.self, from: data),
              let nudge = decoded.nudge else {
            throw WorkoutNudgeError.invalidResponse
        }

        return nudge
    }

    /// Rep targets the routine already knows, from its import context plans —
    /// the same source the coach's saved-routine snapshot uses.
    static func importedRepTargets(for routine: Routine) -> [String: String] {
        guard let plans = routine.importContext?.exercisePlans else { return [:] }

        return plans.reduce(into: [:]) { partial, plan in
            let name = (plan.matchedExerciseName ?? plan.exerciseName)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if let reps = plan.targetReps?.trimmingCharacters(in: .whitespacesAndNewlines),
               !name.isEmpty, !reps.isEmpty, partial[name] == nil {
                partial[name] = reps
            }
        }
    }
}

private struct WorkoutNudgeRequest: Codable {
    var routine: WorkoutNudgeRequestRoutine
    var checkIn: WorkoutNudgeRequestCheckIn
    var preferences: AIUserPreferencesPayload
    /// Tiered training-history digest — the nudge CONSUMES the existing
    /// serialization; the digest shape itself never changes for M4.
    var memory: UserMemory?
}

private struct WorkoutNudgeResponseEnvelope: Codable {
    var nudge: WorkoutNudge?
    var requestId: String?
    var model: String?
}

private struct WorkoutNudgeErrorEnvelope: Codable {
    var error: String
}
