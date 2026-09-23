import Foundation

/// Where an exercise sat in a session, and what that did to the numbers.
///
/// Order changes how much you can lift: RDLs done first and RDLs done third
/// are not the same lift, so their bests are not directly comparable.
/// `WorkoutSession.logs` is a dictionary, so the performed order is recorded
/// separately (`WorkoutSession.exerciseOrder`, written by the logger at
/// finish). Sessions saved before that field existed fall back to the
/// routine's current order — best effort; the logger mirrors mid-workout
/// reorders into the routine, so it is usually right. Foundation-only so
/// `harness/logic-checks/exercise-position` compiles it against the real models.
enum ExercisePositionLogic {

    /// Positioned sessions (with an e1RM) an exercise needs before it earns
    /// a profile in the Advanced section.
    static let minimumSessions = 4
    /// Positions 1...`earlyPositionLimit` are "early"; everything after is "late".
    static let earlyPositionLimit = 2
    /// Both buckets need this many sessions before the late-vs-early delta
    /// is computed — one session per side is an anecdote, not an effect.
    static let minimumBucketSessions = 2

    // MARK: - Order & position

    /// Current routine order keyed by routine id — the legacy-session fallback.
    static func routineOrders(from routines: [Routine]) -> [UUID: [String]] {
        Dictionary(routines.map { ($0.id, $0.exercises) }, uniquingKeysWith: { first, _ in first })
    }

    /// The order the session's exercises were performed in: the recorded
    /// order when the session carries one, else the routine's current order,
    /// else nil (unknown — the session contributes nothing to position math).
    static func performedOrder(
        for session: WorkoutSession,
        routineOrders: [UUID: [String]] = [:]
    ) -> [String]? {
        if let recorded = session.exerciseOrder, !recorded.isEmpty {
            return recorded
        }
        guard let routineID = session.routineID,
              let fallback = routineOrders[routineID],
              !fallback.isEmpty else {
            return nil
        }
        return fallback
    }

    /// True when the exercise actually happened in the session: at least one
    /// checked-off set with usable numbers (`AnalyticsMath.isCountedSet`).
    static func wasPerformed(_ exercise: String, in session: WorkoutSession) -> Bool {
        session.logs[exercise]?.contains(where: AnalyticsMath.isCountedSet) ?? false
    }

    /// 1-based slot of every performed exercise in `order`, keyed by logged
    /// name. Only performed exercises count — a skipped exercise adds no
    /// fatigue, so it does not push the ones after it back. Exercises logged
    /// outside the order have no slot.
    static func positions(in session: WorkoutSession, order: [String]) -> [String: Int] {
        var slots: [String: Int] = [:]
        var seen = Set<String>()
        var slot = 0
        for name in order where seen.insert(name).inserted {
            guard wasPerformed(name, in: session) else { continue }
            slot += 1
            slots[name] = slot
        }
        return slots
    }

    /// Slots for a session using its performed order (recorded, else routine
    /// fallback). Empty when the order is unknown.
    static func positions(
        in session: WorkoutSession,
        routineOrders: [UUID: [String]] = [:]
    ) -> [String: Int] {
        guard let order = performedOrder(for: session, routineOrders: routineOrders) else { return [:] }
        return positions(in: session, order: order)
    }

    /// 1-based slot of one exercise, or nil when unknown / not performed.
    static func position(
        of exercise: String,
        in session: WorkoutSession,
        routineOrders: [UUID: [String]] = [:]
    ) -> Int? {
        positions(in: session, routineOrders: routineOrders)[exercise]
    }

    static func isEarly(_ position: Int) -> Bool {
        position <= earlyPositionLimit
    }

