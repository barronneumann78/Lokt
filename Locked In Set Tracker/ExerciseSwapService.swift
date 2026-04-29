import Foundation
import SwiftUI

struct ExerciseSwapSuggestion: Identifiable, Hashable, Codable {
    var exerciseName: String
    var reason: String
    var preserves: [String]
    var caution: String?

    var id: String { exerciseName }
}

struct ExerciseSwapTarget: Identifiable, Hashable {
    var exerciseName: String
    var sourceNote: String?

    var id: String { exerciseName }
}

struct ExerciseSwapCandidatePayload: Codable {
    var name: String
    var muscleGroup: String
    var equipment: String
    var movementPattern: String
    var difficulty: String
    var primaryMuscles: [String]
    var secondaryMuscles: [String]
    var tags: [String]
}

struct ExerciseSwapRequestPayload: Codable {
    var currentExercise: ExerciseSwapCandidatePayload
    var reason: String
    var candidates: [ExerciseSwapCandidatePayload]
}

private struct ExerciseSwapResponseEnvelope: Codable {
    var suggestions: [ExerciseSwapSuggestion]
    var requestId: String?
    var model: String?
}

private struct ExerciseSwapErrorEnvelope: Codable {
    var error: String
}

enum ExerciseSwapError: LocalizedError {
    case exerciseNotFound
    case invalidReason
    case invalidBackendURL
    case invalidResponse
    case noSuggestions
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .exerciseNotFound:
            return "That exercise could not be found in the library."
        case .invalidReason:
            return "Add a little more detail so Lokt knows what kind of swap you want."
        case .invalidBackendURL:
            return "The AI backend URL is invalid. Update it in Settings before using smart swaps."
        case .invalidResponse:
            return "The backend responded, but the swap suggestions were not usable."
        case .noSuggestions:
            return "Lokt could not find a strong replacement right now."
        case .requestFailed(let message):
            return message
        }
    }
}

struct ExerciseSwapSuggestionService {
    func suggestSwaps(
        currentExerciseName: String,
        reason: String,
        exercises: [Exercise]
    ) async throws -> [ExerciseSwapSuggestion] {
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedReason.count >= 4 else {
            throw ExerciseSwapError.invalidReason
        }

        guard let currentExercise = exercises.exercise(named: currentExerciseName) else {
            throw ExerciseSwapError.exerciseNotFound
        }

        let candidates = localCandidates(for: currentExercise, reason: trimmedReason, exercises: exercises)
        guard !candidates.isEmpty else {
            throw ExerciseSwapError.noSuggestions
        }

        guard !AIBackendConfiguration.candidateBaseURLs.isEmpty else {
            throw ExerciseSwapError.invalidBackendURL
        }

        let payload = ExerciseSwapRequestPayload(
            currentExercise: candidatePayload(for: currentExercise),
            reason: trimmedReason,
            candidates: candidates.map(candidatePayload(for:))
        )

        let (data, response): (Data, URLResponse)

        do {
            let result = try await sendAIBackendRequest(
                path: "api/ai/exercise-swap/suggest",
                timeout: 60,
                body: try JSONEncoder().encode(payload)
            )
            (data, response) = (result.data, result.response)
        } catch {
            throw ExerciseSwapError.requestFailed(
                "I could not reach the AI backend. Make sure your server is running and the backend URL in Settings is correct. \(AIBackendConfiguration.localTestingHint)"
            )
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ExerciseSwapError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let decodedError = try? JSONDecoder().decode(ExerciseSwapErrorEnvelope.self, from: data) {
                throw ExerciseSwapError.requestFailed(decodedError.error)
            }

            throw ExerciseSwapError.requestFailed("The AI backend returned an error (\(httpResponse.statusCode)).")
        }

        guard let decoded = try? JSONDecoder().decode(ExerciseSwapResponseEnvelope.self, from: data) else {
            throw ExerciseSwapError.invalidResponse
        }

        let validNames = Set(candidates.map { $0.name.lowercased() })
        let cleaned = decoded.suggestions.filter { validNames.contains($0.exerciseName.lowercased()) }

        guard !cleaned.isEmpty else {
            throw ExerciseSwapError.noSuggestions
        }

        return Array(cleaned.prefix(4))
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

    private func localCandidates(
        for currentExercise: Exercise,
        reason: String,
        exercises: [Exercise]
    ) -> [Exercise] {
        let loweredReason = reason.lowercased()

        return exercises
            .filter { $0.name.caseInsensitiveCompare(currentExercise.name) != .orderedSame }
            .map { exercise in
                (exercise: exercise, score: score(exercise, against: currentExercise, reason: loweredReason))
            }
            .filter { $0.score > 0 }
            .sorted {
                if $0.score == $1.score {
                    return $0.exercise.name.localizedCaseInsensitiveCompare($1.exercise.name) == .orderedAscending
                }
                return $0.score > $1.score
            }
            .prefix(12)
            .map(\.exercise)
    }

    private func score(_ candidate: Exercise, against current: Exercise, reason: String) -> Int {
        var score = 0

        if candidate.movementPattern == current.movementPattern {
            score += 40
        }

        if candidate.muscleGroup == current.muscleGroup {
            score += 24
        }

        let sharedPrimary = Set(candidate.metadata.primaryMuscles.map { $0.lowercased() })
            .intersection(Set(current.metadata.primaryMuscles.map { $0.lowercased() }))
        score += sharedPrimary.count * 12

        let sharedTags = Set(candidate.metadata.tags.map { $0.lowercased() })
            .intersection(Set(current.metadata.tags.map { $0.lowercased() }))
        score += min(sharedTags.count, 4) * 4

        if candidate.equipment == current.equipment {
            score += 10
        }

        if reason.contains("dumbbell"), candidate.equipment == .dumbbell {
            score += 26
        }

        if reason.contains("home"), [.dumbbell, .band, .bodyweight, .kettlebell].contains(candidate.equipment) {
            score += 24
        }

        if reason.contains("machine"), candidate.equipment != .machine {
            score += 18
        }

        if reason.contains("shoulder") {
            if candidate.metadata.tags.contains(where: { $0.localizedCaseInsensitiveContains("shoulder-friendly") }) {
                score += 26
            }
            if candidate.equipment == .machine || candidate.equipment == .cable {
                score += 10
            }
            if candidate.movementPattern == .isolation {
                score += 4
            }
        }

        if reason.contains("easier") || reason.contains("beginner") {
            switch candidate.difficulty {
            case .beginner:
                score += 24
            case .intermediate:
                score += 10
            case .advanced:
                score -= 6
            }

            if candidate.equipment == .machine {
                score += 8
            }
        }

        if reason.contains("barbell"), candidate.equipment != .barbell {
            score += 10
        }

        return score
    }
}

struct ExerciseSwapSheet: View {
    let target: ExerciseSwapTarget
    let exercises: [Exercise]
    var onApply: (ExerciseSwapSuggestion) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var reason = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var suggestions: [ExerciseSwapSuggestion] = []

