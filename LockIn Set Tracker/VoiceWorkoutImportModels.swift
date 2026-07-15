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
