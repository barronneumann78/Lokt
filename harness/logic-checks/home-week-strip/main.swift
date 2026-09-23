// Logic check: Home screen math (v2 look, phase 2 — HomeInsights).
// - Week strip: seven buckets Mon–Sun in the LOCAL calendar (a Sunday
//   23:30 Los Angeles session is Sunday, not the UTC Monday), Monday-first
//   even when the base calendar starts weeks on Sunday, today flagged once,
//   quiet days present at zero (never missing), letters from the locale.
// - Completed-only volume: explicit `completed == false` never counts,
//   legacy nil counts, free-text weights parse through AnalyticsMath.
// - Vs-last-week percent, and the two hidden-chip cases (no baseline last
//   week; nothing logged yet this week).
// - SESSIONS · 7D rolling window edges; STREAK week counting (quiet current
//   week survives, a gap breaks it).
// - PRs · 30D: reuses the Analytics day-scorecard rule (first-ever day seeds,
//   canonical names merge, unchecked sets never PR, window edges).
// - "Up next": none / single / ungrouped / grouped (least-recently-done
//   sibling, never-done first, stored-order ties, dangling group ids,
//   legacy name-matched sessions, just-done routine never offered).
// Compiles against the REAL Models / AnalyticsModels / ExercisePositionLogic /
// HomeInsights. Deterministic: fixed dates, fixed zone, never Date().
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

func approx(_ lhs: Double?, _ rhs: Double, tolerance: Double = 0.01) -> Bool {
    guard let lhs else { return false }
    return abs(lhs - rhs) <= tolerance
}

// MARK: - Fixed calendar / dates (deterministic — never Date())

// A US-style base calendar (weeks start Sunday) in Los Angeles: proves the
// Monday-first override AND local-day bucketing across a UTC date line.
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

let pushAID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
let pushBID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
let pushCID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
let legsID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
let pushGroupID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
let goneGroupID = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!

func set(_ weight: String, _ reps: String, _ completed: Bool? = true) -> WorkoutSet {
    WorkoutSet(weight: weight, reps: reps, completed: completed)
}

let routineNames: [UUID: String] = [pushAID: "Push A", pushBID: "Push B", pushCID: "Push C", legsID: "Legs"]

var sessionCounter = 0
/// A session for `routineID`, named after it (the app's own matching rule is
/// id OR name, so a mis-named fixture would credit the wrong routine).
func session(
    _ date: Date,
    routineID: UUID? = pushAID,
    name: String? = nil,
    logs: [String: [WorkoutSet]] = ["Bench Press": [set("100", "10")]],
    duration: Int? = nil
) -> WorkoutSession {
    sessionCounter += 1
    let id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", sessionCounter))!
    let routineName = name ?? routineID.flatMap { routineNames[$0] } ?? "Push A"
    return WorkoutSession(id: id, date: date, routineID: routineID, routineName: routineName, logs: logs, durationSeconds: duration)
}

// MARK: - 1. Calendar & week bucketing

do {
    check("weekCalendar starts weeks on Monday even when the base starts on Sunday",
          base.firstWeekday == 1 && calendar.firstWeekday == 2)
    check("weekCalendar keeps the base time zone", calendar.timeZone.identifier == "America/Los_Angeles")

    let week = HomeInsights.week(offset: 0, from: now, calendar: calendar)
    check("this week runs Mon 9/21 00:00 → Mon 9/28 00:00 local",
          week?.start == at(2026, 9, 21, 0) && week?.end == at(2026, 9, 28, 0))
    let last = HomeInsights.week(offset: -1, from: now, calendar: calendar)
    check("last week runs Mon 9/14 → Mon 9/21", last?.start == at(2026, 9, 14, 0) && last?.end == at(2026, 9, 21, 0))

    // Sunday 9/20 23:30 LA is Monday 9/21 06:30 UTC — must stay in LAST week.
    let sundayLate = session(at(2026, 9, 20, 23, 30))
    let mondayEarly = session(at(2026, 9, 21, 0, 0))
    let sundayThisWeek = session(at(2026, 9, 27, 23, 59))
    let nextMonday = session(at(2026, 9, 28, 0, 0))
    let all = [sundayLate, mondayEarly, sundayThisWeek, nextMonday]

    let thisWeek = HomeInsights.sessions(all, inWeekOffset: 0, now: now, calendar: calendar)
    check("Mon 00:00 and Sun 23:59 (local) are this week; late Sunday before and next Monday are not",
          thisWeek.map(\.id) == [mondayEarly.id, sundayThisWeek.id])
    let lastWeek = HomeInsights.sessions(all, inWeekOffset: -1, now: now, calendar: calendar)
    check("late-Sunday-local session (UTC Monday) buckets to last week", lastWeek.map(\.id) == [sundayLate.id])
}

