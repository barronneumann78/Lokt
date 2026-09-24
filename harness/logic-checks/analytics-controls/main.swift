// Logic check: Analytics controls (look v2, agent B — per-chart controls on
// the existing charts).
// - AnalyticsWindow: local-day rolling windows (7d / 30d / 90d / All) with
//   the same edges as Home's SESSIONS · 7D — today included, tomorrow out.
// - Headline tiles: VOLUME · 7D and SETS · 30D, completed-only, window edges.
// - Progression: metric selection (e1RM / top set / volume) on one fixed
//   session set, window filtering, the "≥ 2 e1RM points" picker threshold,
//   the default-exercise rule, the enabled-window and effective-window rules.
// - PR board: standing records, delta vs the previous record, first-ever
//   records carry no delta, ties keep the earlier day, unchecked sets never
//   count, aliases merge, per-window filtering and the PRs tile count.
// - Muscle split donut and distribution per window (30d / 90d / All), "All"
//   has no previous window.
// - Timeline labels, control defaults and storage keys.
// Compiles against the REAL Models / AnalyticsModels / ExercisePositionLogic.
// Deterministic: fixed dates, fixed zone, never Date().
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

func approxAll(_ lhs: [Double], _ rhs: [Double], tolerance: Double = 0.01) -> Bool {
    lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { abs($0 - $1) <= tolerance }
}

// MARK: - Fixed calendar / dates (deterministic — never Date())

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
calendar.locale = Locale(identifier: "en_US")

func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 10, _ min: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

// Wednesday 2026-09-23 10:00 Los Angeles.
let now = at(2026, 9, 23)

func set(_ weight: String, _ reps: String, _ completed: Bool? = true) -> WorkoutSet {
    WorkoutSet(weight: weight, reps: reps, completed: completed)
}

var sessionCounter = 0
func session(_ date: Date, _ logs: [String: [WorkoutSet]]) -> WorkoutSession {
    sessionCounter += 1
    let id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", sessionCounter))!
    return WorkoutSession(id: id, date: date, routineID: nil, routineName: "Session", logs: logs)
}

// Library resolver: "bench" / "Bench Press" are one exercise; "Mystery Lift"
// resolves to nothing (→ the donut's "other" group).
let library: [String: Exercise] = [
    "Bench Press": Exercise(name: "Bench Press", muscleGroup: .chest),
    "Deadlift": Exercise(name: "Deadlift", muscleGroup: .back),
    "Squat": Exercise(name: "Squat", muscleGroup: .legs),
    "Row": Exercise(name: "Row", muscleGroup: .back)
]
func resolve(_ name: String) -> Exercise? {
    if name.lowercased().hasPrefix("bench") { return library["Bench Press"] }
    return library[name]
}

// MARK: - 1. Windows

