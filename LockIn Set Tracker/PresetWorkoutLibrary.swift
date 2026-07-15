import Foundation

enum WorkoutPresetProgramKind: String, CaseIterable, Identifiable {
    case pushDay = "Push Day"
    case pullDay = "Pull Day"
    case legDay = "Leg Day"
    case upper = "Upper"
    case lower = "Lower"
    case fullBody = "Full Body"
    case broSplit = "Bro Split"
    case arnoldSplit = "Arnold Split"

    var id: String { rawValue }
}

enum WorkoutPresetSplitKind: String, CaseIterable, Identifiable {
    case pushPullLegs = "Push Pull Legs"
    case upperLower = "Upper/Lower"
    case broSplit = "Bro Split"
    case arnoldSplit = "Arnold Split"
    case fullBodyBeginner = "Full Body Beginner"

    var id: String { rawValue }
}

struct WorkoutExerciseRole: Identifiable, Hashable {
    let title: String
    let movementPatterns: [MovementPattern]
    let primaryMuscles: [PrimaryMuscleGroup]
    let preferredEquipment: [EquipmentType]
    let allowedDifficulties: [DifficultyLevel]
    let requiredKeywords: [String]
    let preferredKeywords: [String]

    init(
        title: String,
        movementPatterns: [MovementPattern] = [],
        primaryMuscles: [PrimaryMuscleGroup] = [],
        preferredEquipment: [EquipmentType] = [],
        allowedDifficulties: [DifficultyLevel] = [],
        requiredKeywords: [String] = [],
        preferredKeywords: [String] = []
    ) {
        self.title = title
        self.movementPatterns = movementPatterns
        self.primaryMuscles = primaryMuscles
        self.preferredEquipment = preferredEquipment
        self.allowedDifficulties = allowedDifficulties
        self.requiredKeywords = requiredKeywords
        self.preferredKeywords = preferredKeywords
    }

    var id: String { title }

    func matches(_ exercise: Exercise) -> Bool {
        let lowercasedName = exercise.name.lowercased()
        let matchesMovement = movementPatterns.isEmpty || movementPatterns.contains(exercise.movementPattern)
        let matchesMuscle = primaryMuscles.isEmpty || !Set(primaryMuscles).isDisjoint(with: exercise.primaryMuscleGroups)
        let matchesEquipment = preferredEquipment.isEmpty || preferredEquipment.contains(exercise.equipment)
        let matchesDifficulty = allowedDifficulties.isEmpty || allowedDifficulties.contains(exercise.difficulty)
        let matchesRequiredKeywords = requiredKeywords.allSatisfy { lowercasedName.contains($0.lowercased()) }

        return matchesMovement && matchesMuscle && matchesEquipment && matchesDifficulty && matchesRequiredKeywords
    }

    func score(for exercise: Exercise) -> Int {
        var score = 0
        let lowercasedName = exercise.name.lowercased()

        if movementPatterns.contains(exercise.movementPattern) {
            score += 4
        }
        if !Set(primaryMuscles).isDisjoint(with: exercise.primaryMuscleGroups) {
            score += 3
        }
        if preferredEquipment.contains(exercise.equipment) {
            score += 2
        }
        if allowedDifficulties.contains(exercise.difficulty) {
            score += 1
        }
        if preferredKeywords.contains(where: { lowercasedName.contains($0.lowercased()) }) {
            score += 3
        }

        return score
    }
}

struct WorkoutPresetTemplate: Identifiable, Hashable {
    let programKind: WorkoutPresetProgramKind
    let dayTitle: String
    let variant: String?
    let roles: [WorkoutExerciseRole]

    var id: String { routineName }

    var routineName: String {
        if let variant, !variant.isEmpty {
            return "\(dayTitle) \(variant)"
        }
        return dayTitle
    }
}

struct WorkoutPresetProgram: Identifiable, Hashable {
    let kind: WorkoutPresetProgramKind
    let workouts: [WorkoutPresetTemplate]

