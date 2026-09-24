import Foundation

/// Pure rules for the editable voice transcript (owner ask 2026-09-24: "you
/// can't really undo if you say something wrong"). Recording stops → the
/// text lands in a field the user can edit → BUILD WORKOUT parses exactly
/// that text. Foundation-only; verified by `harness/logic-checks/voice-import-gate`.
enum VoiceTranscriptEditing {
    /// Mirrors the server's `transcript.slice(0, 20_000)` in /parse.
    static let maxCharacters = 20_000
    /// Mirrors the server's `transcript.length < 3` rejection in /parse.
    static let minCharacters = 3

    /// Silent truncation at the server cap — no counter, no warning.
    static func capped(_ text: String) -> String {
        text.count <= maxCharacters ? text : String(text.prefix(maxCharacters))
    }

    /// What lands in the field when recording stops: the server transcript
    /// when it heard anything, else the on-device live preview. Empty when
    /// neither heard a word (the caller shows the existing error copy).
    static func initialTranscript(server: String?, live: String) -> String {
        let serverText = (server ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let liveText = live.trimmingCharacters(in: .whitespacesAndNewlines)
        return capped(serverText.isEmpty ? liveText : serverText)
    }

    /// Re-recording asks first only when the user changed the words;
    /// whitespace-only differences are not edits.
    static func hasEdits(current: String, original: String) -> Bool {
        current.trimmingCharacters(in: .whitespacesAndNewlines)
            != original.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// BUILD WORKOUT is live once the text clears the server's floor.
    static func canBuild(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).count >= minCharacters
    }
}