do {
    check("7d starts Thu 9/17 00:00 (today + six days back)", AnalyticsWindow.sevenDays.start(now: now, calendar: calendar) == at(2026, 9, 17, 0))
    check("30d starts Tue 8/25 00:00", AnalyticsWindow.thirtyDays.start(now: now, calendar: calendar) == at(2026, 8, 25, 0))
    check("90d starts Fri 6/26 00:00", AnalyticsWindow.ninetyDays.start(now: now, calendar: calendar) == at(2026, 6, 26, 0))
    check("All has no start", AnalyticsWindow.all.start(now: now, calendar: calendar) == nil)
    check("every bounded window ends at tomorrow 00:00", AnalyticsWindow.sevenDays.end(now: now, calendar: calendar) == at(2026, 9, 24, 0)
          && AnalyticsWindow.ninetyDays.end(now: now, calendar: calendar) == at(2026, 9, 24, 0))

    let w = AnalyticsWindow.sevenDays
    check("7d: 9/16 23:59 out, 9/17 00:00 in, 9/23 23:59 in, 9/24 00:00 out",
          !w.contains(at(2026, 9, 16, 23, 59), now: now, calendar: calendar)
          && w.contains(at(2026, 9, 17, 0), now: now, calendar: calendar)
          && w.contains(at(2026, 9, 23, 23, 59), now: now, calendar: calendar)
          && !w.contains(at(2026, 9, 24, 0), now: now, calendar: calendar))
    check("All contains the distant past and a future-dated session",
          AnalyticsWindow.all.contains(at(2020, 1, 1), now: now, calendar: calendar)
          && AnalyticsWindow.all.contains(at(2030, 1, 1), now: now, calendar: calendar))

    check("control text 7d / 30d / 90d / All", AnalyticsWindow.allCases.map(\.label) == ["7d", "30d", "90d", "All"])
    check("micro suffix 7D / 30D / 90D / ALL", AnalyticsWindow.allCases.map(\.suffix) == ["7D", "30D", "90D", "ALL"])
    check("progression offers all four windows", AnalyticsWindow.progression == [.sevenDays, .thirtyDays, .ninetyDays, .all])
    check("muscle split / distribution offer 30d / 90d / All", AnalyticsWindow.muscle == [.thirtyDays, .ninetyDays, .all])
    check("PR board offers 30d / 90d / All", AnalyticsWindow.prs == [.thirtyDays, .ninetyDays, .all])
    check("raw values are stable storage keys", AnalyticsWindow(rawValue: "ninetyDays") == .ninetyDays && AnalyticsWindow(rawValue: "90d") == nil)
}

// MARK: - 2. Headline tiles (VOLUME · 7D, SETS · 30D)

do {
    let sessions = [
        session(at(2026, 8, 24, 23, 59), ["Bench Press": [set("100", "10")]]),                  // day before 30d → out
        session(at(2026, 8, 25, 0, 0), ["Bench Press": [set("100", "10")]]),                    // 30d edge → 1 set
        session(at(2026, 9, 16, 23, 59), ["Squat": [set("200", "5"), set("200", "5")]]),        // in 30d, out 7d → 2 sets
        session(at(2026, 9, 17, 0, 0), ["Bench Press": [set("110", "5"), set("110", "5", false)],
                                        "Row": [set("bw", "12")]]),                            // 7d edge → 550 lb, 2 sets
        session(at(2026, 9, 23, 9), ["Bench Press": [set("120", "5", nil)]]),                   // today, legacy nil → 600 lb, 1 set
        session(at(2026, 9, 24, 0, 0), ["Bench Press": [set("999", "9")]])                      // tomorrow → out
    ]
    let snapshot = AnalyticsSnapshot.build(sessions: sessions, resolve: resolve, now: now, calendar: calendar)
    check("VOLUME · 7D = 550 + 600 (unchecked set skipped, legacy nil counts, tomorrow out)", approx(snapshot.headline?.volumeLast7Days, 1150))
    check("SETS · 30D = 6 counted sets (8/24 out, 8/25 in, bodyweight reps-only counts)", snapshot.headline?.setsLast30Days == 6)

    let monday = AnalyticsSnapshot.build(sessions: sessions, resolve: resolve, now: at(2026, 9, 21, 8), calendar: calendar)
    check("on Mon 9/21 the 7d window is 9/15–9/21: 2000 + 550, the 9/23 session is not yet in", approx(monday.headline?.volumeLast7Days, 2550))

    check("empty history → empty snapshot, no headline", AnalyticsSnapshot.build(sessions: [], resolve: resolve, now: now, calendar: calendar).headline == nil)
}

// MARK: - Main fixture (progression, PRs, donut, distribution)

