import Foundation

/// Static role clauses for the MUSCLES block on the exercise page.
///
/// Maps (movement pattern x muscle) to a short clause describing what that
/// muscle does in the lift — "drives knee extension", "flexes the elbows" —
/// derived purely from bundled metadata. No AI calls; deterministic; verified
/// by `harness/logic-checks/exercise-muscle-roles`.
enum ExerciseMuscleRoles {

    /// One display row per primary muscle: the raw muscle name from metadata
    /// plus its role clause. Duplicate roles (e.g. "chest" and "lower chest")
    /// collapse into the first-listed name so the block never repeats itself.
    static func primaryRoles(for exercise: Exercise) -> [(muscle: String, clause: String)] {
        var seen = Set<String>()
        var roles: [(muscle: String, clause: String)] = []

        for raw in exercise.metadata.primaryMuscles {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }

            let key = canonicalMuscle(name)
            guard seen.insert(key).inserted else { continue }

            roles.append((muscle: name, clause: clause(for: name, pattern: exercise.movementPattern)))
        }

        return roles
    }

    /// The role clause for one muscle in one movement pattern. Lookup order:
    /// pattern-specific entry, then muscle default, then a safe fallback.
    static func clause(for muscle: String, pattern: MovementPattern) -> String {
        let key = canonicalMuscle(muscle)

        if let specific = patternClauses[pattern]?[key] {
            return specific
        }

        if let general = defaultClauses[key] {
            return general
        }

        return "assists the movement"
    }

    /// Collapses the dataset's raw muscle spellings ("lower chest", "pecs",
    /// "front delts", "gastrocnemius") onto canonical keys.
    static func canonicalMuscle(_ raw: String) -> String {
        let name = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        switch name {
        case "chest", "lower chest", "upper chest", "mid chest", "pecs":
            return "chest"
        case "shoulders", "delts", "front delts":
            return "shoulders"
        case "lateral delts":
            return "lateral delts"
        case "rear delts":
            return "rear delts"
        case "triceps", "long head triceps":
            return "triceps"
        case "biceps", "brachialis":
            return "biceps"
        case "upper back", "mid back":
            return "upper back"
        case "traps", "upper traps":
            return "traps"
        case "abs", "core", "rectus abdominis", "transverse abdominis":
            return "core"
        case "calves", "gastrocnemius":
            return "calves"
        case "forearms", "grip":
            return "forearms"
        case "quads", "quadriceps":
            return "quads"
        case "hamstrings", "glutes", "lats", "spinal erectors", "adductors",
             "abductors", "neck", "legs", "arms", "full body":
            return name
        default:
            return name
        }
    }

    // MARK: - Clause tables

    /// Pattern-specific roles: what the muscle does in THIS movement.
    private static let patternClauses: [MovementPattern: [String: String]] = [
        .squat: [
            "quads": "drives knee extension",
            "glutes": "drives hip extension",
            "hamstrings": "stabilizes the hips and knees",
            "spinal erectors": "holds the spine rigid",
            "core": "braces the trunk",
            "calves": "steadies the ankles",
            "adductors": "assists hip extension",
            "legs": "drives the stand-up",
            "full body": "shares the load head to toe"
        ],
        .hinge: [
            "glutes": "drives hip extension",
            "hamstrings": "drives hip extension",
            "spinal erectors": "holds the spine rigid",
            "lats": "pins the load close to the body",
            "upper back": "keeps the upper back set",
            "traps": "supports the shoulders under load",
            "core": "braces the trunk",
            "quads": "starts the push off the floor",
            "forearms": "grips the load",
            "legs": "drives hip extension",
            "full body": "shares the load head to toe"
        ],
        .horizontalPush: [
            "chest": "primary mover pressing the load",
            "triceps": "extends the elbows",
            "shoulders": "assists the pressing drive",
            "core": "braces the trunk",
            "full body": "shares the load head to toe"
        ],
        .verticalPush: [
            "shoulders": "primary mover pressing overhead",
            "triceps": "locks out the elbows",
            "chest": "assists the pressing drive",
            "traps": "stabilizes the shoulder blades",
            "core": "braces the trunk upright",
            "full body": "shares the load head to toe"
        ],
        .horizontalPull: [
            "upper back": "squeezes the shoulder blades together",
            "lats": "pulls the elbows toward the hips",
            "biceps": "flexes the elbows",
            "rear delts": "pulls the arms back",
            "traps": "controls the shoulder blades",
            "forearms": "grips the load",
            "core": "braces the trunk",
            "full body": "shares the load head to toe"
        ],
        .verticalPull: [
            "lats": "primary mover pulling the elbows down",
            "upper back": "controls the shoulder blades",
            "biceps": "flexes the elbows",
            "forearms": "grips the bar",
            "core": "braces the trunk",
            "full body": "shares the load head to toe"
        ],
        .isolation: [
            "biceps": "flexes the elbows",
            "triceps": "extends the elbows",
            "quads": "extends the knees",
            "hamstrings": "flexes the knees",
            "calves": "lifts the heels",
            "glutes": "drives hip extension",
            "chest": "sweeps the arms together",
            "shoulders": "raises the arms",
            "lateral delts": "lifts the arms out to the side",
            "rear delts": "pulls the arms back",
            "traps": "elevates the shoulders",
            "core": "flexes and braces the trunk",
            "spinal erectors": "extends the spine",
            "forearms": "grips and controls the load",
            "upper back": "squeezes the shoulder blades together",
            "lats": "pulls the elbows down",
            "adductors": "squeezes the legs together",
            "abductors": "drives the legs apart",
            "full body": "shares the load head to toe"
        ]
    ]

    /// Muscle-only defaults for pattern gaps — joint-action phrasing that is
    /// true regardless of the lift.
    private static let defaultClauses: [String: String] = [
        "chest": "assists the pressing drive",
        "shoulders": "raises and steadies the arms",
        "lateral delts": "lifts the arms out to the side",
        "rear delts": "pulls the arms back",
        "triceps": "extends the elbows",
        "biceps": "flexes the elbows",
        "upper back": "controls the shoulder blades",
        "traps": "supports the shoulders under load",
        "lats": "pulls the elbows toward the body",
        "core": "braces the trunk",
        "spinal erectors": "holds the spine rigid",
        "quads": "extends the knees",
        "hamstrings": "drives hip extension",
        "glutes": "drives hip extension",
        "calves": "lifts the heels",
        "adductors": "squeezes the legs together",
        "abductors": "drives the legs apart",
        "forearms": "grips the load",
        "full body": "shares the load head to toe",
        // Dataset pseudo-muscles: stretches/SMR, conditioning work, neck moves.
        "mobility": "frees up range of motion",
        "conditioning": "sustains a high work rate",
        "neck": "moves the head against resistance"
    ]
}
