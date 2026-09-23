// Logic check: exercise position in session (Analytics → Advanced).
// - Position derivation: recorded `exerciseOrder` wins; legacy sessions fall
//   back to the routine's current order; no order → no positions. Only
//   performed exercises (≥1 completed, parseable set) take a slot — a
//   skipped exercise never pushes the ones after it back.
// - Completed-only counting: sets with `completed == false` never count;
//   legacy nil flags do.
// - Early/late split: bests per bucket, bucket counts, late-vs-early percent
//   (needs 2+ sessions per bucket), typical position = mode (ties → earlier).
// - "Not enough history": < minimumSessions positioned sessions → no profile;
//   bodyweight-only sessions (no e1RM) don't count toward it.
// - PR position: the first session to reach the top e1RM, nil when unknown.
// - Ordinals, model decode of legacy blobs, snapshot + day-scorecard wiring,
//   and the user-memory digest's PR-line suffix (under the 6KB cap).
// Compiles against the REAL Models/AnalyticsModels/ExercisePositionLogic/
// AIUserPreferences/UserMemoryStore.
import Foundation

// MARK: - Stubs for app-only symbols the sources reference

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

func day(_ text: String) -> Date { iso.date(from: "\(text)T10:00:00Z")! }
let now = day("2026-09-22")

let legsID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
let pullID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
let goneID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!

func set(_ weight: String, _ reps: String, _ completed: Bool? = true) -> WorkoutSet {
    WorkoutSet(weight: weight, reps: reps, completed: completed)
}

func session(
    _ date: String,
    routineID: UUID? = legsID,
    routineName: String = "Legs",
    logs: [String: [WorkoutSet]],
    order: [String]? = nil
) -> WorkoutSession {
    // Stable ids derived from the date so tie-breaks are deterministic.
    let stamp = date.replacingOccurrences(of: "-", with: "")
    let id = UUID(uuidString: "00000000-0000-0000-0000-0000\(stamp)")!
    return WorkoutSession(
        id: id, date: day(date), routineID: routineID, routineName: routineName,
        logs: logs, durationSeconds: nil, exerciseOrder: order
    )
}

let routineOrders: [UUID: [String]] = [
    legsID: ["Squat", "Romanian Deadlift", "Leg Press", "Leg Curl"],
    pullID: ["Romanian Deadlift", "Pull-Up", "Row"]
]

// MARK: - 1. Position derivation

