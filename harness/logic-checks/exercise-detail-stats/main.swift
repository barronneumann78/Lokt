// Logic check: exercise page stats (look v2, phase 7 — ExerciseDetailInsights).
// - BEST / e1RM / LAST from one fixed session set: completed sets only
//   (explicit `completed == false` never counts, legacy nil counts), e1RM via
//   AnalyticsMath.epleyOneRepMax, LAST = the most recent session's best set,
//   BEST = the top-ranked set across every session.
// - Ranking: an e1RM beats no e1RM, higher e1RM wins, then heavier weight;
//   reps-only (bodyweight) sets rank by reps; `beats` is strict.
// - The "—" rule: a never-performed exercise has no history (the view hides
//   the row); a bodyweight-only history shows "—" for e1RM only.
// - HISTORY rows: newest first (same-day sessions by time), one row per
//   session with a counted set, per-session best set, alias keys merged
//   within a session (best set across them, earliest slot).
// - Position: recorded order wins, legacy sessions fall back to the routine
//   order, unknown → nil; the "3rd in session" tag exists only while the
//   ADVANCED flag is on AND the position is known.
// - Copy helpers (sessions label, day label) and the drop-down defaults.
// Compiles against the REAL Models / AnalyticsModels / ExercisePositionLogic /
// ExerciseDetailInsights. Deterministic: fixed dates, fixed zone, never Date().
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

func approx(_ lhs: Double?, _ rhs: Double, tolerance: Double = 0.05) -> Bool {
    guard let lhs else { return false }
    return abs(lhs - rhs) <= tolerance
}

// MARK: - Fixed dates / IDs (deterministic — never Date())

let iso = ISO8601DateFormatter()
iso.timeZone = TimeZone(identifier: "UTC")
var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "UTC")!
calendar.locale = Locale(identifier: "en_US")

func day(_ text: String, hour: Int = 10) -> Date {
    iso.date(from: "\(text)T\(String(format: "%02d", hour)):00:00Z")!
}
let now = day("2026-09-22")

let pushID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

func set(_ weight: String, _ reps: String, _ completed: Bool? = true) -> WorkoutSet {
    WorkoutSet(weight: weight, reps: reps, completed: completed)
}

var sessionSerial = 0
func session(
    _ date: String,
    hour: Int = 10,
    routineID: UUID? = pushID,
    logs: [String: [WorkoutSet]],
    order: [String]? = nil
) -> WorkoutSession {
    // Stable ids derived from the date and a serial so ties are deterministic.
    sessionSerial += 1
    let stamp = date.replacingOccurrences(of: "-", with: "")
    let id = UUID(uuidString: "00000000-0000-0000-\(String(format: "%04d", sessionSerial))-0000\(stamp)")!
    return WorkoutSession(
        id: id, date: day(date, hour: hour), routineID: routineID, routineName: "Push",
        logs: logs, durationSeconds: nil, exerciseOrder: order
    )
}

let routineOrders: [UUID: [String]] = [
    pushID: ["Bench Press", "Overhead Press", "Dip"]
]

typealias Insights = ExerciseDetailInsights

// MARK: - 1. One counted set

do {
    check("completed set with both numbers carries an Epley e1RM",
          approx(Insights.SetResult(set("225", "6"))?.e1RM, 270))
    check("legacy nil flag counts as completed",
          Insights.SetResult(set("205", "8", nil))?.label == "205 × 8")
    check("explicit completed == false never counts",
          Insights.SetResult(set("315", "3", false)) == nil)
    check("placeholder row (no numbers) never counts",
          Insights.SetResult(set("", "")) == nil)
    check("label: weight × reps through formattedWeight",
          Insights.SetResult(set("225.5", "6"))?.label == "225.5 × 6")
    check("label: free-text weight and rep range parse to the first numbers",
          Insights.SetResult(set("135 lbs", "8-10"))?.label == "135 × 8")
    check("label: reps-only set reads BW × reps",
          Insights.SetResult(set("", "12"))?.label == "BW × 12")
    check("label: weight-only set reads the weight",
          Insights.SetResult(set("225", ""))?.label == "225")

    let heavy = Insights.SetResult(set("225", "6"))!     // 270
    let lighter = Insights.SetResult(set("205", "8"))!   // 259.67
    let bodyweight12 = Insights.SetResult(set("", "12"))!
    let bodyweight8 = Insights.SetResult(set("", "8"))!
    check("higher e1RM beats lower", heavy.beats(lighter) && !lighter.beats(heavy))
    check("any e1RM beats a reps-only set", lighter.beats(bodyweight12) && !bodyweight12.beats(lighter))
    check("reps-only sets rank by reps", bodyweight12.beats(bodyweight8) && !bodyweight8.beats(bodyweight12))
    check("beats is strict — an equal set is not better", !heavy.beats(heavy) && !bodyweight12.beats(bodyweight12))
    check("bestSet picks the top-ranked counted set, ignoring unchecked ones",
          Insights.bestSet(in: [set("205", "8"), set("315", "3", false), set("225", "6")])?.label == "225 × 6")
    check("bestSet is nil when nothing counts",
          Insights.bestSet(in: [set("315", "3", false), set("", "")]) == nil)
}