let history: [WorkoutSession] = [
    session(at(2026, 6, 1), ["Bench Press": [set("100", "10")]]),                        // A  e1RM 133.33 · vol 1000 · max 100
    session(at(2026, 7, 15), ["Bench Press": [set("120", "8")]]),                        // B  e1RM 152 · vol 960 · max 120
    session(at(2026, 8, 20), ["Row": [set("50", "10")]]),                                // C  first-ever Row record (66.67)
    session(at(2026, 9, 1), ["bench": [set("130", "5")]]),                               // D  alias → Bench; e1RM 151.67
    session(at(2026, 9, 5), ["Deadlift": [set("300", "3")]]),                            // E  e1RM 330
    session(at(2026, 9, 10), ["Squat": [set("200", "")]]),                               // F  top set only (no reps)
    session(at(2026, 9, 15), ["Bench Press": [set("200", "5", false)]]),                 // G  unchecked → nothing
    session(at(2026, 9, 18), ["Squat": [set("210", "")]]),                               // H  top set only
    session(at(2026, 9, 20), ["Bench Press": [set("140", "3")]]),                        // I  e1RM 154 (new record)
    session(at(2026, 9, 20, 19), ["Bench Press": [set("138", "3")]]),                    // J  same day, lower (151.8)
    session(at(2026, 9, 21), ["Deadlift": [set("315", "2")]]),                           // K  e1RM 336 (record, +6)
    session(at(2026, 9, 22), ["Bench Press": [set("145", "")], "Mystery Lift": [set("50", "10")]]), // L  top set only; unresolved lift
    session(at(2026, 9, 23, 9), ["Bench Press": [set("140", "3", nil)]])                 // M  ties the 154 record
]
let snap = AnalyticsSnapshot.build(sessions: history, resolve: resolve, now: now, calendar: calendar)
let bench = snap.progression["Bench Press"] ?? []
let deadlift = snap.progression["Deadlift"] ?? []

// MARK: - 3. Progression: picker threshold + default exercise

do {
    check("exercise options: most-trained first (Bench 7, Deadlift 2, Squat 2, Mystery Lift 1, Row 1)",
          snap.exerciseOptions.map(\.name) == ["Bench Press", "Deadlift", "Squat", "Mystery Lift", "Row"])
    check("aliases merge: 'bench' session counts toward Bench Press", snap.exerciseOptions.first?.sessionCount == 7)
    check("an all-unchecked session yields no point", !bench.contains { calendar.isDate($0.date, inSameDayAs: at(2026, 9, 15)) })
    check("e1RM counts: Bench 6 (the reps-less 9/22 session has none), Deadlift 2, Squat 0, Row 1",
          snap.exerciseOptions.map(\.e1RMCount) == [6, 2, 0, 1, 1])

    check("picker threshold is 2 e1RM points", AnalyticsSnapshot.pickerMinimumPoints == 2)
    check("picker lists Bench Press and Deadlift only — Squat (2 top-set points, 0 e1RM) and one-point lifts are out",
          snap.progressionPickerOptions.map(\.name) == ["Bench Press", "Deadlift"])

    let options = snap.progressionPickerOptions
    check("default exercise (nothing stored) = the most-trained chartable lift", AnalyticsSnapshot.progressionExercise(stored: "", options: options) == "Bench Press")
    check("a stored chartable pick wins", AnalyticsSnapshot.progressionExercise(stored: "Deadlift", options: options) == "Deadlift")
    check("a stored pick that is no longer chartable falls back to the default", AnalyticsSnapshot.progressionExercise(stored: "Squat", options: options) == "Bench Press")
    check("a stored pick that no longer exists falls back to the default", AnalyticsSnapshot.progressionExercise(stored: "Ghost", options: options) == "Bench Press")
    check("no chartable lifts → nil (placeholder)", AnalyticsSnapshot.progressionExercise(stored: "Bench Press", options: []) == nil)
    check("empty snapshot has no picker options", AnalyticsSnapshot.empty.progressionPickerOptions.isEmpty)
}

// MARK: - 4. Progression: metric selection + window filtering