do {
    let recorded = session("2026-09-01", logs: [
        "Squat": [set("225", "5")],
        "Romanian Deadlift": [set("185", "8")],
        "Leg Press": [set("360", "10")],
        "Leg Curl": [set("90", "12")]
    ], order: ["Romanian Deadlift", "Squat", "Leg Curl", "Leg Press"])

    let slots = ExercisePositionLogic.positions(in: recorded, routineOrders: routineOrders)
    check("recorded order wins over the routine order",
          slots["Romanian Deadlift"] == 1 && slots["Squat"] == 2 && slots["Leg Curl"] == 3 && slots["Leg Press"] == 4)
    check("position(of:) matches positions(in:)",
          ExercisePositionLogic.position(of: "Leg Curl", in: recorded, routineOrders: routineOrders) == 3)
    check("performedOrder returns the recorded order",
          ExercisePositionLogic.performedOrder(for: recorded, routineOrders: routineOrders)
          == ["Romanian Deadlift", "Squat", "Leg Curl", "Leg Press"])

    let legacy = session("2026-08-01", logs: [
        "Squat": [set("225", "5")],
        "Romanian Deadlift": [set("185", "8")],
        "Leg Curl": [set("90", "12")]
    ])
    let legacySlots = ExercisePositionLogic.positions(in: legacy, routineOrders: routineOrders)
    check("legacy session (no exerciseOrder) falls back to the routine order",
          legacySlots["Squat"] == 1 && legacySlots["Romanian Deadlift"] == 2)
    check("exercise absent from the session takes no slot and pushes nothing back",
          legacySlots["Leg Press"] == nil && legacySlots["Leg Curl"] == 3)
    check("legacy session without a routine → no fallback", 
          ExercisePositionLogic.positions(in: legacy, routineOrders: [:]).isEmpty)

    let orphan = session("2026-08-02", routineID: goneID, logs: ["Squat": [set("225", "5")]])
    check("deleted routine → unknown position",
          ExercisePositionLogic.performedOrder(for: orphan, routineOrders: routineOrders) == nil
          && ExercisePositionLogic.position(of: "Squat", in: orphan, routineOrders: routineOrders) == nil)

    let noRoutine = session("2026-08-03", routineID: nil, logs: ["Squat": [set("225", "5")]])
    check("routine-less session → unknown position",
          ExercisePositionLogic.positions(in: noRoutine, routineOrders: routineOrders).isEmpty)

    let emptyRecorded = session("2026-08-04", logs: ["Squat": [set("225", "5")]], order: [])
    check("empty recorded order falls back to the routine order",
          ExercisePositionLogic.position(of: "Squat", in: emptyRecorded, routineOrders: routineOrders) == 1)

    let extra = session("2026-09-02", logs: [
        "Squat": [set("225", "5")],
        "Face Pull": [set("40", "15")]
    ], order: ["Squat"])
    check("exercise logged outside the order has no slot",
          ExercisePositionLogic.position(of: "Face Pull", in: extra, routineOrders: routineOrders) == nil)

    let duplicated = session("2026-09-03", logs: ["Squat": [set("225", "5")], "Row": [set("135", "8")]],
                             order: ["Squat", "Squat", "Row"])
    let dupSlots = ExercisePositionLogic.positions(in: duplicated, routineOrders: routineOrders)
    check("duplicate names in an order count once", dupSlots["Squat"] == 1 && dupSlots["Row"] == 2)

    let orders = ExercisePositionLogic.routineOrders(from: [
        Routine(id: legsID, name: "Legs", exercises: ["A", "B"]),
        Routine(id: legsID, name: "Legs dup", exercises: ["C"]),
        Routine(id: pullID, name: "Pull", exercises: ["D"])
    ])
    check("routineOrders(from:) keys by id, first wins on a duplicate id",
          orders[legsID] == ["A", "B"] && orders[pullID] == ["D"] && orders.count == 2)
}

// MARK: - 2. Completed-only counting

do {
    let skipped = session("2026-09-05", logs: [
        "Squat": [set("225", "5", false), set("225", "5", false)],   // all unchecked → skipped
        "Romanian Deadlift": [set("185", "8", nil)],                  // legacy nil = completed
        "Leg Press": [set("", "", true)],                              // checked but blank → not counted
        "Leg Curl": [set("90", "12", true)]
    ])
    let slots = ExercisePositionLogic.positions(in: skipped, routineOrders: routineOrders)
    check("all-unchecked exercise did not happen → no slot", slots["Squat"] == nil)
    check("skipped first exercise: RDL becomes 1st, not 2nd", slots["Romanian Deadlift"] == 1)
    check("checked-but-blank sets are not performed", slots["Leg Press"] == nil)
    check("later exercise closes the gap (Leg Curl 2nd)", slots["Leg Curl"] == 2)
    check("wasPerformed: legacy nil flag counts",
          ExercisePositionLogic.wasPerformed("Romanian Deadlift", in: skipped))
    check("wasPerformed: explicit false never counts",
          !ExercisePositionLogic.wasPerformed("Squat", in: skipped))

    let mixed = session("2026-09-06", logs: [
        "Squat": [set("315", "1", false), set("225", "5", true)]
    ], order: ["Squat"])
    let profiles = ExercisePositionLogic.profiles(sessions: [mixed, mixed, mixed, mixed])
    // Four copies share an id/date; the point is only the e1RM source.
    check("unchecked heavier set never feeds the best (225x5 → 262.5, not 315)",
          approx(profiles.first?.earlyBest, 262.5))
}

// MARK: - 3. Early/late split, typical position, PR position