// MARK: - 2. Week strip

do {
    let sessions = [
        session(at(2026, 9, 20, 23, 30), logs: ["Squat": [set("300", "5")]]),        // last week's Sunday → excluded
        session(at(2026, 9, 21, 0, 0), logs: ["Bench Press": [set("100", "10")]]),  // Mon 1000
        session(at(2026, 9, 23, 7), logs: ["Row": [set("50", "10")]]),               // Wed 500
        session(at(2026, 9, 23, 18), logs: ["Curl": [set("25", "10")]]),             // Wed +250
        session(at(2026, 9, 27, 23, 59), logs: ["Deadlift": [set("200", "3")]]),     // Sun 600
        session(at(2026, 9, 28, 0, 0), logs: ["Deadlift": [set("999", "9")]])        // next week → excluded
    ]
    let strip = HomeInsights.weekStrip(sessions: sessions, now: now, calendar: calendar)

    check("strip has exactly seven days", strip.count == 7)
    check("strip runs Mon → Sun", strip.map(\.letter) == ["M", "T", "W", "T", "F", "S", "S"])
    check("strip days start Mon 9/21 and end Sun 9/27",
          strip.first?.day == at(2026, 9, 21, 0) && strip.last?.day == at(2026, 9, 27, 0))
    check("volumes bucket by local day: Mon 1000, Wed 750 (two sessions), Sun 600, others 0",
          strip.map(\.volume) == [1000, 0, 750, 0, 0, 0, 600])
    check("today (Wednesday) is flagged exactly once, at index 2",
          strip.filter(\.isToday).count == 1 && strip[2].isToday)

    let quiet = HomeInsights.weekStrip(sessions: [], now: now, calendar: calendar)
    check("an empty week still yields seven zero-volume days (flat bars, never nothing)",
          quiet.count == 7 && quiet.allSatisfy { $0.volume == 0 } && quiet[2].isToday)

    // A Monday `now` still marks Monday as today and buckets nothing from the prior Sunday.
    let mondayNow = at(2026, 9, 21, 8)
    let mondayStrip = HomeInsights.weekStrip(sessions: sessions, now: mondayNow, calendar: calendar)
    check("on Monday morning today is index 0 and last Sunday's volume is absent",
          mondayStrip[0].isToday && mondayStrip.map(\.volume) == [1000, 0, 750, 0, 0, 0, 600])
}

// MARK: - 3. Completed-only volume

do {
    let mixed = session(now, logs: [
        "Bench Press": [set("100", "10"), set("100", "10", false), set("100", "10", nil)],
        "Row": [set("135 lbs", "8"), set("", ""), set("bw", "12")]
    ])
    check("explicit false never counts; nil (legacy) counts; free-text '135 lbs' parses",
          HomeInsights.sessionVolume(mixed) == 1000 + 1000 + 1080)
    check("counted sets = completed sets with parseable numbers (bodyweight reps-only counts)",
          HomeInsights.countedSets(mixed) == 4)
    check("total volume sums sessions", HomeInsights.totalVolume([mixed, mixed]) == 2 * 3080)

    let strip = HomeInsights.weekStrip(sessions: [mixed], now: now, calendar: calendar)
    check("strip uses the same completed-only rule", strip[2].volume == 3080)
}

// MARK: - 4. Vs-last-week chip

