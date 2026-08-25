import Foundation

/// Static "Variations" selector for the exercise page: 2–3 related exercises
/// computed purely from the bundled library. No AI calls; deterministic;
/// verified by `harness/logic-checks/exercise-variations`.
///
/// Rules:
/// - Candidates share the movement pattern and overlap on at least one primary
///   muscle group, and differ in equipment OR difficulty (never the exercise
///   itself, by id or name).
/// - Ordering prefers same first primary muscle with different equipment, then
///   same equipment at an adjacent difficulty, then any different equipment,
///   then the rest; ties break on shared movement words in the name (so
///   "Barbell Bench Press" outranks an unrelated press for "Dumbbell Bench
///   Press"), then difficulty distance, then name, then id.
enum ExerciseVariations {

    static func variations(for exercise: Exercise, in library: [Exercise], limit: Int = 3) -> [Exercise] {
        guard limit > 0 else { return [] }

        let selfNameKey = exercise.name.lowercased()
        let selfGroups = Set(exercise.primaryMuscleGroups)
        let selfFirstMuscle = firstPrimaryMuscle(of: exercise)
        let selfTokens = movementNameTokens(exercise.name)

        let candidates = library.filter { candidate in
            candidate.id != exercise.id
                && candidate.name.lowercased() != selfNameKey
                && candidate.movementPattern == exercise.movementPattern
                && !selfGroups.isDisjoint(with: candidate.primaryMuscleGroups)
                && (candidate.equipment != exercise.equipment || candidate.difficulty != exercise.difficulty)
        }

        return candidates
            .map { candidate -> RankedCandidate in
                let differentEquipment = candidate.equipment != exercise.equipment
                let sameFirstMuscle = selfFirstMuscle != nil && firstPrimaryMuscle(of: candidate) == selfFirstMuscle
                let distance = difficultyDistance(exercise.difficulty, candidate.difficulty)

                let tier: Int
                if sameFirstMuscle && differentEquipment {
                    tier = 0
                } else if !differentEquipment && distance == 1 {
                    tier = 1
                } else if differentEquipment {
                    tier = 2
                } else {
                    tier = 3
                }

                return RankedCandidate(
                    exercise: candidate,
                    tier: tier,
                    sharedNameTokens: selfTokens.intersection(movementNameTokens(candidate.name)).count,
                    difficultyDistance: distance,
                    nameKey: candidate.name.lowercased()
                )
            }
            .sorted { lhs, rhs in
                if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
                if lhs.sharedNameTokens != rhs.sharedNameTokens { return lhs.sharedNameTokens > rhs.sharedNameTokens }
                if lhs.difficultyDistance != rhs.difficultyDistance { return lhs.difficultyDistance < rhs.difficultyDistance }
                if lhs.nameKey != rhs.nameKey { return lhs.nameKey < rhs.nameKey }
                return lhs.exercise.id < rhs.exercise.id
            }
            .prefix(limit)
            .map(\.exercise)
    }

    // MARK: - Helpers

    private struct RankedCandidate {
        let exercise: Exercise
        let tier: Int
        let sharedNameTokens: Int
        let difficultyDistance: Int
        let nameKey: String
    }

    /// Words that describe the implement or a generic qualifier, not the
    /// movement itself — excluded from the shared-name preference so
    /// "Dumbbell Bench Press" matches "Barbell Bench Press" on "bench press".
    private static let ignoredNameTokens: Set<String> = [
        "dumbbell", "barbell", "machine", "cable", "kettlebell", "band",
        "banded", "medicine", "ball", "bodyweight", "smith", "ez", "bar",
        "weighted", "with", "the", "and", "to", "a", "on", "alternating",
        "single", "double", "one", "two", "arm", "leg"
    ]

    /// The movement-describing words of an exercise name, lowercased.
    private static func movementNameTokens(_ name: String) -> Set<String> {
        let words = name.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
        return Set(words).subtracting(ignoredNameTokens)
    }

    /// The canonical first primary muscle, used as the "same primary muscle"
    /// preference (finer-grained than the muscle-group overlap requirement).
    private static func firstPrimaryMuscle(of exercise: Exercise) -> String? {
        guard let first = exercise.metadata.primaryMuscles.first else { return nil }
        let canonical = ExerciseMuscleRoles.canonicalMuscle(first)
        return canonical.isEmpty ? nil : canonical
    }

    private static func difficultyDistance(_ lhs: DifficultyLevel, _ rhs: DifficultyLevel) -> Int {
        let levels = DifficultyLevel.allCases
        guard let l = levels.firstIndex(of: lhs), let r = levels.firstIndex(of: rhs) else { return 0 }
        return abs(l - r)
    }
}
