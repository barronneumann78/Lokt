import Foundation

enum VoiceWorkoutImportStage {
    case input
    case processing
    case review
}

struct VoiceWorkoutTranscriptionResult: Codable, Hashable {
    var transcript: String
    var model: String?
    var durationSeconds: Double?
}

struct VoiceWorkoutParseRequest: Codable {
    var transcript: String
}

struct VoiceWorkoutParsedExercisePayload: Codable, Hashable {
    var sourceText: String
    var name: String
    var setCount: Int?
    var repText: String?
    var confidence: VoiceParsedConfidence?
}

struct VoiceWorkoutParsePayload: Codable, Hashable {
    var exercises: [VoiceWorkoutParsedExercisePayload]
    var skipped: [String]?
}

/// A phrase the voice import left out of the main routine (unresolved against
/// the library AND low backend confidence, or explicitly skipped by the
/// backend as non-exercise talk). Shown compactly in review so a mishearing
/// can be rescued.
struct VoiceFilteredPhrase: Identifiable, Codable, Hashable {
    var id = UUID()
    var sourceText: String
    var suggestedName: String
    var matchCandidates: [ImportedExerciseMatchCandidate] = []
    var setCount: Int? = nil
    var repText: String? = nil
}