do {
    check("+75% when this week is 1750 vs 1000", approx(HomeInsights.volumeDeltaPercent(current: 1750, previous: 1000), 75))
    check("−40% when this week is 600 vs 1000", approx(HomeInsights.volumeDeltaPercent(current: 600, previous: 1000), -40))
    check("chip hidden when last week had no volume", HomeInsights.volumeDeltaPercent(current: 1750, previous: 0) == nil)
    check("chip hidden when this week has no volume yet", HomeInsights.volumeDeltaPercent(current: 0, previous: 1000) == nil)
    check("chip hidden when both are zero", HomeInsights.volumeDeltaPercent(current: 0, previous: 0) == nil)

    let lastWeekOnly = [session(at(2026, 9, 16), logs: ["Bench Press": [set("100", "10")]])]
    let current = HomeInsights.totalVolume(HomeInsights.sessions(lastWeekOnly, inWeekOffset: 0, now: now, calendar: calendar))
    let previous = HomeInsights.totalVolume(HomeInsights.sessions(lastWeekOnly, inWeekOffset: -1, now: now, calendar: calendar))
    check("end to end: sessions only last week → previous 1000, current 0, chip hidden",
          previous == 1000 && current == 0 && HomeInsights.volumeDeltaPercent(current: current, previous: previous) == nil)
}

// MARK: - 5. Volume label

do {
    let big = HomeInsights.volumeLabel(12_400)
    let small = HomeInsights.volumeLabel(850)
    let zero = HomeInsights.volumeLabel(0)
    check("12,400 → 12.4 k lb", big.value == "12.4" && big.unit == "k lb")
    check("850 → 850 lb", small.value == "850" && small.unit == "lb")
    check("0 → 0 lb", zero.value == "0" && zero.unit == "lb")
}

// MARK: - 6. SESSIONS · 7D window

do {
    let sessions = [
        session(at(2026, 9, 16, 23, 59)),   // 7 days before today's date → out
        session(at(2026, 9, 17, 0, 0)),     // window start → in
        session(at(2026, 9, 20, 12)),
        session(at(2026, 9, 23, 9)),        // today → in
        session(at(2026, 9, 23, 23, 59)),   // later today → in (whole day counts)
        session(at(2026, 9, 24, 0, 0))      // tomorrow → out
    ]
    let last7 = HomeInsights.sessions(sessions, inLastDays: 7, now: now, calendar: calendar)
    check("last 7 days = today plus the six days before it, whole days",
          last7.count == 4 && last7.first?.date == at(2026, 9, 17, 0, 0))
    check("a zero-day window is empty", HomeInsights.sessions(sessions, inLastDays: 0, now: now, calendar: calendar).isEmpty)
}

// MARK: - 7. STREAK weeks

do {
    func streak(_ dates: [Date]) -> Int {
        HomeInsights.streakWeeks(sessions: dates.map { session($0) }, now: now, calendar: calendar)
    }
    check("no sessions → 0", streak([]) == 0)
    check("only the current week → 1", streak([at(2026, 9, 22)]) == 1)
    check("current + two prior weeks → 3", streak([at(2026, 9, 22), at(2026, 9, 15), at(2026, 9, 8)]) == 3)
    check("quiet current week does not break it: last week + the one before → 2",
          streak([at(2026, 9, 15), at(2026, 9, 8)]) == 2)
    check("a gap ends the count: current, skip, two weeks ago → 1", streak([at(2026, 9, 22), at(2026, 9, 8)]) == 1)
    check("quiet current AND last week → 0 even with older history", streak([at(2026, 9, 8), at(2026, 9, 1)]) == 0)
    check("several sessions in one week count once", streak([at(2026, 9, 21), at(2026, 9, 23), at(2026, 9, 14)]) == 2)
    check("Monday-first weeks: a Sunday 9/20 session belongs to LAST week, so with a Wed 9/23 session the streak is 2",
          streak([at(2026, 9, 23), at(2026, 9, 20)]) == 2)
}

// MARK: - 8. PRs · 30D (Analytics day-scorecard rule)

