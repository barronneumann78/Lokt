import Foundation
import UIKit

enum WorkoutPhotoImportError: LocalizedError {
    case unreadableImage
    case invalidBackendURL
    case invalidResponse
    case noTextDetected
    case noExercisesDetected
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .unreadableImage:
            return "That image could not be read. Try another photo or screenshot."
        case .invalidBackendURL:
            return "The AI backend URL is invalid. Update it in Settings before using photo import."
        case .invalidResponse:
            return "The photo import backend responded, but the result could not be understood."
        case .noTextDetected:
            return "I could not find workout text in that image. Try a clearer photo or crop the routine area first."
        case .noExercisesDetected:
            return "I found text, but not enough workout structure to build a routine. You can try a clearer image or a simpler crop."
        case .requestFailed(let message):
            return message
        }
    }
}

struct WorkoutPhotoImportPipeline {
    private let textExtractor = WorkoutPhotoAIClient()
    private let parser = WorkoutTextParser()
    private let matcher = ExerciseMatcher()
    private let customGenerator = ImportedCustomExerciseGenerator()

    func importWorkout(
        from image: UIImage,
        sourceKind: String = "photo",
        exercises: [Exercise],
        progress: @escaping @MainActor (String) -> Void = { _ in }
    ) async throws -> ImportedWorkoutDraft {
        let parsingResult = try await parseWorkout(
            from: image,
            sourceKind: sourceKind,
            exercises: exercises,
            progress: progress
        )

        return ImportedWorkoutDraft(parsingResult: parsingResult)
    }

    func parseWorkout(
        from image: UIImage,
        sourceKind: String = "photo",
        exercises: [Exercise],
        progress: @escaping @MainActor (String) -> Void = { _ in }
    ) async throws -> AIWorkoutParsingResult {
        await progress("Uploading your image...")
        let extraction = try await textExtractor.extractWorkout(from: image)
        await progress("Interpreting the workout structure...")
        await progress("Matching exercises to your library...")
        return try parsingResult(from: extraction, sourceKind: sourceKind, exercises: exercises)
    }

    func buildImportedWorkout(
        from extraction: PhotoWorkoutAIExtractionResult,
        sourceKind: String = "photo",
        exercises: [Exercise]
    ) throws -> ImportedWorkoutDraft {
        let parsingResult = try parsingResult(
            from: extraction,
            sourceKind: sourceKind,
            exercises: exercises
        )

        return ImportedWorkoutDraft(parsingResult: parsingResult)
    }

    func parsingResult(
        from extraction: PhotoWorkoutAIExtractionResult,
        sourceKind: String = "photo",
        exercises: [Exercise]
    ) throws -> AIWorkoutParsingResult {
        let sourceText = extraction.rawText.nonEmptyOrFallback("")

        let extractedDays = parsedDays(from: extraction)
        let parsedDays = extractedDays.isEmpty ? parser.parse(text: sourceText) : extractedDays

        guard parsedDays.contains(where: { !$0.exercises.isEmpty }) else {
            throw WorkoutPhotoImportError.noExercisesDetected
        }

        let importedDays = parsedDays.map(makeImportedDay(exercises: exercises))
        let draft = ImportedWorkoutDraft(sourceText: sourceText, sourceKind: sourceKind, days: importedDays)
        let routineTitle = resolvedRoutineTitle(for: parsedDays, sourceKind: sourceKind)
        return draft.parsingResult(routineTitle: routineTitle)
    }

    private func parsedDays(from extraction: PhotoWorkoutAIExtractionResult) -> [ParsedWorkoutDay] {
        extraction.days
            .map { day in
                let sourceHeading = day.sourceHeading?.condensed()
                return ParsedWorkoutDay(
                    name: day.name.nonEmptyOrFallback("Imported Workout"),
                    sourceHeading: sourceHeading?.isEmpty == false ? sourceHeading : nil,
                    notes: day.notes.map { $0.condensed() }.filter { !$0.isEmpty },
                    exercises: day.exercises.compactMap { exercise in
                        let exerciseText = exercise.exerciseText.titleCasedHeadline()
                        let sourceText = exercise.sourceText.nonEmptyOrFallback(exerciseText)

                        guard exerciseText.containsLetters || sourceText.containsLetters else {
                            return nil
                        }

                        return ParsedExerciseLine(
                            sourceText: sourceText,
                            exerciseText: exerciseText.nonEmptyOrFallback(sourceText.titleCasedHeadline()),
                            setCount: exercise.setCount,
                            repText: exercise.repText?.condensed(),
                            notes: exercise.notes.map { $0.condensed() }.filter { !$0.isEmpty },
                            restSeconds: exercise.restSeconds,
                            intensityNotes: exercise.intensityNotes.map { $0.condensed() }.filter { !$0.isEmpty }
                        )
                    }
                )
            }
            .filter { !$0.exercises.isEmpty || !$0.notes.isEmpty }
    }

    private func resolvedRoutineTitle(for parsedDays: [ParsedWorkoutDay], sourceKind: String) -> String {
        if parsedDays.count == 1,
           let onlyDay = parsedDays.first?.name.trimmingCharacters(in: .whitespacesAndNewlines),
           !onlyDay.isEmpty {
            return onlyDay
        }

        let source = sourceKind.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Photo"
            : sourceKind.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(source.capitalized) Workout Import"
    }

