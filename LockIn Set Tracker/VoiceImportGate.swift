import Foundation

/// Backend-reported confidence that a parsed voice phrase really names an
/// exercise. "high" = clearly spoken exercise name; "low" = garbled or
/// ambiguous mention.
enum VoiceParsedConfidence: String, Codable, Hashable {
    case high
    case low
}

/// Second gate after the backend transcript parse: decides which parsed
/// entries make the imported routine and which are set aside as
/// "didn't sound like exercises" (still rescuable in review).
///
/// Pure logic — verified by `harness/logic-checks/voice-import-gate`.
enum VoiceImportGate {
    /// An entry stays in the main list when it fuzzy-resolves to the exercise
    /// library, or when the backend heard a clear exercise name even though
    /// the library has no match (a genuinely novel exercise → custom entry).
    /// Only unresolved AND low-confidence entries are filtered out.
    static func keeps(resolvedInLibrary: Bool, confidence: VoiceParsedConfidence) -> Bool {
        resolvedInLibrary || confidence == .high
    }

    /// Order-preserving split of parsed entries into kept vs filtered.
    static func partition<Entry>(
        _ entries: [Entry],
        resolvedInLibrary: (Entry) -> Bool,
        confidence: (Entry) -> VoiceParsedConfidence
    ) -> (kept: [Entry], filtered: [Entry]) {
        var kept: [Entry] = []
        var filtered: [Entry] = []

        for entry in entries {
            if keeps(resolvedInLibrary: resolvedInLibrary(entry), confidence: confidence(entry)) {
                kept.append(entry)
            } else {
                filtered.append(entry)
            }
        }

        return (kept, filtered)
    }

    /// Cleans the backend's skipped-phrase list for display: trims, drops
    /// blanks, dedupes case-insensitively (also against phrases already shown,
    /// e.g. filtered entries), preserves order, caps the count.
    static func normalizedSkippedPhrases(
        _ phrases: [String],
        excluding existingPhrases: [String] = [],
        limit: Int = 12
    ) -> [String] {
        var seen = Set(existingPhrases.map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) })
        var result: [String] = []

        for phrase in phrases {
            let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard seen.insert(trimmed.lowercased()).inserted else { continue }
            result.append(trimmed)
            if result.count >= limit { break }
        }

        return result
    }
}
