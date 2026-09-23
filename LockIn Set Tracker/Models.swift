import Foundation

struct RoutineImportedExercisePlan: Codable, Hashable, Identifiable {
    var id = UUID()
    var exerciseName: String
    var sourceText: String
    var targetSets: Int?
    var targetReps: String?
    var restSeconds: Int?
    var notes: String?
    var intensityNotes: [String]
    var matchedExerciseName: String?
    var isCustomExercise: Bool
    /// Load captured at import time (voice: "16 kg", "90"). Optional/defaulted
    /// so routines saved before weight capture still decode.
    var targetWeightText: String? = nil
}

struct RoutineImportContext: Codable, Hashable {
    var sourceKind: String
    var importedAt: Date
    var originalText: String
    var dayName: String?
    var exercisePlans: [RoutineImportedExercisePlan]
}

struct Routine: Identifiable, Codable {
    var id = UUID()
    var name: String
    var exercises: [String]
    var preferredSetCounts: [String: Int]
    var historyNames: [String]?
    var importContext: RoutineImportContext?
    /// Per-exercise adaptation state, keyed by exercise name.
    /// Optional so routines saved before the adaptation loop still decode. See M4.
    var progression: [String: ExerciseProgressionState]? = nil
    /// Optional membership in a `RoutineGroup` (e.g. filing rotating-split
    /// variants like "Chest A"/"Chest B" under one folder). Optional so
    /// routines saved before grouping existed still decode; nil == ungrouped.
    var groupID: UUID? = nil

    init(
        id: UUID = UUID(),
        name: String,
        exercises: [String],
        preferredSetCounts: [String: Int] = [:],
        historyNames: [String]? = nil,
        importContext: RoutineImportContext? = nil,
        groupID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.exercises = exercises
        self.preferredSetCounts = preferredSetCounts
        self.historyNames = Routine.normalizedNames(historyNames ?? [name])
        self.importContext = importContext
        self.groupID = groupID
    }

    func preferredSetCount(for exercise: String) -> Int {
        max(1, preferredSetCounts[exercise] ?? 3)
    }

    var allKnownNames: [String] {
        Routine.normalizedNames((historyNames ?? []) + [name])
    }

    private static func normalizedNames(_ names: [String]) -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []

        for name in names {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let key = trimmed.lowercased()
            if seen.insert(key).inserted {
                normalized.append(trimmed)
            }
        }

        return normalized
    }
}

/// A lightweight, purely organizational folder for routines — e.g. filing a
/// rotating split's day variants ("Chest A" / "Chest B") together. Deleting a
/// group never deletes the routines inside it; they fall back to ungrouped
/// (`Routine.groupID = nil`).
struct RoutineGroup: Identifiable, Codable, Equatable, Hashable {
    var id = UUID()
    var name: String
    /// Ascending sort order for rendering group sections; assigned at
    /// creation from the current max, so it survives deletions untouched.
    var order: Int

    init(id: UUID = UUID(), name: String, order: Int = 0) {
        self.id = id
        self.name = name
        self.order = order
    }
}

struct WorkoutSet: Codable, Equatable {
    var weight: String
    var reps: String
    /// Whether the user checked this set off in the logger. Optional so sessions
    /// saved before completion tracking still decode; those sets were logged by
    /// filling in numbers, so a missing flag counts as completed.
    var completed: Bool? = nil

    /// Single source of truth for "this set happened". Legacy sets (nil flag)
    /// count as completed; only an explicit `false` excludes a set.
    var isCompleted: Bool { completed ?? true }
}

struct WorkoutSession: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var routineID: UUID?
    var routineName: String
    var logs: [String: [WorkoutSet]]
    /// Post-session check-in answer that drives the adaptation loop.
    /// Optional so sessions saved before the loop still decode. See M4.
    var checkIn: SessionCheckIn? = nil
    /// Elapsed workout time captured from the logger timer at finish.
    /// Optional so sessions saved before duration tracking still decode.
    var durationSeconds: Int? = nil
    /// The order exercises were performed in — the logger's on-screen order
    /// at finish (mid-workout reorders and session-added exercises included).
    /// `logs` is a dictionary, so this is the only record of position.
    /// Optional so sessions saved before it existed still decode; those fall
    /// back to the routine's current order (`ExercisePositionLogic`).
    var exerciseOrder: [String]? = nil

    init(
        id: UUID = UUID(),
        date: Date,
        routineID: UUID? = nil,
        routineName: String,
        logs: [String: [WorkoutSet]],
        durationSeconds: Int? = nil,
        exerciseOrder: [String]? = nil
    ) {
        self.id = id
        self.date = date
        self.routineID = routineID
        self.routineName = routineName
        self.logs = logs
        self.durationSeconds = durationSeconds
        self.exerciseOrder = exerciseOrder
    }
}

