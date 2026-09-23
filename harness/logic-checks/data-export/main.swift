// Logic check: DataExport document builder (Settings → Workout History →
// Export My Data). Compiles against the REAL Models/AIUserPreferences/
// ExerciseCSVLoader/DataExport sources.
// Deterministic: fixed dates, fixed UUIDs, fixed timezones. No Date().
import Foundation

// MARK: - Stubs for symbols ExerciseCSVLoader.swift references (UI/app-only)

enum ExerciseMediaCatalog {
    static func imageName(for exerciseName: String) -> String? { nil }
}

enum CustomExerciseLibrary {
    static func loadExercises() -> [Exercise] { [] }
}

enum ExerciseNameMatcher {
    static func invalidateCache() {}
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

// MARK: - Fixed dates / IDs

let iso = ISO8601DateFormatter()
iso.timeZone = TimeZone(identifier: "UTC")

let exportDate = iso.date(from: "2026-08-30T12:00:00Z")!
let sessionDate1 = iso.date(from: "2026-06-01T17:30:00Z")!
let sessionDate2 = iso.date(from: "2026-06-03T18:00:00Z")!
let stateDate = iso.date(from: "2026-06-03T19:00:00Z")!

let routineID1 = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
let routineID2 = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
let sessionID1 = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
let sessionID2 = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
let planID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!

// MARK: - Fixtures (cover optional/legacy model corners)

var routine1 = Routine(
    id: routineID1,
    name: "Push Day",
    exercises: ["Bench Press", "Overhead Press"],
    preferredSetCounts: ["Bench Press": 4]
)
routine1.progression = [
    "Bench Press": ExerciseProgressionState(
        lastWeight: "185",
        lastReps: "5",
        lastOutcome: .aboutRight,
        consecutiveTooHard: 0,
        painFlagged: false,
        updatedAt: stateDate
    )
]

let routine2 = Routine(
    id: routineID2,
    name: "Imported Pull",
    exercises: ["Row"],
    importContext: RoutineImportContext(
        sourceKind: "photo",
        importedAt: sessionDate1,
        originalText: "Row 3x8",
        dayName: nil,
        exercisePlans: [
            RoutineImportedExercisePlan(
                id: planID,
                exerciseName: "Row",
                sourceText: "Row 3x8",
                targetSets: 3,
                targetReps: "8",
                restSeconds: nil,
                notes: nil,
                intensityNotes: [],
                matchedExerciseName: "Seated Cable Row",
                isCustomExercise: false
            )
        ]
    )
)

// Legacy-shaped session: nil completed flags (pre-completion-tracking blobs),
// no check-in, no duration.
let legacySession = WorkoutSession(
    id: sessionID1,
    date: sessionDate1,
    routineID: routineID1,
    routineName: "Push Day",
    logs: [
        "Bench Press": [
            WorkoutSet(weight: "180", reps: "5", completed: nil),
            WorkoutSet(weight: "180", reps: "5", completed: false),
        ]
    ]
)

var modernSession = WorkoutSession(
    id: sessionID2,
    date: sessionDate2,
    routineID: routineID2,
    routineName: "Imported Pull",
    logs: [
        "Row": [WorkoutSet(weight: "120", reps: "8", completed: true)]
    ],
    durationSeconds: 3600
)
modernSession.checkIn = SessionCheckIn(
    overall: .tooHard,
    hadPain: true,
    painNote: "left shoulder",
    perExercise: ["Row": .tooHard],
    recordedAt: stateDate
)

let preferences = AIUserPreferences(
    preferredEquipment: ["Dumbbells", "Cables"],
    dislikedExercises: ["Burpees"],
    primaryGoal: "Build muscle",
    limitations: "Sensitive shoulders",
    trainingStyle: "Hypertrophy",
    defaultTimeLimitMinutes: 45,
    trainingExperience: .returningToTraining,
    age: 36,
    injuryFlags: [.shoulder, .knee]
)

let legacyPreferencesJSON = """
{
  "preferredEquipment": ["Dumbbells"],
  "dislikedExercises": [],
  "primaryGoal": "General fitness",
  "limitations": "",
  "trainingStyle": "Simple",
  "defaultTimeLimitMinutes": 30
}
""".data(using: .utf8)!
let decodedLegacyPreferences = try? JSONDecoder().decode(AIUserPreferences.self, from: legacyPreferencesJSON)
check(
    "legacy AI preferences decode without safety fields",
    decodedLegacyPreferences?.trainingExperience == nil &&
        decodedLegacyPreferences?.age == nil &&
        decodedLegacyPreferences?.injuryFlags == nil
)

let profilePayload = AIUserPreferencesPayload(preferences: preferences)
check(
    "AI preference payload includes safe-profile fields",
    profilePayload.trainingExperience == "returning_to_training" &&
        profilePayload.age == 36 &&
        profilePayload.injuryFlags == ["shoulder", "knee"]
)
check("age validation accepts a plausible age", AIUserPreferences.validAge(from: "36") == 36)
check("age validation rejects out-of-range input", AIUserPreferences.validAge(from: "121") == nil)

let customExercise = Exercise(
    id: "custom-landmine-press",
    name: "Landmine Press",
    muscleGroup: .shoulders,
    equipment: .barbell,
    movementPattern: .verticalPush,
    primaryMuscleGroups: [.shoulders],
    difficulty: .intermediate,
    instructions: "Press the barbell up and away.",
    imageName: nil,
    metadata: ExerciseMetadata(
        primaryMuscles: ["shoulders"],
        secondaryMuscles: ["triceps"],
        movementPattern: "vertical push",
        equipment: ["barbell"],
        difficulty: "Intermediate",
        mechanic: "compound",
        forceType: "push",
        laterality: "bilateral",
        bodyRegion: "upper",
        trainingGoal: ["hypertrophy"],
        exerciseType: "strength",
        gripType: nil,
        stance: nil,
        planeOfMotion: "sagittal",
        tags: ["custom"]
    ),
    description: "Angled overhead press.",
    howTo: ["Set up the landmine.", "Press."],
    cues: ["Ribs down."]
)

func buildFixtureDocument() -> DataExport.Document {
    DataExport.buildDocument(
        routines: [routine1, routine2],
        sessions: [legacySession, modernSession],
        preferences: preferences,
        customExercises: [customExercise],
        appVersion: "1.0 (7)",
        exportedAt: exportDate
    )
}

print("== data-export logic check ==")

// MARK: - Document shape / self-description

let document = buildFixtureDocument()
let data = try! DataExport.encode(document)
let json = String(data: data, encoding: .utf8)!

let topLevel = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
let expectedKeys: Set<String> = [
    "schema", "schemaVersion", "exportDate", "appVersion",
    "routines", "workoutSessions", "aiUserPreferences", "customExercises",
]

print("-- shape --")
check("top-level keys are exactly the documented set", Set(topLevel.keys) == expectedKeys)
check("schema name present", topLevel["schema"] as? String == "lokt-export")
check("schema version present (importer anchor)", topLevel["schemaVersion"] as? Int == 1)
check("export date is ISO 8601 UTC", topLevel["exportDate"] as? String == "2026-08-30T12:00:00Z")
check("app version carried through", topLevel["appVersion"] as? String == "1.0 (7)")
check("output is pretty-printed", json.contains("\n"))

// Sorted keys: verify top-level key order in the encoded text (quoted-key
// positions; every expected key appears exactly once at top level of the
// empty document below, so use that for a clash-free ordering check).
let emptyDocument = DataExport.buildDocument(
    routines: [],
    sessions: [],
    preferences: .empty,
    customExercises: [],
    appVersion: "1.0 (7)",
    exportedAt: exportDate
)
let emptyData = try! DataExport.encode(emptyDocument)
let emptyJSON = String(data: emptyData, encoding: .utf8)!
let orderedKeys = [
    "\"aiUserPreferences\"", "\"appVersion\"", "\"customExercises\"",
    "\"exportDate\"", "\"routines\"", "\"schema\"", "\"schemaVersion\"",
    "\"workoutSessions\"",
]
let keyPositions = orderedKeys.compactMap { emptyJSON.range(of: $0)?.lowerBound }
check(
    "keys are sorted (all present, ascending positions)",
    keyPositions.count == orderedKeys.count && zip(keyPositions, keyPositions.dropFirst()).allSatisfy { $0 < $1 }
)

// MARK: - Round trip

print("-- round trip --")

let decoded = try! JSONDecoder().decode(DataExport.Document.self, from: data)
let reencoded = try! DataExport.encode(decoded)
check("decode → re-encode is byte-identical", reencoded == data)

check("routines survive (count + ids)", decoded.routines.map(\.id) == [routineID1, routineID2])
check("routine fields survive", decoded.routines[0].name == "Push Day"
    && decoded.routines[0].preferredSetCounts["Bench Press"] == 4
    && decoded.routines[0].exercises == ["Bench Press", "Overhead Press"])
check("progression state survives", decoded.routines[0].progression?["Bench Press"]?.lastWeight == "185"
    && decoded.routines[0].progression?["Bench Press"]?.lastOutcome == .aboutRight)
check("import context survives", decoded.routines[1].importContext?.sourceKind == "photo"
    && decoded.routines[1].importContext?.exercisePlans.first?.matchedExerciseName == "Seated Cable Row")

check("sessions survive (count + ids)", decoded.workoutSessions.map(\.id) == [sessionID1, sessionID2])
let decodedLegacySets = decoded.workoutSessions[0].logs["Bench Press"]!
check("legacy nil completed stays nil (isCompleted == true)",
    decodedLegacySets[0].completed == nil && decodedLegacySets[0].isCompleted)
check("explicit false completed stays false",
    decodedLegacySets[1].completed == false && !decodedLegacySets[1].isCompleted)
check("legacy session has no check-in/duration",
    decoded.workoutSessions[0].checkIn == nil && decoded.workoutSessions[0].durationSeconds == nil)
check("check-in survives", decoded.workoutSessions[1].checkIn?.overall == .tooHard
    && decoded.workoutSessions[1].checkIn?.hadPain == true
    && decoded.workoutSessions[1].checkIn?.perExercise?["Row"] == .tooHard)
check("session dates survive exactly",
    decoded.workoutSessions[0].date == sessionDate1 && decoded.workoutSessions[1].date == sessionDate2)
check("duration survives", decoded.workoutSessions[1].durationSeconds == 3600)

check("AI preferences survive", decoded.aiUserPreferences == preferences)
check("custom exercises survive", decoded.customExercises == [customExercise])

// The nested payloads use the app's default Codable encoding, so a future
// importer can hand `routines`/`workoutSessions` straight to the existing
// store decoding. Cross-check: extract the routines array from the export and
// decode it with a PLAIN JSONDecoder as the store would.
let routinesFragment = try! JSONSerialization.data(withJSONObject: topLevel["routines"]!)
let storeDecodedRoutines = try? JSONDecoder().decode([Routine].self, from: routinesFragment)
check("routines fragment decodes with the store's plain JSONDecoder",
    storeDecodedRoutines?.map(\.id) == [routineID1, routineID2])

// MARK: - Determinism

print("-- determinism --")
let dataAgain = try! DataExport.encode(buildFixtureDocument())
check("same input → byte-identical export", dataAgain == data)

// MARK: - Exclusions (settings noise / derived caches never leak in)

print("-- exclusions --")
for banned in [
    "exerciseInsightsV1",     // insight cache
    "userMemoryDigestV1",     // derived AI memory digest
    "discoveryAskCoachUses",  // discovery-hint counters
    "discoveryExerciseInfoUses",
    "discoveryReviewNudgeSeen",
    "accentScheme",           // appearance setting
    "aiBackendBaseURL",       // backend URL
    "appToken",               // backend auth
] {
    check("excluded: \(banned)", !json.contains(banned) && !emptyJSON.contains(banned))
}

// MARK: - Filename

print("-- filename --")
let utc = TimeZone(identifier: "UTC")!
check("filename matches lokt-export-YYYY-MM-DD.json",
    DataExport.filename(for: exportDate, timeZone: utc) == "lokt-export-2026-08-30.json")
let lateUTC = iso.date(from: "2026-08-30T02:00:00Z")!
check("filename uses the local calendar day",
    DataExport.filename(for: lateUTC, timeZone: TimeZone(identifier: "America/New_York")!) == "lokt-export-2026-08-29.json")

// MARK: - Empty data (fresh install still exports a valid document)

print("-- empty data --")
let emptyTop = try! JSONSerialization.jsonObject(with: emptyData) as! [String: Any]
check("empty export keeps all top-level keys", Set(emptyTop.keys) == expectedKeys)
check("empty routines is an empty array", (emptyTop["routines"] as? [Any])?.isEmpty == true)
check("empty sessions is an empty array", (emptyTop["workoutSessions"] as? [Any])?.isEmpty == true)
check("empty custom exercises is an empty array", (emptyTop["customExercises"] as? [Any])?.isEmpty == true)
let decodedEmpty = try? JSONDecoder().decode(DataExport.Document.self, from: emptyData)
check("empty export round-trips", decodedEmpty?.aiUserPreferences == AIUserPreferences.empty)

print("==========================")
if failures == 0 {
    print("ALL CHECKS PASSED")
    exit(0)
} else {
    print("\(failures) CHECK(S) FAILED")
    exit(1)
}
