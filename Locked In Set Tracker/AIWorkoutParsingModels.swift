import Foundation

struct AIWorkoutParsingResult: Codable, Hashable {
    var routineTitle: String
    var sourceKind: String
    var sourceText: String
    var days: [AIWorkoutParsingDay]

    var matchedExercises: [AIWorkoutParsingExerciseMatch] {
        days.flatMap(\.matchedExercises)
    }

    var uncertainMatches: [AIWorkoutParsingExerciseMatch] {
        days.flatMap(\.uncertainMatches)
    }

    var unmatchedItems: [AIWorkoutParsingUnmatchedItem] {
        days.flatMap(\.unmatchedItems)
    }
}

struct AIWorkoutParsingDay: Codable, Hashable {
    var name: String
    var notes: [String]
    var matchedExercises: [AIWorkoutParsingExerciseMatch]
    var uncertainMatches: [AIWorkoutParsingExerciseMatch]
    var unmatchedItems: [AIWorkoutParsingUnmatchedItem]
}

struct AIWorkoutParsingExerciseMatch: Identifiable, Codable, Hashable {
    var id = UUID()
    var orderIndex: Int
    var sourceText: String
    var exerciseName: String
    var matchCandidates: [ImportedExerciseMatchCandidate]
    var confidence: ImportedExerciseConfidence
    var setCount: Int?
    var repText: String?
    var notes: String?
    var restSeconds: Int?
    var intensityNotes: [String]
}

struct AIWorkoutParsingUnmatchedItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var orderIndex: Int
    var sourceText: String
    var suggestedName: String
    var matchCandidates: [ImportedExerciseMatchCandidate]
    var setCount: Int?
    var repText: String?
    var notes: String?
    var restSeconds: Int?
    var intensityNotes: [String]
    var customExercise: Exercise?
}

extension ImportedWorkoutDraft {
    init(parsingResult: AIWorkoutParsingResult) {
        let convertedDays = parsingResult.days.compactMap { day -> ImportedWorkoutDayDraft? in
            let orderedExercises = day.orderedExercises
            guard !orderedExercises.isEmpty else { return nil }

            return ImportedWorkoutDayDraft(
                name: day.name.nilIfEmpty ?? parsingResult.routineTitle.nilIfEmpty ?? "Imported Workout",
                sourceHeading: nil,
                notes: day.notes,
                exercises: orderedExercises
            )
        }

        self.init(
            sourceText: parsingResult.sourceText,
            sourceKind: parsingResult.sourceKind,
            days: convertedDays
        )
    }

