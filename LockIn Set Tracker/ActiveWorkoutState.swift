import Foundation

/// Snapshot of an in-progress workout. The logger persists it on meaningful
/// mutations so quitting the app never loses a live session; the Workout tab
/// reads it to offer resume. Lives under its OWN UserDefaults key
/// (`activeWorkoutV1`) — additive, never touching the store-owned
/// `"routines"`/`"workoutSessions"` keys.
struct ActiveWorkoutState: Codable, Equatable {
    var routineID: UUID
    var routineName: String
    var startedAt: Date
    var lastInteractionAt: Date
    /// Seconds actually spent logging: interaction-to-interaction deltas
    /// accumulate, idle gaps longer than `idleGapCutoff` count as zero.
    /// Optional so a blob saved by a build without the field still decodes
    /// (the estimate then falls back to lastInteractionAt − startedAt).
    var activeSeconds: TimeInterval? = nil
    var logs: [String: [WorkoutSet]]
    var preferredSetCounts: [String: Int]

    // MARK: - Thresholds (single home; every function takes `now` so the
    // logic check can inject fixed dates)

    /// Elapsed beyond this is implausible for one workout — the finish flow
    /// inserts the duration-fix step instead of trusting the clock.
    static let implausibleElapsed: TimeInterval = 3 * 3600
    /// No interaction for this long marks the workout stale ("yesterday").
    static let staleAfter: TimeInterval = 12 * 3600
    /// Interaction gaps longer than this don't count as active logging time.
    static let idleGapCutoff: TimeInterval = 30 * 60
    /// Duration-fix wheel granularity (5 minutes).
    static let durationStep = 300

    /// The clock has been running ancient — surface it, never auto-discard.
    func isStale(now: Date) -> Bool {
        now.timeIntervalSince(lastInteractionAt) > Self.staleAfter
    }

    /// True when elapsed wall-clock time can't be trusted as the duration.
    func needsDurationFix(now: Date) -> Bool {
        now.timeIntervalSince(startedAt) > Self.implausibleElapsed
    }

    /// State after a meaningful interaction at `now`: bumps the interaction
    /// clock and accumulates active time, ignoring idle gaps (a resumed
    /// workout keeps yesterday's span instead of absorbing the overnight gap).
    func updatingActivity(now: Date) -> ActiveWorkoutState {
        var updated = self
        let gap = now.timeIntervalSince(lastInteractionAt)
        let counted = (gap >= 0 && gap <= Self.idleGapCutoff) ? gap : 0
        updated.activeSeconds = max(0, (activeSeconds ?? 0) + counted)
        updated.lastInteractionAt = now
        return updated
    }

    /// Where the duration-fix wheel STARTS — what the workout probably took,
    /// never zero. The active logging span (fallback: lastInteraction − start
    /// for legacy blobs), rounded UP to the 5-minute step so it never lands
    /// below the span, floored at one step, capped at wall-clock elapsed.
    func smartDurationSeconds(now: Date) -> Int {
        let elapsed = max(0, now.timeIntervalSince(startedAt))
        let fallbackSpan = max(0, lastInteractionAt.timeIntervalSince(startedAt))
        let span = max(0, min(activeSeconds ?? fallbackSpan, elapsed))
        let step = Self.durationStep
        let rounded = max(step, (Int(span) + step - 1) / step * step)
        return min(rounded, max(step, Int(elapsed)))
    }
}

/// UserDefaults persistence for the single active-workout slot.
enum ActiveWorkoutStore {
    static let key = "activeWorkoutV1"

    static func load(defaults: UserDefaults = .standard) -> ActiveWorkoutState? {
        guard let data = defaults.data(forKey: key),
              let state = try? JSONDecoder().decode(ActiveWorkoutState.self, from: data) else {
            return nil
        }
        return state
    }

    static func save(_ state: ActiveWorkoutState, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: key)
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }

    /// The routine an active state resumes into, or nil when it was deleted
    /// meanwhile — the caller then clears the state (graceful discard).
    static func resumableRoutine(for state: ActiveWorkoutState, in routines: [Routine]) -> Routine? {
        routines.first { $0.id == state.routineID }
    }

    /// True when the logs carry anything worth resuming. An untouched logger
    /// never claims the slot (so opening routine B doesn't clobber routine A's
    /// in-progress workout until the user actually logs something).
    static func hasMeaningfulContent(_ logs: [String: [WorkoutSet]]) -> Bool {
        logs.values.contains { sets in
            sets.contains { set in
                set.completed == true ||
                !set.weight.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                !set.reps.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }
    }
}