// RDL: 4 sessions early (positions 1–2), 3 late (3+), 1 unknown (deleted routine).
let history: [WorkoutSession] = [
    // Pull day (recorded): RDL first
    session("2026-06-01", routineID: pullID, routineName: "Pull", logs: [
        "Romanian Deadlift": [set("205", "8")], "Pull-Up": [set("bw", "10")], "Row": [set("135", "10")]
    ], order: ["Romanian Deadlift", "Pull-Up", "Row"]),
    // Legs (legacy → routine fallback): RDL 2nd
    session("2026-06-08", logs: [
        "Squat": [set("225", "5")], "Romanian Deadlift": [set("215", "8")], "Leg Press": [set("360", "10")]
    ]),
    // Legs (recorded): RDL 3rd
    session("2026-06-15", logs: [
        "Squat": [set("235", "5")], "Leg Press": [set("360", "10")], "Romanian Deadlift": [set("195", "8")]
    ], order: ["Squat", "Leg Press", "Romanian Deadlift"]),
    // Legs (recorded): RDL 3rd — all-time PR set late (225x8 → 285)
    session("2026-06-22", logs: [
        "Squat": [set("245", "5")], "Leg Press": [set("380", "10")], "Romanian Deadlift": [set("225", "8")]
    ], order: ["Squat", "Leg Press", "Romanian Deadlift"]),
    // Pull day (recorded): RDL first, same PR value repeated (strict > keeps the first)
    session("2026-06-29", routineID: pullID, routineName: "Pull", logs: [
        "Romanian Deadlift": [set("225", "8")], "Row": [set("145", "10")]
    ], order: ["Romanian Deadlift", "Pull-Up", "Row"]),
    // Legs (recorded): RDL 4th (late)
    session("2026-07-06", logs: [
        "Squat": [set("245", "5")], "Leg Press": [set("380", "10")], "Leg Curl": [set("90", "12")],
        "Romanian Deadlift": [set("205", "8")]
    ], order: ["Squat", "Leg Press", "Leg Curl", "Romanian Deadlift"]),
    // Deleted routine, no recorded order: RDL position unknown (still counts for the PR walk)
    session("2026-07-13", routineID: goneID, routineName: "Old", logs: [
        "Romanian Deadlift": [set("200", "8")]
    ]),
    // Legs (recorded): RDL 1st
    session("2026-07-20", logs: [
        "Romanian Deadlift": [set("210", "8")], "Squat": [set("245", "5")]
    ], order: ["Romanian Deadlift", "Squat"])
]

do {
    let profiles = ExercisePositionLogic.profiles(sessions: history, routineOrders: routineOrders)
    let rdl = profiles.first { $0.exercise == "Romanian Deadlift" }
    check("RDL earns a profile", rdl != nil)
    check("positioned session count excludes the unknown-order session", rdl?.sessionCount == 7)
    check("typical position = mode (1st ×3 vs 3rd ×2 vs 2nd/4th ×1)", rdl?.typicalPosition == 1)
    check("early bucket: 4 sessions", rdl?.earlyCount == 4)
    check("late bucket: 3 sessions", rdl?.lateCount == 3)
    check("early best = 225x8 → 285", approx(rdl?.earlyBest, 285))
    check("late best = 225x8 → 285", approx(rdl?.lateBest, 285))
    check("late vs early = 0%", approx(rdl?.lateVsEarlyPercent, 0))
    check("PR position = first session to reach 285 (June 22, 3rd)", rdl?.prPosition == 3)

    // Squat: 5 positioned sessions, positions 1,1,1,2,1 → typical 1st; late bucket empty.
    let squat = profiles.first { $0.exercise == "Squat" }
    check("Squat: typical 1st, no late sessions",
          squat?.typicalPosition == 1 && squat?.lateCount == 0 && squat?.lateBest == nil)
    check("Squat: delta needs both buckets", squat?.lateVsEarlyPercent == nil)
    check("Squat PR (245x5 → 285.8) came 1st", squat?.prPosition == 1)

    // Leg Press: 4 sessions — 3rd on the legacy day (routine fallback), 2nd ×3 recorded.
    let legPress = profiles.first { $0.exercise == "Leg Press" }
    check("Leg Press: 4 positioned sessions, 3 early / 1 late, typical 2nd",
          legPress?.sessionCount == 4 && legPress?.earlyCount == 3 && legPress?.lateCount == 1
          && legPress?.typicalPosition == 2)

    check("sorted by session count desc, then name",
          profiles.map(\.exercise) == ["Romanian Deadlift", "Squat", "Leg Press"])
    check("Row (3 sessions) and Leg Curl (2) fall under the threshold",
          !profiles.contains { $0.exercise == "Row" || $0.exercise == "Leg Curl" })
    check("Pull-Up (bodyweight, no e1RM) never profiles",
          !profiles.contains { $0.exercise == "Pull-Up" })
}

