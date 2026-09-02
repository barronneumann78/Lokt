import Foundation
import Combine

/// Single source of truth for routines and workout sessions (build plan M1).
///
/// Historically these were JSON-encoded into `UserDefaults` and read/written
/// directly from ~10 different views, with no single owner. `WorkoutStore`
/// centralizes that. It intentionally reads and writes the *same* keys and the
/// *same* encoding as the old code (`"routines"` / `"workoutSessions"`), so:
///   1. Existing saved data loads unchanged.
///   2. Views not yet migrated keep working against `UserDefaults` directly.
///
/// The next increment (M1b) migrates those call sites to go through this store,
/// after which `reload()` becomes unnecessary. Until then, call `reload()` when a
/// screen that still writes `UserDefaults` directly hands control back.
@MainActor
final class WorkoutStore: ObservableObject {

    // Keep in sync with the legacy string keys used throughout the app.
    static let routinesKey = "routines"
    static let sessionsKey = "workoutSessions"

    @Published private(set) var routines: [Routine]
    @Published private(set) var sessions: [WorkoutSession]

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.routines = Self.decodeArray(Routine.self, forKey: Self.routinesKey, from: defaults)
        self.sessions = Self.decodeArray(WorkoutSession.self, forKey: Self.sessionsKey, from: defaults)
    }

    // MARK: - Loading / persistence

    /// Re-read from `UserDefaults`. Use this after a not-yet-migrated screen wrote
    /// the keys directly, so the store's published state stays in sync.
    func reload() {
        routines = Self.decodeArray(Routine.self, forKey: Self.routinesKey, from: defaults)
        sessions = Self.decodeArray(WorkoutSession.self, forKey: Self.sessionsKey, from: defaults)
    }

    private func persistRoutines() {
        guard let data = try? encoder.encode(routines) else { return }
        defaults.set(data, forKey: Self.routinesKey)
    }

    private func persistSessions() {
        guard let data = try? encoder.encode(sessions) else { return }
        defaults.set(data, forKey: Self.sessionsKey)
    }

    private static func decodeArray<T: Decodable>(_ type: T.Type, forKey key: String, from defaults: UserDefaults) -> [T] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([T].self, from: data) else {
            return []
        }
        return decoded
    }

    // MARK: - Routine CRUD

    func routine(withID id: UUID) -> Routine? {
        routines.first { $0.id == id }
    }

    func addRoutine(_ routine: Routine) {
        routines.append(routine)
        persistRoutines()
    }

    /// Insert or update `routine` based on its `id`.
    func upsertRoutine(_ routine: Routine) {
        if let index = routines.firstIndex(where: { $0.id == routine.id }) {
            routines[index] = routine
        } else {
            routines.append(routine)
        }
        persistRoutines()
    }

    func deleteRoutine(id: UUID) {
        routines.removeAll { $0.id == id }
        persistRoutines()
    }

    func replaceRoutines(_ newRoutines: [Routine]) {
        routines = newRoutines
        persistRoutines()
    }

    // MARK: - Session CRUD

    func addSession(_ session: WorkoutSession) {
        sessions.append(session)
        persistSessions()
        // Refresh the derived AI memory digest (a pure function of the raw
        // data — never a second persistence path for it).
        UserMemoryStore.refresh(defaults: defaults)
    }

    func session(withID id: UUID) -> WorkoutSession? {
        sessions.first { $0.id == id }
    }

    /// Replace the stored session with the same id (the session editor's save
    /// path). Never inserts — correcting a session that no longer exists is a
    /// no-op, not a resurrection.
    func updateSession(_ session: WorkoutSession) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[index] = session
        persistSessions()
        // Corrections rewrite history — rebuild the derived AI memory digest,
        // same as every other session-writing path.
        UserMemoryStore.refresh(defaults: defaults)
    }

    // MARK: - Adaptation loop (spine §6) — foundation for M4

    /// Current adaptation state for an exercise within a routine, if any.
    func progressionState(for exerciseName: String, in routineID: UUID) -> ExerciseProgressionState? {
        routine(withID: routineID)?.progression?[exerciseName]
    }

    /// Attach a post-session check-in to a stored session and fold it into the
    /// per-exercise progression state on the session's routine.
    ///
    /// This does not itself call the AI. It only records what happened and updates
    /// the rolling state that M4's revise call will read to nudge the next session.
    func recordCheckIn(_ checkIn: SessionCheckIn, forSessionID sessionID: UUID) {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[sessionIndex].checkIn = checkIn
        persistSessions()

        let session = sessions[sessionIndex]
        guard let routineID = session.routineID,
              let routineIndex = routines.firstIndex(where: { $0.id == routineID }) else {
            return
        }

        var progression = routines[routineIndex].progression ?? [:]

        for (exerciseName, sets) in session.logs {
            let outcome = checkIn.perExercise?[exerciseName] ?? checkIn.overall
            var state = progression[exerciseName] ?? ExerciseProgressionState()

            if let lastSet = sets.last(where: \.isCompleted) {
                state.lastWeight = lastSet.weight
                state.lastReps = lastSet.reps
            }
            state.lastOutcome = outcome
            state.consecutiveTooHard = (outcome == .tooHard) ? state.consecutiveTooHard + 1 : 0
            if let painExercise = checkIn.painExercise?.trimmingCharacters(in: .whitespacesAndNewlines),
               !painExercise.isEmpty {
                // M4's sheet names the exercise that hurt — flag exactly that one.
                state.painFlagged = checkIn.hadPain
                    && exerciseName.caseInsensitiveCompare(painExercise) == .orderedSame
            } else {
                // Coarse fallback (check-ins without a named exercise): session-level
                // pain applied to exercises the user found too hard.
                state.painFlagged = checkIn.hadPain && outcome == .tooHard
            }
            // The session this check-in describes consumed any applied nudge;
            // a fresh nudge (if the user applies one) repopulates these.
            state.suggestedWeightText = nil
            state.suggestedRepText = nil
            state.nudgeNote = nil
            state.updatedAt = Date()

            progression[exerciseName] = state
        }

        routines[routineIndex].progression = progression
        persistRoutines()
        // Check-in outcomes feed the AI memory digest's recent tier.
        UserMemoryStore.refresh(defaults: defaults)
    }
}