    var id: String { kind.rawValue }
}

struct WorkoutPresetSplit: Identifiable, Hashable {
    let kind: WorkoutPresetSplitKind
    let title: String
    let subtitle: String
    let scheduleHint: String
    let templates: [WorkoutPresetTemplate]

    var id: String { kind.rawValue }
}

struct EquipmentAccessProfile: Hashable {
    let availableEquipment: Set<EquipmentType>

    var isRestricted: Bool {
        !availableEquipment.isEmpty
    }

    func allows(_ equipment: EquipmentType) -> Bool {
        availableEquipment.isEmpty || availableEquipment.contains(equipment)
    }

    func preferenceScore(for equipment: EquipmentType) -> Int {
        guard isRestricted else { return 0 }
        return allows(equipment) ? 5 : -3
    }
}

struct GeneratedPresetWorkout {
    let template: WorkoutPresetTemplate
    let matches: [GeneratedPresetMatch]
    let missingRoles: [WorkoutExerciseRole]
    let equipmentProfile: EquipmentAccessProfile

    var exerciseNames: [String] {
        matches.map(\.exercise.name)
    }

    var asRoutine: Routine {
        Routine(name: template.routineName, exercises: exerciseNames)
    }
}

struct GeneratedPresetMatch: Identifiable {
    let role: WorkoutExerciseRole
    let exercise: Exercise
    let alternatives: [Exercise]
    let respectsEquipmentProfile: Bool

    var id: String { "\(role.title)-\(exercise.name)" }
}

enum PresetWorkoutGenerator {
    static func generate(
        template: WorkoutPresetTemplate,
        from exercises: [Exercise],
        equipmentProfile: EquipmentAccessProfile = EquipmentAccessProfile(availableEquipment: [])
    ) -> GeneratedPresetWorkout {
        var usedNames = Set<String>()
        var matches: [GeneratedPresetMatch] = []
        var missingRoles: [WorkoutExerciseRole] = []

        for role in template.roles {
            let matchingCandidates = exercises
                .filter { role.matches($0) && !usedNames.contains($0.name) }

            let preferredCandidates = matchingCandidates
                .filter { equipmentProfile.allows($0.equipment) }

            let rankedCandidates = rankedExercises(
                matchingCandidates,
                for: role,
                equipmentProfile: equipmentProfile
            )

            let bestMatch = rankedExercises(
                preferredCandidates.isEmpty ? matchingCandidates : preferredCandidates,
                for: role,
                equipmentProfile: equipmentProfile
            ).first

            if let bestMatch {
                usedNames.insert(bestMatch.name)
                let alternatives = rankedCandidates
                    .filter { $0.name != bestMatch.name }
                    .prefix(2)

                matches.append(
                    GeneratedPresetMatch(
                        role: role,
                        exercise: bestMatch,
                        alternatives: Array(alternatives),
                        respectsEquipmentProfile: equipmentProfile.allows(bestMatch.equipment)
                    )
                )
            } else {
                missingRoles.append(role)
            }
        }

        return GeneratedPresetWorkout(
            template: template,
            matches: matches,
            missingRoles: missingRoles,
            equipmentProfile: equipmentProfile
        )
    }

    private static func rankedExercises(
        _ exercises: [Exercise],
        for role: WorkoutExerciseRole,
        equipmentProfile: EquipmentAccessProfile
    ) -> [Exercise] {
        exercises.sorted { lhs, rhs in
            let leftScore = role.score(for: lhs) + equipmentProfile.preferenceScore(for: lhs.equipment)
            let rightScore = role.score(for: rhs) + equipmentProfile.preferenceScore(for: rhs.equipment)

            if leftScore == rightScore {
                return lhs.name < rhs.name
            }

            return leftScore > rightScore
        }
    }
}