// MARK: - 4. Delta math and bucket minimums

do {
    func legs(_ date: String, rdl: String, position: Int) -> WorkoutSession {
        var order = ["Squat", "Leg Press", "Leg Curl", "Hip Thrust"]
        order.insert("Romanian Deadlift", at: position - 1)
        var logs: [String: [WorkoutSet]] = ["Romanian Deadlift": [set(rdl, "8")]]
        for name in order where name != "Romanian Deadlift" { logs[name] = [set("100", "10")] }
        return session(date, logs: logs, order: order)
    }
    let sessions = [
        legs("2026-08-01", rdl: "250", position: 1),
        legs("2026-08-08", rdl: "240", position: 2),
        legs("2026-08-15", rdl: "225", position: 3),
        legs("2026-08-22", rdl: "220", position: 4)
    ]
    let rdl = ExercisePositionLogic.profiles(sessions: sessions).first { $0.exercise == "Romanian Deadlift" }
    check("early best 250x8 → 316.7", approx(rdl?.earlyBest, 316.67))
    check("late best 225x8 → 285", approx(rdl?.lateBest, 285))
    check("late vs early = −10%", approx(rdl?.lateVsEarlyPercent, -10.0))
    check("typical position tie (1,2,3,4 once each) → earliest slot", rdl?.typicalPosition == 1)

    let oneLate = Array(sessions.prefix(3)) + [legs("2026-08-29", rdl: "230", position: 1)]
    let thin = ExercisePositionLogic.profiles(sessions: oneLate).first { $0.exercise == "Romanian Deadlift" }
    check("one late session → bucket best shown but no delta",
          thin?.lateCount == 1 && approx(thin?.lateBest, 285) && thin?.lateVsEarlyPercent == nil)

    check("isEarly: 1–2 early, 3+ late",
          ExercisePositionLogic.isEarly(1) && ExercisePositionLogic.isEarly(2) && !ExercisePositionLogic.isEarly(3))
    check("constants: 4 sessions / early ≤2 / 2 per bucket",
          ExercisePositionLogic.minimumSessions == 4
          && ExercisePositionLogic.earlyPositionLimit == 2
          && ExercisePositionLogic.minimumBucketSessions == 2)
}

// MARK: - 5. Threshold

do {
    func s(_ date: String, weight: String) -> WorkoutSession {
        session(date, logs: ["Squat": [set(weight, "5")]], order: ["Squat"])
    }
    let three = [s("2026-08-01", weight: "225"), s("2026-08-08", weight: "230"), s("2026-08-15", weight: "235")]
    check("3 positioned sessions → no profile", ExercisePositionLogic.profiles(sessions: three).isEmpty)
    let four = three + [s("2026-08-22", weight: "240")]
    check("4 positioned sessions → profile", ExercisePositionLogic.profiles(sessions: four).count == 1)

    // A 4th session with an unknown position does not cross the threshold.
    let unknown = three + [session("2026-08-22", routineID: goneID, logs: ["Squat": [set("240", "5")]])]
    check("unknown-position session does not count toward the threshold",
          ExercisePositionLogic.profiles(sessions: unknown).isEmpty)

    // A 4th session with reps only (no e1RM) does not cross it either.
    let bodyweight = three + [session("2026-08-22", logs: ["Squat": [set("", "20")]], order: ["Squat"])]
    check("no-e1RM session does not count toward the threshold",
          ExercisePositionLogic.profiles(sessions: bodyweight).isEmpty)
}

// MARK: - 6. Ordinals

