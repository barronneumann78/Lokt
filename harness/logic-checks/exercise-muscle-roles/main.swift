// Logic check: ExerciseMuscleRoles clause mapper.
// Compiles against the REAL ExerciseCSVLoader/ExerciseMuscleRoles sources.
// Deterministic: fixed inputs + the read-only bundled dataset. No Date().
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

print("== exercise-muscle-roles logic check ==")
print("-- clause table --")

// The task's canonical examples.
check("squat + quads -> knee extension", ExerciseMuscleRoles.clause(for: "quads", pattern: .squat) == "drives knee extension")
check("hinge + glutes -> hip extension", ExerciseMuscleRoles.clause(for: "glutes", pattern: .hinge) == "drives hip extension")
check("hinge + hamstrings -> hip extension", ExerciseMuscleRoles.clause(for: "hamstrings", pattern: .hinge) == "drives hip extension")
check("horizontal push + chest -> primary mover", ExerciseMuscleRoles.clause(for: "chest", pattern: .horizontalPush) == "primary mover pressing the load")
check("horizontal push + triceps -> extends the elbows", ExerciseMuscleRoles.clause(for: "triceps", pattern: .horizontalPush) == "extends the elbows")

// Pattern-specific vs default resolution.
check("vertical pull + lats is pattern-specific", ExerciseMuscleRoles.clause(for: "lats", pattern: .verticalPull) == "primary mover pulling the elbows down")
check("isolation + biceps -> flexes the elbows", ExerciseMuscleRoles.clause(for: "biceps", pattern: .isolation) == "flexes the elbows")
check("pattern gap falls back to muscle default (squat + biceps)", ExerciseMuscleRoles.clause(for: "biceps", pattern: .squat) == "flexes the elbows")
check("unknown muscle falls back to generic clause", ExerciseMuscleRoles.clause(for: "mystery muscle", pattern: .squat) == "assists the movement")

// Canonicalization of dataset spellings.
check("pecs canonicalizes to chest", ExerciseMuscleRoles.canonicalMuscle("pecs") == "chest")
check("lower chest canonicalizes to chest", ExerciseMuscleRoles.canonicalMuscle("lower chest") == "chest")
check("gastrocnemius canonicalizes to calves", ExerciseMuscleRoles.canonicalMuscle("gastrocnemius") == "calves")
check("rectus abdominis canonicalizes to core", ExerciseMuscleRoles.canonicalMuscle("Rectus Abdominis") == "core")
check("canonicalization is case/whitespace tolerant", ExerciseMuscleRoles.canonicalMuscle("  Upper Back ") == "upper back")
check("pecs gets the chest clause on a push", ExerciseMuscleRoles.clause(for: "pecs", pattern: .horizontalPush) == "primary mover pressing the load")

// MARK: - primaryRoles on a fixture

func makeExercise(name: String, pattern: MovementPattern, primaryMuscles: [String]) -> Exercise {
    Exercise(
        id: name.lowercased(),
        name: name,
        muscleGroup: .other,
        equipment: .barbell,
        movementPattern: pattern,
        primaryMuscleGroups: [.legs],
        difficulty: .intermediate,
        instructions: "",
        imageName: nil,
        metadata: ExerciseMetadata(
            primaryMuscles: primaryMuscles,
            secondaryMuscles: [],
            movementPattern: "",
            equipment: [],
            difficulty: "Intermediate",
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

print("-- primaryRoles --")

let deadlift = makeExercise(name: "Deadlift", pattern: .hinge, primaryMuscles: ["glutes", "hamstrings", "spinal erectors"])
let deadliftRoles = ExerciseMuscleRoles.primaryRoles(for: deadlift)
check("one row per primary muscle, in metadata order", deadliftRoles.map(\.muscle) == ["glutes", "hamstrings", "spinal erectors"])
check("deadlift erectors hold the spine rigid", deadliftRoles.last?.clause == "holds the spine rigid")

let dupes = makeExercise(name: "Weird Press", pattern: .horizontalPush, primaryMuscles: ["chest", "pecs", "lower chest", "triceps"])
let dupeRoles = ExerciseMuscleRoles.primaryRoles(for: dupes)
check("canonical duplicates collapse to the first spelling", dupeRoles.map(\.muscle) == ["chest", "triceps"])

let blank = makeExercise(name: "Blank", pattern: .isolation, primaryMuscles: ["", "  ", "abs"])
check("blank muscle names are dropped", ExerciseMuscleRoles.primaryRoles(for: blank).map(\.muscle) == ["abs"])

// MARK: - Real-dataset coverage sweep (dataset is read-only and guarded by checks.sh)

print("-- real dataset --")

let datasetURL = URL(fileURLWithPath: "LockIn Set Tracker/exercises.json")
guard let data = try? Data(contentsOf: datasetURL),
      let library = try? JSONDecoder().decode([Exercise].self, from: data) else {
    print("  FAIL  could not load LockIn Set Tracker/exercises.json (run from repo root)")
    exit(1)
}

check("bundled library decodes (1036 exercises)", library.count == 1036)

var totalRows = 0
var fallbackRows = 0
var fallbackMuscles: [String: Int] = [:]
var emptyRoleExercises = 0
for exercise in library {
    let roles = ExerciseMuscleRoles.primaryRoles(for: exercise)
    if roles.isEmpty { emptyRoleExercises += 1 }
    for role in roles {
        totalRows += 1
        if role.clause == "assists the movement" {
            fallbackRows += 1
            fallbackMuscles[ExerciseMuscleRoles.canonicalMuscle(role.muscle), default: 0] += 1
        }
    }
}

check("every exercise produces at least one muscle row", emptyRoleExercises == 0)
let fallbackShare = Double(fallbackRows) / Double(totalRows)
check("at least 90% of rows get a real clause (not the fallback)", fallbackShare <= 0.10)
print("  INFO  \(totalRows) primary-muscle rows across the library; \(fallbackRows) fall back (\(Int((fallbackShare * 100).rounded()))%)")
for (muscle, count) in fallbackMuscles.sorted(by: { $0.value > $1.value }).prefix(8) {
    print("  INFO  fallback: \(muscle) x\(count)")
}

print(failures == 0 ? "ALL CHECKS PASSED" : "CHECKS FAILED (\(failures))")
exit(failures == 0 ? 0 : 1)