do {
    // Canonical resolver: "bench" / "Bench" / "Bench Press" are one exercise.
    let library = ["Bench Press": Exercise(name: "Bench Press", muscleGroup: .chest),
                   "Squat": Exercise(name: "Squat", muscleGroup: .legs),
                   "Row": Exercise(name: "Row", muscleGroup: .back)]
    func resolve(_ name: String) -> Exercise? {
        let key = name.lowercased()
        if key.hasPrefix("bench") { return library["Bench Press"] }
        return library[name]
    }
    func prs(_ sessions: [WorkoutSession], now: Date = now) -> Int {
        HomeInsights.prCount(sessions: sessions, lastDays: 30, now: now, calendar: calendar, resolve: resolve)
    }

    // Window on Wed 9/23: Tue 8/25 through Wed 9/23.
    let seed = session(at(2026, 8, 1), logs: ["Bench": [set("100", "5")]])                // first ever → no PR, outside window anyway
    let pr1 = session(at(2026, 9, 1), logs: ["Bench Press": [set("110", "5")]])           // beats 100 → PR
    let flat = session(at(2026, 9, 10), logs: ["bench": [set("105", "5")]])               // below 110 → no PR
    let pr2 = session(at(2026, 9, 20), logs: ["Bench Press": [set("120", "5")]])          // beats 110 → PR
    check("two e1RM PRs in the window; names canonicalize so 8/1 seeds the baseline",
          prs([seed, pr1, flat, pr2]) == 2)

    let squatFirst = session(at(2026, 9, 15), logs: ["Squat": [set("200", "5")]])
    check("an exercise's first-ever day inside the window seeds, it is not a PR",
          prs([seed, pr1, flat, pr2, squatFirst]) == 2)

    let unchecked = session(at(2026, 9, 22), logs: ["Bench Press": [set("200", "5", false)]])
    check("an unchecked heavier set never earns a PR", prs([seed, pr1, flat, pr2, unchecked]) == 2)

    let rowSeed = session(at(2026, 8, 1), logs: ["Row": [set("100", "5")]])
    let rowEdgeOut = session(at(2026, 8, 24), logs: ["Row": [set("110", "5")]])           // day before the window
    check("a PR the day before the window is not counted", prs([rowSeed, rowEdgeOut]) == 0)
    let rowEdgeIn = session(at(2026, 8, 25, 0, 0), logs: ["Row": [set("110", "5")]])      // window start
    check("a PR on the window's first day is counted", prs([rowSeed, rowEdgeIn]) == 1)

    let twoSameDay = [
        session(at(2026, 9, 1), logs: ["Bench Press": [set("110", "5")]]),
        session(at(2026, 9, 1, 19), logs: ["Bench Press": [set("115", "5")]])
    ]
    check("two sessions on one day yield one PR for that exercise (per-day rule)", prs([seed] + twoSameDay) == 1)
    check("no sessions → 0", prs([]) == 0)
}

// MARK: - 9. Up next