do {
    func points(_ series: [AnalyticsSnapshot.ProgressionPoint], _ metric: ProgressionMetric, _ window: AnalyticsWindow) -> [AnalyticsSnapshot.MetricPoint] {
        AnalyticsSnapshot.progressionPoints(series, metric: metric, window: window, now: now, calendar: calendar)
    }
    check("metric switch order and labels: e1RM · Top set · Volume",
          ProgressionMetric.allCases == [.estOneRepMax, .maxWeight, .volume]
          && ProgressionMetric.allCases.map(\.label) == ["e1RM", "Top set", "Volume"])
    check("metric raw values are stable storage keys", ProgressionMetric(rawValue: "maxWeight") == .maxWeight)

    let e1RMAll = points(bench, .estOneRepMax, .all)
    check("e1RM · All: six Epley values, oldest first, reps-less session dropped",
          approxAll(e1RMAll.map(\.value), [133.33, 152, 151.67, 154, 151.8, 154]))
    check("Top set · All: seven heaviest-set values (the reps-less 145 counts)",
          approxAll(points(bench, .maxWeight, .all).map(\.value), [100, 120, 130, 140, 138, 145, 140]))
    check("Volume · All: six tonnage values",
          approxAll(points(bench, .volume, .all).map(\.value), [1000, 960, 650, 420, 414, 420]))

    check("e1RM · 7d: the two 9/20 sessions and 9/23", points(bench, .estOneRepMax, .sevenDays).map(\.date) == [at(2026, 9, 20), at(2026, 9, 20, 19), at(2026, 9, 23, 9)])
    check("e1RM · 30d: 9/1 joins", points(bench, .estOneRepMax, .thirtyDays).count == 4)
    check("e1RM · 90d: 7/15 joins, 6/1 stays out", points(bench, .estOneRepMax, .ninetyDays).map(\.date).first == at(2026, 7, 15)
          && points(bench, .estOneRepMax, .ninetyDays).count == 5)
    check("Top set · 7d: four points (9/22 reps-less session included)", points(bench, .maxWeight, .sevenDays).count == 4)

    let enabledDeadlift = AnalyticsSnapshot.enabledWindows(deadlift, metric: .estOneRepMax, now: now, calendar: calendar)
    check("Deadlift (9/5, 9/21): 7d has one point → disabled; 30d / 90d / All enabled", enabledDeadlift == [.thirtyDays, .ninetyDays, .all])
    let enabledBench = AnalyticsSnapshot.enabledWindows(bench, metric: .volume, now: now, calendar: calendar)
    check("Bench volume: every window has a line", enabledBench == Set(AnalyticsWindow.allCases))
    let single = [AnalyticsSnapshot.ProgressionPoint(date: at(2026, 1, 1), e1RM: 100, volume: nil, maxWeight: nil)]
    check("a lone old point enables only All (one point still draws a dot)",
          AnalyticsSnapshot.enabledWindows(single, metric: .estOneRepMax, now: now, calendar: calendar) == [.all])
    check("a lone old point has no volume line at all",
          AnalyticsSnapshot.enabledWindows(single, metric: .volume, now: now, calendar: calendar).isEmpty)

    check("effective window: stored 7d with 7d disabled → the next wider enabled (30d)", AnalyticsSnapshot.effectiveWindow(stored: .sevenDays, enabled: enabledDeadlift) == .thirtyDays)
    check("effective window: stored 90d enabled → 90d", AnalyticsSnapshot.effectiveWindow(stored: .ninetyDays, enabled: enabledDeadlift) == .ninetyDays)
    check("effective window: only All enabled → All", AnalyticsSnapshot.effectiveWindow(stored: .sevenDays, enabled: [.all]) == .all)
    check("effective window: nothing enabled → All", AnalyticsSnapshot.effectiveWindow(stored: .thirtyDays, enabled: []) == .all)
}

// MARK: - 5. PR board

