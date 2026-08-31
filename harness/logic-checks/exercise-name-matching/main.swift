// Logic check: ExerciseNameMatcher resolution against the REAL bundled dataset.
// Added with the researched dataset expansion (+58 entries): pins that the new
// canonical names resolve for the queries they were added to catch, and that
// they do NOT steal resolutions that belong to pre-existing entries.
// Compiles against the REAL ExerciseNameMatcher/ExerciseCSVLoader sources.
// Deterministic: the read-only bundled dataset. No Date().
import Foundation

// MARK: - Stubs for symbols ExerciseCSVLoader.swift references (UI/app-only)

enum ExerciseMediaCatalog {
    static func imageName(for exerciseName: String) -> String? { nil }
}

enum CustomExerciseLibrary {
    static func loadExercises() -> [Exercise] { [] }
}

// `exercise(named:)` ships in ExerciseDetailView.swift (SwiftUI, not compilable
// here); this mirror must stay byte-for-byte equivalent to that implementation.
extension Array where Element == Exercise {
    func exercise(named name: String) -> Exercise? {
        first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
}

// MARK: - Check plumbing

var failures = 0
func check(_ name: String, _ condition: Bool) {
    if condition {
        print("  PASS  \(name)")
    } else {
        print("  FAIL  \(name)")
        failures += 1
    }
}

print("== exercise-name-matching logic check ==")

let datasetURL = URL(fileURLWithPath: "LockIn Set Tracker/exercises.json")
guard let data = try? Data(contentsOf: datasetURL),
      let library = try? JSONDecoder().decode([Exercise].self, from: data) else {
    print("  FAIL  could not load LockIn Set Tracker/exercises.json (run from repo root)")
    exit(1)
}

check("bundled library decodes (1094 exercises)", library.count == 1094)

func resolves(_ query: String, to expected: String) {
    let hit = library.resolvedExercise(named: query)
    check("\"\(query)\" -> \(expected)", hit?.name == expected)
    if let hit, hit.name != expected {
        print("        actually resolved to: \(hit.name)")
    }
}

// MARK: - New canonical names catch the queries they were added for

print("-- expansion entries resolve --")
resolves("sldl", to: "Stiff-Leg Deadlift")
resolves("SLDL", to: "Stiff-Leg Deadlift")
resolves("stiff leg deadlift", to: "Stiff-Leg Deadlift")
resolves("db sldl", to: "Dumbbell Stiff-Leg Deadlift")
resolves("dumbbell stiff leg deadlift", to: "Dumbbell Stiff-Leg Deadlift")
resolves("trap bar deadlift", to: "Trap Bar Deadlift")
resolves("kb deadlift", to: "Kettlebell Deadlift")
resolves("single leg rdl", to: "Single-Leg Romanian Deadlift")
resolves("nordic curl", to: "Nordic Hamstring Curl")
resolves("machine hip thrust", to: "Machine Hip Thrust")
resolves("zercher squat", to: "Zercher Squat")
resolves("pause squat", to: "Pause Squat")
resolves("wall sit", to: "Wall Sit")
resolves("hip abduction machine", to: "Machine Hip Abduction")
resolves("pause bench press", to: "Pause Bench Press")
resolves("machine chest fly", to: "Machine Chest Fly")
resolves("machine lateral raise", to: "Machine Lateral Raise")
resolves("landmine press", to: "Landmine Press")
resolves("z press", to: "Z Press")
resolves("seated overhead press", to: "Seated Barbell Overhead Press")
resolves("pendlay row", to: "Pendlay Row")
resolves("t bar row", to: "T-Bar Row")
resolves("chest supported row", to: "Chest-Supported Dumbbell Row")
resolves("machine row", to: "Seated Machine Row")
resolves("wide grip lat pulldown", to: "Wide-Grip Lat Pulldown")
resolves("dumbbell shrug", to: "Dumbbell Shrug")
resolves("dumbbell pullover", to: "Dumbbell Pullover")
resolves("dead hang", to: "Dead Hang")
resolves("skull crushers", to: "Skull Crusher")
resolves("zottman curl", to: "Zottman Curl")
resolves("side plank", to: "Side Plank")
resolves("bicycle crunch", to: "Bicycle Crunch")
resolves("hollow body hold", to: "Hollow Hold")
resolves("superman", to: "Superman")
resolves("toes to bar", to: "Toes-to-Bar")
resolves("l-sit", to: "L-Sit")
resolves("snatch", to: "Snatch")
resolves("wall balls", to: "Wall Ball Shot")
resolves("rowing machine", to: "Rowing Machine")
resolves("jump rope", to: "Jump Rope")
resolves("treadmill run", to: "Treadmill Run")
resolves("couch stretch", to: "Couch Stretch")
resolves("cable glute kickback", to: "Cable Glute Kickback")
resolves("tibialis raise", to: "Tibialis Raise")

// MARK: - Pre-existing resolutions must NOT be stolen by the new entries

print("-- no stealing from existing entries --")
resolves("rdl", to: "Romanian Deadlift")
resolves("romanian deadlift", to: "Romanian Deadlift")
resolves("dumbbell rdl", to: "Romanian Deadlift")
resolves("hip thrust", to: "Barbell Hip Thrust")
resolves("back extension", to: "Back extension")
resolves("overhead press", to: "Barbell Overhead Press")
resolves("ohp", to: "Barbell Overhead Press")
resolves("military press", to: "Standing Military Press")
resolves("lateral raise", to: "Dumbbell Lateral Raise")
resolves("seated row", to: "Seated Cable Row")
resolves("machine upright row", to: "Smith Machine Upright Row")
resolves("lat pulldown", to: "Lat Pulldown")
resolves("lying t-bar row", to: "Lying T-Bar Row")
resolves("leg curl", to: "Seated Leg Curl")
resolves("plank", to: "Plank")
resolves("power snatch", to: "Power Snatch")
resolves("cable crossover", to: "Cable Crossover")
resolves("ez bar skullcrusher", to: "EZ-Bar Skullcrusher")
resolves("glute bridge", to: "Glute bridge")
check("\"bench press\" still resolves to an original bench press",
      { let n = library.resolvedExercise(named: "bench press")?.name
        return n != nil && n != "Pause Bench Press" }())

// MARK: - Known alias gaps (single tokens / vocab the matcher cannot bridge).
// Not assertions: documented for the alias layer (Agent 2). If these start
// resolving, aliases landed - update this note.

print("-- known alias gaps (informational) --")
for gap in ["pec deck", "assault bike", "dips", "thruster", "reverse fly",
            "hex bar deadlift", "shrugs", "hyperextension", "sl deadlift"] {
    let hit = library.resolvedExercise(named: gap)
    print("  INFO  \"\(gap)\" -> \(hit?.name ?? "nil (needs alias)")")
}

print(failures == 0 ? "ALL CHECKS PASSED" : "CHECKS FAILED (\(failures))")
exit(failures == 0 ? 0 : 1)
