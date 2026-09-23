// Logic check: Coach saved-lineage persistence.
// A revised Coach draft must update its saved routine in place, preserving the
// routine id, name history, import context, and progression state. This uses
// only fixed fixtures and the real persistence seam — never the AI client.
import Foundation

// MARK: - Stubs for AI-memory symbols referenced by the compiled app sources

struct UserMemory: Codable {}

enum AIBackendSecrets {
    static let appToken: String? = nil
}

enum UserMemoryStore {
    static func current() -> UserMemory? { nil }

    @discardableResult
    static func refresh(now: Date = Date(), defaults: UserDefaults = .standard) -> Bool {
        true
    }
}

@MainActor
func runLogicCheck() {
        var failures = 0
        func check(_ name: String, _ condition: Bool) {
            if condition {
                print("  PASS  \(name)")
            } else {
                print("  FAIL  \(name)")
                failures += 1
            }
        }

        let fixedDate = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let routineID = UUID(uuidString: "00000000-0000-0000-0000-000000000401")!
        let suiteName = "coach-routine-persistence-logic-check"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = WorkoutStore(defaults: defaults)

        var existing = Routine(
            id: routineID,
            name: "Original Full Body",
            exercises: ["Goblet Squat"],
            preferredSetCounts: ["Goblet Squat": 3],
            historyNames: ["Original Full Body"]
        )
        existing.progression = [
            "Goblet Squat": ExerciseProgressionState(
                lastWeight: "40 lb",
                lastReps: "10",
                lastOutcome: .aboutRight,
                updatedAt: fixedDate
            )
        ]
        store.addRoutine(existing)

        let revisedDraft = AIGeneratedRoutineDraft(
            title: "Full Body A",
            summary: "",
            rationale: "",
            routineNotes: [],
            exercises: [
                AIGeneratedExercise(name: "Goblet Squat", sets: 4, reps: "8", notes: nil, reasoning: nil, tip: nil, recommendedSets: nil, catalogMatch: true),
                AIGeneratedExercise(name: "Incline Push-Up", sets: 3, reps: "10", notes: nil, reasoning: nil, tip: nil, recommendedSets: nil, catalogMatch: true)
            ],
            sourcePrompt: "fixture",
            model: nil
        )

        let result = CoachRoutinePersistence.save(revisedDraft, replacing: routineID, in: store)
        if case .updated(let updated)? = result {
            check("result reports an update", updated.id == routineID)
        } else {
            check("result reports an update", false)
        }

        let saved = store.routine(withID: routineID)
        check("only one routine remains", store.routines.count == 1)
        check("same id is retained", saved?.id == routineID)
        check("draft contents replace the routine", saved?.name == "Full Body A" && saved?.exercises == ["Goblet Squat", "Incline Push-Up"])
        check("name history survives", saved?.allKnownNames == ["Original Full Body", "Full Body A"])
        check("progression survives", saved?.progression?["Goblet Squat"]?.lastWeight == "40 lb")

        defaults.removePersistentDomain(forName: suiteName)
    exit(failures > 0 ? 1 : 0)
}

Task { @MainActor in
    runLogicCheck()
}
dispatchMain()
