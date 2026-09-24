import Foundation

/// Pure logic behind the exercise page's numbers (look v2, phase 7): the
/// BEST / e1RM / LAST tiles and the HISTORY drop-down. Completed sets only
/// (`AnalyticsMath.isCountedSet`), e1RM through `AnalyticsMath` (never
/// reimplemented), positions through `ExercisePositionLogic` (never
/// duplicated). Foundation-only so
/// `harness/logic-checks/exercise-detail-stats` compiles it with pinned dates.
enum ExerciseDetailInsights {

    // MARK: - One counted set

    /// A logged set that counts on the page: checked off, with at least one
    /// parseable number. Sets with both numbers carry an Epley e1RM; a
    /// reps-only set (bodyweight) or a weight-only set still ranks, below
    /// any set that has an e1RM.
    struct SetResult: Equatable {
        var weight: Double?
        var reps: Int?
        var e1RM: Double?

        init?(_ set: WorkoutSet) {
            guard AnalyticsMath.isCountedSet(set) else { return nil }
            weight = AnalyticsMath.parseWeight(set.weight)
            reps = AnalyticsMath.parseReps(set.reps)
            if let weight, let reps {
                e1RM = AnalyticsMath.epleyOneRepMax(weight: weight, reps: reps)
            }
        }

        /// "225 × 6", "BW × 12" (reps only), "225" (weight only).
        var label: String {
            switch (weight, reps) {
            case let (weight?, reps?):
                return "\(AnalyticsMath.formattedWeight(weight)) × \(reps)"
            case let (nil, reps?):
                return "BW × \(reps)"
            case let (weight?, nil):
                return AnalyticsMath.formattedWeight(weight)
            case (nil, nil):
                return "—"
            }
        }

        /// Ranking: an e1RM beats no e1RM; a higher e1RM wins, ties go to
        /// the heavier weight; without an e1RM more reps win, then more
        /// weight. Strict — an equal set is not "better", so the first one
        /// seen keeps its place.
        func beats(_ other: SetResult) -> Bool {
            switch (e1RM, other.e1RM) {
            case let (mine?, theirs?):
                if mine != theirs { return mine > theirs }
                return (weight ?? 0) > (other.weight ?? 0)
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                if (reps ?? 0) != (other.reps ?? 0) { return (reps ?? 0) > (other.reps ?? 0) }
                return (weight ?? 0) > (other.weight ?? 0)
            }
        }
    }

    /// The best counted set in a group by `beats`; nil when nothing counts.
    static func bestSet(in sets: [WorkoutSet]) -> SetResult? {
        var best: SetResult?
        for set in sets {
            guard let result = SetResult(set) else { continue }
            if best.map({ result.beats($0) }) ?? true {
                best = result
            }
        }
        return best
    }

    // MARK: - History & tiles

    /// One session's line in HISTORY: when, the session's best set, and
    /// where the exercise sat (nil when the order is unknown).
    struct HistoryRow: Identifiable, Equatable {
        var id: UUID
        var date: Date
        var bestSet: SetResult
        var position: Int?
    }

    struct Stats: Equatable {
        /// Every session with a counted set for the exercise, newest first.
        var history: [HistoryRow]
        /// The all-time best set — the first session to reach the top rank.
        var best: SetResult?

        static let empty = Stats(history: [], best: nil)

        var hasHistory: Bool { !history.isEmpty }
        var sessionCount: Int { history.count }
        /// LAST = the most recent session's best set.
        var last: SetResult? { history.first?.bestSet }
        /// The rows the drop-down shows; the header still counts them all.
        var recent: [HistoryRow] { Array(history.prefix(ExerciseDetailInsights.recentRowLimit)) }

        // Tile copy. "—" only when the exercise has history but that tile has
        // nothing to say (a bodyweight lift has no e1RM); a never-performed
        // exercise hides the whole row instead (`hasHistory`).
        var bestLabel: String { best?.label ?? "—" }
        var e1RMLabel: String { best?.e1RM.map(AnalyticsMath.formattedWeight) ?? "—" }
        var lastLabel: String { last?.label ?? "—" }
    }

    static let recentRowLimit = 10

    /// The page's numbers for one exercise. `isMatch` decides which log keys
    /// belong to the exercise — the view resolves aliases through the
    /// library; the default is a case-insensitive name match. Keys matching
    /// within one session merge: best set across them, earliest slot.
    static func stats(
        for exerciseName: String,
        sessions: [WorkoutSession],
        routineOrders: [UUID: [String]] = [:],
        isMatch: ((String) -> Bool)? = nil
    ) -> Stats {
        let matches = isMatch ?? { $0.caseInsensitiveCompare(exerciseName) == .orderedSame }
        let newestFirst = sessions.sorted {
            $0.date != $1.date ? $0.date > $1.date : $0.id.uuidString > $1.id.uuidString
        }

        var rows: [HistoryRow] = []
        for session in newestFirst {
            var sets: [WorkoutSet] = []
            var names: [String] = []
            for name in session.logs.keys.sorted() where matches(name) {
                sets.append(contentsOf: session.logs[name] ?? [])
                names.append(name)
            }
            guard let best = bestSet(in: sets) else { continue }

            let slots = ExercisePositionLogic.positions(in: session, routineOrders: routineOrders)
            rows.append(HistoryRow(
                id: session.id,
                date: session.date,
                bestSet: best,
                position: names.compactMap { slots[$0] }.min()
            ))
        }

        // All-time best: walk oldest → newest with strict `beats`, so the
        // first session to reach the top set keeps it (the PR digest's rule).
        var best: SetResult?
        for row in rows.reversed() where best.map({ row.bestSet.beats($0) }) ?? true {
            best = row.bestSet
        }

        return Stats(history: rows, best: best)
    }

    // MARK: - Copy

    /// "3rd in session" — only while the ADVANCED analytics layer is on and
    /// the position is known; nil otherwise so the row stays quiet.
    static func positionTag(_ position: Int?, advanced: Bool) -> String? {
        guard advanced, let position else { return nil }
        return "\(ExercisePositionLogic.ordinal(position)) in session"
    }

    /// "1 session" / "5 sessions" for the HISTORY header.
    static func sessionsLabel(_ count: Int) -> String {
        "\(count) session\(count == 1 ? "" : "s")"
    }

    /// "Sep 15" inside `now`'s year, "Sep 15, 2025" otherwise.
    static func dayLabel(_ date: Date, now: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale
        formatter.timeZone = calendar.timeZone
        let sameYear = calendar.isDate(date, equalTo: now, toGranularity: .year)
        formatter.setLocalizedDateFormatFromTemplate(sameYear ? "MMM d" : "MMM d yyyy")
        return formatter.string(from: date)
    }
}

/// The page's drop-down sections and their persisted open state — per app,
/// not per exercise. FORM CUES opens by default; everything else starts
/// closed.
enum ExerciseDetailSection: String, CaseIterable {
    case formCues
    case howTo
    case plainWords
    case variations
    case history

    var storageKey: String { "exerciseDetail.\(rawValue).openV1" }

    var opensByDefault: Bool { self == .formCues }
}
