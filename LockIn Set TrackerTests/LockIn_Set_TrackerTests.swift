//
//  LockIn_Set_TrackerTests.swift
//  LockIn Set TrackerTests
//
//  Created by Barron Neumann on 7/9/25.
//

import Foundation
import Testing
@testable import Lokt

@Suite("Deterministic workout flows", .serialized)
@MainActor
struct LockIn_Set_TrackerTests {

    @Test("AI draft remains a review until explicit save")
    func aiReviewBeforeSave() {
        let store = WorkoutStore(defaults: isolatedDefaults())
        let draft = makeDraft(title: "  Starter strength  ", exercises: [
            makeExercise(name: "  Goblet Squat  ", sets: 4, reps: "8-10")
        ])

        let reviewedRoutine = AIWorkoutRoutineSaver.makeRoutine(from: draft)

        #expect(store.routines.isEmpty)
        #expect(reviewedRoutine?.name == "Starter strength")
        #expect(reviewedRoutine?.exercises == ["Goblet Squat"])

        AIWorkoutRoutineSaver.save(draft, to: store)

        #expect(store.routines.count == 1)
        #expect(store.routines[0].name == "Starter strength")
        #expect(store.routines[0].preferredSetCount(for: "Goblet Squat") == 4)
    }

    @Test("Coach revisions update their saved routine in place")
    func coachUpdatesInPlace() {
        let store = WorkoutStore(defaults: isolatedDefaults())
        let routineID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
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
                updatedAt: Self.fixedDate
            )
        ]
        store.addRoutine(existing)

        let revisedDraft = makeDraft(title: "Full Body A", exercises: [
            makeExercise(name: "Goblet Squat", sets: 4, reps: "8"),
            makeExercise(name: "Incline Push-Up", sets: 3, reps: "10")
        ])

        let result = CoachRoutinePersistence.save(revisedDraft, replacing: routineID, in: store)

        if case .updated(let updated)? = result {
            #expect(updated.id == routineID)
        } else {
            Issue.record("Expected an in-place Coach update")
        }
        #expect(store.routines.count == 1)
        #expect(store.routines[0].id == routineID)
        #expect(store.routines[0].name == "Full Body A")
        #expect(store.routines[0].exercises == ["Goblet Squat", "Incline Push-Up"])
        #expect(store.routines[0].allKnownNames == ["Original Full Body", "Full Body A"])
        #expect(store.routines[0].progression?["Goblet Squat"]?.lastWeight == "40 lb")
    }

    @Test("Meaningful in-progress workout resumes the saved routine")
    func resumesInProgressWorkout() {
        let defaults = isolatedDefaults()
        let routineID = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
        let routine = Routine(
            id: routineID,
            name: "Push Day",
            exercises: ["Bench Press"],
            preferredSetCounts: ["Bench Press": 3]
        )
        let state = ActiveWorkoutState(
            routineID: routineID,
            routineName: routine.name,
            startedAt: Self.fixedDate,
            lastInteractionAt: Self.fixedDate.addingTimeInterval(120),
            activeSeconds: 120,
            logs: ["Bench Press": [WorkoutSet(weight: "135", reps: "8", completed: true)]],
            preferredSetCounts: routine.preferredSetCounts
        )

        ActiveWorkoutStore.save(state, defaults: defaults)
        let restored = ActiveWorkoutStore.load(defaults: defaults)

        #expect(restored == state)
        #expect(ActiveWorkoutStore.hasMeaningfulContent(restored?.logs ?? [:]))
        #expect(ActiveWorkoutStore.resumableRoutine(for: restored!, in: [routine])?.id == routineID)
    }

    @Test("Check-in produces an explicitly applied nudge without networking")
    func checkInNudgeApply() {
        let store = WorkoutStore(defaults: isolatedDefaults())
        let routineID = UUID(uuidString: "00000000-0000-0000-0000-000000000301")!
        let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000302")!
        let routine = Routine(
            id: routineID,
            name: "Strength A",
            exercises: ["Bench Press"],
            preferredSetCounts: ["Bench Press": 3]
        )
        let session = WorkoutSession(
            id: sessionID,
            date: Self.fixedDate,
            routineID: routineID,
            routineName: routine.name,
            logs: ["Bench Press": [WorkoutSet(weight: "135 lb", reps: "8", completed: true)]]
        )
        store.addRoutine(routine)
        store.addSession(session)

        let checkIn = SessionCheckIn(overall: .tooEasy, recordedAt: Self.fixedDate)
        store.recordCheckIn(checkIn, forSessionID: sessionID)
        let nudge = WorkoutNudge(
            overallNote: "Add a small amount next time.",
            exercises: [
                WorkoutNudgeItem(
                    name: "Bench Press",
                    suggestedWeightText: "140 lb",
                    repText: "8-10",
                    setCount: 4,
                    whyNote: "Your last set was comfortable."
                )
            ]
        )

        let afterCheckIn = store.routine(withID: routineID)!
        #expect(store.session(withID: sessionID)?.checkIn == checkIn)
        #expect(afterCheckIn.progression?["Bench Press"]?.lastOutcome == .tooEasy)
        #expect(afterCheckIn.progression?["Bench Press"]?.lastWeight == "135 lb")

        let applied = nudge.applied(to: afterCheckIn, at: Self.fixedDate.addingTimeInterval(60))
        store.upsertRoutine(applied)

        let saved = store.routine(withID: routineID)!
        #expect(saved.id == routineID)
        #expect(saved.exercises == ["Bench Press"])
        #expect(saved.preferredSetCount(for: "Bench Press") == 4)
        #expect(saved.progression?["Bench Press"]?.suggestedWeightText == "140 lb")
        #expect(saved.progression?["Bench Press"]?.suggestedRepText == "8-10")
        #expect(saved.progression?["Bench Press"]?.nudgeNote == "Your last set was comfortable.")
    }

    private static let fixedDate = Date(timeIntervalSinceReferenceDate: 1_000_000)

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "LoktTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeDraft(title: String, exercises: [AIGeneratedExercise]) -> AIGeneratedRoutineDraft {
        AIGeneratedRoutineDraft(
            title: title,
            summary: "A reviewed plan.",
            rationale: "A deterministic test fixture.",
            routineNotes: [],
            exercises: exercises,
            sourcePrompt: "test fixture",
            model: nil
        )
    }

    private func makeExercise(name: String, sets: Int, reps: String) -> AIGeneratedExercise {
        AIGeneratedExercise(
            name: name,
            sets: sets,
            reps: reps,
            notes: nil,
            reasoning: nil,
            tip: nil,
            recommendedSets: nil,
            catalogMatch: true
        )
    }
}