do {
    let records = snap.prRecords
    check("records: one per lift with an e1RM, most recent first (Mystery 9/22, Deadlift 9/21, Bench 9/20, Row 8/20); Squat has none",
          records.map(\.exercise) == ["Mystery Lift", "Deadlift", "Bench Press", "Row"])

    let benchRecord = records.first { $0.exercise == "Bench Press" }
    check("Bench record is 154 lb, set on 9/20 (the day's best of two sessions)", approx(benchRecord?.e1RM, 154) && benchRecord?.day == at(2026, 9, 20, 0))
    check("Bench delta = 154 − 152 (the record that stood before 9/20, not the 9/1 dip)", approx(benchRecord?.previousBest, 152) && approx(benchRecord?.delta, 2))
    check("a later tie (9/23) does not move the record day", benchRecord?.day == at(2026, 9, 20, 0))
    check("an unchecked heavier set (200 × 5 on 9/15) never becomes the record", (benchRecord?.e1RM ?? 0) < 200)

    let deadliftRecord = records.first { $0.exercise == "Deadlift" }
    check("Deadlift record 336 lb, ↑ 6 over 330", approx(deadliftRecord?.e1RM, 336) && approx(deadliftRecord?.delta, 6) && deadliftRecord?.isPR == true)

    let rowRecord = records.first { $0.exercise == "Row" }
    check("a first-ever record carries no delta and is not a PR", rowRecord?.delta == nil && rowRecord?.isPR == false)
    check("an unresolved lift keeps its logged name and still gets a record", records.first?.exercise == "Mystery Lift" && records.first?.isPR == false)

    func inWindow(_ window: AnalyticsWindow) -> [AnalyticsSnapshot.PRRecord] {
        AnalyticsSnapshot.prRecords(records, in: window, now: now, calendar: calendar)
    }
    check("PRs · 30d: Mystery Lift, Deadlift, Bench (Row's 8/20 record is out)", inWindow(.thirtyDays).map(\.exercise) == ["Mystery Lift", "Deadlift", "Bench Press"])
    check("PRs · 90d: Row's 8/20 record joins", inWindow(.ninetyDays).map(\.exercise) == ["Mystery Lift", "Deadlift", "Bench Press", "Row"])
    check("PRs · All: everything", inWindow(.all).count == 4)
    check("PRs tile counts only records that beat an earlier one: 2 in 30d, 2 in 90d, 2 all-time",
          inWindow(.thirtyDays).filter(\.isPR).count == 2 && inWindow(.ninetyDays).filter(\.isPR).count == 2 && inWindow(.all).filter(\.isPR).count == 2)
    check("empty snapshot has no records", AnalyticsSnapshot.empty.prRecords.isEmpty)
}

// MARK: - 6. Muscle split donut per window

do {
    let thirty = snap.donuts[.thirtyDays]
    check("30d donut: 10 counted sets (unchecked 9/15 set excluded, reps-less squat sets count)", thirty?.totalSets == 10)
    check("30d donut: chest 5, back 2, legs 2 (name tie-break), other 1 last",
          thirty?.segments.map(\.group) == [MuscleGroup.chest.rawValue, MuscleGroup.back.rawValue, MuscleGroup.legs.rawValue, MuscleGroup.other.rawValue]
          && thirty?.segments.map(\.sets) == [5, 2, 2, 1])
    check("30d donut shares sum to 1 (50 / 20 / 20 / 10)", approxAll(thirty?.segments.map(\.share) ?? [], [0.5, 0.2, 0.2, 0.1]))
    check("90d donut: 7/15 and 8/20 join → 12 sets", snap.donuts[.ninetyDays]?.totalSets == 12 && snap.donuts[.ninetyDays]?.segments.first?.sets == 6)
    check("All donut: 6/1 joins → 13 sets", snap.donuts[.all]?.totalSets == 13)
    check("only the muscle windows are precomputed (no 7d donut)", snap.donuts[.sevenDays] == nil && snap.donuts.count == 3)
    check("a window with no sets has no donut", AnalyticsSnapshot.build(sessions: [history[0]], resolve: resolve, now: now, calendar: calendar).donuts[.thirtyDays] == nil)
}