do {
    let expected: [Int: String] = [
        1: "1st", 2: "2nd", 3: "3rd", 4: "4th", 10: "10th", 11: "11th", 12: "12th", 13: "13th",
        21: "21st", 22: "22nd", 23: "23rd", 101: "101st", 111: "111th", 112: "112th"
    ]
    check("ordinal suffixes", expected.allSatisfy { ExercisePositionLogic.ordinal($0.key) == $0.value })
    check("digest suffix with PR", ExercisePositionLogic.digestSuffix(for: ExercisePositionLogic.ExerciseProfile(
        exercise: "RDL", sessionCount: 5, typicalPosition: 3, earlyBest: 1, earlyCount: 1,
        lateBest: 1, lateCount: 4, prPosition: 1)) == " · usually 3rd, PR came 1st")
    check("digest suffix without PR position", ExercisePositionLogic.digestSuffix(for: ExercisePositionLogic.ExerciseProfile(
        exercise: "RDL", sessionCount: 5, typicalPosition: 2, earlyBest: 1, earlyCount: 5,
        lateBest: nil, lateCount: 0, prPosition: nil)) == " · usually 2nd")
    check("digest suffix without a profile is empty", ExercisePositionLogic.digestSuffix(for: nil) == "")
}

// MARK: - 7. Model: legacy decode + round-trip

do {
    let legacyJSON = """
    [{"id":"44444444-4444-4444-4444-444444444444","date":0,"routineName":"Legs",
      "logs":{"Squat":[{"weight":"225","reps":"5"}]}}]
    """.data(using: .utf8)!
    let decoded = try? JSONDecoder().decode([WorkoutSession].self, from: legacyJSON)
    check("legacy blob without exerciseOrder decodes", decoded?.count == 1)
    check("legacy exerciseOrder is nil", decoded?[0].exerciseOrder == nil)

    let modern = session("2026-09-10", logs: ["Squat": [set("225", "5")]], order: ["Squat", "Leg Curl"])
    let data = try! JSONEncoder().encode([modern])
    let back = try! JSONDecoder().decode([WorkoutSession].self, from: data)
    check("exerciseOrder survives an encode/decode round-trip", back[0].exerciseOrder == ["Squat", "Leg Curl"])
    check("init default leaves exerciseOrder nil",
          WorkoutSession(date: now, routineName: "X", logs: [:]).exerciseOrder == nil)
}

// MARK: - 8. Snapshot + day scorecard wiring

do {
    let resolve: (String) -> Exercise? = { name in
        // "RDL" alias → canonical Romanian Deadlift, everything else literal.
        let canonical = name == "RDL" ? "Romanian Deadlift" : name
        return Exercise(name: canonical, muscleGroup: canonical == "Squat" ? .legs : .other)
    }
    let aliased = history + [
        session("2026-07-27", logs: ["RDL": [set("215", "8")], "Squat": [set("245", "5")]], order: ["RDL", "Squat"])
    ]
    let snapshot = AnalyticsSnapshot.build(
        sessions: aliased, resolve: resolve, routineOrders: routineOrders, now: now, calendar: calendar
    )
    let rdl = snapshot.exerciseOrderProfiles.first { $0.exercise == "Romanian Deadlift" }
    check("snapshot carries exercise-order profiles", !snapshot.exerciseOrderProfiles.isEmpty)
    check("aliases merge into the canonical profile (RDL session counted)", rdl?.sessionCount == 8)
    check("empty snapshot has no profiles", AnalyticsSnapshot.empty.exerciseOrderProfiles.isEmpty)
    check("build without routineOrders still compiles and drops legacy positions",
          AnalyticsSnapshot.build(sessions: history, resolve: resolve, now: now, calendar: calendar)
              .exerciseOrderProfiles.first { $0.exercise == "Romanian Deadlift" }?.sessionCount == 6)

    // Day scorecard: June 22 set the RDL PR at position 3.
    let prDay = calendar.startOfDay(for: day("2026-06-22"))
    let scorecard = AnalyticsSnapshot.dayScorecard(
        day: prDay, sessionsByDay: snapshot.sessionsByDay, resolve: resolve, routineOrders: routineOrders
    )
    let pr = scorecard.prs.first { $0.exercise == "Romanian Deadlift" }
    check("day scorecard flags the RDL PR", pr != nil && approx(pr?.e1RM, 285))
    check("PR carries its position in session (3rd)", pr?.position == 3)
    check("Leg Press PR that day also positioned (2nd)",
          scorecard.prs.first { $0.exercise == "Leg Press" }?.position == 2)

    // A PR on a legacy day resolves through the routine fallback; without it, nil.
    let legacyDay = calendar.startOfDay(for: day("2026-06-08"))
    let withFallback = AnalyticsSnapshot.dayScorecard(
        day: legacyDay, sessionsByDay: snapshot.sessionsByDay, resolve: resolve, routineOrders: routineOrders
    )
    let withoutFallback = AnalyticsSnapshot.dayScorecard(
        day: legacyDay, sessionsByDay: snapshot.sessionsByDay, resolve: resolve
    )
    check("legacy-day PR position via routine fallback (RDL 2nd)",
          withFallback.prs.first { $0.exercise == "Romanian Deadlift" }?.position == 2)
    check("legacy-day PR position nil without a fallback",
          withoutFallback.prs.first { $0.exercise == "Romanian Deadlift" }?.position == nil)
    check("PR list unchanged by the position plumbing",
          withFallback.prs.map(\.exercise) == withoutFallback.prs.map(\.exercise))
}

