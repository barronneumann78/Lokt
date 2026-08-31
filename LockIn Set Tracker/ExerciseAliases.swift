import Foundation

/// Gym slang, abbreviations, and alternate names -> canonical library exercise
/// names. This is the vocabulary layer in front of `ExerciseNameMatcher`: an
/// alias hit wins before fuzzy token matching, and the Exercise Library search
/// surfaces alias targets while typing.
///
/// Rules for the table:
/// - Keys are stored in NORMALIZED form: lowercase, punctuation stripped,
///   each word singularized by `normalizedKey(for:)` (so "Lat Raises",
///   "lat-raise", and "lat raises" all land on the "lat raise" key). The
///   `exercise-name-matching` logic check asserts every key is its own
///   normalized form and that every value names a real dataset exercise.
/// - Only slang with ONE defensible target in THIS library is mapped.
///   Genuinely ambiguous slang (e.g. "db press", "kickbacks") is deliberately
///   absent - the fuzzy matcher or the user disambiguates.
/// - Values must match `exercises.json` names exactly (case included).
enum ExerciseAliases {
    static let table: [String: String] = [
        // MARK: Chest
        "pec deck": "Machine Chest Fly",
        "pec dec": "Machine Chest Fly",
        "pec deck fly": "Machine Chest Fly",
        "pec deck machine": "Machine Chest Fly",
        "chest fly": "Dumbbell chest fly",
        "chest flye": "Dumbbell chest fly",
        "bench": "Barbell Bench Press",
        "flat bench": "Barbell Bench Press",
        "flat bench press": "Barbell Bench Press",
        "incline bench": "Barbell Incline Bench Press - Medium Grip",
        "incline bench press": "Barbell Incline Bench Press - Medium Grip",
        "decline bench": "Decline Barbell Bench Press",
        "cgbp": "Close-grip bench press",
        "smith bench": "Smith Machine Bench Press",
        "hex press": "Dumbbell Crush Press",
        "squeeze press": "Dumbbell Crush Press",
        "crossover": "Cable Crossover",
        "dip": "Parallel Bar Dip",
        "tricep dip": "Parallel Bar Dip",

        // MARK: Shoulders
        "military press": "Standing Military Press",
        "seated military press": "Seated Barbell Overhead Press",
        "strict press": "Barbell Overhead Press",
        "standing press": "Barbell Overhead Press",
        "arnold": "Arnold press",
        "lat raise": "Dumbbell Lateral Raise",
        "front raise": "Dumbbell front raise",
        "rear delt row": "Bent-over dumbbell rear delt row",
        "reverse fly": "Bent-over dumbbell rear delt fly",
        "reverse flye": "Bent-over dumbbell rear delt fly",
        "bent over fly": "Bent-over dumbbell rear delt fly",
        "reverse pec deck": "Machine Rear Delt Fly",
        "reverse pec dec": "Machine Rear Delt Fly",
        "upright row": "Barbell upright row",
        "shrug": "Barbell Shrug",
        "shoulder shrug": "Barbell Shrug",
        "halo": "Dumbbell Halo",
        "windmill": "Kettlebell Windmill",
        "scaption": "Dumbbell Scaption",

        // MARK: Back
        "barbell row": "Barbell Bent-Over Row",
        "bb row": "Barbell Bent-Over Row",
        "db row": "One-Arm Dumbbell Row",
        "dumbbell row": "One-Arm Dumbbell Row",
        "low row": "Seated Cable Row",
        "pendlay": "Pendlay Row",
        "pullover": "Dumbbell Pullover",
        "chin": "Chin-Up",
        "australian pull up": "Inverted Row",
        "trx row": "Suspended Row",
        "scap pull up": "Scapular Pull-Up",
        "back raise": "Back extension",
        "hyperextension": "Back extension",
        "45 degree hyperextension": "45-Degree Back Extension",
        "reverse hyper": "Reverse Hyperextension",
        "superman hold": "Superman",

        // MARK: Arms
        "skullcrusher": "Skull Crusher",
        "ez bar skull crusher": "EZ-Bar Skullcrusher",
        "lying tricep extension": "Skull Crusher",
        "french press": "Skull Crusher",
        "pushdown": "Cable Triceps Pushdown",
        "cable curl": "Standing Biceps Cable Curl",
        "21": "Bicep Curls \"21s\"", // "21s" normalizes to "21"
        "zottman": "Zottman Curl",

        // MARK: Legs & glutes
        "squat": "Back Squat",
        "high bar squat": "Back Squat",
        "low bar squat": "Back Squat",
        "front squat": "Barbell front squat",
        "air squat": "Bodyweight Squat",
        "box squat": "Barbell Squat To A Box",
        "goblet": "Goblet Squat",
        "bss": "Bulgarian Split Squat",
        "bulgarian": "Bulgarian Split Squat",
        "zercher": "Zercher Squat",
        "ssb": "Safety Bar Squat",
        "ssb squat": "Safety Bar Squat",
        "cossack": "Cossack Squat",
        "paused squat": "Pause Squat",
        "leg press calf raise": "Calf Press On The Leg Press Machine",
        "lunge": "Forward lunge",
        "side lunge": "Lateral Lunge",
        "deadlift": "Barbell Deadlift",
        "conventional deadlift": "Barbell Deadlift",
        "hex bar deadlift": "Trap Bar Deadlift",
        "hexbar deadlift": "Trap Bar Deadlift",
        "sl deadlift": "Single-Leg Romanian Deadlift",
        "single leg deadlift": "Single-Leg Romanian Deadlift",
        "sl rdl": "Single-Leg Romanian Deadlift",
        "hamstring curl": "Seated Leg Curl",
        "ham curl": "Seated Leg Curl",
        "seated hamstring curl": "Seated Leg Curl",
        "nordic": "Nordic Hamstring Curl",
        "ghr": "Glute Ham Raise",
        "quad extension": "Leg Extension",
        "calf raise": "Standing Calf Raises",
        "toe raise": "Tibialis Raise",
        "tib raise": "Tibialis Raise",
        "glute drive": "Machine Hip Thrust",
        "hip bridge": "Glute bridge",
        "abductor": "Machine Hip Abduction",
        "abductor machine": "Machine Hip Abduction",
        "hip abductor": "Machine Hip Abduction",
        "outer thigh machine": "Machine Hip Abduction",
        "adductor": "Machine Hip Adduction",
        "adductor machine": "Machine Hip Adduction",
        "hip adductor": "Machine Hip Adduction",
        "inner thigh machine": "Machine Hip Adduction",

        // MARK: Core
        "rollout": "Ab Wheel Rollout",
        "deadbug": "Dead bug reach",
        "woodchop": "Standing Cable Wood Chop",
        "wood chop": "Standing Cable Wood Chop",
        "woodchopper": "Standing Cable Wood Chop",
        "cable woodchop": "Standing Cable Wood Chop",
        "cable wood chop": "Standing Cable Wood Chop",
        "hollow body": "Hollow Hold",
        "t2b": "Toes-to-Bar",
        "ttb": "Toes-to-Bar",
        "copenhagen": "Copenhagen plank",

        // MARK: Conditioning & carries
        "assault bike": "Air Bike",
        "airdyne": "Air Bike",
        "fan bike": "Air Bike",
        "echo bike": "Air Bike",
        "bike": "Bicycling",
        "stationary bike": "Bicycling",
        "cycling": "Bicycling",
        "treadmill": "Treadmill Run",
        "running": "Treadmill Run",
        "run": "Treadmill Run",
        "rower": "Rowing Machine",
        "erg": "Rowing Machine",
        "row machine": "Rowing Machine",
        "rowing": "Rowing Machine",
        "elliptical": "Elliptical Trainer",
        "stair climber": "Stairmaster",
        "stairclimber": "Stairmaster",
        "stepmill": "Stairmaster",
        "skipping rope": "Jump Rope",
        "prowler": "Sled Push",
        "prowler push": "Sled Push",
        "farmer walk": "Farmer's Carry",
        "yoke": "Yoke Walk",
        "log press": "Log Lift",
        "tgu": "Dumbbell Fix Turkish Get-Up",
        "man maker": "Dumbbell Fix Full Man Maker",
        "thruster": "Barbell thruster",
        "paused bench": "Pause Bench Press",
        "paused bench press": "Pause Bench Press",
        "pause bench": "Pause Bench Press"
    ]

