import Foundation

struct ExerciseInsightRecord: Codable {
    var cues: [String]?
    var simpleExplanation: String?
}

/// Small per-exercise cache so AI cues and plain-language explanations are
/// fetched once and reused on later visits. Keyed by lowercased exercise name.
enum ExerciseInsightCache {
    private static let storageKey = "exerciseInsightsV1"

    static func record(for exerciseName: String) -> ExerciseInsightRecord? {
        loadAll()[key(for: exerciseName)]
    }

    static func saveCues(_ cues: [String], for exerciseName: String) {
        var records = loadAll()
        var record = records[key(for: exerciseName)] ?? ExerciseInsightRecord()
        record.cues = cues
        records[key(for: exerciseName)] = record
        saveAll(records)
    }

    static func saveSimpleExplanation(_ explanation: String, for exerciseName: String) {
        var records = loadAll()
        var record = records[key(for: exerciseName)] ?? ExerciseInsightRecord()
        record.simpleExplanation = explanation
        records[key(for: exerciseName)] = record
        saveAll(records)
    }

    private static func key(for exerciseName: String) -> String {
        exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func loadAll() -> [String: ExerciseInsightRecord] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: ExerciseInsightRecord].self, from: data) else {
            return [:]
        }

        return decoded
    }

    private static func saveAll(_ records: [String: ExerciseInsightRecord]) {
        guard let encoded = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(encoded, forKey: storageKey)
    }
}

private struct ExerciseInsightRequestPayload: Codable {
    var exercise: ExerciseSwapCandidatePayload
    var mode: String
}

private struct ExerciseFormCuesResponseEnvelope: Codable {
    var cues: [String]
}

private struct ExerciseSimpleExplanationResponseEnvelope: Codable {
    var explanation: String
}

private struct ExerciseInsightErrorEnvelope: Codable {
    var error: String
}

/// Fetches brief form cues and plain-language explanations from the backend's
/// `/api/ai/exercise-coach/explain` endpoint.
struct ExerciseInsightService {
    func formCues(for exercise: Exercise) async throws -> [String] {
        let data = try await requestInsight(for: exercise, mode: "cues")

        guard let decoded = try? JSONDecoder().decode(ExerciseFormCuesResponseEnvelope.self, from: data) else {
            throw ExerciseCoachError.invalidResponse
        }

        let cues = decoded.cues
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !cues.isEmpty else {
            throw ExerciseCoachError.invalidResponse
        }

        return Array(cues.prefix(3))
    }

    func simpleExplanation(for exercise: Exercise) async throws -> String {
        let data = try await requestInsight(for: exercise, mode: "simple")

        guard let decoded = try? JSONDecoder().decode(ExerciseSimpleExplanationResponseEnvelope.self, from: data) else {
            throw ExerciseCoachError.invalidResponse
        }

        let explanation = decoded.explanation.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !explanation.isEmpty else {
            throw ExerciseCoachError.invalidResponse
        }

        return explanation
    }

    private func requestInsight(for exercise: Exercise, mode: String) async throws -> Data {
        let payload = ExerciseInsightRequestPayload(
            exercise: ExerciseSwapCandidatePayload(
                name: exercise.name,
                muscleGroup: exercise.muscleGroup.rawValue,
                equipment: exercise.equipment.rawValue,
                movementPattern: exercise.movementPattern.rawValue,
                difficulty: exercise.difficulty.rawValue,
                primaryMuscles: exercise.metadata.primaryMuscles,
                secondaryMuscles: exercise.metadata.secondaryMuscles,
                tags: exercise.metadata.tags
            ),
            mode: mode
        )

        let (data, response): (Data, URLResponse)

        do {
            let result = try await sendAIBackendRequest(
                path: "api/ai/exercise-coach/explain",
                timeout: 60,
                body: try JSONEncoder().encode(payload)
            )
            (data, response) = (result.data, result.response)
        } catch {
            throw ExerciseCoachError.requestFailed(
                "I could not reach Lokt’s AI service. \(AIBackendConfiguration.connectionHelp)"
            )
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ExerciseCoachError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let decodedError = try? JSONDecoder().decode(ExerciseInsightErrorEnvelope.self, from: data) {
                throw ExerciseCoachError.requestFailed(decodedError.error)
            }

            throw ExerciseCoachError.requestFailed("The AI backend returned an error (\(httpResponse.statusCode)).")
        }

        return data
    }
}