    private let service = ExerciseSwapSuggestionService()
    private let quickReasons = [
        "This machine is taken",
        "Give me a dumbbell version",
        "Easier on shoulders",
        "Home gym alternative"
    ]

    var body: some View {
        NavigationView {
            ZStack {
                AppBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        headerCard
                        inputCard

                        if let errorMessage {
                            swapMessageCard(title: "Couldn’t Find a Swap Yet", text: errorMessage, tint: AppTheme.secondary)
                        }

                        if !suggestions.isEmpty {
                            suggestionsCard
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle("Smart Swap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(target.exerciseName)
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)

            if let sourceNote = target.sourceNote, !sourceNote.isEmpty {
                Text(sourceNote)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
            } else {
                Text("Tell Lokt why you want a change and it will suggest replacements that keep the workout’s purpose intact.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(20)
        .glassCard()
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Why do you want to swap it?")
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], alignment: .leading, spacing: 10) {
                ForEach(quickReasons, id: \.self) { quickReason in
                    Button(quickReason) {
                        reason = quickReason
                        requestSuggestions()
                    }
                    .buttonStyle(TertiaryButtonStyle())
                }
            }

            TextField("Example: machine taken, dumbbell version, easier on shoulders", text: $reason, axis: .vertical)
                .textFieldStyle(TrackerTextFieldStyle())
                .lineLimit(2...4)

            Button(isLoading ? "Finding Swaps..." : "Find Swaps") {
                requestSuggestions()
            }
            .buttonStyle(PrimaryButtonStyle(fill: AppTheme.primary))
            .disabled(isLoading || reason.trimmingCharacters(in: .whitespacesAndNewlines).count < 4)
            .opacity(isLoading || reason.trimmingCharacters(in: .whitespacesAndNewlines).count < 4 ? 0.6 : 1)
        }
        .padding(20)
        .glassCard()
    }

    private var suggestionsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Suggested Replacements")
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            ForEach(suggestions) { suggestion in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(suggestion.exerciseName)
                                .font(.headline.weight(.bold))
                                .foregroundStyle(AppTheme.textPrimary)

                            Text(suggestion.reason)
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()
                    }

                    if !suggestion.preserves.isEmpty {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], alignment: .leading, spacing: 8) {
                            ForEach(suggestion.preserves, id: \.self) { item in
                                TagChip(title: item)
                            }
                        }
                    }

                    if let caution = suggestion.caution, !caution.isEmpty {
                        Text(caution)
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondary)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppTheme.secondary.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    Button("Apply Swap") {
                        onApply(suggestion)
                        dismiss()
                    }
                    .buttonStyle(PrimaryButtonStyle(fill: AppTheme.success))
                }
                .padding(16)
                .surfaceCard()
            }
        }
        .padding(20)
        .glassCard()
    }

    private func requestSuggestions() {
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedReason.count >= 4 else { return }

        errorMessage = nil
        isLoading = true

        Task { @MainActor in
            defer { isLoading = false }

            do {
                suggestions = try await service.suggestSwaps(
                    currentExerciseName: target.exerciseName,
                    reason: trimmedReason,
                    exercises: exercises
                )
            } catch {
                suggestions = []
                errorMessage = error.localizedDescription
            }
        }
    }

    private func swapMessageCard(title: String, text: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(20)
        .background(tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        }
    }
}
