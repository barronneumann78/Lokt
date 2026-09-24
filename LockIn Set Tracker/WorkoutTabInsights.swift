import Foundation

/// Pure logic behind the Workout tab's routine list (look v2): which member of
/// a rotation group is up next, the last-done chip text and the header's count
/// line. Nothing here forks `HomeInsights.nextRoutine` — the per-group pick is
/// that same rule run over one group's members, so Home's "Up next" and the
/// tab's gradient START name the same routine. Foundation-only so
/// `harness/logic-checks/workout-rotation` can compile it with pinned dates.
enum WorkoutTabInsights {

    // MARK: - Next member per group

    /// The group's next member: `HomeInsights.nextRoutine` over the members
    /// alone — least-recently-done first, a never-done member ahead of any
    /// done one, the member just done last, ties by stored order. A lone
    /// member is always next; an empty group has none.
    static func nextMember(
        of group: RoutineGroup,
        routines: [Routine],
        sessions: [WorkoutSession]
    ) -> Routine? {
        let members = routines.filter { $0.groupID == group.id }
        return HomeInsights.nextRoutine(routines: members, groups: [group], sessions: sessions)
    }

    /// Which cards wear the gradient START: every group's next member, plus
    /// the overall next (`HomeInsights.nextRoutine`) when it sits outside
    /// every group. An overall next inside a group is that group's next
    /// member already, so Home's "Up next" always lands on a gradient START.
    struct Rotation {
        /// Each group's next member, keyed by group id (empty groups absent).
        let nextByGroup: [UUID: Routine]
        /// The overall next when it is ungrouped (a dangling group id reads
        /// as ungrouped, exactly as the tab renders it); nil otherwise.
        let ungroupedNext: Routine?

        func isNext(_ routineID: UUID) -> Bool {
            ungroupedNext?.id == routineID || nextByGroup.values.contains { $0.id == routineID }
        }
    }

    static func rotation(
        routines: [Routine],
        groups: [RoutineGroup],
        sessions: [WorkoutSession]
    ) -> Rotation {
        var nextByGroup: [UUID: Routine] = [:]
        for group in groups {
            if let next = nextMember(of: group, routines: routines, sessions: sessions) {
                nextByGroup[group.id] = next
            }
        }

        let groupIDs = Set(groups.map(\.id))
        let overall = HomeInsights.nextRoutine(routines: routines, groups: groups, sessions: sessions)
        let overallIsUngrouped = overall.map { routine in
            routine.groupID.map { !groupIDs.contains($0) } ?? true
        } ?? false

        return Rotation(nextByGroup: nextByGroup, ungroupedNext: overallIsUngrouped ? overall : nil)
    }

    // MARK: - Last done

    /// The card's last-done chip: "Never", "Today", a weekday ("Mon") inside
    /// the current Mon–Sun week, "Last Thu" for the week before, then a short
    /// date ("Sep 2" — with the year once it differs from `now`'s). Weeks are
    /// Home's Monday-first weeks (`HomeInsights.weekCalendar`).
    static func lastDoneLabel(_ date: Date?, now: Date, calendar: Calendar) -> String {
        guard let date else { return "Never" }
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }

        let weekday = calendar.shortWeekdaySymbols[calendar.component(.weekday, from: date) - 1]
        if let thisWeek = HomeInsights.week(offset: 0, from: now, calendar: calendar),
           HomeInsights.week(thisWeek, contains: date) {
            return weekday
        }
        if let lastWeek = HomeInsights.week(offset: -1, from: now, calendar: calendar),
           HomeInsights.week(lastWeek, contains: date) {
            return "Last \(weekday)"
        }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale
        formatter.timeZone = calendar.timeZone
        let sameYear = calendar.isDate(date, equalTo: now, toGranularity: .year)
        formatter.setLocalizedDateFormatFromTemplate(sameYear ? "MMM d" : "MMM d yyyy")
        return formatter.string(from: date)
    }

    // MARK: - Copy

    /// "5 ROUTINES · 2 GROUPS" — singular at one, the group segment only once
    /// a group exists, "NO ROUTINES YET" for an empty library.
    static func countLine(routineCount: Int, groupCount: Int) -> String {
        guard routineCount > 0 else { return "NO ROUTINES YET" }
        var line = "\(routineCount) ROUTINE\(routineCount == 1 ? "" : "S")"
        if groupCount > 0 {
            line += " · \(groupCount) GROUP\(groupCount == 1 ? "" : "S")"
        }
        return line
    }

    /// Names at or under this length read as "<name> is next" in the group
    /// header chip; longer ones become "Next: <name>" (the view tail-truncates).
    static let shortNameLimit = 12

    static func nextChipText(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count <= shortNameLimit ? "\(trimmed) is next" : "Next: \(trimmed)"
    }

    /// The card's one-line exercise preview: the first `limit` names joined
    /// with " · " (the view tail-truncates); empty for an exercise-less routine.
    static func exercisePreview(_ exercises: [String], limit: Int = 3) -> String {
        exercises.prefix(limit).joined(separator: " · ")
    }
}
