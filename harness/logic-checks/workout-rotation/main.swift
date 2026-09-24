// Logic check: Workout tab rotation (look v2, phase 6 — WorkoutTabInsights).
// - Next member per group: HomeInsights.nextRoutine run over ONE group's
//   members (never forked): never-done member wins, rotation wraps, the
//   member just done is never next, a lone member is always next, an empty
//   group has none, other groups' sessions don't move the pick, legacy
//   name-matched sessions count.
// - Rotation (which cards wear the gradient START): each group's next, plus
//   the overall next only when it is ungrouped (dangling group id included);
//   with no groups exactly the overall next; Home's "Up next" is always one.
// - Last-done chip: Never / Today / weekday this Mon–Sun week / "Last Thu" /
//   short date, local-day bucketing, year once it differs.
// - Header count line, "is next" chip wording, three-name exercise preview.
// Compiles against the REAL Models / AnalyticsModels / ExercisePositionLogic /
// HomeInsights / WorkoutTabInsights. Deterministic: fixed dates, fixed zone.
import Foundation

// MARK: - Stubs for app-only symbols AnalyticsModels.swift references

enum MuscleGroup: String, Hashable {
    case chest, back, shoulders, arms, legs, core, other
}

struct Exercise: Codable {
    var name: String
    var muscleGroup: MuscleGroup

