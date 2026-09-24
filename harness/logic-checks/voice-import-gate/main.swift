// Logic check: VoiceImportGate — the app-side second gate of the voice
// import extraction discipline. Compiles against the REAL VoiceImportGate.swift.
// An entry survives when it fuzzy-resolves to the library OR the backend heard
// a clear exercise name; only unresolved AND low-confidence entries are
// filtered out (rescuable, never silently in the routine).
import Foundation

var failures = 0
func check(_ name: String, _ condition: Bool) {
    if condition {
        print("  PASS  \(name)")
    } else {
        print("  FAIL  \(name)")
        failures += 1
    }
}

// MARK: - keeps(resolvedInLibrary:confidence:)

check("resolved + high confidence is kept",
      VoiceImportGate.keeps(resolvedInLibrary: true, confidence: .high))
check("resolved + low confidence is kept (library match wins)",
      VoiceImportGate.keeps(resolvedInLibrary: true, confidence: .low))
check("unresolved + high confidence is kept (novel exercise -> custom)",
      VoiceImportGate.keeps(resolvedInLibrary: false, confidence: .high))
check("unresolved + low confidence is filtered",
      !VoiceImportGate.keeps(resolvedInLibrary: false, confidence: .low))

// MARK: - partition preserves order and routes correctly

struct Entry: Equatable {
    var name: String
    var resolved: Bool
    var confidence: VoiceParsedConfidence
}

let entries = [
    Entry(name: "Bench Press", resolved: true, confidence: .high),
    Entry(name: "Zercher Mule Kick", resolved: false, confidence: .low),
    Entry(name: "Dumbbell Curl", resolved: true, confidence: .low),
    Entry(name: "Nordic Ham Curl", resolved: false, confidence: .high),
    Entry(name: "Pump City", resolved: false, confidence: .low)
]

let (kept, filtered) = VoiceImportGate.partition(
    entries,
    resolvedInLibrary: { $0.resolved },
    confidence: { $0.confidence }
)

check("partition keeps 3 of 5", kept.count == 3)
check("partition filters 2 of 5", filtered.count == 2)
check("kept preserves spoken order",
      kept.map(\.name) == ["Bench Press", "Dumbbell Curl", "Nordic Ham Curl"])
check("filtered preserves spoken order",
      filtered.map(\.name) == ["Zercher Mule Kick", "Pump City"])

let (allKept, noneFiltered) = VoiceImportGate.partition(
    [Entry(name: "Plank", resolved: true, confidence: .high)],
    resolvedInLibrary: { $0.resolved },
    confidence: { $0.confidence }
)
check("single resolved entry: kept 1, filtered 0", allKept.count == 1 && noneFiltered.isEmpty)

let (emptyKept, emptyFiltered) = VoiceImportGate.partition(
    [Entry](),
    resolvedInLibrary: { $0.resolved },
    confidence: { $0.confidence }
)
check("empty input: both buckets empty", emptyKept.isEmpty && emptyFiltered.isEmpty)

// MARK: - normalizedSkippedPhrases

check("skipped: trims and drops blanks",
      VoiceImportGate.normalizedSkippedPhrases(["  beast mode  ", "", "   "]) == ["beast mode"])
check("skipped: dedupes case-insensitively, keeps first spelling",
      VoiceImportGate.normalizedSkippedPhrases(["Beast Mode", "beast mode", "pump city"]) == ["Beast Mode", "pump city"])
check("skipped: excludes phrases already shown elsewhere",
      VoiceImportGate.normalizedSkippedPhrases(["maybe abs", "crush it"], excluding: ["Maybe Abs"]) == ["crush it"])
check("skipped: caps at limit, preserving order",
      VoiceImportGate.normalizedSkippedPhrases(["a", "b", "c", "d"], limit: 2) == ["a", "b"])
check("skipped: empty input yields empty output",
      VoiceImportGate.normalizedSkippedPhrases([]).isEmpty)

// MARK: - VoiceParsedConfidence decoding contract with the backend

check("confidence decodes 'high'",
      (try? JSONDecoder().decode(VoiceParsedConfidence.self, from: Data("\"high\"".utf8))) == .high)
check("confidence decodes 'low'",
      (try? JSONDecoder().decode(VoiceParsedConfidence.self, from: Data("\"low\"".utf8))) == .low)

// MARK: - VoiceTranscriptEditing (the editable transcript step, owner ask 2026-09-24)

check("transcript cap: 20,001 chars truncate silently to the server's 20,000",
      VoiceTranscriptEditing.capped(String(repeating: "a", count: 20_001)).count == 20_000)
check("transcript cap: text under the cap is untouched",
      VoiceTranscriptEditing.capped("bench press 3 by 8") == "bench press 3 by 8")
check("initial transcript prefers the server transcript over the live preview",
      VoiceTranscriptEditing.initialTranscript(server: " Bench press, three sets. ", live: "bench press three sets") == "Bench press, three sets.")
check("initial transcript falls back to the live preview when the server heard nothing",
      VoiceTranscriptEditing.initialTranscript(server: "  \n", live: " bench press ") == "bench press"
      && VoiceTranscriptEditing.initialTranscript(server: nil, live: "").isEmpty)
check("has edits: whitespace-only changes are not edits, word changes are",
      !VoiceTranscriptEditing.hasEdits(current: " bench press\n", original: "bench press")
      && VoiceTranscriptEditing.hasEdits(current: "bench press 4 sets", original: "bench press 3 sets"))
check("can build: mirrors the server's 3-character floor after trimming",
      !VoiceTranscriptEditing.canBuild("  ab ") && VoiceTranscriptEditing.canBuild(" abs "))

if failures == 0 {
    print("VOICE-IMPORT-GATE CHECKS PASSED")
    exit(0)
} else {
    print("VOICE-IMPORT-GATE CHECKS FAILED (\(failures))")
    exit(1)
}