    func parsingResult(routineTitle: String? = nil) -> AIWorkoutParsingResult {
        let resolvedRoutineTitle = routineTitle?.nilIfEmpty
            ?? Self.defaultRoutineTitle(days: days, sourceKind: sourceKind)

        return AIWorkoutParsingResult(
            routineTitle: resolvedRoutineTitle,
            sourceKind: sourceKind,
            sourceText: sourceText,
            days: days.map { day in
                let categorized = day.exercises.enumerated().reduce(
                    into: (
                        matched: [AIWorkoutParsingExerciseMatch](),
                        uncertain: [AIWorkoutParsingExerciseMatch](),
                        unmatched: [AIWorkoutParsingUnmatchedItem]()
                    )
                ) { partialResult, entry in
                    let orderIndex = entry.offset
                    let exercise = entry.element

                    switch exercise.matchStatus {
                    case .matched:
                        partialResult.matched.append(
                            AIWorkoutParsingExerciseMatch(
                                orderIndex: orderIndex,
                                sourceText: exercise.sourceText,
                                exerciseName: exercise.resolvedExerciseName,
                                matchCandidates: exercise.matchCandidates,
                                confidence: exercise.confidence,
                                setCount: exercise.setCount,
                                repText: exercise.repText,
                                notes: exercise.notes.nilIfEmpty,
                                restSeconds: exercise.restSeconds,
                                intensityNotes: exercise.intensityNotes
                            )
                        )
                    case .uncertain:
                        partialResult.uncertain.append(
                            AIWorkoutParsingExerciseMatch(
                                orderIndex: orderIndex,
                                sourceText: exercise.sourceText,
                                exerciseName: exercise.resolvedExerciseName,
                                matchCandidates: exercise.matchCandidates,
                                confidence: exercise.confidence,
                                setCount: exercise.setCount,
                                repText: exercise.repText,
                                notes: exercise.notes.nilIfEmpty,
                                restSeconds: exercise.restSeconds,
                                intensityNotes: exercise.intensityNotes
                            )
                        )
                    case .unmatched:
                        partialResult.unmatched.append(
                            AIWorkoutParsingUnmatchedItem(
                                orderIndex: orderIndex,
                                sourceText: exercise.sourceText,
                                suggestedName: exercise.resolvedExerciseName,
                                matchCandidates: exercise.matchCandidates,
                                setCount: exercise.setCount,
                                repText: exercise.repText,
                                notes: exercise.notes.nilIfEmpty,
                                restSeconds: exercise.restSeconds,
                                intensityNotes: exercise.intensityNotes,
                                customExercise: exercise.customExercise
                            )
                        )
                    }
                }

                return AIWorkoutParsingDay(
                    name: day.name,
                    notes: day.notes,
                    matchedExercises: categorized.matched,
                    uncertainMatches: categorized.uncertain,
                    unmatchedItems: categorized.unmatched
                )
            }
        )
    }

    private static func defaultRoutineTitle(days: [ImportedWorkoutDayDraft], sourceKind: String) -> String {
        if days.count == 1, let onlyDay = days.first?.name.nilIfEmpty {
            return onlyDay
        }

        let source = (sourceKind.nilIfEmpty ?? "AI").capitalized
        return "\(source) Workout Import"
    }
}

private extension AIWorkoutParsingDay {
    var orderedExercises: [ImportedExerciseDraft] {
        let matched = matchedExercises.map { OrderedExercise(orderIndex: $0.orderIndex, exercise: $0.importedDraft) }
        let uncertain = uncertainMatches.map { OrderedExercise(orderIndex: $0.orderIndex, exercise: $0.importedDraft) }
        let unmatched = unmatchedItems.map { OrderedExercise(orderIndex: $0.orderIndex, exercise: $0.importedDraft) }

        return (matched + uncertain + unmatched)
            .sorted { lhs, rhs in
                if lhs.orderIndex == rhs.orderIndex {
                    return lhs.exercise.resolvedExerciseName.localizedCaseInsensitiveCompare(rhs.exercise.resolvedExerciseName) == .orderedAscending
                }

                return lhs.orderIndex < rhs.orderIndex
            }
            .map(\.exercise)
    }
}

private struct OrderedExercise {
    var orderIndex: Int
    var exercise: ImportedExerciseDraft
}

private extension AIWorkoutParsingExerciseMatch {
    var importedDraft: ImportedExerciseDraft {
        ImportedExerciseDraft(
            sourceText: sourceText,
            exerciseName: exerciseName,
            matchedExerciseName: exerciseName,
            matchCandidates: matchCandidates,
            setCount: setCount,
            repText: repText,
            notes: notes ?? "",
            restSeconds: restSeconds,
            intensityNotes: intensityNotes,
            confidence: confidence,
            isCustomExercise: false,
            customExercise: nil
        )
    }
}

private extension AIWorkoutParsingUnmatchedItem {
    var importedDraft: ImportedExerciseDraft {
        ImportedExerciseDraft(
            sourceText: sourceText,
            exerciseName: suggestedName,
            matchedExerciseName: nil,
            matchCandidates: matchCandidates,
            setCount: setCount,
            repText: repText,
            notes: notes ?? "",
            restSeconds: restSeconds,
            intensityNotes: intensityNotes,
            confidence: .low,
            isCustomExercise: true,
            customExercise: customExercise
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
