import Foundation

struct ExerciseCoachSuggestion: Identifiable, Hashable, Codable {
    var exerciseName: String
    var reason: String

    var id: String { exerciseName }
}

struct ExerciseCoachReply: Hashable, Codable {
    var question: String
    var answer: String
    var suggestions: [ExerciseCoachSuggestion]
}

private struct ExerciseCoachRequestPayload: Codable {
    var currentExercise: ExerciseSwapCandidatePayload
    var question: String
    var candidates: [ExerciseSwapCandidatePayload]
}

private struct ExerciseCoachResponseEnvelope: Codable {
    var answer: String
    var suggestions: [ExerciseCoachSuggestion]
    var requestId: String?
    var model: String?
}

private struct ExerciseCoachErrorEnvelope: Codable {
    var error: String
}

enum ExerciseCoachError: LocalizedError {
    case invalidQuestion
    case invalidBackendURL
    case invalidResponse
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidQuestion:
            return "Ask a slightly more specific question so Lokt knows what to help with."
        case .invalidBackendURL:
            return "The AI backend URL is invalid. Update it in Settings before using coach answers."
        case .invalidResponse:
            return "The coach answer came back in a format that Lokt could not use."
        case .requestFailed(let message):
            return message
        }
    }
}

struct ExerciseCoachService {
    private let swapService = ExerciseSwapSuggestionService()

    func reply(
        for question: String,
        exercise: Exercise,
        exercises: [Exercise]
    ) async throws -> ExerciseCoachReply {
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuestion.count >= 4 else {
            throw ExerciseCoachError.invalidQuestion
        }

        let loweredQuestion = trimmedQuestion.lowercased()

        if isMuscleQuestion(loweredQuestion) {
            return localMuscleReply(for: trimmedQuestion, exercise: exercise)
        }

        if isWhyQuestion(loweredQuestion) {
            return localWhyReply(for: trimmedQuestion, exercise: exercise)
        }

        if let swapReason = mappedSwapReason(for: loweredQuestion) {
            let suggestions = try await swapService.suggestSwaps(
                currentExerciseName: exercise.name,
                reason: swapReason,
                exercises: exercises
            )
            return swapReply(for: trimmedQuestion, originalExercise: exercise, suggestions: suggestions)
        }

        return try await requestCoachReply(
            question: trimmedQuestion,
            exercise: exercise,
            exercises: exercises
        )
    }

    private func localMuscleReply(for question: String, exercise: Exercise) -> ExerciseCoachReply {
        let primary = exercise.metadata.primaryMuscles.prefix(2)
        let secondary = exercise.metadata.secondaryMuscles.prefix(2)

        var parts: [String] = []

        if !primary.isEmpty {
            parts.append("This mainly trains \(naturalList(Array(primary))).")
        }

        if !secondary.isEmpty {
            parts.append("\(naturalList(Array(secondary)).capitalizedFirstLetter) help as secondary movers.")
        }

        parts.append("It’s a \(exercise.movementPattern.rawValue.lowercased()) pattern using \(exercise.equipment.rawValue.lowercased()) equipment.")

        return ExerciseCoachReply(
            question: question,
            answer: parts.joined(separator: " "),
            suggestions: []
        )
    }

    private func localWhyReply(for question: String, exercise: Exercise) -> ExerciseCoachReply {
        let primary = exercise.metadata.primaryMuscles.first ?? exercise.muscleGroup.rawValue.lowercased()
        let goals = Array(exercise.metadata.trainingGoal.prefix(2))

        var parts = [
            "This usually earns a spot because it trains \(primary) through a \(exercise.movementPattern.rawValue.lowercased()) pattern."
        ]

        if !goals.isEmpty {
            parts.append("It fits best when you want \(naturalList(goals)) without changing the whole session’s focus.")
        } else {
            parts.append("It gives you a straightforward way to keep the session focused on the target area.")
        }

        return ExerciseCoachReply(
            question: question,
            answer: parts.joined(separator: " "),
            suggestions: []
        )
    }

    private func swapReply(
        for question: String,
        originalExercise: Exercise,
        suggestions: [ExerciseSwapSuggestion]
    ) -> ExerciseCoachReply {
        let mappedSuggestions = suggestions.map {
            ExerciseCoachSuggestion(exerciseName: $0.exerciseName, reason: $0.reason)
        }

        let answer: String
        if let first = suggestions.first {
            answer = "\(first.exerciseName) is the cleanest swap. \(first.reason)"
        } else {
            answer = "Lokt found a few swaps that keep the session pointed at the same job."
        }

        return ExerciseCoachReply(
            question: question,
            answer: answer,
            suggestions: mappedSuggestions
        )
    }