// MARK: - 9. User-memory digest: PR-line suffix, shape and cap intact

do {
    let memory = UserMemoryBuilder.build(
        sessions: history,
        preferences: AIUserPreferences.empty,
        resolve: { Exercise(name: $0, muscleGroup: .other) },
        routineOrders: routineOrders,
        now: now,
        calendar: calendar
    )
    let prs = memory.lifetime?.allTimePRs ?? []
    let rdlLine = prs.first { $0.hasPrefix("Romanian Deadlift") }
    check("digest PR line carries the position suffix",
          rdlLine == "Romanian Deadlift e1RM 285 (2026-06-22) · usually 1st, PR came 3rd")
    let rowLine = prs.first { $0.hasPrefix("Row") }
    check("under-threshold lift keeps the plain PR line",
          rowLine == "Row e1RM 193.3 (2026-06-29)")
    check("every PR line fits the backend's 100-char clamp", prs.allSatisfy { $0.count <= 100 })
    check("digest stays under the 6KB cap",
          (UserMemoryBuilder.encoded(memory)?.count ?? .max) <= UserMemoryBuilder.maxEncodedBytes)

    let plain = UserMemoryBuilder.build(
        sessions: history,
        preferences: AIUserPreferences.empty,
        resolve: { Exercise(name: $0, muscleGroup: .other) },
        now: now,
        calendar: calendar
    )
    let plainRDL = plain.lifetime?.allTimePRs?.first { $0.hasPrefix("Romanian Deadlift") }
    check("without routine orders the legacy session is unpositioned but the suffix still forms (6 sessions)",
          plainRDL == "Romanian Deadlift e1RM 285 (2026-06-22) · usually 1st, PR came 3rd")
    check("digest shape unchanged: no new top-level or lifetime keys",
          {
              guard let data = UserMemoryBuilder.encoded(memory),
                    let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let lifetime = object["lifetime"] as? [String: Any] else { return false }
              let topKeys = Set(object.keys)
              let lifetimeKeys = Set(lifetime.keys)
              return topKeys.isSubset(of: ["schemaVersion", "generatedAt", "sourceSessionCount",
                                           "recentSessions", "weeklySummaries", "lifetime"])
                  && lifetimeKeys.isSubset(of: ["since", "totalSessions", "totalVolume", "sessionsPerWeek",
                                                "longestStreakWeeks", "allTimePRs", "painHistory",
                                                "limitations", "months"])
          }())
}

print("==========================")
if failures == 0 {
    print("ALL CHECKS PASSED")
    exit(0)
} else {
    print("\(failures) CHECK(S) FAILED")
    exit(1)
}