    private func makeImportedDay(exercises: [Exercise]) -> (ParsedWorkoutDay) -> ImportedWorkoutDayDraft {
        { day in
            ImportedWorkoutDayDraft(
                name: day.name,
                sourceHeading: day.sourceHeading,
                notes: day.notes,
                exercises: day.exercises.map { exercise in
                    let resolution = matcher.resolve(exerciseName: exercise.exerciseText, dayName: day.name, exercises: exercises)

                    switch resolution {
                    case let .matched(exerciseMatch, confidence, candidates):
                        return ImportedExerciseDraft(
                            sourceText: exercise.sourceText,
                            exerciseName: exercise.exerciseText,
                            matchedExerciseName: exerciseMatch.name,
                            matchCandidates: candidates,
                            setCount: exercise.setCount,
                            repText: exercise.repText,
                            notes: exercise.notes.joined(separator: " • "),
                            restSeconds: exercise.restSeconds,
                            intensityNotes: exercise.intensityNotes,
                            confidence: confidence,
                            isCustomExercise: false,
                            customExercise: nil
                        )
                    case let .custom(candidates):
                        let customExercise = customGenerator.makeExercise(
                            from: exercise.exerciseText,
                            dayName: day.name,
                            notes: exercise.notes,
                            intensityNotes: exercise.intensityNotes,
                            existingExercises: exercises
                        )

                        return ImportedExerciseDraft(
                            sourceText: exercise.sourceText,
                            exerciseName: customExercise.name,
                            matchedExerciseName: nil,
                            matchCandidates: candidates,
                            setCount: exercise.setCount,
                            repText: exercise.repText,
                            notes: exercise.notes.joined(separator: " • "),
                            restSeconds: exercise.restSeconds,
                            intensityNotes: exercise.intensityNotes,
                            confidence: .low,
                            isCustomExercise: true,
                            customExercise: customExercise
                        )
                    }
                }
            )
        }
    }
}

enum ImportedWorkoutSaver {
    static func save(_ draft: ImportedWorkoutDraft) {
        let customExercises = draft.days
            .flatMap(\.exercises)
            .compactMap { exercise in
                exercise.isCustomExercise ? exercise.customExercise?.withResolvedName(exercise.resolvedExerciseName) : nil
            }

        CustomExerciseLibrary.upsert(customExercises)

        var routines = loadRoutines()

        let importedRoutines = draft.days.compactMap { day -> Routine? in
            let exercises = day.exercises.map(\.resolvedExerciseName)
            guard !exercises.isEmpty else { return nil }

            let preferredSetCounts = day.exercises.reduce(into: [String: Int]()) { counts, exercise in
                counts[exercise.resolvedExerciseName] = max(1, exercise.setCount ?? 3)
            }

            let importPlans = day.exercises.map { exercise in
                RoutineImportedExercisePlan(
                    exerciseName: exercise.resolvedExerciseName,
                    sourceText: exercise.sourceText,
                    targetSets: exercise.setCount,
                    targetReps: exercise.repText,
                    restSeconds: exercise.restSeconds,
                    notes: exercise.notes.isEmpty ? nil : exercise.notes,
                    intensityNotes: exercise.intensityNotes,
                    matchedExerciseName: exercise.matchedExerciseName,
                    isCustomExercise: exercise.isCustomExercise
                )
            }

            return Routine(
                name: day.name.nonEmptyOrFallback("Imported Workout"),
                exercises: exercises,
                preferredSetCounts: preferredSetCounts,
                importContext: RoutineImportContext(
                    sourceKind: draft.sourceKind,
                    importedAt: Date(),
                    originalText: draft.sourceText,
                    dayName: day.name,
                    exercisePlans: importPlans
                )
            )
        }

        routines.append(contentsOf: importedRoutines)

        if let encoded = try? JSONEncoder().encode(routines) {
            UserDefaults.standard.set(encoded, forKey: "routines")
        }
    }

    private static func loadRoutines() -> [Routine] {
        guard let data = UserDefaults.standard.data(forKey: "routines"),
              let decoded = try? JSONDecoder().decode([Routine].self, from: data) else {
            return []
        }

        return decoded
    }
}

private struct ParsedWorkoutDay {
    var name: String
    var sourceHeading: String?
    var notes: [String]
    var exercises: [ParsedExerciseLine]
}

private struct ParsedExerciseLine {
    var sourceText: String
    var exerciseText: String
    var setCount: Int?
    var repText: String?
    var notes: [String]
    var restSeconds: Int?
    var intensityNotes: [String]
}

private struct WorkoutTextParser {
    private let defaultDayName = "Imported Workout"
    private let headingKeywords = [
        "push day", "pull day", "leg day", "legs", "push", "pull",
        "upper day", "lower day", "upper", "lower", "full body",
        "day 1", "day 2", "day 3", "day 4", "day 5",
        "workout a", "workout b", "workout c",
        "chest", "back", "shoulders", "arms", "legs",
        "glutes", "hamstrings", "quads", "posterior chain"
    ]
    private let exerciseSignals = [
        "press", "curl", "row", "pulldown", "pullup", "pull-up",
        "raise", "extension", "fly", "deadlift", "squat", "lunge",
        "thrust", "crunch", "carry", "swing", "pushdown", "bench"
    ]