// MARK: - 2. BEST / e1RM / LAST from a fixed session set

let sessionA = session("2026-09-01", logs: [
    "Bench Press": [set("205", "8"), set("225", "6"), set("315", "3", false)],
    "Overhead Press": [set("95", "8")],
    "Dip": [set("", "10")]
], order: ["Overhead Press", "Bench Press", "Dip"])

let sessionB = session("2026-09-10", logs: [   // legacy: no recorded order, nil flags
    "Bench Press": [set("205", "8", nil)],
    "Overhead Press": [set("100", "5", nil)]
])

let sessionC = session("2026-09-15", logs: [
    "Bench Press": [set("215", "5"), set("200", "10")],
    "Dip": [set("", "12")],
    "Overhead Press": [set("95", "6", false)]   // skipped → takes no slot
], order: ["Dip", "Overhead Press", "Bench Press"])

let sessionD = session("2026-09-18", routineID: nil, logs: [   // unknown order
    "bench press": [set("185", "12")]
])

let sessionE = session("2026-09-20", logs: [   // only unchecked sets → no row
    "Bench Press": [set("225", "6", false)]
])

let fixture = [sessionE, sessionB, sessionD, sessionA, sessionC]

do {
    let stats = Insights.stats(for: "Bench Press", sessions: fixture, routineOrders: routineOrders)

    check("history has one row per session with a counted set (unchecked-only session dropped)",
          stats.sessionCount == 4 && stats.history.map(\.id) == [sessionD.id, sessionC.id, sessionB.id, sessionA.id])
    check("history is newest first",
          stats.history.map(\.date) == [sessionD.date, sessionC.date, sessionB.date, sessionA.date])
    check("per-session best set: the highest e1RM in that session",
          stats.history.map(\.bestSet.label) == ["185 × 12", "200 × 10", "205 × 8", "225 × 6"])
    check("BEST = the top-ranked set across every session (completed only — the unchecked 315 × 3 never wins)",
          stats.bestLabel == "225 × 6")
    check("e1RM tile = BEST's Epley e1RM through formattedWeight",
          stats.e1RMLabel == "270" && approx(stats.best?.e1RM, 270))
    check("LAST = the most recent session's best set",
          stats.lastLabel == "185 × 12" && stats.last == stats.history.first?.bestSet)
    check("log keys match case-insensitively by default", stats.history.contains { $0.id == sessionD.id })
    check("hasHistory is true once any session counts", stats.hasHistory)
}

// MARK: - 3. Position per row and the tag gating

do {
    let stats = Insights.stats(for: "Bench Press", sessions: fixture, routineOrders: routineOrders)
    let positions = Dictionary(uniqueKeysWithValues: stats.history.map { ($0.id, $0.position) })

    check("recorded order wins: Bench sat 2nd behind the performed Overhead Press",
          positions[sessionA.id] == 2)
    check("legacy session falls back to the routine order: Bench 1st",
          positions[sessionB.id] == 1)
    check("a skipped exercise takes no slot: Dip 1st, Overhead Press skipped, Bench 2nd",
          positions[sessionC.id] == 2)
    check("no routine and no recorded order → position unknown (nil)",
          positions[sessionD.id] == .some(nil))

    check("tag reads '2nd in session' with ADVANCED on", Insights.positionTag(2, advanced: true) == "2nd in session")
    check("tag uses ExercisePositionLogic ordinals (1st / 3rd / 22nd)",
          Insights.positionTag(1, advanced: true) == "1st in session"
          && Insights.positionTag(3, advanced: true) == "3rd in session"
          && Insights.positionTag(22, advanced: true) == "22nd in session")
    check("ADVANCED off → no tag even with a known position", Insights.positionTag(2, advanced: false) == nil)
    check("unknown position → no tag even with ADVANCED on", Insights.positionTag(nil, advanced: true) == nil)
}

// MARK: - 4. The "—" rule