    /// Canonical library name for an alias, or nil when the text is not a
    /// known alias. Lookup is tolerant of case, punctuation, and plurals.
    static func canonicalName(for text: String) -> String? {
        let key = normalizedKey(for: text)
        guard !key.isEmpty else { return nil }
        return table[key]
    }

    /// Canonical names whose alias key starts with the (normalized) text.
    /// Powers the Exercise Library search while the user is still typing
    /// ("pec de" already surfaces Machine Chest Fly). The table is small, so a
    /// linear scan per keystroke is cheap.
    static func canonicalNames(matchingPrefix text: String) -> Set<String> {
        let key = normalizedKey(for: text)
        guard !key.isEmpty else { return [] }

        var hits: Set<String> = []
        for (alias, canonical) in table where alias.hasPrefix(key) {
            hits.insert(canonical)
        }
        return hits
    }

    /// Lookup-key normalization: lowercase, split on anything that is not a
    /// letter or digit, singularize each word, rejoin with single spaces.
    static func normalizedKey(for text: String) -> String {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .map(singularizedKeyWord)
            .joined(separator: " ")
    }

    /// Case/punctuation folding WITHOUT singularization, for substring search
    /// ("chin up" must match "Chin-Up"). Precompute once per library, never
    /// per keystroke per exercise.
    static func searchFold(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func singularizedKeyWord(_ word: String) -> String {
        if word.hasSuffix("sses") {                             // presses -> press
            return String(word.dropLast(2))
        }
        if word.hasSuffix("ches") || word.hasSuffix("shes") {   // crunches -> crunch
            return String(word.dropLast(2))
        }
        if word.count > 4, word.hasSuffix("ies") {              // flies -> fly
            return String(word.dropLast(3)) + "y"
        }
        if word.hasSuffix("ss") || word.count <= 2 {
            return word
        }
        if word.hasSuffix("s") {
            return String(word.dropLast())
        }
        return word
    }
}
