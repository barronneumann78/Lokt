import Foundation
import Combine

/// Single source of truth for routines and workout sessions (build plan M1).
///
/// Historically these were JSON-encoded into `UserDefaults` and read/written
/// directly from ~10 different views, with no single owner. `WorkoutStore`
/// centralizes that. It intentionally reads and writes the *same* keys and the
/// *same* encoding as the old code (`"routines"` / `"workoutSessions"`), so:
///   1. Existing saved data loads unchanged.
///   2. Existing data remains available through one published owner.
@MainActor
final class WorkoutStore: ObservableObject {

    // Keep in sync with the legacy string keys used throughout the app.
    static let routinesKey = "routines"
    static let sessionsKey = "workoutSessions"
    // Newer key, same array+UserDefaults pattern as the two above. Routine
    // grouping is purely organizational and layers on top of `routines`
    // without touching its encoding.
    static let routineGroupsKey = "routineGroups"

    @Published private(set) var routines: [Routine]
    @Published private(set) var sessions: [WorkoutSession]
    @Published private(set) var routineGroups: [RoutineGroup]

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.routines = Self.decodeArray(Routine.self, forKey: Self.routinesKey, from: defaults)
        self.sessions = Self.decodeArray(WorkoutSession.self, forKey: Self.sessionsKey, from: defaults)
        self.routineGroups = Self.decodeArray(RoutineGroup.self, forKey: Self.routineGroupsKey, from: defaults)
    }

    // MARK: - Persistence

    private func persistRoutines() {
        guard let data = try? encoder.encode(routines) else { return }
        defaults.set(data, forKey: Self.routinesKey)
    }

    private func persistSessions() {
        guard let data = try? encoder.encode(sessions) else { return }
        defaults.set(data, forKey: Self.sessionsKey)
    }

    private func persistRoutineGroups() {
        guard let data = try? encoder.encode(routineGroups) else { return }
        defaults.set(data, forKey: Self.routineGroupsKey)
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

    // MARK: - Routine group CRUD
    // Purely organizational: groups never own or delete routines, they only
    // tag `Routine.groupID`. Deleting a group always ungroups its members
    // rather than touching `routines`.

    /// Create a new named group, appended after every existing group.
    @discardableResult
    func addRoutineGroup(name: String) -> RoutineGroup {
        let nextOrder = (routineGroups.map(\.order).max() ?? -1) + 1
        let group = RoutineGroup(name: name, order: nextOrder)
        routineGroups.append(group)
        persistRoutineGroups()
        return group
    }

    func renameRoutineGroup(id: UUID, name: String) {
        guard let index = routineGroups.firstIndex(where: { $0.id == id }) else { return }
        routineGroups[index].name = name
        persistRoutineGroups()
    }

    /// Delete a group, empty or not. Member routines become ungrouped —
    /// never deleted.
    func deleteRoutineGroup(id: UUID) {
        guard routineGroups.contains(where: { $0.id == id }) else { return }
        routineGroups.removeAll { $0.id == id }
        persistRoutineGroups()

        var didUngroup = false
        for index in routines.indices where routines[index].groupID == id {
            routines[index].groupID = nil
            didUngroup = true
        }
        if didUngroup { persistRoutines() }
    }

    /// Move a routine into `groupID`, or back to ungrouped when `nil`.
    func setRoutineGroup(_ groupID: UUID?, forRoutineID routineID: UUID) {
        guard let index = routines.firstIndex(where: { $0.id == routineID }) else { return }
        guard routines[index].groupID != groupID else { return }
        routines[index].groupID = groupID
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

    /// Replace the whole session history after a deliberate destructive edit,
    /// such as removing one exercise from every saved workout. This is the
    /// only bulk-session write path outside this store.
    func replaceSessions(_ newSessions: [WorkoutSession]) {
        sessions = newSessions
        persistSessions()
        UserMemoryStore.refresh(defaults: defaults)
    }

    /// Clear all session history while preserving the historical behavior of
    /// removing the legacy key instead of encoding an empty array.
    func deleteAllSessions() {
        sessions = []
        defaults.removeObject(forKey: Self.sessionsKey)
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