do {
    let none = Insights.stats(for: "Bench Press", sessions: [], routineOrders: routineOrders)
    check("never performed: no history (the view hides the tile row)", !none.hasHistory && none.sessionCount == 0)
    check("never performed: every tile label is a dash", none.bestLabel == "—" && none.e1RMLabel == "—" && none.lastLabel == "—")
    check("never performed: no recent rows and LAST is nil", none.recent.isEmpty && none.last == nil)

    let onlyUnchecked = Insights.stats(for: "Bench Press", sessions: [sessionE], routineOrders: routineOrders)
    check("a session with only unchecked sets is 'never performed'", !onlyUnchecked.hasHistory)

    let otherLift = Insights.stats(for: "Squat", sessions: fixture, routineOrders: routineOrders)
    check("sessions that logged other exercises do not count", !otherLift.hasHistory)

    let pullUps = [
        session("2026-09-02", logs: ["Pull-Up": [set("", "8"), set("", "12"), set("bw", "10")]]),
        session("2026-09-09", logs: ["Pull-Up": [set("", "9")]])
    ]
    let bodyweight = Insights.stats(for: "Pull-Up", sessions: pullUps)
    check("bodyweight-only history: BEST and LAST read BW × reps",
          bodyweight.bestLabel == "BW × 12" && bodyweight.lastLabel == "BW × 9")
    check("bodyweight-only history: e1RM alone shows the dash", bodyweight.e1RMLabel == "—" && bodyweight.hasHistory)

    let weighted = pullUps + [session("2026-09-16", logs: ["Pull-Up": [set("25", "8"), set("", "14")]])]
    let mixed = Insights.stats(for: "Pull-Up", sessions: weighted)
    check("a weighted set beats every bodyweight set for BEST and e1RM",
          mixed.bestLabel == "25 × 8" && mixed.e1RMLabel == "31.7" && mixed.lastLabel == "25 × 8")
}

// MARK: - 5. Aliases merge within a session; same-day ordering; recent limit

do {
    let aliasSession = session("2026-09-03", logs: [
        "Barbell Bench Press": [set("230", "5")],   // e1RM 268.3
        "Bench Press": [set("225", "6")],           // e1RM 270
        "Squat": [set("315", "5")]
    ], order: ["Barbell Bench Press", "Squat", "Bench Press"])
    let aliases: Set<String> = ["bench press", "barbell bench press"]
    let merged = Insights.stats(
        for: "Bench Press",
        sessions: [aliasSession],
        routineOrders: routineOrders,
        isMatch: { aliases.contains($0.lowercased()) }
    )
    check("alias keys merge into one row per session", merged.sessionCount == 1)
    check("merged row takes the best set across the aliases", merged.bestLabel == "225 × 6" && merged.e1RMLabel == "270")
    check("merged row takes the earliest slot across the aliases", merged.history.first?.position == 1)

    let morning = session("2026-09-15", hour: 9, logs: ["Bench Press": [set("185", "8")]])
    let evening = session("2026-09-15", hour: 18, logs: ["Bench Press": [set("195", "8")]])
    let sameDay = Insights.stats(for: "Bench Press", sessions: [morning, evening])
    check("two sessions on one day are two rows, later first; LAST is the later one",
          sameDay.sessionCount == 2 && sameDay.history.first?.id == evening.id && sameDay.lastLabel == "195 × 8")

    var many: [WorkoutSession] = []
    for dayIndex in 1...12 {
        many.append(session(String(format: "2026-08-%02d", dayIndex), logs: [
            "Bench Press": [set("\(100 + dayIndex)", "5")]
        ]))
    }
    let long = Insights.stats(for: "Bench Press", sessions: many.shuffled())
    check("recent rows cap at recentRowLimit while the header counts every session",
          Insights.recentRowLimit == 10 && long.recent.count == 10 && long.sessionCount == 12)
    check("recent rows start with the newest session", long.recent.first?.bestSet.label == "112 × 5")
    check("BEST scans the whole history, not just the recent rows",
          long.bestLabel == "112 × 5" && long.history.last?.bestSet.label == "101 × 5")
}

// MARK: - 6. Copy helpers and drop-down defaults

do {
    check("sessions label is singular at one", Insights.sessionsLabel(1) == "1 session")
    check("sessions label is plural otherwise", Insights.sessionsLabel(0) == "0 sessions" && Insights.sessionsLabel(5) == "5 sessions")

    check("day label drops the year inside now's year",
          Insights.dayLabel(day("2026-09-15"), now: now, calendar: calendar) == "Sep 15")
    check("day label carries the year once it differs",
          Insights.dayLabel(day("2025-12-03"), now: now, calendar: calendar) == "Dec 3, 2025")

    check("FORM CUES opens by default", ExerciseDetailSection.formCues.opensByDefault)
    check("every other section starts closed",
          ExerciseDetailSection.allCases.filter(\.opensByDefault) == [.formCues])
    let keys = ExerciseDetailSection.allCases.map(\.storageKey)
    check("storage keys are unique and namespaced per app",
          Set(keys).count == keys.count && keys.allSatisfy { $0.hasPrefix("exerciseDetail.") && $0.hasSuffix("V1") })
    check("the five sections are cues / how-to / plain words / variations / history",
          ExerciseDetailSection.allCases == [.formCues, .howTo, .plainWords, .variations, .history])
}

print("==========================")
if failures == 0 {
    print("ALL CHECKS PASSED")
    exit(0)
} else {
    print("\(failures) CHECK(S) FAILED")
    exit(1)
}