// MARK: - Adaptation loop (spine §6)

/// How the last set of an exercise felt to the user. Drives the next session's
/// load/volume nudge within the same template (not a full replan).
enum CheckInOutcome: String, Codable, CaseIterable, Hashable, Identifiable {
    case tooEasy
    case aboutRight
    case tooHard

    var id: String { rawValue }

    /// Short user-facing label for the check-in UI.
    var label: String {
        switch self {
        case .tooEasy: return "Too easy"
        case .aboutRight: return "About right"
        case .tooHard: return "Too hard"
        }
    }
}

/// A short post-session check-in. Kept deliberately small so a real beginner
/// actually answers it every session (the riskiest assumption in the spine, §7).
struct SessionCheckIn: Codable, Hashable {
    /// Overall difficulty of the session.
    var overall: CheckInOutcome
    /// True if the user reported pain during the session. Pain flags route to a
    /// real check-in rather than silent auto-adjust (spine §6 safety branch).
    var hadPain: Bool
    /// Optional free-text describing the pain (e.g. "left knee on lunges").
    var painNote: String?
    /// Which exercise hurt, quick-picked from the session's exercises.
    /// Optional so check-ins recorded before M4's sheet still decode.
    var painExercise: String? = nil
    /// Optional per-exercise difficulty answers, keyed by exercise name.
    /// Absent means the user only answered at the session level.
    var perExercise: [String: CheckInOutcome]?
    /// When the check-in was recorded.
    var recordedAt: Date

    init(
        overall: CheckInOutcome,
        hadPain: Bool = false,
        painNote: String? = nil,
        painExercise: String? = nil,
        perExercise: [String: CheckInOutcome]? = nil,
        recordedAt: Date = Date()
    ) {
        self.overall = overall
        self.hadPain = hadPain
        self.painNote = painNote
        self.painExercise = painExercise
        self.perExercise = perExercise
        self.recordedAt = recordedAt
    }
}

/// Rolling adaptation state for a single exercise inside a routine. Updated after
/// each session so the next session can nudge load/volume within the same template.
struct ExerciseProgressionState: Codable, Hashable {
    /// Last weight the user logged for this exercise, as free text ("bodyweight",
    /// "40", etc.) to match how `WorkoutSet.weight` is stored.
    var lastWeight: String?
    /// Last rep count logged, as free text to match `WorkoutSet.reps`.
    var lastReps: String?
    /// Most recent check-in outcome for this exercise.
    var lastOutcome: CheckInOutcome?
    /// How many sessions in a row the user reported "too hard". A pattern here
    /// (or any pain flag) triggers a real check-in instead of silent adjustment.
    var consecutiveTooHard: Int
    /// Whether a pain flag is currently open against this exercise.
    var painFlagged: Bool
    /// When this state was last updated.
    var updatedAt: Date
    /// Applied next-session load target from an accepted nudge (free text with
    /// unit, e.g. "145 lb"). Optional so pre-M4 states still decode.
    var suggestedWeightText: String? = nil
    /// Applied next-session rep target from an accepted nudge (e.g. "8-10").
    var suggestedRepText: String? = nil
    /// One-line why for the applied nudge, surfaced in the logger next session.
    var nudgeNote: String? = nil

    init(
        lastWeight: String? = nil,
        lastReps: String? = nil,
        lastOutcome: CheckInOutcome? = nil,
        consecutiveTooHard: Int = 0,
        painFlagged: Bool = false,
        updatedAt: Date = Date(),
        suggestedWeightText: String? = nil,
        suggestedRepText: String? = nil,
        nudgeNote: String? = nil
    ) {
        self.lastWeight = lastWeight
        self.lastReps = lastReps
        self.lastOutcome = lastOutcome
        self.consecutiveTooHard = consecutiveTooHard
        self.painFlagged = painFlagged
        self.updatedAt = updatedAt
        self.suggestedWeightText = suggestedWeightText
        self.suggestedRepText = suggestedRepText
        self.nudgeNote = nudgeNote
    }

    /// True when the user needs a real check-in rather than a silent nudge
    /// (spine §6): repeated "too hard" or an open pain flag.
    var needsRealCheckIn: Bool {
        painFlagged || consecutiveTooHard >= 2
    }
}