    private func requestCoachReply(
        question: String,
        exercise: Exercise,
        exercises: [Exercise]
    ) async throws -> ExerciseCoachReply {
        guard !AIBackendConfiguration.candidateBaseURLs.isEmpty else {
            throw ExerciseCoachError.invalidBackendURL
        }

        let payload = ExerciseCoachRequestPayload(
            currentExercise: candidatePayload(for: exercise),
            question: question,
            candidates: coachCandidates(for: exercise, question: question, exercises: exercises).map(candidatePayload(for:))
        )

        let (data, response): (Data, URLResponse)

        do {
            let result = try await sendAIBackendRequest(
                path: "api/ai/exercise-coach/answer",
                timeout: 60,
                body: try JSONEncoder().encode(payload)
            )
            (data, response) = (result.data, result.response)
        } catch {
            throw ExerciseCoachError.requestFailed(
                "I could not reach the AI backend. Make sure your server is running and the backend URL in Settings is correct. \(AIBackendConfiguration.localTestingHint)"
            )
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ExerciseCoachError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let decodedError = try? JSONDecoder().decode(ExerciseCoachErrorEnvelope.self, from: data) {
                throw ExerciseCoachError.requestFailed(decodedError.error)
            }

            throw ExerciseCoachError.requestFailed("The AI backend returned an error (\(httpResponse.statusCode)).")
        }

        guard let decoded = try? JSONDecoder().decode(ExerciseCoachResponseEnvelope.self, from: data) else {
            throw ExerciseCoachError.invalidResponse
        }

        let validNames = Set(payload.candidates.map { $0.name.lowercased() })
        let suggestions = decoded.suggestions.filter { validNames.contains($0.exerciseName.lowercased()) }
        let answer = decoded.answer.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !answer.isEmpty else {
            throw ExerciseCoachError.invalidResponse
        }

        return ExerciseCoachReply(
            question: question,
            answer: answer,
            suggestions: Array(suggestions.prefix(3))
        )
    }

    private func candidatePayload(for exercise: Exercise) -> ExerciseSwapCandidatePayload {
        ExerciseSwapCandidatePayload(
            name: exercise.name,
            muscleGroup: exercise.muscleGroup.rawValue,
            equipment: exercise.equipment.rawValue,
            movementPattern: exercise.movementPattern.rawValue,
            difficulty: exercise.difficulty.rawValue,
            primaryMuscles: exercise.metadata.primaryMuscles,
            secondaryMuscles: exercise.metadata.secondaryMuscles,
            tags: exercise.metadata.tags
        )
    }

    private func coachCandidates(
        for currentExercise: Exercise,
        question: String,
        exercises: [Exercise]
    ) -> [Exercise] {
        let loweredQuestion = question.lowercased()

        return exercises
            .filter { $0.name.caseInsensitiveCompare(currentExercise.name) != .orderedSame }
            .map { exercise in
                (exercise: exercise, score: candidateScore(exercise, against: currentExercise, question: loweredQuestion))
            }
            .filter { $0.score > 0 }
            .sorted {
                if $0.score == $1.score {
                    return $0.exercise.name.localizedCaseInsensitiveCompare($1.exercise.name) == .orderedAscending
                }
                return $0.score > $1.score
            }
            .prefix(10)
            .map(\.exercise)
    }

    private func candidateScore(_ candidate: Exercise, against current: Exercise, question: String) -> Int {
        var score = 0

        if candidate.movementPattern == current.movementPattern {
            score += 36
        }

        if candidate.muscleGroup == current.muscleGroup {
            score += 24
        }

        let sharedPrimary = Set(candidate.metadata.primaryMuscles.map { $0.lowercased() })
            .intersection(Set(current.metadata.primaryMuscles.map { $0.lowercased() }))
        score += sharedPrimary.count * 10

        let sharedTags = Set(candidate.metadata.tags.map { $0.lowercased() })
            .intersection(Set(current.metadata.tags.map { $0.lowercased() }))
        score += min(sharedTags.count, 4) * 4

        if question.contains("dumbbell"), candidate.equipment == .dumbbell {
            score += 28
        }

        if question.contains("shoulder") || question.contains("hurt") || question.contains("pain") {
            if candidate.metadata.tags.contains(where: { $0.localizedCaseInsensitiveContains("shoulder-friendly") }) {
                score += 28
            }
            if candidate.equipment == .machine || candidate.equipment == .cable {
                score += 10
            }
        }

        if question.contains("easier") || question.contains("beginner") {
            switch candidate.difficulty {
            case .beginner:
                score += 24
            case .intermediate:
                score += 10
            case .advanced:
                score -= 8
            }
        }

        if question.contains("home") {
            if [.dumbbell, .band, .bodyweight, .kettlebell].contains(candidate.equipment) {
                score += 24
            } else {
                score -= 4
            }
        }

        if candidate.equipment == current.equipment {
            score += 8
        }

        return score
    }

    private func isMuscleQuestion(_ question: String) -> Bool {
        question.contains("what muscles") ||
        question.contains("what does this hit") ||
        question.contains("what does this work") ||
        question.contains("what does it hit")
    }

    private func isWhyQuestion(_ question: String) -> Bool {
        question.contains("why is this here") ||
        question == "why this" ||
        question.contains("why do this") ||
        question.contains("why this exercise")
    }

    private func mappedSwapReason(for question: String) -> String? {
        if question.contains("easier") || question.contains("beginner") {
            return "Give me an easier version"
        }

        if question.contains("shoulder") || question.contains("hurt") || question.contains("pain") {
            return "Easier on shoulders"
        }

        if question.contains("substitute") || question.contains("swap") || question.contains("instead") {
            return "What can I substitute?"
        }

        if question.contains("dumbbell") {
            return "Give me a dumbbell version"
        }

        if question.contains("home") {
            return "Home gym alternative"
        }

        return nil
    }

    private func naturalList(_ values: [String]) -> String {
        switch values.count {
        case 0:
            return ""
        case 1:
            return values[0]
        case 2:
            return "\(values[0]) and \(values[1])"
        default:
            return values.dropLast().joined(separator: ", ") + ", and " + (values.last ?? "")
        }
    }
}

private extension String {
    var capitalizedFirstLetter: String {
        guard let first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}
