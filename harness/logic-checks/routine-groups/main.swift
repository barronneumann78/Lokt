// Logic check: routine grouping ("folders" for rotating-split variants).
// - Models: `Routine.groupID` and `RoutineGroup` decode-safety — legacy JSON
//   (no groupID key, no "routineGroups" key at all) must decode without
//   crashing and land ungrouped, never dropping the routine.
// - WorkoutStore group CRUD: create (ascending order survives deletions),
//   rename, delete (members fall back to ungrouped, never deleted, empty
//   groups deletable too), and move/remove-from-group — each persists the
//   same legacy-compatible JSON shape under its UserDefaults key.
// Compiles against the REAL Models.swift / WorkoutStore.swift.
import Foundation

// MARK: - Stubs for app-only symbols WorkoutStore.swift references

enum UserMemoryStore {
    static var refreshCount = 0
    @discardableResult
    static func refresh(now: Date = Date(), defaults: UserDefaults = .standard) -> Bool {
        refreshCount += 1
        return true
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

let suiteName = "routine-groups-logic-check"

func freshDefaults() -> UserDefaults {
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

let routineAID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
let routineBID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
let routineCID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!

@MainActor
func runChecks() {

    // MARK: Decode safety — legacy data with no groupID / no groups key at all

    do {
        let defaults = freshDefaults()

        // A pre-grouping saved routine blob: no "groupID" key present.
        let legacyJSON = """
        [{"id":"\(routineAID.uuidString)","name":"Push Day","exercises":["Bench Press"],"preferredSetCounts":{}}]
        """
        defaults.set(legacyJSON.data(using: .utf8)!, forKey: "routines")
        // No "routineGroups" key written at all — simulates every install
        // before this feature shipped.

        let store = WorkoutStore(defaults: defaults)
        check("legacy routine blob (no groupID key) decodes without dropping the routine",
              store.routines.count == 1)
        check("legacy routine decodes as ungrouped", store.routines.first?.groupID == nil)
        check("missing routineGroups key decodes to an empty array, not a crash",
              store.routineGroups.isEmpty)
    }

    // MARK: Round-trip: a routine saved WITH a groupID decodes back correctly

    do {
        let defaults = freshDefaults()
        let groupID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let json = """
        [{"id":"\(routineAID.uuidString)","name":"Chest A","exercises":[],"preferredSetCounts":{},"groupID":"\(groupID.uuidString)"}]
        """
        defaults.set(json.data(using: .utf8)!, forKey: "routines")
        let store = WorkoutStore(defaults: defaults)
        check("routine saved with a groupID round-trips it", store.routines.first?.groupID == groupID)
    }

    // MARK: Group CRUD

    do {
        let defaults = freshDefaults()
        let store = WorkoutStore(defaults: defaults)

        store.addRoutine(Routine(id: routineAID, name: "Chest A", exercises: []))
        store.addRoutine(Routine(id: routineBID, name: "Chest B", exercises: []))
        store.addRoutine(Routine(id: routineCID, name: "Leg A", exercises: []))

        let chestGroup = store.addRoutineGroup(name: "Chest Day")
        let legGroup = store.addRoutineGroup(name: "Leg Day")
        check("groups persist under the routineGroups key",
              (defaults.data(forKey: "routineGroups")
                .flatMap { try? JSONDecoder().decode([RoutineGroup].self, from: $0) })?.count == 2)
        check("second group's order is strictly greater (ascending, stable order)",
              legGroup.order > chestGroup.order)

        store.setRoutineGroup(chestGroup.id, forRoutineID: routineAID)
        store.setRoutineGroup(chestGroup.id, forRoutineID: routineBID)
        store.setRoutineGroup(legGroup.id, forRoutineID: routineCID)

        check("assigning a group sets groupID", store.routine(withID: routineAID)?.groupID == chestGroup.id)
        check("a second routine can join the same group", store.routine(withID: routineBID)?.groupID == chestGroup.id)
        check("a different routine keeps its own group", store.routine(withID: routineCID)?.groupID == legGroup.id)

        let persistedRoutines = defaults.data(forKey: "routines")
            .flatMap { try? JSONDecoder().decode([Routine].self, from: $0) }
        check("group assignment persists to the routines key",
              persistedRoutines?.first(where: { $0.id == routineAID })?.groupID == chestGroup.id)

        store.setRoutineGroup(nil, forRoutineID: routineAID)
        check("removing from a group sets groupID back to nil", store.routine(withID: routineAID)?.groupID == nil)
        check("removing from a group never deletes the routine", store.routine(withID: routineAID) != nil)

        store.renameRoutineGroup(id: legGroup.id, name: "Leg Day (Renamed)")
        check("rename updates the group's name",
              store.routineGroups.first(where: { $0.id == legGroup.id })?.name == "Leg Day (Renamed)")
        check("rename does not touch other groups",
              store.routineGroups.first(where: { $0.id == chestGroup.id })?.name == "Chest Day")

        store.renameRoutineGroup(id: UUID(), name: "Ghost")
        check("renaming a nonexistent group id is a no-op", store.routineGroups.count == 2)

        // Delete a NON-empty group: member routines fall back to ungrouped,
        // never deleted.
        store.deleteRoutineGroup(id: chestGroup.id)
        check("deleting a group removes it from routineGroups",
              !store.routineGroups.contains(where: { $0.id == chestGroup.id }))
        check("a routine that was in the deleted group becomes ungrouped",
              store.routine(withID: routineBID)?.groupID == nil)
        check("deleting a group never deletes its routines", store.routines.count == 3)

        // Delete an EMPTY group.
        let emptyGroup = store.addRoutineGroup(name: "Arms Day")
        check("a freshly created empty group has no members",
              store.routines.filter { $0.groupID == emptyGroup.id }.isEmpty)
        store.deleteRoutineGroup(id: emptyGroup.id)
        check("an empty group can be deleted too",
              !store.routineGroups.contains(where: { $0.id == emptyGroup.id }))

        store.deleteRoutineGroup(id: UUID())
        check("deleting a nonexistent group id is a safe no-op (no crash, count unchanged)",
              store.routineGroups.count == 1)

        defaults.removePersistentDomain(forName: suiteName)
    }
}

MainActor.assumeIsolated {
    runChecks()
}

print("==========================")
if failures == 0 {
    print("ALL CHECKS PASSED")
    exit(0)
} else {
    print("\(failures) CHECK(S) FAILED")
    exit(1)
}
