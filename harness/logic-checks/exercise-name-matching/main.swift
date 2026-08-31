// Logic check: ExerciseNameMatcher resolution against the REAL bundled dataset.
// Added with the researched dataset expansion (+58 entries): pins that the new
// canonical names resolve for the queries they were added to catch, and that
// they do NOT steal resolutions that belong to pre-existing entries.
// Extended with the alias layer (ExerciseAliases): gym slang/abbreviations
// resolve, alias-table integrity is verified against the dataset, and the two
// normalizer fixes (-ches singularization, legged<->leg bridging) are pinned.
// Compiles against the REAL ExerciseNameMatcher/ExerciseAliases/
// ExerciseCSVLoader sources. Deterministic: read-only bundled dataset. No Date().
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

// MARK: - Alias layer (ExerciseAliases). The former "known alias gaps" INFO
// list is now asserted: every gap Agent 1 documented resolves through the
// alias table, plus the standard gym vocabulary the table carries.

print("-- alias layer: former gaps resolve --")
resolves("pec deck", to: "Machine Chest Fly")
resolves("Pec-Deck", to: "Machine Chest Fly")           // punctuation/case folded
resolves("pec deck machine", to: "Machine Chest Fly")
resolves("assault bike", to: "Air Bike")
resolves("airdyne", to: "Air Bike")
resolves("dips", to: "Parallel Bar Dip")
resolves("dip", to: "Parallel Bar Dip")
resolves("thruster", to: "Barbell thruster")
resolves("thrusters", to: "Barbell thruster")           // plural-tolerant keys
resolves("reverse fly", to: "Bent-over dumbbell rear delt fly")
resolves("reverse flys", to: "Bent-over dumbbell rear delt fly")
resolves("reverse flies", to: "Bent-over dumbbell rear delt fly")
resolves("reverse pec deck", to: "Machine Rear Delt Fly")
resolves("hex bar deadlift", to: "Trap Bar Deadlift")
resolves("shrugs", to: "Barbell Shrug")
resolves("hyperextension", to: "Back extension")
resolves("hyperextensions", to: "Back extension")
resolves("reverse hyper", to: "Reverse Hyperextension")
resolves("sl deadlift", to: "Single-Leg Romanian Deadlift")
resolves("single leg deadlift", to: "Single-Leg Romanian Deadlift")
resolves("side lunge", to: "Lateral Lunge")
resolves("woodchop", to: "Standing Cable Wood Chop")
resolves("wood chop", to: "Standing Cable Wood Chop")
resolves("woodchoppers", to: "Standing Cable Wood Chop")
resolves("ez bar skull crusher", to: "EZ-Bar Skullcrusher")
resolves("lying triceps extension", to: "Skull Crusher")
resolves("paused squat", to: "Pause Squat")
resolves("paused bench", to: "Pause Bench Press")

print("-- alias layer: standard gym vocabulary --")
resolves("bss", to: "Bulgarian Split Squat")
resolves("bulgarian", to: "Bulgarian Split Squat")
resolves("ghr", to: "Glute Ham Raise")
resolves("military press", to: "Standing Military Press")
resolves("chins", to: "Chin-Up")
resolves("lat raises", to: "Dumbbell Lateral Raise")
resolves("skullcrushers", to: "Skull Crusher")
resolves("french press", to: "Skull Crusher")
resolves("calf raises", to: "Standing Calf Raises")
resolves("hamstring curl", to: "Seated Leg Curl")
resolves("barbell row", to: "Barbell Bent-Over Row")
resolves("db row", to: "One-Arm Dumbbell Row")
resolves("front squat", to: "Barbell front squat")
resolves("front raise", to: "Dumbbell front raise")
resolves("upright row", to: "Barbell upright row")
resolves("sl rdl", to: "Single-Leg Romanian Deadlift")
resolves("erg", to: "Rowing Machine")
resolves("prowler", to: "Sled Push")
resolves("t2b", to: "Toes-to-Bar")
resolves("21s", to: "Bicep Curls \"21s\"")
resolves("deadlift", to: "Barbell Deadlift")
resolves("squat", to: "Back Squat")

print("-- vocabulary that already worked must keep working --")
resolves("good mornings", to: "Good Morning")
resolves("kb swing", to: "Kettlebell Swing")
resolves("hip thrusts", to: "Barbell Hip Thrust")

// MARK: - Abbreviation-expansion bridges (one-word <-> split spellings, dl)

print("-- expansion bridges --")
resolves("pullup", to: "Pull-Up")
resolves("pullups", to: "Pullups")   // exact dataset name still wins over the bridge
resolves("chinups", to: "Chin-Up")
resolves("situps", to: "Sit-Up")
resolves("pushup", to: "Push-Up")
resolves("neutral grip pullup", to: "Neutral-Grip Pull-Up")
resolves("diamond pushup", to: "Diamond push-up")
resolves("close grip pulldown", to: "Close-grip pull-down")
resolves("rope pushdown", to: "Cable rope push-down")
resolves("trap bar dl", to: "Trap Bar Deadlift")
resolves("sumo dl", to: "Sumo Deadlift")

// MARK: - Normalizer defect fixes

print("-- normalizer: -ches singularization --")
resolves("bicycle crunches", to: "Bicycle Crunch")
resolves("decline crunches", to: "Decline Crunch")
resolves("cable crunches", to: "Cable Seated Crunch")
resolves("snatches", to: "Snatch")

print("-- normalizer: legged<->leg bridging (second pass only) --")
resolves("stiff legged", to: "Stiff-Leg Deadlift")
resolves("single legged deadlift", to: "Single-Leg Romanian Deadlift")
resolves("one leg deadlift", to: "Kettlebell One-Legged Deadlift")
// The bridge must NOT steal exact-vocabulary resolutions that already worked:
resolves("db sldl", to: "Dumbbell Stiff-Leg Deadlift")
resolves("dumbbell stiff legged deadlift", to: "Stiff-Legged Dumbbell Deadlift")

// MARK: - Alias table integrity (checked against the REAL dataset, not by hand)

print("-- alias table integrity --")
var missingTargets: [String] = []
var unnormalizedKeys: [String] = []
for (alias, target) in ExerciseAliases.table {
    if library.exercise(named: target) == nil {
        missingTargets.append("\(alias) -> \(target)")
    }
    if ExerciseAliases.normalizedKey(for: alias) != alias {
        unnormalizedKeys.append(alias)
    }
}
check("every alias target exists in the library (\(ExerciseAliases.table.count) aliases)",
      missingTargets.isEmpty)
missingTargets.forEach { print("        missing: \($0)") }
check("every alias key is stored in normalized form", unnormalizedKeys.isEmpty)
unnormalizedKeys.forEach { print("        unnormalized: \($0)") }

let normalizedLibraryNames = Set(library.map { ExerciseAliases.normalizedKey(for: $0.name) })
let shadowingKeys = ExerciseAliases.table.keys.filter { normalizedLibraryNames.contains($0) }
check("no alias key shadows a real (normalized) exercise name", shadowingKeys.isEmpty)
shadowingKeys.forEach { print("        shadows: \($0)") }

check("alias table is generous (>= 100 entries)", ExerciseAliases.table.count >= 100)

print(failures == 0 ? "ALL CHECKS PASSED" : "CHECKS FAILED (\(failures))")
exit(failures == 0 ? 0 : 1)