do {
    let pushA = Routine(id: pushAID, name: "Push A", exercises: ["Bench Press"], groupID: pushGroupID)
    let pushB = Routine(id: pushBID, name: "Push B", exercises: ["Incline Press"], groupID: pushGroupID)
    let pushC = Routine(id: pushCID, name: "Push C", exercises: ["Dip"], groupID: pushGroupID)
    let legs = Routine(id: legsID, name: "Legs", exercises: ["Squat"])
    let pushGroup = RoutineGroup(id: pushGroupID, name: "Push", order: 0)

    func next(_ routines: [Routine], _ groups: [RoutineGroup] = [], _ sessions: [WorkoutSession]) -> UUID? {
        HomeInsights.nextRoutine(routines: routines, groups: groups, sessions: sessions)?.id
    }

    // none / single
    check("no routines → nil (CREATE A ROUTINE)", next([], [], []) == nil)
    check("single routine → that one even when never done", next([legs], [], []) == legsID)
    check("single routine → that one even when just done", next([legs], [], [session(now, routineID: legsID, name: "Legs")]) == legsID)

    // ungrouped
    let ungrouped = [Routine(id: pushAID, name: "Push A", exercises: []),
                     Routine(id: pushBID, name: "Push B", exercises: []),
                     legs]
    check("ungrouped, none done → first in stored order", next(ungrouped, [], []) == pushAID)
    check("ungrouped → never-done routine before any done one",
          next(ungrouped, [], [session(at(2026, 9, 22), routineID: pushAID), session(at(2026, 9, 10), routineID: pushBID)]) == legsID)
    check("ungrouped, all done → least recently done",
          next(ungrouped, [], [session(at(2026, 9, 22), routineID: pushAID),
                               session(at(2026, 9, 10), routineID: pushBID),
                               session(at(2026, 9, 15), routineID: legsID)]) == pushBID)
    check("ungrouped → the routine just done is never offered while another exists",
          next(ungrouped, [], [session(at(2026, 9, 22), routineID: pushAID),
                               session(at(2026, 9, 21), routineID: pushBID),
                               session(at(2026, 9, 20), routineID: legsID)]) == legsID)

    // grouped
    let grouped = [pushA, pushB, pushC, legs]
    check("grouped → least-recently-done sibling of the routine just done, ahead of a never-done routine outside the group",
          next(grouped, [pushGroup], [session(at(2026, 9, 22), routineID: pushAID),
                                      session(at(2026, 9, 15), routineID: pushBID),
                                      session(at(2026, 9, 18), routineID: pushCID)]) == pushBID)
    check("grouped → never-done sibling first, stored-order tie-break (B before C)",
          next(grouped, [pushGroup], [session(at(2026, 9, 22), routineID: pushAID)]) == pushBID)
    check("grouped → after A then B, C is next",
          next(grouped, [pushGroup], [session(at(2026, 9, 20), routineID: pushAID),
                                      session(at(2026, 9, 22), routineID: pushBID)]) == pushCID)
    check("grouped → the rotation wraps: after A, B, C the least recent is A again",
          next(grouped, [pushGroup], [session(at(2026, 9, 18), routineID: pushAID),
                                      session(at(2026, 9, 20), routineID: pushBID),
                                      session(at(2026, 9, 22), routineID: pushCID)]) == pushAID)
    check("most recent routine is ungrouped → overall least-recently-done rule",
          next(grouped, [pushGroup], [session(at(2026, 9, 22), routineID: legsID),
                                      session(at(2026, 9, 10), routineID: pushAID),
                                      session(at(2026, 9, 12), routineID: pushBID),
                                      session(at(2026, 9, 14), routineID: pushCID)]) == pushAID)
    check("most recent routine's group no longer exists (dangling id) → reads as ungrouped",
          next(grouped, [], [session(at(2026, 9, 22), routineID: pushAID),
                             session(at(2026, 9, 21), routineID: pushBID),
                             session(at(2026, 9, 20), routineID: pushCID),
                             session(at(2026, 9, 19), routineID: legsID)]) == legsID)
    let loneGroup = RoutineGroup(id: goneGroupID, name: "Solo", order: 1)
    let soloLegs = Routine(id: legsID, name: "Legs", exercises: ["Squat"], groupID: goneGroupID)
    check("most recent routine is alone in its group → no sibling → overall rule",
          next([pushA, pushB, soloLegs], [pushGroup, loneGroup],
               [session(at(2026, 9, 22), routineID: legsID),
                session(at(2026, 9, 20), routineID: pushAID)]) == pushBID)

    // legacy sessions without a routine id match by name (the logger's rule)
    check("legacy session (no routineID) matched by name marks the routine as done",
          next(ungrouped, [], [session(at(2026, 9, 22), routineID: nil, name: "Push A"),
                               session(at(2026, 9, 21), routineID: nil, name: "Push B")]) == legsID)
    let renamed = Routine(id: pushAID, name: "Push Day", exercises: [], historyNames: ["Push A"])
    check("a renamed routine still counts sessions logged under its old name",
          HomeInsights.lastDoneDates(routines: [renamed], sessions: [session(at(2026, 9, 22), routineID: nil, name: "Push A")])[pushAID] == at(2026, 9, 22))

    // lastDoneDates keeps the latest date per routine
    let dates = HomeInsights.lastDoneDates(routines: grouped, sessions: [
        session(at(2026, 9, 1), routineID: pushAID), session(at(2026, 9, 22), routineID: pushAID), session(at(2026, 9, 10), routineID: pushAID)
    ])
    check("lastDoneDates keeps the latest session per routine and omits never-done ones",
          dates[pushAID] == at(2026, 9, 22) && dates[pushBID] == nil && dates.count == 1)
}

// MARK: - Summary

if failures == 0 {
    print("ALL PASSED")
    exit(0)
} else {
    print("\(failures) FAILED")
    exit(1)
}