enum PresetWorkoutLibrary {
    static let programs: [WorkoutPresetProgram] = [
        WorkoutPresetProgram(
            kind: .pushDay,
            workouts: [
                WorkoutPresetTemplate(
                    programKind: .pushDay,
                    dayTitle: "Push Day",
                    variant: "A",
                    roles: [
                        WorkoutExerciseRole(title: "Main Horizontal Press", movementPatterns: [.horizontalPush], primaryMuscles: [.chest], preferredEquipment: [.barbell, .dumbbell]),
                        WorkoutExerciseRole(title: "Incline Press", movementPatterns: [.horizontalPush], primaryMuscles: [.chest], preferredEquipment: [.dumbbell, .barbell], requiredKeywords: ["incline"]),
                        WorkoutExerciseRole(title: "Vertical Press", movementPatterns: [.verticalPush], primaryMuscles: [.shoulders]),
                        WorkoutExerciseRole(title: "Lateral Raise", movementPatterns: [.isolation], primaryMuscles: [.shoulders], preferredEquipment: [.dumbbell, .cable], requiredKeywords: ["raise"], preferredKeywords: ["lateral"]),
                        WorkoutExerciseRole(title: "Triceps Isolation", movementPatterns: [.isolation], primaryMuscles: [.triceps], preferredEquipment: [.cable, .dumbbell], preferredKeywords: ["triceps", "pushdown", "extension"])
                    ]
                ),
                WorkoutPresetTemplate(
                    programKind: .pushDay,
                    dayTitle: "Push Day",
                    variant: "B",
                    roles: [
                        WorkoutExerciseRole(title: "Machine or Dumbbell Press", movementPatterns: [.horizontalPush], primaryMuscles: [.chest], preferredEquipment: [.machine, .dumbbell]),
                        WorkoutExerciseRole(title: "Chest Isolation", movementPatterns: [.isolation, .horizontalPush], primaryMuscles: [.chest], preferredEquipment: [.cable, .machine, .dumbbell]),
                        WorkoutExerciseRole(title: "Overhead Press", movementPatterns: [.verticalPush], primaryMuscles: [.shoulders], preferredEquipment: [.dumbbell, .barbell]),
                        WorkoutExerciseRole(title: "Shoulder Isolation", movementPatterns: [.isolation], primaryMuscles: [.shoulders], preferredEquipment: [.dumbbell, .cable], preferredKeywords: ["raise"]),
                        WorkoutExerciseRole(title: "Triceps Finish", movementPatterns: [.isolation], primaryMuscles: [.triceps], preferredEquipment: [.cable, .machine, .dumbbell], preferredKeywords: ["triceps", "pushdown", "extension"])
                    ]
                )
            ]
        ),
        WorkoutPresetProgram(
            kind: .pullDay,
            workouts: [
                WorkoutPresetTemplate(
                    programKind: .pullDay,
                    dayTitle: "Pull Day",
                    variant: "A",
                    roles: [
                        WorkoutExerciseRole(title: "Main Vertical Pull", movementPatterns: [.verticalPull], primaryMuscles: [.back]),
                        WorkoutExerciseRole(title: "Main Horizontal Pull", movementPatterns: [.horizontalPull], primaryMuscles: [.back]),
                        WorkoutExerciseRole(title: "Secondary Pull", movementPatterns: [.horizontalPull, .verticalPull], primaryMuscles: [.back]),
                        WorkoutExerciseRole(title: "Rear Delt or Upper Back Isolation", movementPatterns: [.isolation, .horizontalPull], primaryMuscles: [.shoulders, .back], preferredEquipment: [.cable, .dumbbell, .machine], preferredKeywords: ["rear", "reverse"]),
                        WorkoutExerciseRole(title: "Biceps Isolation", movementPatterns: [.isolation], primaryMuscles: [.biceps], preferredEquipment: [.dumbbell, .cable, .barbell], preferredKeywords: ["curl", "biceps", "hammer"])
                    ]
                ),
                WorkoutPresetTemplate(
                    programKind: .pullDay,
                    dayTitle: "Pull Day",
                    variant: "B",
                    roles: [
                        WorkoutExerciseRole(title: "Lat-Focused Pull", movementPatterns: [.verticalPull], primaryMuscles: [.back], preferredEquipment: [.cable, .machine, .bodyweight]),
                        WorkoutExerciseRole(title: "Chest-Supported or Cable Row", movementPatterns: [.horizontalPull], primaryMuscles: [.back], preferredEquipment: [.machine, .cable, .dumbbell]),
                        WorkoutExerciseRole(title: "Hinge Pull", movementPatterns: [.hinge], primaryMuscles: [.back], preferredEquipment: [.barbell, .dumbbell]),
                        WorkoutExerciseRole(title: "Upper Back Isolation", movementPatterns: [.isolation, .horizontalPull], primaryMuscles: [.back, .shoulders], preferredEquipment: [.cable, .machine]),
                        WorkoutExerciseRole(title: "Biceps Finish", movementPatterns: [.isolation], primaryMuscles: [.biceps], preferredEquipment: [.dumbbell, .cable], preferredKeywords: ["curl", "biceps", "hammer"])
                    ]
                )
            ]
        ),
        WorkoutPresetProgram(
            kind: .legDay,
            workouts: [
                WorkoutPresetTemplate(
                    programKind: .legDay,
                    dayTitle: "Leg Day",
                    variant: "A",
                    roles: [
                        WorkoutExerciseRole(title: "Main Squat", movementPatterns: [.squat], primaryMuscles: [.legs], preferredEquipment: [.barbell, .machine]),
                        WorkoutExerciseRole(title: "Main Hinge", movementPatterns: [.hinge], primaryMuscles: [.legs], preferredEquipment: [.barbell, .dumbbell]),
                        WorkoutExerciseRole(title: "Unilateral Leg Work", movementPatterns: [.squat], primaryMuscles: [.legs], preferredEquipment: [.dumbbell, .bodyweight, .barbell]),
                        WorkoutExerciseRole(title: "Leg Isolation", movementPatterns: [.isolation], primaryMuscles: [.legs], preferredEquipment: [.machine, .cable]),
                        WorkoutExerciseRole(title: "Leg Finisher", movementPatterns: [.isolation], primaryMuscles: [.legs])
                    ]
                ),
                WorkoutPresetTemplate(
                    programKind: .legDay,
                    dayTitle: "Leg Day",
                    variant: "B",
                    roles: [
                        WorkoutExerciseRole(title: "Quad-Focused Squat", movementPatterns: [.squat], primaryMuscles: [.legs], preferredEquipment: [.machine, .barbell]),
                        WorkoutExerciseRole(title: "Posterior Chain Hinge", movementPatterns: [.hinge], primaryMuscles: [.legs], preferredEquipment: [.barbell, .dumbbell]),
                        WorkoutExerciseRole(title: "Single-Leg Movement", movementPatterns: [.squat, .isolation], primaryMuscles: [.legs], preferredEquipment: [.dumbbell, .bodyweight]),
                        WorkoutExerciseRole(title: "Hamstring or Glute Isolation", movementPatterns: [.isolation], primaryMuscles: [.legs], preferredEquipment: [.machine, .cable]),
                        WorkoutExerciseRole(title: "Calf or Leg Accessory", movementPatterns: [.isolation], primaryMuscles: [.legs], preferredEquipment: [.machine, .bodyweight])
                    ]
                )
            ]
        ),
        WorkoutPresetProgram(
            kind: .upper,
            workouts: [
                WorkoutPresetTemplate(
                    programKind: .upper,
                    dayTitle: "Upper",
                    variant: "A",
                    roles: [
                        WorkoutExerciseRole(title: "Horizontal Press", movementPatterns: [.horizontalPush], primaryMuscles: [.chest]),
                        WorkoutExerciseRole(title: "Vertical Pull", movementPatterns: [.verticalPull], primaryMuscles: [.back]),
                        WorkoutExerciseRole(title: "Horizontal Pull", movementPatterns: [.horizontalPull], primaryMuscles: [.back]),
                        WorkoutExerciseRole(title: "Vertical Press", movementPatterns: [.verticalPush], primaryMuscles: [.shoulders]),
                        WorkoutExerciseRole(title: "Arm Isolation", movementPatterns: [.isolation], primaryMuscles: [.biceps, .triceps])
                    ]
                ),
                WorkoutPresetTemplate(
                    programKind: .upper,
                    dayTitle: "Upper",
                    variant: "B",
                    roles: [
                        WorkoutExerciseRole(title: "Incline or Machine Press", movementPatterns: [.horizontalPush], primaryMuscles: [.chest], preferredEquipment: [.dumbbell, .machine]),
                        WorkoutExerciseRole(title: "Lat-Focused Pull", movementPatterns: [.verticalPull], primaryMuscles: [.back]),
                        WorkoutExerciseRole(title: "Row Variation", movementPatterns: [.horizontalPull], primaryMuscles: [.back]),
                        WorkoutExerciseRole(title: "Shoulder Isolation", movementPatterns: [.isolation, .verticalPush], primaryMuscles: [.shoulders]),
                        WorkoutExerciseRole(title: "Secondary Arm Isolation", movementPatterns: [.isolation], primaryMuscles: [.biceps, .triceps])
                    ]
                )
            ]
        ),
        WorkoutPresetProgram(
            kind: .lower,
            workouts: [
                WorkoutPresetTemplate(
                    programKind: .lower,
                    dayTitle: "Lower",
                    variant: "A",
                    roles: [
                        WorkoutExerciseRole(title: "Squat Pattern", movementPatterns: [.squat], primaryMuscles: [.legs]),
                        WorkoutExerciseRole(title: "Hinge Pattern", movementPatterns: [.hinge], primaryMuscles: [.legs]),
                        WorkoutExerciseRole(title: "Single-Leg Pattern", movementPatterns: [.squat, .isolation], primaryMuscles: [.legs]),
                        WorkoutExerciseRole(title: "Leg Isolation", movementPatterns: [.isolation], primaryMuscles: [.legs]),
                        WorkoutExerciseRole(title: "Lower Accessory", movementPatterns: [.isolation], primaryMuscles: [.legs])
                    ]
                )
            ]
        ),
        WorkoutPresetProgram(
            kind: .fullBody,
            workouts: [
                WorkoutPresetTemplate(
                    programKind: .fullBody,
                    dayTitle: "Full Body",
                    variant: "A",
                    roles: [
                        WorkoutExerciseRole(title: "Squat Pattern", movementPatterns: [.squat], primaryMuscles: [.legs]),
                        WorkoutExerciseRole(title: "Horizontal Press", movementPatterns: [.horizontalPush], primaryMuscles: [.chest]),
                        WorkoutExerciseRole(title: "Horizontal Pull", movementPatterns: [.horizontalPull], primaryMuscles: [.back]),
                        WorkoutExerciseRole(title: "Hinge or Vertical Pull", movementPatterns: [.hinge, .verticalPull], primaryMuscles: [.legs, .back]),
                        WorkoutExerciseRole(title: "Shoulder or Arm Accessory", movementPatterns: [.isolation], primaryMuscles: [.shoulders, .biceps, .triceps])
                    ]
                ),
                WorkoutPresetTemplate(
                    programKind: .fullBody,
                    dayTitle: "Full Body",
                    variant: "B",
                    roles: [
                        WorkoutExerciseRole(title: "Beginner Leg Pattern", movementPatterns: [.squat], primaryMuscles: [.legs], preferredEquipment: [.machine, .dumbbell, .bodyweight], allowedDifficulties: [.beginner, .intermediate]),
                        WorkoutExerciseRole(title: "Machine or Dumbbell Press", movementPatterns: [.horizontalPush], primaryMuscles: [.chest], preferredEquipment: [.machine, .dumbbell], allowedDifficulties: [.beginner, .intermediate]),
                        WorkoutExerciseRole(title: "Supported Pull", movementPatterns: [.verticalPull, .horizontalPull], primaryMuscles: [.back], preferredEquipment: [.machine, .cable, .bodyweight], allowedDifficulties: [.beginner, .intermediate]),
                        WorkoutExerciseRole(title: "Simple Hinge", movementPatterns: [.hinge], primaryMuscles: [.legs], preferredEquipment: [.dumbbell, .barbell], allowedDifficulties: [.beginner, .intermediate]),
                        WorkoutExerciseRole(title: "Easy Accessory", movementPatterns: [.isolation], primaryMuscles: [.shoulders, .biceps, .triceps], preferredEquipment: [.machine, .dumbbell, .cable], allowedDifficulties: [.beginner, .intermediate])
                    ]
                )
            ]
        ),
        WorkoutPresetProgram(
            kind: .broSplit,
            workouts: [
                WorkoutPresetTemplate(
                    programKind: .broSplit,
                    dayTitle: "Chest Day",
                    variant: "A",
                    roles: [
                        WorkoutExerciseRole(title: "Main Press", movementPatterns: [.horizontalPush], primaryMuscles: [.chest]),
                        WorkoutExerciseRole(title: "Secondary Press", movementPatterns: [.horizontalPush, .verticalPush], primaryMuscles: [.chest, .shoulders]),
                        WorkoutExerciseRole(title: "Chest Isolation", movementPatterns: [.isolation, .horizontalPush], primaryMuscles: [.chest]),
                        WorkoutExerciseRole(title: "Triceps Isolation", movementPatterns: [.isolation], primaryMuscles: [.triceps])
                    ]
                ),
                WorkoutPresetTemplate(
                    programKind: .broSplit,
                    dayTitle: "Back Day",
                    variant: "A",
                    roles: [
                        WorkoutExerciseRole(title: "Vertical Pull", movementPatterns: [.verticalPull], primaryMuscles: [.back]),
                        WorkoutExerciseRole(title: "Horizontal Pull", movementPatterns: [.horizontalPull], primaryMuscles: [.back]),
                        WorkoutExerciseRole(title: "Secondary Row or Pull", movementPatterns: [.horizontalPull, .verticalPull], primaryMuscles: [.back]),
                        WorkoutExerciseRole(title: "Biceps Isolation", movementPatterns: [.isolation], primaryMuscles: [.biceps])
                    ]
                ),
                WorkoutPresetTemplate(
                    programKind: .broSplit,
                    dayTitle: "Leg Day",
                    variant: "A",
                    roles: [
                        WorkoutExerciseRole(title: "Squat Pattern", movementPatterns: [.squat], primaryMuscles: [.legs]),
                        WorkoutExerciseRole(title: "Hinge Pattern", movementPatterns: [.hinge], primaryMuscles: [.legs]),
                        WorkoutExerciseRole(title: "Leg Isolation", movementPatterns: [.isolation], primaryMuscles: [.legs]),
                        WorkoutExerciseRole(title: "Leg Accessory", movementPatterns: [.isolation], primaryMuscles: [.legs])
                    ]
                ),
                WorkoutPresetTemplate(
                    programKind: .broSplit,
                    dayTitle: "Shoulder Day",
                    variant: "A",
                    roles: [
                        WorkoutExerciseRole(title: "Vertical Press", movementPatterns: [.verticalPush], primaryMuscles: [.shoulders]),
                        WorkoutExerciseRole(title: "Lateral Raise", movementPatterns: [.isolation], primaryMuscles: [.shoulders], requiredKeywords: ["raise"], preferredKeywords: ["lateral"]),
                        WorkoutExerciseRole(title: "Rear Delt Work", movementPatterns: [.isolation, .horizontalPull], primaryMuscles: [.shoulders, .back]),
                        WorkoutExerciseRole(title: "Triceps Accessory", movementPatterns: [.isolation], primaryMuscles: [.triceps])
                    ]
                ),
                WorkoutPresetTemplate(
                    programKind: .broSplit,
                    dayTitle: "Arm Day",
                    variant: "A",
                    roles: [
                        WorkoutExerciseRole(title: "Biceps Isolation 1", movementPatterns: [.isolation], primaryMuscles: [.biceps], preferredKeywords: ["curl", "biceps", "hammer"]),
                        WorkoutExerciseRole(title: "Triceps Isolation 1", movementPatterns: [.isolation], primaryMuscles: [.triceps], preferredKeywords: ["triceps", "pushdown", "extension"]),
                        WorkoutExerciseRole(title: "Biceps Isolation 2", movementPatterns: [.isolation], primaryMuscles: [.biceps], preferredKeywords: ["curl", "biceps", "hammer"]),
                        WorkoutExerciseRole(title: "Triceps Isolation 2", movementPatterns: [.isolation], primaryMuscles: [.triceps], preferredKeywords: ["triceps", "pushdown", "extension"])
                    ]
                )
            ]
        ),
        WorkoutPresetProgram(
            kind: .arnoldSplit,
            workouts: [
                WorkoutPresetTemplate(
                    programKind: .arnoldSplit,
                    dayTitle: "Chest + Back",
                    variant: "A",
                    roles: [
                        WorkoutExerciseRole(title: "Horizontal Press", movementPatterns: [.horizontalPush], primaryMuscles: [.chest]),
                        WorkoutExerciseRole(title: "Vertical Pull", movementPatterns: [.verticalPull], primaryMuscles: [.back]),
                        WorkoutExerciseRole(title: "Secondary Press", movementPatterns: [.horizontalPush, .verticalPush], primaryMuscles: [.chest, .shoulders]),
                        WorkoutExerciseRole(title: "Row Variation", movementPatterns: [.horizontalPull], primaryMuscles: [.back]),
                        WorkoutExerciseRole(title: "Chest or Back Isolation", movementPatterns: [.isolation], primaryMuscles: [.chest, .back])
                    ]
                ),
                WorkoutPresetTemplate(
                    programKind: .arnoldSplit,
                    dayTitle: "Shoulders + Arms",
                    variant: "A",
                    roles: [
                        WorkoutExerciseRole(title: "Vertical Press", movementPatterns: [.verticalPush], primaryMuscles: [.shoulders]),
                        WorkoutExerciseRole(title: "Lateral Raise", movementPatterns: [.isolation], primaryMuscles: [.shoulders], requiredKeywords: ["raise"], preferredKeywords: ["lateral"]),
                        WorkoutExerciseRole(title: "Biceps Isolation", movementPatterns: [.isolation], primaryMuscles: [.biceps], preferredKeywords: ["curl", "biceps", "hammer"]),
                        WorkoutExerciseRole(title: "Triceps Isolation", movementPatterns: [.isolation], primaryMuscles: [.triceps], preferredKeywords: ["triceps", "pushdown", "extension"]),
                        WorkoutExerciseRole(title: "Shoulder Accessory", movementPatterns: [.isolation], primaryMuscles: [.shoulders])
                    ]
                ),
                WorkoutPresetTemplate(
                    programKind: .arnoldSplit,
                    dayTitle: "Legs",
                    variant: "A",
                    roles: [
                        WorkoutExerciseRole(title: "Main Squat", movementPatterns: [.squat], primaryMuscles: [.legs]),
                        WorkoutExerciseRole(title: "Main Hinge", movementPatterns: [.hinge], primaryMuscles: [.legs]),
                        WorkoutExerciseRole(title: "Single-Leg Work", movementPatterns: [.squat, .isolation], primaryMuscles: [.legs]),
                        WorkoutExerciseRole(title: "Leg Isolation", movementPatterns: [.isolation], primaryMuscles: [.legs]),
                        WorkoutExerciseRole(title: "Leg Accessory", movementPatterns: [.isolation], primaryMuscles: [.legs])
                    ]
                )
            ]
        )
    ]