    func parse(text: String) -> [ParsedWorkoutDay] {
        let cleanedLines = rawLines(from: text)
        guard !cleanedLines.isEmpty else { return [] }

        var days: [ParsedWorkoutDay] = []
        var currentDay = ParsedWorkoutDay(name: initialDayName(from: cleanedLines), sourceHeading: nil, notes: [], exercises: [])

        for line in cleanedLines {
            if let heading = detectDayHeading(in: line) {
                if !currentDay.exercises.isEmpty || !currentDay.notes.isEmpty {
                    days.append(currentDay)
                }

                currentDay = ParsedWorkoutDay(name: heading, sourceHeading: line, notes: [], exercises: [])
                continue
            }

            if let parsedExercise = parseExerciseLine(from: line) {
                currentDay.exercises.append(parsedExercise)
            } else {
                currentDay.notes.append(line)
            }
        }

        if !currentDay.exercises.isEmpty || !currentDay.notes.isEmpty {
            days.append(currentDay)
        }

        if days.isEmpty {
            return [ParsedWorkoutDay(name: defaultDayName, sourceHeading: nil, notes: [], exercises: cleanedLines.compactMap(parseExerciseLine(from:)))]
        }

        return days
            .filter { !$0.exercises.isEmpty || !$0.notes.isEmpty }
            .enumerated()
            .map { index, day in
                var day = day
                if day.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    day.name = days.count == 1 ? defaultDayName : "Imported Day \(index + 1)"
                }
                return day
            }
    }

    private func rawLines(from text: String) -> [String] {
        text
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .flatMap { line in
                line
                    .components(separatedBy: CharacterSet(charactersIn: "|"))
                    .flatMap { $0.components(separatedBy: ";") }
            }
            .map(cleanLine)
            .filter { !$0.isEmpty }
    }

    private func cleanLine(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"^\s*[•*\-]+\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^\s*\d+[\.\)]\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r-–—:"))
    }

    private func initialDayName(from lines: [String]) -> String {
        guard let first = lines.first else { return defaultDayName }
        if detectDayHeading(in: first) != nil {
            return defaultDayName
        }

        guard !looksLikeExerciseLine(first), first.wordCount <= 5 else {
            return defaultDayName
        }

        return first.titleCasedHeadline()
    }

    private func detectDayHeading(in line: String) -> String? {
        let normalized = line.matchNormalized()
        guard !normalized.isEmpty else { return nil }
        guard !containsSetOrRepSignal(line) else { return nil }

        let explicitHeading = line.hasSuffix(":") || normalized.hasPrefix("day ") || normalized.hasPrefix("workout ")
        let keywordMatch = headingKeywords.contains { normalized == $0 || normalized.hasPrefix($0 + " ") || normalized.hasSuffix(" " + $0) }
        let slashSplit = normalized.contains("/") && normalized.wordCount <= 4

        guard explicitHeading || keywordMatch || slashSplit else { return nil }

        if !explicitHeading && exerciseSignals.contains(where: normalized.contains) {
            return nil
        }

        return line
            .trimmingCharacters(in: CharacterSet(charactersIn: ":-–— "))
            .titleCasedHeadline()
    }

    private func parseExerciseLine(from line: String) -> ParsedExerciseLine? {
        let workingSetCount = firstIntegerMatch(in: line, pattern: #"(?i)\b(\d+)\s*(working(?:\s*sets?)?|work sets?)\b"#)
        let totalSetCount = firstIntegerMatch(in: line, pattern: #"(?i)\b(\d+)\s*sets?\b"#)
        let setRepMatch = firstSetRepMatch(in: line)
        let setCount = setRepMatch?.0 ?? workingSetCount ?? totalSetCount
        let repText = setRepMatch?.1 ?? firstTextMatch(in: line, pattern: #"(?i)\b(\d+\s*(?:-\s*\d+)?)\s*reps?\b"#)
        let restSeconds = parseRestSeconds(from: line)
        let intensityNotes = intensityNotes(from: line)
        let notes = notes(from: line)

        var stripped = line
        stripped = removingMatches(in: stripped, pattern: #"(?i)\b\d+\s*[x×]\s*(?:\d+\s*(?:-\s*\d+)?|amrap|failure)\b"#)
        stripped = removingMatches(in: stripped, pattern: #"(?i)\b\d+\s*sets?\b"#)
        stripped = removingMatches(in: stripped, pattern: #"(?i)\b\d+\s*(working(?:\s*sets?)?|work sets?)\b"#)
        stripped = removingMatches(in: stripped, pattern: #"(?i)\b\d+\s*(warmups?|warm-up(?:\s*sets?)?)\b"#)
        stripped = removingMatches(in: stripped, pattern: #"(?i)\b\d+\s*(?:sec|secs|seconds|s|min|mins|minutes)\b(?:\s*rest)?\b"#)
        stripped = removingMatches(in: stripped, pattern: #"(?i)\b(?:rpe\s*\d+(?:\.\d+)?|rir\s*\d+|amrap|failure|drop set|dropset|top set)\b"#)
        stripped = stripped
            .components(separatedBy: CharacterSet(charactersIn: "-–—:,"))
            .map(cleanLine)
            .first(where: { !$0.isEmpty }) ?? stripped

        let exerciseText = stripped.titleCasedHeadline()
        guard exerciseText.containsLetters else { return nil }
        guard looksLikeExerciseLine(line) || setCount != nil || repText != nil else { return nil }

        return ParsedExerciseLine(
            sourceText: line,
            exerciseText: exerciseText,
            setCount: setCount,
            repText: repText?.condensed(),
            notes: notes,
            restSeconds: restSeconds,
            intensityNotes: intensityNotes
        )
    }

    private func looksLikeExerciseLine(_ line: String) -> Bool {
        let normalized = line.matchNormalized()
        guard normalized.containsLetters else { return false }
        if containsSetOrRepSignal(line) {
            return true
        }

        return exerciseSignals.contains { normalized.contains($0) }
    }

    private func containsSetOrRepSignal(_ line: String) -> Bool {
        line.range(of: #"(?i)\b\d+\s*[x×]\s*(?:\d+|amrap|failure)\b|\b\d+\s*sets?\b|\b\d+\s*reps?\b"#, options: .regularExpression) != nil
    }

    private func parseRestSeconds(from line: String) -> Int? {
        guard let match = line.firstMatch(of: /(?i)\b(\d+)\s*(sec|secs|seconds|s|min|mins|minutes)\b(?:\s*rest)?/) else {
            return nil
        }

        guard let value = Int(String(match.1)) else { return nil }
        let unit = String(match.2).lowercased()

        if unit.hasPrefix("min") {
            return value * 60
        }

        return value
    }

    private func intensityNotes(from line: String) -> [String] {
        var notes: [String] = []

        if let rpe = firstTextMatch(in: line, pattern: #"(?i)\bRPE\s*\d+(?:\.\d+)?\b"#) {
            notes.append(rpe.uppercased())
        }

        if let rir = firstTextMatch(in: line, pattern: #"(?i)\bRIR\s*\d+\b"#) {
            notes.append(rir.uppercased())
        }

        if line.range(of: #"(?i)\bdrop set\b|\bdropset\b"#, options: .regularExpression) != nil {
            notes.append("Drop set")
        }

        if line.range(of: #"(?i)\bfailure\b"#, options: .regularExpression) != nil {
            notes.append("To failure")
        }

        if line.range(of: #"(?i)\bAMRAP\b"#, options: .regularExpression) != nil {
            notes.append("AMRAP")
        }

        if line.range(of: #"(?i)\btop set\b"#, options: .regularExpression) != nil {
            notes.append("Top set")
        }

        return notes.uniquePreservingOrder()
    }

    private func notes(from line: String) -> [String] {
        var notes: [String] = []

        if let warmups = firstTextMatch(in: line, pattern: #"(?i)\b\d+\s*(warmups?|warm-up(?:\s*sets?)?)\b"#) {
            notes.append(warmups.condensed())
        }

        if let workingSets = firstTextMatch(in: line, pattern: #"(?i)\b\d+\s*(working(?:\s*sets?)?|work sets?)\b"#) {
            notes.append(workingSets.condensed())
        }

        let chunks = line
            .components(separatedBy: CharacterSet(charactersIn: "-–—"))
            .map(cleanLine)
            .filter { !$0.isEmpty }

        if chunks.count > 1 {
            notes.append(contentsOf: chunks.dropFirst())
        }

        return notes
            .map { $0.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression) }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ", ")) }
            .filter { !$0.isEmpty }
            .uniquePreservingOrder()
    }

    private func firstSetRepMatch(in value: String) -> (Int, String)? {
        guard let match = value.firstMatch(of: /(?i)\b(\d+)\s*[x×]\s*(\d+(?:\s*-\s*\d+)?|amrap|failure)\b/) else {
            return nil
        }

        guard let setCount = Int(String(match.1)) else { return nil }
        return (setCount, String(match.2).uppercasedIfNeeded())
    }

    private func firstIntegerMatch(in value: String, pattern: String) -> Int? {
        guard let match = firstTextMatch(in: value, pattern: pattern),
              let digits = match.firstMatch(of: /\d+/),
              let result = Int(String(digits.0)) else {
            return nil
        }

        return result
    }

    private func firstTextMatch(in value: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(value.startIndex..., in: value)
        guard let match = regex.firstMatch(in: value, range: range) else { return nil }
        guard let stringRange = Range(match.range, in: value) else { return nil }
        return String(value[stringRange])
    }

    private func removingMatches(in value: String, pattern: String) -> String {
        value.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    }
}

enum ExerciseMatchResolution {
    case matched(Exercise, ImportedExerciseConfidence, [ImportedExerciseMatchCandidate])
    case custom([ImportedExerciseMatchCandidate])
}

struct ExerciseMatcher {
    func resolve(exerciseName: String, dayName: String, exercises: [Exercise]) -> ExerciseMatchResolution {
        let normalizedQuery = normalize(exerciseName)
        let queryTokens = Set(normalizedQuery.split(separator: " ").map(String.init))
        let dayTokens = Set(normalize(dayName).split(separator: " ").map(String.init))

        let candidates = exercises.map { exercise -> ImportedExerciseMatchCandidate in
            let normalizedExerciseName = normalize(exercise.name)
            let exerciseTokens = Set(normalizedExerciseName.split(separator: " ").map(String.init))

            let tokenScore = jaccardScore(lhs: queryTokens, rhs: exerciseTokens)
            let editScore = normalizedSimilarity(lhs: normalizedQuery, rhs: normalizedExerciseName)
            let containmentBonus = normalizedExerciseName.contains(normalizedQuery) || normalizedQuery.contains(normalizedExerciseName) ? 0.12 : 0
            let leadingTokenBonus = leadingTokenScore(lhs: normalizedQuery, rhs: normalizedExerciseName)
            let dayContextBonus = dayContextScore(dayTokens: dayTokens, exercise: exercise)
            let exactBonus = normalizedQuery == normalizedExerciseName ? 0.24 : 0

            let score = min(1.0, 0.42 * tokenScore + 0.38 * editScore + containmentBonus + leadingTokenBonus + dayContextBonus + exactBonus)
            return ImportedExerciseMatchCandidate(name: exercise.name, score: score)
        }
        .sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

            return lhs.score > rhs.score
        }

        guard let best = candidates.first,
              let matchedExercise = exercises.first(where: { $0.name == best.name }) else {
            return .custom([])
        }

        let runnerUpScore = candidates.dropFirst().first?.score ?? 0
        let confidenceGap = best.score - runnerUpScore
        let topCandidates = Array(candidates.prefix(5))

        if best.score >= 0.86 && confidenceGap >= 0.07 {
            return .matched(matchedExercise, .high, topCandidates)
        }

        if best.score >= 0.74 {
            return .matched(matchedExercise, .medium, topCandidates)
        }

        return .custom(topCandidates)
    }

    private func normalize(_ value: String) -> String {
        var output = value.lowercased()
        let replacements: [(String, String)] = [
            (#"(?<![a-z])db(?![a-z])"#, "dumbbell"),
            (#"(?<![a-z])bb(?![a-z])"#, "barbell"),
            (#"(?<![a-z])ohp(?![a-z])"#, "overhead press"),
            (#"(?<![a-z])rdl(?![a-z])"#, "romanian deadlift"),
            (#"(?<![a-z])sldl(?![a-z])"#, "stiff leg deadlift"),
            (#"\blat\s+raise(s)?\b"#, "lateral raise"),
            (#"\bflys\b|\bflies\b|\bflyes\b"#, "fly"),
            (#"\bpressdowns?\b"#, "pushdown"),
            (#"\btri[ -]?cep\b"#, "triceps"),
            (#"\btri\b"#, "triceps"),
            (#"\bbi\b"#, "biceps"),
            (#"\bsmith\s+incline\s+press\b"#, "smith machine incline bench press"),
            (#"\bdb\s+bench\b"#, "dumbbell bench press"),
            (#"\bbb\s+bench\b"#, "barbell bench press"),
            (#"\bcable\s+flys?\b"#, "cable fly"),
            (#"\bpullup\b"#, "pull up"),
            (#"\bchinup\b"#, "chin up")
        ]

        for (pattern, replacement) in replacements {
            output = output.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }

        output = output
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: #"[^a-z0-9\s]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return output
    }

    private func jaccardScore(lhs: Set<String>, rhs: Set<String>) -> Double {
        guard !lhs.isEmpty || !rhs.isEmpty else { return 0 }
        let intersection = lhs.intersection(rhs).count
        let union = lhs.union(rhs).count
        return union == 0 ? 0 : Double(intersection) / Double(union)
    }

    private func normalizedSimilarity(lhs: String, rhs: String) -> Double {
        let lhsChars = Array(lhs)
        let rhsChars = Array(rhs)

        guard !lhsChars.isEmpty || !rhsChars.isEmpty else { return 1 }
        guard !lhsChars.isEmpty, !rhsChars.isEmpty else { return 0 }

        var distances = Array(0...rhsChars.count)

        for (leftIndex, leftChar) in lhsChars.enumerated() {
            var previous = distances[0]
            distances[0] = leftIndex + 1

            for (rightIndex, rightChar) in rhsChars.enumerated() {
                let old = distances[rightIndex + 1]
                if leftChar == rightChar {
                    distances[rightIndex + 1] = previous
                } else {
                    distances[rightIndex + 1] = min(previous, distances[rightIndex], old) + 1
                }
                previous = old
            }
        }

        let maxLength = max(lhsChars.count, rhsChars.count)
        return 1 - Double(distances[rhsChars.count]) / Double(maxLength)
    }

    private func leadingTokenScore(lhs: String, rhs: String) -> Double {
        let lhsTokens = lhs.split(separator: " ")
        let rhsTokens = rhs.split(separator: " ")
        let count = min(lhsTokens.count, rhsTokens.count)
        guard count > 0 else { return 0 }

        var matches = 0
        for index in 0..<count where lhsTokens[index] == rhsTokens[index] {
            matches += 1
        }

        return matches > 0 ? min(0.16, Double(matches) * 0.05) : 0
    }

    private func dayContextScore(dayTokens: Set<String>, exercise: Exercise) -> Double {
        guard !dayTokens.isEmpty else { return 0 }

        let muscleTokens = Set((exercise.metadata.primaryMuscles + exercise.metadata.secondaryMuscles + [exercise.muscleGroup.rawValue])
            .flatMap { normalize($0).split(separator: " ").map(String.init) })

        let overlap = dayTokens.intersection(muscleTokens).count
        if overlap > 0 {
            return min(0.08, Double(overlap) * 0.03)
        }

        if dayTokens.contains("push"), [.chest, .shoulders, .arms].contains(exercise.muscleGroup) {
            return 0.04
        }

        if dayTokens.contains("pull"), [.back, .arms].contains(exercise.muscleGroup) {
            return 0.04
        }

        if dayTokens.contains("legs") || dayTokens.contains("lower"), exercise.muscleGroup == .legs {
            return 0.04
        }

        if dayTokens.contains("upper"), [.chest, .back, .shoulders, .arms].contains(exercise.muscleGroup) {
            return 0.03
        }

        return 0
    }
}

struct ImportedCustomExerciseGenerator {
    func makeExercise(
        from sourceName: String,
        dayName: String,
        notes: [String],
        intensityNotes: [String],
        existingExercises: [Exercise]
    ) -> Exercise {
        let cleanName = uniqueName(for: sourceName.titleCasedHeadline(), existingExercises: existingExercises)
        let normalizedSource = sourceName.matchNormalized()
        let muscleGroup = inferMuscleGroup(source: normalizedSource, dayName: dayName.matchNormalized())
        let equipment = inferEquipment(source: normalizedSource)
        let movementPattern = inferMovementPattern(source: normalizedSource)
        let difficulty = inferDifficulty(source: normalizedSource, equipment: equipment)
        let primaryGroups = inferPrimaryGroups(source: normalizedSource, muscleGroup: muscleGroup)
        let primaryMuscles = inferPrimaryMuscles(source: normalizedSource, muscleGroup: muscleGroup)
        let secondaryMuscles = inferSecondaryMuscles(source: normalizedSource, muscleGroup: muscleGroup)
        let laterality = inferLaterality(source: normalizedSource)
        let mechanic = movementPattern == .isolation ? "isolation" : "compound"
        let forceType = inferForceType(from: movementPattern)
        let bodyRegion = inferBodyRegion(from: muscleGroup)
        let trainingGoal = inferTrainingGoal(from: movementPattern, intensityNotes: intensityNotes)
        let gripType = inferGripType(source: normalizedSource)
        let planeOfMotion = inferPlaneOfMotion(source: normalizedSource, movementPattern: movementPattern)
        let tags = inferTags(
            source: normalizedSource,
            muscleGroup: muscleGroup,
            equipment: equipment,
            movementPattern: movementPattern,
            primaryMuscles: primaryMuscles,
            secondaryMuscles: secondaryMuscles,
            laterality: laterality,
            notes: notes,
            intensityNotes: intensityNotes
        )

        let description = makeDescription(name: cleanName, muscleGroup: muscleGroup, movementPattern: movementPattern)
        let howTo = makeHowTo(name: cleanName, movementPattern: movementPattern, equipment: equipment, laterality: laterality)
        let cues = makeCues(movementPattern: movementPattern, equipment: equipment)

        return Exercise(
            id: "custom-\(UUID().uuidString.lowercased())",
            name: cleanName,
            muscleGroup: muscleGroup,
            equipment: equipment,
            movementPattern: movementPattern,
            primaryMuscleGroups: primaryGroups,
            difficulty: difficulty,
            instructions: "Custom Imported Exercise. Review and refine the details if needed.",
            imageName: nil,
            metadata: ExerciseMetadata(
                primaryMuscles: primaryMuscles,
                secondaryMuscles: secondaryMuscles,
                movementPattern: movementPattern.rawValue.lowercased(),
                equipment: [equipment.rawValue.lowercased()],
                difficulty: difficulty.rawValue.lowercased(),
                mechanic: mechanic,
                forceType: forceType,
                laterality: laterality,
                bodyRegion: bodyRegion,
                trainingGoal: trainingGoal,
                exerciseType: "strength",
                gripType: gripType,
                stance: inferStance(from: movementPattern, laterality: laterality),
                planeOfMotion: planeOfMotion,
                tags: tags
            ),
            description: description,
            howTo: howTo,
            cues: cues
        )
    }

    private func uniqueName(for baseName: String, existingExercises: [Exercise]) -> String {
        let existingNames = Set(existingExercises.map { $0.name.lowercased() })
        guard existingNames.contains(baseName.lowercased()) else { return baseName }

        let customBase = "\(baseName) (Custom)"
        guard existingNames.contains(customBase.lowercased()) else { return customBase }

        for index in 2...50 {
            let candidate = "\(baseName) (Custom \(index))"
            if !existingNames.contains(candidate.lowercased()) {
                return candidate
            }
        }

        return "\(baseName) \(UUID().uuidString.prefix(4))"
    }

    private func inferMuscleGroup(source: String, dayName: String) -> MuscleGroup {
        if source.contains(anyOf: ["squat", "lunge", "leg press", "deadlift", "rdl", "calf", "hamstring", "glute", "quad", "hip thrust"]) {
            return .legs
        }

        if source.contains(anyOf: ["row", "pulldown", "pull up", "pullup", "chin up", "face pull"]) {
            return .back
        }

        if source.contains(anyOf: ["press", "bench", "fly", "push up", "push-up"]) {
            return source.contains(anyOf: ["shoulder", "overhead", "arnold", "lateral", "rear delt"]) ? .shoulders : .chest
        }

        if source.contains(anyOf: ["curl", "pushdown", "triceps", "biceps", "skullcrusher", "extension"]) {
            return .arms
        }

        if source.contains(anyOf: ["plank", "crunch", "ab wheel", "hanging knee", "pallof", "twist"]) {
            return .core
        }

        if dayName.contains("push") {
            return .chest
        }

        if dayName.contains("pull") {
            return .back
        }

        if dayName.contains(anyOf: ["legs", "lower"]) {
            return .legs
        }

        return .other
    }

    private func inferEquipment(source: String) -> EquipmentType {
        if source.contains(anyOf: ["dumbbell", "db"]) { return .dumbbell }
        if source.contains(anyOf: ["barbell", "bb", "ez bar", "axle"]) { return .barbell }
        if source.contains(anyOf: ["cable", "pulley"]) { return .cable }
        if source.contains(anyOf: ["machine", "smith", "press machine"]) { return .machine }
        if source.contains("kettlebell") { return .kettlebell }
        if source.contains(anyOf: ["band", "resistance band"]) { return .band }
        if source.contains("medicine ball") { return .medicineBall }
        if source.contains(anyOf: ["bodyweight", "push up", "pull up", "chin up", "dip", "plank"]) { return .bodyweight }
        return .other
    }

    private func inferMovementPattern(source: String) -> MovementPattern {
        if source.contains(anyOf: ["row", "rear delt fly", "face pull"]) { return .horizontalPull }
        if source.contains(anyOf: ["pulldown", "pull up", "pullup", "chin up", "chinup"]) { return .verticalPull }
        if source.contains(anyOf: ["overhead press", "shoulder press", "arnold press", "push press", "military press"]) { return .verticalPush }
        if source.contains(anyOf: ["bench", "chest press", "fly", "push up", "push-up", "dip"]) { return .horizontalPush }
        if source.contains(anyOf: ["squat", "lunge", "leg press", "step up", "split squat"]) { return .squat }
        if source.contains(anyOf: ["deadlift", "rdl", "good morning", "swing", "hip thrust", "hinge"]) { return .hinge }
        return .isolation
    }

    private func inferPrimaryGroups(source: String, muscleGroup: MuscleGroup) -> [PrimaryMuscleGroup] {
        switch muscleGroup {
        case .chest:
            return [.chest]
        case .back:
            return [.back]
        case .shoulders:
            return [.shoulders]
        case .legs:
            return [.legs]
        case .core:
            return [.core]
        case .arms:
            if source.contains(anyOf: ["pushdown", "triceps", "extension", "skullcrusher"]) {
                return [.triceps]
            }
            return [.biceps]
        case .cardio, .fullBody, .mobility, .other:
            return [.core]
        }
    }

    private func inferPrimaryMuscles(source: String, muscleGroup: MuscleGroup) -> [String] {
        if source.contains("incline") { return ["upper chest"] }
        if source.contains("decline") { return ["lower chest"] }
        if source.contains("lateral") { return ["lateral delts"] }
        if source.contains(anyOf: ["rear delt", "face pull"]) { return ["rear delts"] }
        if source.contains(anyOf: ["overhead", "arnold", "shoulder"]) { return ["front delts"] }
        if source.contains(anyOf: ["curl", "preacher", "hammer"]) { return source.contains("hammer") ? ["brachialis"] : ["biceps"] }
        if source.contains(anyOf: ["pushdown", "triceps", "skullcrusher", "extension"]) { return ["triceps"] }
        if source.contains(anyOf: ["row", "face pull"]) { return ["upper back"] }
        if source.contains(anyOf: ["pulldown", "pull up", "chin up"]) { return ["lats"] }
        if source.contains(anyOf: ["rdl", "deadlift", "stiff leg"]) { return ["hamstrings"] }
        if source.contains(anyOf: ["hip thrust", "glute"]) { return ["glutes"] }
        if source.contains(anyOf: ["squat", "leg press", "split squat", "lunge"]) { return ["quads"] }
        if source.contains(anyOf: ["calf"]) { return ["calves"] }
        if source.contains(anyOf: ["crunch", "ab", "plank", "pallof", "twist"]) { return ["abs"] }

        switch muscleGroup {
        case .chest:
            return ["chest"]
        case .back:
            return ["upper back"]
        case .shoulders:
            return ["delts"]
        case .arms:
            return ["arms"]
        case .legs:
            return ["legs"]
        case .core:
            return ["core"]
        case .cardio, .fullBody, .mobility, .other:
            return ["full body"]
        }
    }

    private func inferSecondaryMuscles(source: String, muscleGroup: MuscleGroup) -> [String] {
        switch muscleGroup {
        case .chest:
            return source.contains("incline") ? ["front delts", "triceps"] : ["triceps", "front delts"]
        case .back:
            return source.contains("pulldown") ? ["upper back", "biceps"] : ["lats", "rear delts"]
        case .shoulders:
            return ["triceps", "upper chest"]
        case .arms:
            if source.contains(anyOf: ["hammer", "reverse"]) {
                return ["brachioradialis", "forearms"]
            }
            return source.contains(anyOf: ["triceps", "pushdown", "extension"]) ? ["front delts"] : ["forearms"]
        case .legs:
            return source.contains(anyOf: ["rdl", "deadlift", "hinge"]) ? ["glutes", "spinal erectors"] : ["glutes", "hamstrings"]
        case .core:
            return ["obliques"]
        case .cardio, .fullBody, .mobility, .other:
            return []
        }
    }

    private func inferDifficulty(source: String, equipment: EquipmentType) -> DifficultyLevel {
        if source.contains(anyOf: ["pistol", "snatch", "clean", "advanced", "atlas"]) {
            return .advanced
        }

        if equipment == .machine || equipment == .bodyweight {
            return .beginner
        }

        return .intermediate
    }

    private func inferLaterality(source: String) -> String {
        if source.contains(anyOf: ["one arm", "one-arm", "single arm", "single-arm", "unilateral", "alternating"]) {
            return "unilateral"
        }

        return "bilateral"
    }

    private func inferForceType(from movementPattern: MovementPattern) -> String {
        switch movementPattern {
        case .horizontalPush, .verticalPush:
            return "push"
        case .horizontalPull, .verticalPull:
            return "pull"
        case .squat:
            return "squat"
        case .hinge:
            return "hinge"
        case .isolation:
            return "isolation"
        }
    }

    private func inferBodyRegion(from muscleGroup: MuscleGroup) -> String {
        switch muscleGroup {
        case .legs:
            return "lower body"
        case .core:
            return "core"
        case .cardio, .fullBody:
            return "full body"
        case .mobility:
            return "mobility"
        case .chest, .back, .shoulders, .arms:
            return "upper body"
        case .other:
            return "full body"
        }
    }

    private func inferTrainingGoal(from movementPattern: MovementPattern, intensityNotes: [String]) -> [String] {
        var goals = ["hypertrophy"]

        if movementPattern == .squat || movementPattern == .hinge {
            goals.append("strength")
        }

        if intensityNotes.contains(where: { $0.localizedCaseInsensitiveContains("amrap") }) {
            goals.append("conditioning")
        }

        return goals.uniquePreservingOrder()
    }

    private func inferGripType(source: String) -> String? {
        if source.contains("hammer") || source.contains("neutral") {
            return "neutral"
        }

        if source.contains("reverse") {
            return "pronated"
        }

        if source.contains(anyOf: ["curl", "row", "pulldown", "bench", "press"]) {
            return "neutral or pronated"
        }

        return nil
    }

    private func inferStance(from movementPattern: MovementPattern, laterality: String) -> String? {
        if laterality == "unilateral" {
            return "split stance"
        }

        switch movementPattern {
        case .squat:
            return "standing"
        case .hinge:
            return "hip-width standing"
        case .horizontalPush, .horizontalPull:
            return "bench or supported setup"
        case .verticalPush, .verticalPull, .isolation:
            return nil
        }
    }

    private func inferPlaneOfMotion(source: String, movementPattern: MovementPattern) -> String {
        if source.contains(anyOf: ["twist", "rotation", "rotational"]) {
            return "transverse"
        }

        if source.contains(anyOf: ["lateral", "side"]) {
            return "frontal"
        }

        switch movementPattern {
        case .horizontalPush, .horizontalPull, .verticalPush, .verticalPull, .squat, .hinge, .isolation:
            return "sagittal"
        }
    }

    private func inferTags(
        source: String,
        muscleGroup: MuscleGroup,
        equipment: EquipmentType,
        movementPattern: MovementPattern,
        primaryMuscles: [String],
        secondaryMuscles: [String],
        laterality: String,
        notes: [String],
        intensityNotes: [String]
    ) -> [String] {
        var tags = primaryMuscles + secondaryMuscles
        tags.append(contentsOf: movementTags(for: source, movementPattern: movementPattern))
        tags.append(equipment.rawValue.lowercased())
        tags.append(laterality)
        tags.append(muscleGroup.rawValue.lowercased())
        tags.append(contentsOf: notes.map { $0.lowercased() })
        tags.append(contentsOf: intensityNotes.map { $0.lowercased() })
        tags.append("custom imported exercise")
        return tags.uniquePreservingOrder()
    }

    private func movementTags(for source: String, movementPattern: MovementPattern) -> [String] {
        var tags: [String] = []

        switch movementPattern {
        case .horizontalPush:
            tags.append(contentsOf: ["push", "compound"])
        case .verticalPush:
            tags.append(contentsOf: ["vertical press", "push"])
        case .horizontalPull:
            tags.append(contentsOf: ["row", "pull"])
        case .verticalPull:
            tags.append(contentsOf: ["pulldown", "pull"])
        case .squat:
            tags.append(contentsOf: ["squat", "lower body"])
        case .hinge:
            tags.append(contentsOf: ["hinge", "posterior chain"])
        case .isolation:
            tags.append("isolation")
        }

        if source.contains("incline") { tags.append("incline") }
        if source.contains("smith") { tags.append("smith machine") }
        if source.contains("home") || source.contains("band") { tags.append("home-gym") }

        return tags
    }

    private func makeDescription(name: String, muscleGroup: MuscleGroup, movementPattern: MovementPattern) -> String {
        switch movementPattern {
        case .horizontalPush:
            return "\(name) appears to be an imported pressing movement for the \(muscleGroup.rawValue.lowercased()) and supporting triceps/shoulder work."
        case .verticalPush:
            return "\(name) appears to be an imported overhead pressing movement that emphasizes the shoulders with triceps support."
        case .horizontalPull:
            return "\(name) appears to be an imported rowing movement for the upper back and lats."
        case .verticalPull:
            return "\(name) appears to be an imported vertical pull focused on the lats and upper back."
        case .squat:
            return "\(name) appears to be an imported lower-body squat pattern for the quads and glutes."
        case .hinge:
            return "\(name) appears to be an imported hinge pattern for the hamstrings, glutes, and posterior chain."
        case .isolation:
            return "\(name) appears to be an imported accessory movement. Review the exact setup and intent before relying on it."
        }
    }

    private func makeHowTo(name: String, movementPattern: MovementPattern, equipment: EquipmentType, laterality: String) -> [String] {
        switch movementPattern {
        case .horizontalPush:
            return [
                "Set up for \(name) with the \(equipment.rawValue.lowercased()) positioned so you can keep your chest up and shoulders packed.",
                "Lower or guide the load with control until you reach a strong pressing position.",
                "Press smoothly while keeping your wrists stacked and your ribcage stable."
            ]
        case .verticalPush:
            return [
                "Start \(name) with the weight set at shoulder level and your trunk braced.",
                "Press overhead without leaning back or losing ribcage position.",
                "Lower under control to the start position and repeat evenly."
            ]
        case .horizontalPull:
            return [
                "Set your torso and brace before starting each row.",
                "Pull the weight toward your torso without shrugging or yanking.",
                "Lower with control and keep tension through the back between reps."
            ]
        case .verticalPull:
            return [
                "Set your shoulders down before initiating the pull.",
                "Drive elbows toward your sides while keeping your torso steady.",
                "Return to the stretched position with control instead of letting the weight yank you."
            ]
        case .squat:
            return [
                "Set your stance and brace before descending.",
                "Lower with control while keeping pressure through the whole foot.",
                "Stand back up by driving through the floor and keeping your torso organized."
            ]
        case .hinge:
            return [
                "Start by pushing your hips back and keeping your spine long.",
                "Lower only as far as you can keep tension in the posterior chain.",
                "Drive the hips through to stand tall without overextending at lockout."
            ]
        case .isolation:
            return [
                "Set up \(name) so the target muscle starts under control.",
                "Move through the intended joint action without using extra body English.",
                "Pause briefly in the hard part of the rep and lower under control."
            ]
        }
    }

    private func makeCues(movementPattern: MovementPattern, equipment: EquipmentType) -> [String] {
        switch movementPattern {
        case .horizontalPush:
            return ["Keep your shoulders packed", "Lower with control", "Drive through the target muscle"]
        case .verticalPush:
            return ["Brace before you press", "Reach up without flaring your ribs", "Control the descent"]
        case .horizontalPull:
            return ["Lead with the elbows", "Keep your chest proud", "Do not yank the weight"]
        case .verticalPull:
            return ["Pull elbows to your sides", "Keep shoulders down", "Use the full stretch"]
        case .squat:
            return ["Brace first", "Keep pressure through the midfoot", "Stand up hard but controlled"]
        case .hinge:
            return ["Push the hips back", "Keep the bar or handle close", "Finish tall without leaning back"]
        case .isolation:
            return [
                equipment == .cable ? "Let the cable keep tension on the target area" : "Stay strict through the range",
                "Do not rush the lowering phase",
                "Keep the working muscle doing the job"
            ]
        }
    }
}

private extension Exercise {
    func withResolvedName(_ name: String) -> Exercise {
        var copy = self
        copy.name = name
        return copy
    }
}

private extension String {
    var wordCount: Int {
        split(separator: " ").count
    }

    var containsLetters: Bool {
        rangeOfCharacter(from: .letters) != nil
    }

    func matchNormalized() -> String {
        lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: #"[^a-z0-9/\s]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func titleCasedHeadline() -> String {
        matchNormalized()
            .split(separator: " ")
            .map { token -> String in
                if token.count <= 3, token.allSatisfy({ $0.isNumber || $0 == "/" }) {
                    return String(token)
                }

                return token.prefix(1).uppercased() + token.dropFirst()
            }
            .joined(separator: " ")
            .replacingOccurrences(of: " Db ", with: " DB ")
            .replacingOccurrences(of: " Bb ", with: " BB ")
    }

    func condensed() -> String {
        replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func uppercasedIfNeeded() -> String {
        lowercased() == "amrap" ? "AMRAP" : condensed()
    }

    func nonEmptyOrFallback(_ fallback: String) -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    func contains(anyOf values: [String]) -> Bool {
        values.contains(where: contains)
    }
}

private extension Array where Element == String {
    func uniquePreservingOrder() -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for value in self {
            let key = value.lowercased()
            if seen.insert(key).inserted {
                result.append(value)
            }
        }

        return result
    }
}
