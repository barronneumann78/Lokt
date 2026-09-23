import Foundation

/// Pure math behind the Home screen: the Mon–Sun week strip, the stat row and
/// the "up next" routine. Every function takes `now` and a calendar so
/// `harness/logic-checks/home-week-strip` can pin dates. Tonnage and set
/// counts route through `AnalyticsMath` (completed sets only — a legacy nil
/// flag counts, an explicit `false` never does), so Home agrees with
/// Analytics on what a set is worth. Foundation-only on purpose.
enum HomeInsights {

    // MARK: - Week (Monday-first)

    /// Home's week runs Mon–Sun regardless of locale (training splits start on
    /// Monday): a copy of `base` whose week starts on Monday. Time zone,
    /// locale and day boundaries stay the user's own.
    static func weekCalendar(_ base: Calendar = .current) -> Calendar {
        var calendar = base
        calendar.firstWeekday = 2
        return calendar
    }

    /// The Mon–Sun week `offset` weeks away from the one containing `now`.
    static func week(offset: Int, from now: Date, calendar: Calendar) -> DateInterval? {
        guard let current = calendar.dateInterval(of: .weekOfYear, for: now),
              let start = calendar.date(byAdding: .weekOfYear, value: offset, to: current.start) else {
            return nil
        }
        return calendar.dateInterval(of: .weekOfYear, for: start)
    }

    /// Half-open membership: `DateInterval.contains` is inclusive at `end`,
    /// which would file a session stamped exactly Monday 00:00 under BOTH
    /// weeks (caught by the logic check).
    static func week(_ week: DateInterval, contains date: Date) -> Bool {
        date >= week.start && date < week.end
    }

    static func sessions(
        _ sessions: [WorkoutSession],
        inWeekOffset offset: Int,
        now: Date,
        calendar: Calendar
    ) -> [WorkoutSession] {
        guard let week = week(offset: offset, from: now, calendar: calendar) else { return [] }
        return sessions.filter { self.week(week, contains: $0.date) }
    }

    /// Sessions dated within the last `days` local calendar days, today included
    /// (`days: 7` on a Wednesday = last Thursday through today).
    static func sessions(
        _ sessions: [WorkoutSession],
        inLastDays days: Int,
        now: Date,
        calendar: Calendar
    ) -> [WorkoutSession] {
        let today = calendar.startOfDay(for: now)
        guard days > 0,
              let start = calendar.date(byAdding: .day, value: -(days - 1), to: today),
              let end = calendar.date(byAdding: .day, value: 1, to: today) else {
            return []
        }
        return sessions.filter { $0.date >= start && $0.date < end }
    }

    // MARK: - Volume (completed sets only)

    static func sessionVolume(_ session: WorkoutSession) -> Double {
        session.logs.values
            .flatMap { $0 }
            .compactMap(AnalyticsMath.setVolume)
            .reduce(0, +)
    }

    static func countedSets(_ session: WorkoutSession) -> Int {
        session.logs.values
            .flatMap { $0 }
            .filter(AnalyticsMath.isCountedSet)
            .count
    }

    static func totalVolume(_ sessions: [WorkoutSession]) -> Double {
        sessions.map(sessionVolume).reduce(0, +)
    }

    /// Percent change of this week against last. Nil — the chip hides — when
    /// last week logged nothing (no baseline) or this week hasn't logged yet
    /// (a "−100%" on Monday morning tells the user nothing).
    static func volumeDeltaPercent(current: Double, previous: Double) -> Double? {
        guard previous > 0, current > 0 else { return nil }
        return (current - previous) / previous * 100
    }

    /// Hero / row tonnage: ("12.4", "k lb") at or above 1,000 lb, else ("850", "lb").
    static func volumeLabel(_ volume: Double) -> (value: String, unit: String) {
        if volume >= 1000 {
            return (String(format: "%.1f", volume / 1000), "k lb")
        }
        return ("\(Int(volume))", "lb")
    }

    // MARK: - Week strip

    struct DayVolume: Identifiable, Equatable {
        /// Start of the local day.
        let day: Date
        /// Very short weekday symbol ("M", "T", …) from the calendar's locale.
        let letter: String
        let volume: Double
        let isToday: Bool
        var id: Date { day }
    }

    /// Seven entries, Monday through Sunday of the week containing `now`, each
    /// carrying that local day's completed-set tonnage (0 for quiet days —
    /// the strip renders a minimum-height bar, never a gap).
    static func weekStrip(sessions: [WorkoutSession], now: Date, calendar: Calendar) -> [DayVolume] {
        guard let week = week(offset: 0, from: now, calendar: calendar) else { return [] }
        let today = calendar.startOfDay(for: now)

        var volumeByDay: [Date: Double] = [:]
        for session in sessions where self.week(week, contains: session.date) {
            volumeByDay[calendar.startOfDay(for: session.date), default: 0] += sessionVolume(session)
        }

        let symbols = calendar.veryShortWeekdaySymbols
        return (0..<7).compactMap { index in
            guard let date = calendar.date(byAdding: .day, value: index, to: week.start) else { return nil }
            let day = calendar.startOfDay(for: date)
            let weekday = calendar.component(.weekday, from: day)
            return DayVolume(
                day: day,
                letter: symbols[weekday - 1],
                volume: volumeByDay[day] ?? 0,
                isToday: day == today
            )
        }
    }