    /// "1st", "2nd", "3rd", "4th", "11th"–"13th", "21st", ...
    static func ordinal(_ value: Int) -> String {
        let suffix: String
        if (11...13).contains(value % 100) {
            suffix = "th"
        } else {
            switch value % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(value)\(suffix)"
    }

    // MARK: - Per-exercise profile

    /// One exercise's positional history. Bests are Epley e1RMs from
    /// completed sets only (`AnalyticsMath.bestE1RM`).
    struct ExerciseProfile: Identifiable, Equatable {
        var id: String { exercise }
        /// Canonical (library-resolved) exercise name.
        var exercise: String
        /// Sessions with both a known position and an e1RM.
        var sessionCount: Int
        /// Most common position; ties go to the earlier slot.
        var typicalPosition: Int
        /// Best e1RM at positions 1–2 and how many sessions fed it.
        var earlyBest: Double?
        var earlyCount: Int
        /// Best e1RM at positions 3+ and how many sessions fed it.
        var lateBest: Double?
        var lateCount: Int
        /// Position in the session that set the all-time e1RM; nil when that
        /// session's order is unknown.
        var prPosition: Int?

        /// Late best relative to early best, in percent — the fatigue effect
        /// as a number. Nil until both buckets have `minimumBucketSessions`.
        var lateVsEarlyPercent: Double? {
            guard let earlyBest, let lateBest, earlyBest > 0,
                  earlyCount >= minimumBucketSessions,
                  lateCount >= minimumBucketSessions else { return nil }
            return (lateBest - earlyBest) / earlyBest * 100
        }
    }

    /// Profiles for every exercise with at least `minimumSessions` positioned
    /// sessions, most-trained first. `canonical` merges logged aliases the
    /// same way the progression chart does.
    static func profiles(
        sessions: [WorkoutSession],
        routineOrders: [UUID: [String]] = [:],
        canonical: (String) -> String = { $0 }
    ) -> [ExerciseProfile] {
        struct Observation {
            var position: Int?
            var e1RM: Double
        }

        let sorted = sessions.sorted {
            $0.date != $1.date ? $0.date < $1.date : $0.id.uuidString < $1.id.uuidString
        }

        var observations: [String: [Observation]] = [:]
        for session in sorted {
            let slots = positions(in: session, routineOrders: routineOrders)

            // Aliases resolving to one exercise within a session merge: the
            // earliest slot and the best set win.
            var perExercise: [String: Observation] = [:]
            for (name, sets) in session.logs {
                guard let e1RM = AnalyticsMath.bestE1RM(in: sets) else { continue }
                let key = canonical(name)
                let slot = slots[name]
                if let existing = perExercise[key] {
                    perExercise[key] = Observation(
                        position: [existing.position, slot].compactMap { $0 }.min(),
                        e1RM: max(existing.e1RM, e1RM)
                    )
                } else {
                    perExercise[key] = Observation(position: slot, e1RM: e1RM)
                }
            }
            for (key, observation) in perExercise {
                observations[key, default: []].append(observation)
            }
        }

        var profiles: [ExerciseProfile] = []
        for (exercise, history) in observations {
            let positioned = history.compactMap { observation -> (position: Int, e1RM: Double)? in
                observation.position.map { ($0, observation.e1RM) }
            }
            guard positioned.count >= minimumSessions else { continue }

            var counts: [Int: Int] = [:]
            for entry in positioned {
                counts[entry.position, default: 0] += 1
            }
            guard let typical = counts.max(by: { lhs, rhs in
                lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key > rhs.key
            })?.key else { continue }

            let early = positioned.filter { isEarly($0.position) }
            let late = positioned.filter { !isEarly($0.position) }

            // All-time PR = the first session to reach the top e1RM (strict >
            // in chronological order, matching the user-memory digest).
            var best: Observation?
            for observation in history where best.map({ observation.e1RM > $0.e1RM }) ?? true {
                best = observation
            }

            profiles.append(ExerciseProfile(
                exercise: exercise,
                sessionCount: positioned.count,
                typicalPosition: typical,
                earlyBest: early.map(\.e1RM).max(),
                earlyCount: early.count,
                lateBest: late.map(\.e1RM).max(),
                lateCount: late.count,
                prPosition: best?.position
            ))
        }

        return profiles.sorted { lhs, rhs in
            if lhs.sessionCount != rhs.sessionCount { return lhs.sessionCount > rhs.sessionCount }
            return lhs.exercise < rhs.exercise
        }
    }

    /// The coach-facing suffix for an all-time PR line, e.g.
    /// " · usually 3rd, PR came 1st". Empty without enough history.
    static func digestSuffix(for profile: ExerciseProfile?) -> String {
        guard let profile else { return "" }
        var text = " · usually \(ordinal(profile.typicalPosition))"
        if let pr = profile.prPosition {
            text += ", PR came \(ordinal(pr))"
        }
        return text
    }
}
