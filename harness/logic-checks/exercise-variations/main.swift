// Logic check: ExerciseVariations selector.
// Compiles against the REAL ExerciseCSVLoader/ExerciseVariations sources.
// Deterministic: fixed fixtures + the read-only bundled dataset. No Date().
import Foundation

// MARK: - Stubs for symbols ExerciseCSVLoader.swift references (UI/app-only)

enum ExerciseMediaCatalog {
    static func imageName(for exerciseName: String) -> String? { nil }
}

enum CustomExerciseLibrary {
    static func loadExercises() -> [Exercise] { [] }
}

enum ExerciseNameMatcher {
    static func invalidateCache() {}
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

// MARK: - Fixture factory

func makeExercise(
    id: String,
    name: String,
    pattern: MovementPattern,
    groups: [PrimaryMuscleGroup],
    equipment: EquipmentType,
    difficulty: DifficultyLevel,
    primaryMuscles: [String] = []
) -> Exercise {
    Exercise(
        id: id,
        name: name,
        muscleGroup: .other,
        equipment: equipment,
        movementPattern: pattern,
        primaryMuscleGroups: groups,
        difficulty: difficulty,
        instructions: "",
        imageName: nil,
        metadata: ExerciseMetadata(
            primaryMuscles: primaryMuscles,
            secondaryMuscles: [],
            movementPattern: "",
            equipment: [],
            difficulty: difficulty.rawValue,
            mechanic: "compound",
            forceType: "",
            laterality: "",
            bodyRegion: "",
            trainingGoal: [],
            exerciseType: "",
            gripType: nil,
            stance: nil,
            planeOfMotion: "",
            tags: []
        ),
        description: "",
        howTo: [],
        cues: []
    )
}

// MARK: - Synthetic fixtures

let base = makeExercise(id: "base", name: "Barbell Box Squat", pattern: .squat, groups: [.legs], equipment: .barbell, difficulty: .intermediate, primaryMuscles: ["quads"])

let sameMuscleDiffEquip = makeExercise(id: "a", name: "Dumbbell Goblet Squat", pattern: .squat, groups: [.legs], equipment: .dumbbell, difficulty: .beginner, primaryMuscles: ["quads"])
let sameEquipAdjacent = makeExercise(id: "b", name: "Barbell Front Squat", pattern: .squat, groups: [.legs], equipment: .barbell, difficulty: .advanced, primaryMuscles: ["quads"])
let otherMuscleDiffEquip = makeExercise(id: "c", name: "Kettlebell Squat", pattern: .squat, groups: [.legs], equipment: .kettlebell, difficulty: .intermediate, primaryMuscles: ["glutes"])
let sameEquipAdjacentLater = makeExercise(id: "d", name: "Barbell Pause Squat", pattern: .squat, groups: [.legs], equipment: .barbell, difficulty: .beginner, primaryMuscles: ["quads"])
let identicalTwin = makeExercise(id: "e", name: "Barbell Low-Bar Squat", pattern: .squat, groups: [.legs], equipment: .barbell, difficulty: .intermediate, primaryMuscles: ["quads"])
let wrongPattern = makeExercise(id: "f", name: "Romanian Deadlift", pattern: .hinge, groups: [.legs], equipment: .dumbbell, difficulty: .beginner, primaryMuscles: ["hamstrings"])
let wrongGroup = makeExercise(id: "g", name: "Machine Chest Press", pattern: .squat, groups: [.chest], equipment: .machine, difficulty: .beginner, primaryMuscles: ["chest"])
let sameNameDifferentID = makeExercise(id: "h", name: "barbell box squat", pattern: .squat, groups: [.legs], equipment: .machine, difficulty: .beginner, primaryMuscles: ["quads"])

let fixtureLibrary = [base, sameMuscleDiffEquip, sameEquipAdjacent, otherMuscleDiffEquip, sameEquipAdjacentLater, identicalTwin, wrongPattern, wrongGroup, sameNameDifferentID]

print("== exercise-variations logic check ==")
print("-- fixtures --")

let picks = ExerciseVariations.variations(for: base, in: fixtureLibrary)

check("returns at most 3", picks.count <= 3)
check("never returns self by id", !picks.contains { $0.id == base.id })
check("never returns a same-name duplicate", !picks.contains { $0.id == "h" })
check("excludes other movement patterns", !picks.contains { $0.id == "f" })
check("excludes non-overlapping muscle groups", !picks.contains { $0.id == "g" })
check("excludes same equipment + same difficulty", !picks.contains { $0.id == "e" })
check("tier 0 first: same first muscle + different equipment", picks.first?.id == "a")
check("tier 1 next: same equipment + adjacent difficulty, name-ordered", picks.count > 2 && picks[1].id == "b" && picks[2].id == "d")
check("tier 2 (diff equipment, diff first muscle) loses to tier 1", !picks.contains { $0.id == "c" })

// Tier 2 vs tier 3, from a beginner base so a difficulty distance of 2 exists.
let beginnerBase = makeExercise(id: "bb", name: "Beginner Barbell Squat", pattern: .squat, groups: [.legs], equipment: .barbell, difficulty: .beginner, primaryMuscles: ["quads"])
let tier2Pick = makeExercise(id: "t2p", name: "Kettlebell Glute Squat", pattern: .squat, groups: [.legs], equipment: .kettlebell, difficulty: .beginner, primaryMuscles: ["glutes"])
let tier3Pick = makeExercise(id: "t3p", name: "Advanced Barbell Squat", pattern: .squat, groups: [.legs], equipment: .barbell, difficulty: .advanced, primaryMuscles: ["quads"])
let tierPicks = ExerciseVariations.variations(for: beginnerBase, in: [beginnerBase, tier3Pick, tier2Pick])
check("tier 2 beats tier 3 (same equipment, distance-2 difficulty)", tierPicks.map(\.id) == ["t2p", "t3p"])

// Shared movement words beat alphabetical order inside a tier: for a bench
// press, a differently-equipped bench press outranks an unrelated chest move.
let bench = makeExercise(id: "bp", name: "Dumbbell Bench Press", pattern: .horizontalPush, groups: [.chest], equipment: .dumbbell, difficulty: .intermediate, primaryMuscles: ["chest"])
let benchCousin = makeExercise(id: "bp1", name: "Barbell Bench Press", pattern: .horizontalPush, groups: [.chest], equipment: .barbell, difficulty: .intermediate, primaryMuscles: ["chest"])
let unrelatedName = makeExercise(id: "bp2", name: "Alligator Crawl", pattern: .horizontalPush, groups: [.chest], equipment: .bodyweight, difficulty: .intermediate, primaryMuscles: ["chest"])
let benchPicks2 = ExerciseVariations.variations(for: bench, in: [bench, unrelatedName, benchCousin])
check("shared movement words outrank alphabetical order", benchPicks2.map(\.id) == ["bp1", "bp2"])

// Name tie-break inside one tier: two tier-0 candidates differing only by name.
let tieA = makeExercise(id: "t1", name: "Zebra Squat", pattern: .squat, groups: [.legs], equipment: .dumbbell, difficulty: .intermediate, primaryMuscles: ["quads"])
let tieB = makeExercise(id: "t2", name: "Alpha Squat", pattern: .squat, groups: [.legs], equipment: .dumbbell, difficulty: .intermediate, primaryMuscles: ["quads"])
let tiePicks = ExerciseVariations.variations(for: base, in: [base, tieA, tieB])
check("stable name tie-break within a tier", tiePicks.map(\.id) == ["t2", "t1"])

// Determinism: input order must not change the result.
let shuffled: [Exercise] = [sameEquipAdjacentLater, wrongGroup, identicalTwin, sameMuscleDiffEquip, wrongPattern, base, sameNameDifferentID, otherMuscleDiffEquip, sameEquipAdjacent]
check("order-independent (deterministic)", ExerciseVariations.variations(for: base, in: shuffled).map(\.id) == picks.map(\.id))

// No matches → empty (section hides).
let loner = makeExercise(id: "z", name: "Neck Harness Curl", pattern: .isolation, groups: [.shoulders], equipment: .other, difficulty: .advanced, primaryMuscles: ["neck"])
check("no good match returns empty", ExerciseVariations.variations(for: loner, in: fixtureLibrary + [loner]).isEmpty)

check("limit parameter respected", ExerciseVariations.variations(for: base, in: fixtureLibrary, limit: 1).count == 1)
check("limit zero returns empty", ExerciseVariations.variations(for: base, in: fixtureLibrary, limit: 0).isEmpty)

// MARK: - Real-dataset property sweep (dataset is read-only and guarded by checks.sh)

print("-- real dataset --")

let datasetURL = URL(fileURLWithPath: "LockIn Set Tracker/exercises.json")
guard let data = try? Data(contentsOf: datasetURL),
      let library = try? JSONDecoder().decode([Exercise].self, from: data) else {
    print("  FAIL  could not load LockIn Set Tracker/exercises.json (run from repo root)")
    exit(1)
}

check("bundled library decodes (1036 exercises)", library.count == 1036)

var violations: [String] = []
var withVariations = 0
for exercise in library {
    let result = ExerciseVariations.variations(for: exercise, in: library)
    if !result.isEmpty { withVariations += 1 }
    if result.count > 3 { violations.append("\(exercise.name): >3 results") }
    for pick in result {
        if pick.id == exercise.id { violations.append("\(exercise.name): returned self") }
        if pick.name.lowercased() == exercise.name.lowercased() { violations.append("\(exercise.name): same-name pick") }
        if pick.movementPattern != exercise.movementPattern { violations.append("\(exercise.name): pattern mismatch") }
        if Set(pick.primaryMuscleGroups).isDisjoint(with: exercise.primaryMuscleGroups) { violations.append("\(exercise.name): no muscle-group overlap") }
        if pick.equipment == exercise.equipment && pick.difficulty == exercise.difficulty { violations.append("\(exercise.name): no equipment/difficulty difference") }
    }
}
check("invariants hold across all \(library.count) exercises", violations.isEmpty)
if !violations.isEmpty { violations.prefix(5).forEach { print("        \($0)") } }
print("  INFO  \(withVariations)/\(library.count) exercises get at least one variation")

// Pinned real selections (stable: dataset is read-only).
func names(for exerciseName: String) -> [String] {
    guard let exercise = library.first(where: { $0.name == exerciseName }) else { return ["<missing: \(exerciseName)>"] }
    return ExerciseVariations.variations(for: exercise, in: library).map(\.name)
}

let squatPicks = names(for: "Barbell Full Squat")
check("Barbell Full Squat gets 3 non-barbell quad variations", squatPicks.count == 3 && !squatPicks.contains { $0.localizedCaseInsensitiveContains("barbell") })

let benchPicks = names(for: "Dumbbell Bench Press")
check("Dumbbell Bench Press gets 3 chest variations, none dumbbell-named self-dupes", benchPicks.count == 3 && !benchPicks.contains("Dumbbell Bench Press"))
check("Dumbbell Bench Press picks are actual bench presses", benchPicks.allSatisfy { $0.localizedCaseInsensitiveContains("bench press") })
print("  INFO  Barbell Full Squat -> \(squatPicks.joined(separator: " | "))")
print("  INFO  Dumbbell Bench Press -> \(benchPicks.joined(separator: " | "))")

print(failures == 0 ? "ALL CHECKS PASSED" : "CHECKS FAILED (\(failures))")
exit(failures == 0 ? 0 : 1)