    enum CodingKeys: String, CodingKey { case name }
    init(name: String, muscleGroup: MuscleGroup) {
        self.name = name
        self.muscleGroup = muscleGroup
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        muscleGroup = .other
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
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

// MARK: - Fixed calendar / dates (deterministic — never Date())

// US-style base calendar (weeks start Sunday) in Los Angeles: proves the
// Monday-first weeks and local-day bucketing the chip relies on.
var base = Calendar(identifier: .gregorian)
base.timeZone = TimeZone(identifier: "America/Los_Angeles")!
base.locale = Locale(identifier: "en_US")
base.firstWeekday = 1
let calendar = HomeInsights.weekCalendar(base)

func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 10, _ min: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

// Wednesday 2026-09-23 10:00 Los Angeles. This week: Mon 9/21 – Sun 9/27.
let now = at(2026, 9, 23)

let chestAID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
let chestBID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
let chestCID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
let legsAID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
let legsBID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
let armsID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
let coreID = UUID(uuidString: "77777777-7777-7777-7777-777777777777")!
let chestGroupID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
let legsGroupID = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
let goneGroupID = UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!

let chestGroup = RoutineGroup(id: chestGroupID, name: "Chest", order: 0)
let legsGroup = RoutineGroup(id: legsGroupID, name: "Legs", order: 1)

let chestA = Routine(id: chestAID, name: "Chest A", exercises: ["Bench Press"], groupID: chestGroupID)
let chestB = Routine(id: chestBID, name: "Chest B", exercises: ["Incline Press"], groupID: chestGroupID)
let chestC = Routine(id: chestCID, name: "Chest C", exercises: ["Dip"], groupID: chestGroupID)
let legsA = Routine(id: legsAID, name: "Legs A", exercises: ["Squat"], groupID: legsGroupID)
let legsB = Routine(id: legsBID, name: "Legs B", exercises: ["Deadlift"], groupID: legsGroupID)
let arms = Routine(id: armsID, name: "Arms", exercises: ["Curl"])
let core = Routine(id: coreID, name: "Core", exercises: ["Plank"])

let routineNames: [UUID: String] = [
    chestAID: "Chest A", chestBID: "Chest B", chestCID: "Chest C",
    legsAID: "Legs A", legsBID: "Legs B", armsID: "Arms", coreID: "Core"
]

var sessionCounter = 0
/// A session for `routineID`, named after it (the app's matching rule is id
/// OR name, so a mis-named fixture would credit the wrong routine).
func session(_ date: Date, routineID: UUID?, name: String? = nil) -> WorkoutSession {
    sessionCounter += 1
    let id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", sessionCounter))!
    let routineName = name ?? routineID.flatMap { routineNames[$0] } ?? "Chest A"
    return WorkoutSession(
        id: id,
        date: date,
        routineID: routineID,
        routineName: routineName,
        logs: ["Bench Press": [WorkoutSet(weight: "100", reps: "10", completed: true)]],
        durationSeconds: nil
    )
}

let library = [chestA, chestB, chestC, legsA, legsB, arms]

func nextMember(_ group: RoutineGroup, _ routines: [Routine] = library, _ sessions: [WorkoutSession]) -> UUID? {
    WorkoutTabInsights.nextMember(of: group, routines: routines, sessions: sessions)?.id
}

// MARK: - 1. Next member per group

print("Next member per group:")

check("no sessions → first member in stored order",
      nextMember(chestGroup, library, []) == chestAID)
check("never-done member wins over every done one",
      nextMember(chestGroup, library, [session(at(2026, 9, 20), routineID: chestAID),
                                       session(at(2026, 9, 22), routineID: chestBID)]) == chestCID)
check("all done → least recently done (rotation wraps to A after A, B, C)",
      nextMember(chestGroup, library, [session(at(2026, 9, 18), routineID: chestAID),
                                       session(at(2026, 9, 20), routineID: chestBID),
                                       session(at(2026, 9, 22), routineID: chestCID)]) == chestAID)
check("after A then B, C is next",
      nextMember(chestGroup, library, [session(at(2026, 9, 20), routineID: chestAID),
                                       session(at(2026, 9, 22), routineID: chestBID)]) == chestCID)
check("the member just done is never next while a sibling exists",
      nextMember(chestGroup, library, [session(at(2026, 9, 22), routineID: chestAID),
                                       session(at(2026, 9, 15), routineID: chestBID),
                                       session(at(2026, 9, 16), routineID: chestCID)]) == chestBID)
check("two-member rotation alternates: A done yesterday → B",
      nextMember(legsGroup, library, [session(at(2026, 9, 22), routineID: legsAID),
                                      session(at(2026, 9, 19), routineID: legsBID)]) == legsBID)
check("two-member rotation alternates: then B done today → A",
      nextMember(legsGroup, library, [session(at(2026, 9, 22), routineID: legsAID),
                                      session(at(2026, 9, 19), routineID: legsBID),
                                      session(at(2026, 9, 23), routineID: legsBID)]) == legsAID)
check("a lone member is next even when it was just done",
      nextMember(legsGroup, [chestA, legsA, arms], [session(at(2026, 9, 23), routineID: legsAID)]) == legsAID)
check("a lone member is next when never done",
      nextMember(legsGroup, [chestA, legsA, arms], []) == legsAID)
check("an empty group has no next member",
      nextMember(legsGroup, [chestA, chestB, arms], []) == nil)
check("sessions of routines outside the group never move the pick",
      nextMember(chestGroup, library, [session(at(2026, 9, 22), routineID: chestAID),
                                       session(at(2026, 9, 15), routineID: chestBID),
                                       session(at(2026, 9, 16), routineID: chestCID),
                                       session(at(2026, 9, 23), routineID: legsAID),
                                       session(at(2026, 9, 23, 12), routineID: armsID)]) == chestBID)
check("a legacy session without a routine id counts by name",
      nextMember(chestGroup, library, [session(at(2026, 9, 22), routineID: nil, name: "Chest A"),
                                       session(at(2026, 9, 21), routineID: nil, name: "Chest C")]) == chestBID)
check("per-group pick equals HomeInsights.nextRoutine over the members alone (no fork)",
      nextMember(chestGroup, library, [session(at(2026, 9, 22), routineID: chestAID)])
        == HomeInsights.nextRoutine(routines: [chestA, chestB, chestC], groups: [chestGroup],
                                    sessions: [session(at(2026, 9, 22), routineID: chestAID)])?.id)

// MARK: - 2. Rotation — which cards wear the gradient START

print("Rotation (gradient START cards):")

func rotation(_ routines: [Routine] = library, _ groups: [RoutineGroup] = [chestGroup, legsGroup], _ sessions: [WorkoutSession]) -> WorkoutTabInsights.Rotation {
    WorkoutTabInsights.rotation(routines: routines, groups: groups, sessions: sessions)
}

do {
    // Arms (ungrouped) done most recently → overall next is the least recent
    // overall (Legs B, never done, stored before nothing else never-done).
    let sessions = [session(at(2026, 9, 23), routineID: armsID),
                    session(at(2026, 9, 20), routineID: chestAID),
                    session(at(2026, 9, 21), routineID: chestBID),
                    session(at(2026, 9, 22), routineID: chestCID),
                    session(at(2026, 9, 19), routineID: legsAID)]
    let r = rotation(library, [chestGroup, legsGroup], sessions)
    check("each group carries its own next (Chest → A, Legs → never-done B)",
          r.nextByGroup[chestGroupID]?.id == chestAID && r.nextByGroup[legsGroupID]?.id == legsBID)
    check("overall next inside a group → no ungrouped pill",
          r.ungroupedNext == nil)
    check("isNext: exactly the two group nexts",
          r.isNext(chestAID) && r.isNext(legsBID) && !r.isNext(chestBID) && !r.isNext(chestCID)
            && !r.isNext(legsAID) && !r.isNext(armsID))
    check("Home's Up next is one of the gradient cards",
          HomeInsights.nextRoutine(routines: library, groups: [chestGroup, legsGroup], sessions: sessions)
            .map { r.isNext($0.id) } == true)
}

do {
    // The just-done routine's group siblings come before a never-done routine
    // outside the group (Home's documented rule): Legs B done today → overall
    // next is Legs A, NOT never-done Arms. No ungrouped pill.
    let sessions = [session(at(2026, 9, 20), routineID: chestAID),
                    session(at(2026, 9, 21), routineID: chestBID),
                    session(at(2026, 9, 22), routineID: chestCID),
                    session(at(2026, 9, 19), routineID: legsAID),
                    session(at(2026, 9, 23), routineID: legsBID)]
    let r = rotation(library, [chestGroup, legsGroup], sessions)
    check("just-done group's sibling is the overall next → never-done ungrouped Arms gets no pill",
          r.ungroupedNext == nil && !r.isNext(armsID))
    check("group nexts (Chest → A, Legs → A)",
          r.nextByGroup[chestGroupID]?.id == chestAID && r.nextByGroup[legsGroupID]?.id == legsAID)
    check("Home's Up next is one of the gradient cards (sibling case)",
          HomeInsights.nextRoutine(routines: library, groups: [chestGroup, legsGroup], sessions: sessions)
            .map { r.isNext($0.id) } == true)
}

do {
    // Ungrouped fallback: the most recent routine (Arms) is ungrouped, so the
    // overall next is the least-recently-done overall — never-done Core,
    // also ungrouped → the ungrouped list gets a pill too.
    let sessions = [session(at(2026, 9, 20), routineID: chestAID),
                    session(at(2026, 9, 21), routineID: chestBID),
                    session(at(2026, 9, 22), routineID: chestCID),
                    session(at(2026, 9, 19), routineID: legsAID),
                    session(at(2026, 9, 18), routineID: legsBID),
                    session(at(2026, 9, 23), routineID: armsID)]
    let r = rotation(library + [core], [chestGroup, legsGroup], sessions)
    check("overall next ungrouped → ungrouped pill on it (Core)", r.ungroupedNext?.id == coreID)
    check("group nexts unaffected by the ungrouped pill (Chest → A, Legs → B)",
          r.nextByGroup[chestGroupID]?.id == chestAID && r.nextByGroup[legsGroupID]?.id == legsBID)
    check("isNext: one per group plus the ungrouped next, never the just-done Arms",
          r.isNext(coreID) && r.isNext(chestAID) && r.isNext(legsBID)
            && !r.isNext(armsID) && !r.isNext(legsAID) && !r.isNext(chestBID) && !r.isNext(chestCID))
    check("Home's Up next is one of the gradient cards (ungrouped case)",
          HomeInsights.nextRoutine(routines: library + [core], groups: [chestGroup, legsGroup], sessions: sessions)
            .map { r.isNext($0.id) } == true)
}

do {
    // No groups at all → exactly the overall next, nothing else.
    let flat = [Routine(id: chestAID, name: "Chest A", exercises: []),
                Routine(id: chestBID, name: "Chest B", exercises: []),
                arms]
    let sessions = [session(at(2026, 9, 22), routineID: chestAID),
                    session(at(2026, 9, 10), routineID: chestBID),
                    session(at(2026, 9, 15), routineID: armsID)]
    let r = rotation(flat, [], sessions)
    check("no groups → no per-group nexts", r.nextByGroup.isEmpty)
    check("no groups → the overall next (least recently done) wears the pill",
          r.ungroupedNext?.id == chestBID && r.isNext(chestBID) && !r.isNext(chestAID) && !r.isNext(armsID))
    check("no groups, no sessions → first in stored order",
          rotation(flat, [], []).ungroupedNext?.id == chestAID)
}

do {
    // A routine whose group was deleted (dangling id) reads as ungrouped:
    // Chest A (alone in its group, just done) has no sibling, so the overall
    // rule picks never-done Arms — dangling id and all — for the pill.
    let dangling = Routine(id: armsID, name: "Arms", exercises: [], groupID: goneGroupID)
    let sessions = [session(at(2026, 9, 22), routineID: chestAID)]
    let r = rotation([chestA, dangling], [chestGroup], sessions)
    check("dangling group id → treated as ungrouped: never-done Arms is the overall next and gets the pill",
          r.ungroupedNext?.id == armsID && r.nextByGroup[goneGroupID] == nil)
    check("the lone Chest member keeps its group pill", r.nextByGroup[chestGroupID]?.id == chestAID && r.isNext(chestAID))

    // With siblings present the just-done group's rotation wins instead.
    let siblings = rotation([chestA, chestB, chestC, dangling], [chestGroup],
                            [session(at(2026, 9, 22), routineID: chestAID),
                             session(at(2026, 9, 21), routineID: chestBID),
                             session(at(2026, 9, 20), routineID: chestCID)])
    check("dangling routine gets no pill while the just-done group still rotates (Chest → C)",
          siblings.ungroupedNext == nil && siblings.nextByGroup[chestGroupID]?.id == chestCID)
}

do {
    // Single-member group whose member was just done: it keeps its pill
    // (nothing else to rotate to) while the overall next lives elsewhere.
    let sessions = [session(at(2026, 9, 23), routineID: legsAID)]
    let r = rotation([chestA, chestB, legsA, arms], [chestGroup, legsGroup], sessions)
    check("lone-member group keeps a pill on its member even just done", r.isNext(legsAID))
    check("overall next (never-done Chest A) is Chest's next, so no second ungrouped pill",
          r.nextByGroup[chestGroupID]?.id == chestAID && r.ungroupedNext == nil)
}

check("empty library → nothing is next",
      rotation([], [chestGroup], []).nextByGroup.isEmpty && rotation([], [chestGroup], []).ungroupedNext == nil)

// MARK: - 3. Last-done chip

print("Last-done chip:")

func label(_ date: Date?) -> String {
    WorkoutTabInsights.lastDoneLabel(date, now: now, calendar: calendar)
}

check("never done → Never", label(nil) == "Never")
check("earlier today → Today", label(at(2026, 9, 23, 6)) == "Today")
check("Monday of this week → Mon", label(at(2026, 9, 21)) == "Mon")
check("yesterday (Tue, this week) → Tue", label(at(2026, 9, 22)) == "Tue")
check("Sunday 9/20 → Last Sun (Monday-first week, even on a Sunday-first base calendar)",
      label(at(2026, 9, 20)) == "Last Sun")
check("Thursday 9/17 → Last Thu", label(at(2026, 9, 17)) == "Last Thu")
check("Monday 9/14 → Last Mon (first day of last week)", label(at(2026, 9, 14)) == "Last Mon")
check("Sunday 9/13 → short date (two weeks back)", label(at(2026, 9, 13)) == "Sep 13")
check("Sunday 9/20 23:30 Los Angeles is still Last Sun (local day, not the UTC Monday)",
      label(at(2026, 9, 20, 23, 30)) == "Last Sun")
check("earlier this year → month + day", label(at(2026, 9, 2)) == "Sep 2")
check("a different year carries the year", label(at(2025, 8, 2)) == "Aug 2, 2025")

// MARK: - 4. Copy

print("Header count line:")
check("empty library → NO ROUTINES YET", WorkoutTabInsights.countLine(routineCount: 0, groupCount: 0) == "NO ROUTINES YET")
check("one routine, no groups → 1 ROUTINE", WorkoutTabInsights.countLine(routineCount: 1, groupCount: 0) == "1 ROUTINE")
check("five routines, no groups → 5 ROUTINES (group segment omitted)", WorkoutTabInsights.countLine(routineCount: 5, groupCount: 0) == "5 ROUTINES")
check("one group → singular", WorkoutTabInsights.countLine(routineCount: 5, groupCount: 1) == "5 ROUTINES · 1 GROUP")
check("two groups → 5 ROUTINES · 2 GROUPS", WorkoutTabInsights.countLine(routineCount: 5, groupCount: 2) == "5 ROUTINES · 2 GROUPS")
check("no routines but leftover groups → still NO ROUTINES YET", WorkoutTabInsights.countLine(routineCount: 0, groupCount: 2) == "NO ROUTINES YET")

print("Next chip wording:")
check("short name → '<name> is next'", WorkoutTabInsights.nextChipText(for: "Chest B") == "Chest B is next")
check("12-character name still reads '<name> is next'", WorkoutTabInsights.nextChipText(for: "Upper Body A") == "Upper Body A is next")
check("13-character name → 'Next: <name>'", WorkoutTabInsights.nextChipText(for: "Upper Body AB") == "Next: Upper Body AB")
check("surrounding whitespace is trimmed", WorkoutTabInsights.nextChipText(for: "  Push  ") == "Push is next")

print("Exercise preview:")
check("five exercises → first three joined with ' · '",
      WorkoutTabInsights.exercisePreview(["Bench", "Row", "Squat", "Curl", "Dip"]) == "Bench · Row · Squat")
check("two exercises → both", WorkoutTabInsights.exercisePreview(["Bench", "Row"]) == "Bench · Row")
check("no exercises → empty (the view hides the line)", WorkoutTabInsights.exercisePreview([]) == "")

// MARK: - Summary

print("==========================")
if failures == 0 {
    print("ALL CHECKS PASSED")
    exit(0)
} else {
    print("\(failures) CHECK(S) FAILED")
    exit(1)
}