    static let splits: [WorkoutPresetSplit] = [
        WorkoutPresetSplit(
            kind: .pushPullLegs,
            title: "Push Pull Legs",
            subtitle: "A simple 3-day classic with one push day, one pull day, and one leg day.",
            scheduleHint: "Great if you want a balanced split that is easy to repeat each week.",
            templates: [
                requiredTemplate(program: .pushDay, routineName: "Push Day A"),
                requiredTemplate(program: .pullDay, routineName: "Pull Day A"),
                requiredTemplate(program: .legDay, routineName: "Leg Day A")
            ]
        ),
        WorkoutPresetSplit(
            kind: .upperLower,
            title: "Upper/Lower",
            subtitle: "A straightforward split that alternates upper-body and lower-body sessions.",
            scheduleHint: "Great if you want fewer workout types to remember and plenty of room to recover.",
            templates: [
                requiredTemplate(program: .upper, routineName: "Upper A"),
                requiredTemplate(program: .lower, routineName: "Lower A")
            ]
        ),
        WorkoutPresetSplit(
            kind: .broSplit,
            title: "Bro Split",
            subtitle: "One main muscle group focus per day for easy-to-understand sessions.",
            scheduleHint: "Great if you want each workout to feel focused and easy to follow.",
            templates: [
                requiredTemplate(program: .broSplit, routineName: "Chest Day A"),
                requiredTemplate(program: .broSplit, routineName: "Back Day A"),
                requiredTemplate(program: .broSplit, routineName: "Leg Day A"),
                requiredTemplate(program: .broSplit, routineName: "Shoulder Day A"),
                requiredTemplate(program: .broSplit, routineName: "Arm Day A")
            ]
        ),
        WorkoutPresetSplit(
            kind: .arnoldSplit,
            title: "Arnold Split",
            subtitle: "Chest and back together, shoulders and arms together, then a leg day.",
            scheduleHint: "Great if you want a classic bodybuilding structure without too many choices.",
            templates: [
                requiredTemplate(program: .arnoldSplit, routineName: "Chest + Back A"),
                requiredTemplate(program: .arnoldSplit, routineName: "Shoulders + Arms A"),
                requiredTemplate(program: .arnoldSplit, routineName: "Legs A")
            ]
        ),
        WorkoutPresetSplit(
            kind: .fullBodyBeginner,
            title: "Full Body Beginner",
            subtitle: "A beginner-friendly full-body option with simple exercise coverage.",
            scheduleHint: "Great if you want the easiest starting point and still want something editable later.",
            templates: [
                requiredTemplate(program: .fullBody, routineName: "Full Body A"),
                requiredTemplate(program: .fullBody, routineName: "Full Body B")
            ]
        )
    ]

    static func program(for kind: WorkoutPresetProgramKind) -> WorkoutPresetProgram? {
        programs.first { $0.kind == kind }
    }

    static func split(for kind: WorkoutPresetSplitKind) -> WorkoutPresetSplit? {
        splits.first { $0.kind == kind }
    }

    private static func requiredTemplate(program kind: WorkoutPresetProgramKind, routineName: String) -> WorkoutPresetTemplate {
        guard let template = program(for: kind)?.workouts.first(where: { $0.routineName == routineName }) else {
            fatalError("Missing preset template: \(kind.rawValue) / \(routineName)")
        }

        return template
    }
}
