import Foundation

/// Identifies one numeric cell in the workout logger grid: (exercise, set
/// index, weight|reps). The single focus coordinate shared by the logger's
/// focus state, the set rows, and the keyboard toolbar's Next advance.
enum LoggerField: Hashable {
    case weight(String, Int)
    case reps(String, Int)

    var exercise: String {
        switch self {
        case let .weight(exercise, _), let .reps(exercise, _):
            return exercise
        }
    }

    var setIndex: Int {
        switch self {
        case let .weight(_, index), let .reps(_, index):
            return index
        }
    }

    var kind: LoggerFieldKind {
        switch self {
        case .weight: return .weight
        case .reps: return .reps
        }
    }
}

/// Which cell of a set row a field lives in.
enum LoggerFieldKind: Hashable {
    case weight
    case reps
}

/// Pure focus-advance logic: Next walks weight → reps → next set's weight →
/// next exercise's first set, skipping nothing, and returns nil only past the
/// last reps cell of the last exercise (where Next becomes Done).
enum LoggerFocusModel {
    static func nextField(
        after field: LoggerField,
        exercises: [String],
        setCount: (String) -> Int
    ) -> LoggerField? {
        switch field {
        case let .weight(exercise, set):
            return .reps(exercise, set)

        case let .reps(exercise, set):
            guard let exerciseIndex = exercises.firstIndex(of: exercise) else {
                return nil
            }

            if set + 1 < setCount(exercise) {
                return .weight(exercise, set + 1)
            }

            let nextExerciseIndex = exerciseIndex + 1
            guard exercises.indices.contains(nextExerciseIndex) else {
                return nil
            }

            return .weight(exercises[nextExerciseIndex], 0)
        }
    }

    /// True exactly when `nextField` would return nil for this field — the
    /// reps cell of the last set of the last exercise (its Next reads Done).
    static func isFinalField(
        _ field: LoggerField,
        exercises: [String],
        setCount: (String) -> Int
    ) -> Bool {
        nextField(after: field, exercises: exercises, setCount: setCount) == nil
    }

    /// The set the pinned COMPLETE SET pill acts on — the same "active" set
    /// the table highlights: the first incomplete set walking exercises in
    /// order. `isCompleted` answers for (exercise, set index); a set the logs
    /// haven't padded yet is simply incomplete. nil once every set is checked
    /// (the pill then reads WRAP UP).
    static func completionTarget(
        exercises: [String],
        setCount: (String) -> Int,
        isCompleted: (String, Int) -> Bool
    ) -> (exercise: String, setIndex: Int)? {
        for exercise in exercises {
            for index in 0..<max(1, setCount(exercise)) where !isCompleted(exercise, index) {
                return (exercise, index)
            }
        }
        return nil
    }

    /// Where focus lands after COMPLETE SET checks (exercise, setIndex) with
    /// the keyboard up: exactly the walk Next takes from that set's reps cell —
    /// the next set's weight, then the next exercise's first weight, nil past
    /// the last set of the last exercise (focus stays put; Done dismisses).
    static func fieldAfterCompleting(
        exercise: String,
        setIndex: Int,
        exercises: [String],
        setCount: (String) -> Int
    ) -> LoggerField? {
        nextField(after: .reps(exercise, setIndex), exercises: exercises, setCount: setCount)
    }
}
