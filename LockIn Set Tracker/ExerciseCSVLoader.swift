import Foundation

enum MuscleGroup: String, CaseIterable, Codable {
    case chest = "Chest"
    case back = "Back"
    case shoulders = "Shoulders"
    case arms = "Arms"
    case legs = "Legs"
    case core = "Core"
    case cardio = "Cardio"
    case fullBody = "Full Body"
    case mobility = "Mobility"
    case other = "Other"
}

enum EquipmentType: String, CaseIterable, Codable {
    case dumbbell = "Dumbbell"
    case barbell = "Barbell"
    case machine = "Machine"
    case cable = "Cable"
    case kettlebell = "Kettlebell"
    case band = "Band"
    case medicineBall = "Medicine Ball"
    case bodyweight = "Bodyweight"
    case other = "Other"
}

enum MovementPattern: String, CaseIterable, Codable {
    case horizontalPush = "Horizontal Push"
    case verticalPush = "Vertical Push"
    case horizontalPull = "Horizontal Pull"
    case verticalPull = "Vertical Pull"
    case squat = "Squat"
    case hinge = "Hinge"
    case isolation = "Isolation"
}

enum PrimaryMuscleGroup: String, CaseIterable, Codable {
    case chest = "Chest"
    case back = "Back"
    case shoulders = "Shoulders"
    case triceps = "Triceps"
    case biceps = "Biceps"
    case legs = "Legs"
    case core = "Core"
}

enum DifficultyLevel: String, CaseIterable, Codable {
    case beginner = "Beginner"
    case intermediate = "Intermediate"
    case advanced = "Advanced"
}

struct ExerciseMetadata: Codable, Hashable {
    var primaryMuscles: [String]
    var secondaryMuscles: [String]
    var movementPattern: String
    var equipment: [String]
    var difficulty: String
    var mechanic: String
    var forceType: String
    var laterality: String
    var bodyRegion: String
    var trainingGoal: [String]
    var exerciseType: String
    var gripType: String?
    var stance: String?
    var planeOfMotion: String
    var tags: [String]
}

struct Exercise: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    var muscleGroup: MuscleGroup
    var equipment: EquipmentType
    var movementPattern: MovementPattern
    var primaryMuscleGroups: [PrimaryMuscleGroup]
    var difficulty: DifficultyLevel
    var instructions: String
    var imageName: String?
    var metadata: ExerciseMetadata
    var description: String
    var howTo: [String]
    var cues: [String]

    var tags: [String] {
        metadata.tags
    }

    var summaryTags: [String] {
        Array(metadata.tags.prefix(3))
    }

    var primaryMuscleGroupText: String {
        metadata.primaryMuscles.prefix(2).joined(separator: ", ")
    }

    var libraryMetadataLine: String {
        [primaryMuscleGroupText, equipment.rawValue]
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
    }

    var libraryPreviewText: String {
        "\(metadata.movementPattern.sentenceStyled) • \(difficulty.rawValue)"
    }

    var placeholderSystemImageName: String {
        switch muscleGroup {
        case .chest:
            return "figure.strengthtraining.traditional"
        case .back:
            return "figure.strengthtraining.traditional"
        case .shoulders:
            return "dumbbell.fill"
        case .arms:
            return "dumbbell.fill"
        case .legs:
            return "figure.run"
        case .core:
            return "figure.strengthtraining.traditional"
        case .cardio:
            return "heart.circle.fill"
        case .fullBody:
            return "figure.strengthtraining.traditional"
        case .mobility:
            return "figure.walk"
        case .other:
            return "figure.strengthtraining.traditional"
        }
    }
}

/// Loads the bundled exercise library plus the user's custom exercises.
///
/// Decoding the bundled JSON (~2 MB, 1k+ exercises) is expensive, so exactly one
/// instance lives at the app root (`LockInSetTrackerApp`) and is shared via
/// `.environmentObject`. Consume it with `@EnvironmentObject`; never construct a
/// second instance in a view. When custom exercises change, call
/// `reloadCustomExercises()` — it re-merges without re-decoding the JSON.
final class ExerciseStore: ObservableObject {
    @Published var exercises: [Exercise] = []

    /// Case/punctuation-folded names, index-aligned with `exercises`.
    /// Precomputed here (the single place `exercises` is rebuilt) so the
    /// library search never lowercases 1,000+ names per keystroke.
    private(set) var searchKeys: [String] = []

    /// The decoded bundled library, kept so custom-exercise refreshes never
    /// re-decode the JSON.
    private var bundledExercises: [Exercise] = []
    /// Snapshot of the custom exercises last merged, so no-op refreshes skip
    /// publishing and cache invalidation.
    private var lastMergedCustomExercises: [Exercise] = []

    init() {
        loadExercises()
    }

    func loadExercises() {
        guard let url = Bundle.main.url(forResource: "exercises", withExtension: "json") else {
            print("Exercise JSON file not found")
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([Exercise].self, from: data)

            bundledExercises = decoded.map { exercise in
                var exercise = exercise

                if exercise.imageName == nil {
                    exercise.imageName = ExerciseMediaCatalog.imageName(for: exercise.name)
                }

                if exercise.instructions.isEmpty {
                    exercise.instructions = exercise.description
                }

                return exercise
            }

            merge(customExercises: CustomExerciseLibrary.loadExercises())
        } catch {
            print("Error loading exercise JSON: \(error)")
        }
    }

    /// Cheap refresh after custom exercises may have changed (e.g. a photo or
    /// voice import saved one): re-merges the persisted custom list into the
    /// already-decoded bundled library. Skips entirely when nothing changed;
    /// otherwise also invalidates the fuzzy-match memo cache, since custom
    /// exercises participate in name resolution.
    func reloadCustomExercises() {
        let customExercises = CustomExerciseLibrary.loadExercises()
        guard customExercises != lastMergedCustomExercises else { return }

        merge(customExercises: customExercises)
        ExerciseNameMatcher.invalidateCache()
    }

    private func merge(customExercises: [Exercise]) {
        lastMergedCustomExercises = customExercises

        let prepared = customExercises.map { exercise in
            var exercise = exercise

            if exercise.instructions.isEmpty {
                exercise.instructions = exercise.description
            }

            return exercise
        }

        // Bundled wins on name collisions, case-insensitively.
        var seenNames = Set<String>()
        exercises = (bundledExercises + prepared).filter { exercise in
            seenNames.insert(exercise.name.lowercased()).inserted
        }
        searchKeys = exercises.map { ExerciseAliases.searchFold($0.name) }
    }
}

private extension String {
    var sentenceStyled: String {
        guard let first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}
