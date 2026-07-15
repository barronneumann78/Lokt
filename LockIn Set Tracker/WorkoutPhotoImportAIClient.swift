import Foundation
import UIKit

struct PhotoWorkoutAIExtractionResult: Codable, Hashable {
    var rawText: String
    var days: [PhotoWorkoutAIExtractionDay]
}

struct PhotoWorkoutAIExtractionDay: Codable, Hashable {
    var name: String
    var sourceHeading: String?
    var notes: [String]
    var exercises: [PhotoWorkoutAIExtractionExercise]
}

struct PhotoWorkoutAIExtractionExercise: Codable, Hashable {
    var sourceText: String
    var exerciseText: String
    var setCount: Int?
    var repText: String?
    var notes: [String]
    var restSeconds: Int?
    var intensityNotes: [String]
}

struct WorkoutPhotoAIClient {
    func extractWorkout(from image: UIImage) async throws -> PhotoWorkoutAIExtractionResult {
        guard !AIBackendConfiguration.candidateBaseURLs.isEmpty else {
            throw WorkoutPhotoImportError.invalidBackendURL
        }

        let payload = try image.preparedPhotoImportPayload()
        let (data, response): (Data, URLResponse)

        do {
            let preferences = AIUserPreferencesPayload(preferences: AIUserPreferencesStore.load())
            let result = try await sendAIBackendRequest(
                path: "api/ai/photo-to-workout/extract",
                timeout: 90,
                body: try JSONEncoder().encode(
                    WorkoutPhotoAIRequest(
                        imageBase64: payload.data.base64EncodedString(),
                        fileName: payload.fileName,
                        mimeType: payload.mimeType,
                        preferences: preferences
                    )
                )
            )
            (data, response) = (result.data, result.response)
        } catch {
            throw WorkoutPhotoImportError.requestFailed(
                "I could not reach the photo import backend. Make sure your server is running and the backend URL in Settings is correct. \(AIBackendConfiguration.localTestingHint)"
            )
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WorkoutPhotoImportError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let decodedError = try? JSONDecoder().decode(WorkoutPhotoAIErrorEnvelope.self, from: data) {
                throw WorkoutPhotoImportError.requestFailed(decodedError.error)
            }

            throw WorkoutPhotoImportError.requestFailed(
                "The photo import backend returned an error (\(httpResponse.statusCode))."
            )
        }

        guard let decoded = try? JSONDecoder().decode(WorkoutPhotoAIResponseEnvelope.self, from: data) else {
            throw WorkoutPhotoImportError.invalidResponse
        }

        let extraction = decoded.extraction.sanitized()
        let hasExercises = extraction.days.contains { !$0.exercises.isEmpty }
        let hasText = !extraction.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        guard hasExercises || hasText else {
            throw WorkoutPhotoImportError.noTextDetected
        }

        return extraction
    }
}

private struct WorkoutPhotoAIRequest: Codable {
    var imageBase64: String
    var fileName: String
    var mimeType: String
    var preferences: AIUserPreferencesPayload
}

private struct WorkoutPhotoAIResponseEnvelope: Codable {
    var extraction: PhotoWorkoutAIExtractionResult
    var requestId: String?
    var model: String?
}

private struct WorkoutPhotoAIErrorEnvelope: Codable {
    var error: String
}

private extension PhotoWorkoutAIExtractionResult {
    func sanitized() -> PhotoWorkoutAIExtractionResult {
        let sanitizedDays = days
            .map { $0.sanitized() }
            .filter { !$0.exercises.isEmpty || !$0.notes.isEmpty || !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        let cleanedRawText = rawText.condensed()
        if !cleanedRawText.isEmpty {
            return PhotoWorkoutAIExtractionResult(rawText: cleanedRawText, days: sanitizedDays)
        }

        let derivedRawText = sanitizedDays
            .flatMap { day -> [String] in
                let heading = day.sourceHeading?.condensed()
                let exerciseLines = day.exercises.map(\.sourceText)
                return [heading].compactMap { $0 } + day.notes + exerciseLines
            }
            .joined(separator: "\n")
            .condensed()

        return PhotoWorkoutAIExtractionResult(rawText: derivedRawText, days: sanitizedDays)
    }
}

private extension PhotoWorkoutAIExtractionDay {
    func sanitized() -> PhotoWorkoutAIExtractionDay {
        let cleanName = name.condensed()
        let cleanHeading = sourceHeading?.condensed().nilIfEmpty
        let cleanNotes = notes
            .map { $0.condensed() }
            .filter { !$0.isEmpty }
        let cleanExercises = exercises
            .map { $0.sanitized() }
            .filter { !$0.exerciseText.isEmpty || !$0.sourceText.isEmpty }

        return PhotoWorkoutAIExtractionDay(
            name: cleanName,
            sourceHeading: cleanHeading,
            notes: cleanNotes,
            exercises: cleanExercises
        )
    }
}

private extension PhotoWorkoutAIExtractionExercise {
    func sanitized() -> PhotoWorkoutAIExtractionExercise {
        let cleanSourceText = sourceText.condensed()
        let cleanExerciseText = exerciseText.condensed()
        let resolvedSource = cleanSourceText.isEmpty ? cleanExerciseText : cleanSourceText
        let resolvedExercise = cleanExerciseText.isEmpty ? cleanSourceText : cleanExerciseText
        let cleanRepText = repText?.condensed().nilIfEmpty
        let cleanNotes = notes
            .map { $0.condensed() }
            .filter { !$0.isEmpty }
        let cleanIntensityNotes = intensityNotes
            .map { $0.condensed() }
            .filter { !$0.isEmpty }

        let boundedSetCount: Int? = {
            guard let setCount else { return nil }
            return max(1, min(20, setCount))
        }()

        let boundedRest: Int? = {
            guard let restSeconds else { return nil }
            return max(0, min(1_800, restSeconds))
        }()

        return PhotoWorkoutAIExtractionExercise(
            sourceText: resolvedSource,
            exerciseText: resolvedExercise,
            setCount: boundedSetCount,
            repText: cleanRepText,
            notes: cleanNotes,
            restSeconds: boundedRest,
            intensityNotes: cleanIntensityNotes
        )
    }
}

private extension UIImage {
    func preparedPhotoImportPayload() throws -> (data: Data, mimeType: String, fileName: String) {
        let normalized = normalizedForPhotoImport()

        if let pngData = normalized.pngData(), pngData.count <= 5_000_000 {
            return (pngData, "image/png", "photo-workout-import.png")
        }

        if let jpegData = normalized.jpegData(compressionQuality: 0.92) {
            return (jpegData, "image/jpeg", "photo-workout-import.jpg")
        }

        throw WorkoutPhotoImportError.unreadableImage
    }

    func normalizedForPhotoImport() -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

private extension String {
    func condensed() -> String {
        replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmpty: String? {
        let trimmed = condensed()
        return trimmed.isEmpty ? nil : trimmed
    }
}