// MARK: - 7. Muscle distribution per window

do {
    let thirty = snap.distributions[.thirtyDays]
    check("30d distribution: 10 workouts / 10 sets now vs 1 workout / 1 set in the 30 days before", thirty?.currentWorkouts == 10 && thirty?.currentSets == 10 && thirty?.previousWorkouts == 1 && thirty?.previousSets == 1)
    check("30d axes (chest, core, shoulders, arms, legs, back): current 5/0/0/0/2/2, previous back 1",
          thirty?.axes.map(\.currentSets) == [5, 0, 0, 0, 2, 2] && thirty?.axes.map(\.previousSets) == [0, 0, 0, 0, 0, 1])
    check("30d has a previous window", thirty?.hasPrevious == true)

    let ninety = snap.distributions[.ninetyDays]
    check("90d distribution: 12 workouts now, the 6/1 session is the previous window", ninety?.currentWorkouts == 12 && ninety?.previousWorkouts == 1 && ninety?.previousSets == 1)

    let all = snap.distributions[.all]
    check("All distribution: every session, no previous window", all?.currentWorkouts == 13 && all?.currentSets == 13 && all?.hasPrevious == false && all?.previousSets == 0)
    check("only the muscle windows are precomputed (no 7d distribution)", snap.distributions[.sevenDays] == nil)
}

// MARK: - 8. Timeline labels

do {
    func labels(_ a: Date, _ b: Date) -> [String] { AnalyticsSnapshot.timelineLabels(from: a, to: b, calendar: calendar) }
    check("Jun → Sep span lists the months", labels(at(2026, 6, 1), at(2026, 9, 23)) == ["Jun", "Jul", "Aug", "Sep"])
    check("a span inside one month shows first and last dates", labels(at(2026, 9, 17), at(2026, 9, 23)) == ["Sep 17", "Sep 23"])
    check("a single day shows once", labels(at(2026, 9, 23), at(2026, 9, 23, 19)) == ["Sep 23"])
    check("a short span across a month boundary still names both months", labels(at(2026, 8, 30), at(2026, 9, 2)) == ["Aug", "Sep"])
    let long = labels(at(2025, 7, 1), at(2026, 9, 1))
    check("over twelve months: six evenly spread labels carrying the year", long.count == 6 && long.first == "Jul '25" && long.last == "Sep '26")
}

// MARK: - 9. Control defaults and keys

do {
    check("default metric is e1RM", AnalyticsControls.defaultMetric == .estOneRepMax)
    check("default progression window is 90d", AnalyticsControls.defaultProgressionWindow == .ninetyDays)
    check("default PR / split / distribution windows are 30d",
          AnalyticsControls.defaultPRWindow == .thirtyDays && AnalyticsControls.defaultSplitWindow == .thirtyDays && AnalyticsControls.defaultDistributionWindow == .thirtyDays)
    let keys = [AnalyticsControls.progressionExerciseKey, AnalyticsControls.progressionMetricKey, AnalyticsControls.progressionWindowKey,
                AnalyticsControls.prWindowKey, AnalyticsControls.splitWindowKey, AnalyticsControls.distributionWindowKey]
    check("six distinct storage keys, all namespaced under analytics", Set(keys).count == 6 && keys.allSatisfy { $0.hasPrefix("analytics") })
    check("the defaults are offered by their controls",
          AnalyticsWindow.progression.contains(AnalyticsControls.defaultProgressionWindow)
          && AnalyticsWindow.prs.contains(AnalyticsControls.defaultPRWindow)
          && AnalyticsWindow.muscle.contains(AnalyticsControls.defaultSplitWindow)
          && AnalyticsWindow.muscle.contains(AnalyticsControls.defaultDistributionWindow))
}

// MARK: - Summary

if failures == 0 {
    print("ALL PASSED")
    exit(0)
} else {
    print("\(failures) FAILED")
    exit(1)
}