    // MARK: - Stat row

    /// Consecutive weeks (Mon–Sun) with at least one session, counting back
    /// from the current week. A quiet current week doesn't break the streak —
    /// it isn't over yet — so the count then starts from last week.
    static func streakWeeks(sessions: [WorkoutSession], now: Date, calendar: Calendar) -> Int {
        let weekStarts = Set(sessions.compactMap { calendar.dateInterval(of: .weekOfYear, for: $0.date)?.start })
        guard !weekStarts.isEmpty,
              let currentStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start else {
            return 0
        }

        var cursor: Date? = weekStarts.contains(currentStart)
            ? currentStart
            : calendar.date(byAdding: .weekOfYear, value: -1, to: currentStart)
        var streak = 0
        while let week = cursor, weekStarts.contains(week) {
            streak += 1
            cursor = calendar.date(byAdding: .weekOfYear, value: -1, to: week)
        }
        return streak
    }

    /// e1RM PRs set in the last `days` local days — the SAME rule as the
    /// Analytics day scorecard (`AnalyticsSnapshot.dayScorecard`): a day's best
    /// Epley e1RM per canonical exercise beats every earlier day; an exercise's
    /// first-ever day seeds the baseline without a PR. Summed over the window's
    /// lifting days. `resolve` is the library lookup Analytics uses, so
    /// "bench" and "Bench Press" are one exercise here too.
    static func prCount(
        sessions: [WorkoutSession],
        lastDays days: Int,
        now: Date,
        calendar: Calendar,
        resolve: (String) -> Exercise?
    ) -> Int {
        let today = calendar.startOfDay(for: now)
        guard days > 0,
              let windowStart = calendar.date(byAdding: .day, value: -(days - 1), to: today) else {
            return 0
        }

        var sessionsByDay: [Date: [WorkoutSession]] = [:]
        for session in sessions {
            sessionsByDay[calendar.startOfDay(for: session.date), default: []].append(session)
        }

        return sessionsByDay.keys
            .filter { $0 >= windowStart && $0 <= today }
            .reduce(0) { count, day in
                count + AnalyticsSnapshot.dayScorecard(
                    day: day,
                    sessionsByDay: sessionsByDay,
                    resolve: resolve
                ).prs.count
            }
    }

    // MARK: - Up next

    /// When each routine was last done. A session counts for a routine when
    /// its `routineID` matches, or its name is one of the routine's known
    /// names — the logger's own matching rule, so legacy sessions saved
    /// without an id still count.
    static func lastDoneDates(routines: [Routine], sessions: [WorkoutSession]) -> [UUID: Date] {
        var lastDone: [UUID: Date] = [:]
        for routine in routines {
            let knownNames = Set(routine.allKnownNames)
            for session in sessions
            where session.routineID == routine.id || knownNames.contains(session.routineName) {
                if session.date > (lastDone[routine.id] ?? .distantPast) {
                    lastDone[routine.id] = session.date
                }
            }
        }
        return lastDone
    }

    /// The routine the START pill offers.
    /// - No routines → nil (the pill reads CREATE A ROUTINE).
    /// - One routine → that one, done or not.
    /// - The most recently done routine sits in a group with other members →
    ///   the least-recently-done OTHER member of that group (never-done first,
    ///   ties by stored order): a rotating split's natural next variant.
    /// - Otherwise → the least-recently-done routine overall (never-done
    ///   first, ties by stored order).
    /// A `groupID` that names no existing group reads as ungrouped, exactly
    /// as the Workout tab renders it.
    static func nextRoutine(
        routines: [Routine],
        groups: [RoutineGroup],
        sessions: [WorkoutSession]
    ) -> Routine? {
        guard let first = routines.first else { return nil }
        guard routines.count > 1 else { return first }

        let lastDone = lastDoneDates(routines: routines, sessions: sessions)
        let groupIDs = Set(groups.map(\.id))

        func storedIndex(_ routine: Routine) -> Int {
            routines.firstIndex { $0.id == routine.id } ?? routines.count
        }

        func leastRecent(in candidates: [Routine]) -> Routine? {
            candidates.min { lhs, rhs in
                let lhsDate = lastDone[lhs.id] ?? .distantPast
                let rhsDate = lastDone[rhs.id] ?? .distantPast
                if lhsDate != rhsDate { return lhsDate < rhsDate }
                return storedIndex(lhs) < storedIndex(rhs)
            }
        }

        // Most recently done routine; an exact tie keeps the earlier-stored one.
        var mostRecent: (routine: Routine, date: Date)?
        for routine in routines {
            guard let date = lastDone[routine.id] else { continue }
            if let current = mostRecent, current.date >= date { continue }
            mostRecent = (routine, date)
        }

        if let mostRecent,
           let groupID = mostRecent.routine.groupID,
           groupIDs.contains(groupID) {
            let siblings = routines.filter { $0.groupID == groupID && $0.id != mostRecent.routine.id }
            if let next = leastRecent(in: siblings) {
                return next
            }
        }

        return leastRecent(in: routines)
    }
}
