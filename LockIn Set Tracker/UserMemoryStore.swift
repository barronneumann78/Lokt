import Foundation

// MARK: - Tiered user-memory digest
//
// A compact, AI-facing summary of the user's real training history, derived
// entirely from the raw stored data (`"workoutSessions"`, check-ins, and
// `aiUserPreferences`). The raw data is NEVER modified, trimmed, or compacted —
// this digest is a pure function of it, lives under its own UserDefaults key,
// and can always be rebuilt from scratch (so it self-heals if it ever drifts).
//
// Tier rules (the newest information is the most detailed; older information
// is summarized so history since the very first session survives cheaply):
//   - Recent   (last 14 days):  per-session detail.
//   - Mid      (15–90 days):    weekly summaries.
//   - Lifetime (90+ days):      monthly one-liners + durable facts (all-time
//                               PRs, pain history, consistency, training age).

struct UserMemory: Codable {
    var schemaVersion: Int? = 1
    /// When the digest was built. Tier boundaries move with the calendar, so a
    /// digest from an earlier day is stale even if no sessions were added.
    var generatedAt: Date? = nil
    /// Fingerprint of the raw data this digest was derived from.
    var sourceSessionCount: Int? = nil
    var recentSessions: [RecentSessionMemory]? = nil
    var weeklySummaries: [WeeklySummaryMemory]? = nil
    var lifetime: LifetimeMemory? = nil

    var isEmpty: Bool {
        (recentSessions ?? []).isEmpty && (weeklySummaries ?? []).isEmpty && lifetime == nil
    }
}

/// One fully-detailed session inside the recent tier. Newest first.
struct RecentSessionMemory: Codable {
    var date: String
    var routine: String
    var sets: Int? = nil
    var volume: Int? = nil
    var durationMinutes: Int? = nil
    /// Check-in outcome ("too easy" / "about right" / "too hard"), when answered.
    var checkIn: String? = nil
    var painNote: String? = nil
    /// Best set per exercise, heaviest first ("Bench Press 135x8 (e1RM 171)").
    var bestSets: [String]? = nil
    /// All-time e1RM bests broken in this session.
    var prs: [String]? = nil
}

/// One week of the mid tier (15–90 days ago). Newest first.
struct WeeklySummaryMemory: Codable {
    var weekOf: String
    var sessions: Int
    var sets: Int? = nil
    var volume: Int? = nil
    /// Dominant muscle groups by completed sets.
    var focus: [String]? = nil
    var prs: [String]? = nil
    /// Exercises whose first-ever appearance was this week.
    var introduced: [String]? = nil
    /// Established exercises last seen this week (not logged since).
    var dropped: [String]? = nil
}

/// One month (or, once collapsed, one year) of the lifetime tier.
struct MonthlySummaryMemory: Codable {
    /// "2026-04", or "2025" once the entry is collapsed into a year rollup.
    var month: String
    var sessions: Int
    var volume: Int? = nil
    var focus: [String]? = nil
}

/// Durable lifetime facts plus monthly one-liners back to the first session.
struct LifetimeMemory: Codable {
    var since: String? = nil
    var totalSessions: Int? = nil
    var totalVolume: Int? = nil
    var sessionsPerWeek: Double? = nil
    var longestStreakWeeks: Int? = nil
    /// "Bench Press e1RM 171 (2026-07-12)", strongest first.
    var allTimePRs: [String]? = nil
    /// Dated pain reports from post-session check-ins, newest first.
    var painHistory: [String]? = nil
    /// Standing limitations merged from the saved preference profile.
    var limitations: String? = nil
    var months: [MonthlySummaryMemory]? = nil
}

// MARK: - Builder (pure, testable)

enum UserMemoryBuilder {

    static let recentDays = 14
    static let midDays = 90
    /// Hard cap on the serialized digest (well under ~2k tokens).
    static let maxEncodedBytes = 6000

    private static let maxBestSetsPerSession = 6
    private static let maxFocusGroups = 2
    private static let maxAllTimePRs = 10
    private static let maxPainHistory = 8
    private static let maxMonthlyEntries = 18
    private static let maxIntroducedPerWeek = 5

    /// Build the digest from raw sessions + preferences. Pure — inject the
    /// exercise resolver (for muscle-group focus), clock, and calendar so the
    /// math stays deterministic and testable, mirroring `AnalyticsSnapshot`.
    static func build(
        sessions: [WorkoutSession],
        preferences: AIUserPreferences,
        resolve: (String) -> Exercise?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> UserMemory {
        var memory = UserMemory(generatedAt: now, sourceSessionCount: sessions.count)

        let sorted = sessions.sorted {
            $0.date != $1.date ? $0.date < $1.date : $0.id.uuidString < $1.id.uuidString
        }
        guard !sorted.isEmpty else { return memory }

        var resolutionCache: [String: Exercise?] = [:]
        func resolved(_ name: String) -> Exercise? {
            if let cached = resolutionCache[name] { return cached }
            let match = resolve(name)
            resolutionCache[name] = match
            return match
        }
        func canonical(_ name: String) -> String {
            resolved(name)?.name ?? name
        }

        // Chronological walk: per-session stats, all-time PR tracking, and
        // first/last appearance of each canonical exercise.
        var stats: [SessionStats] = []
        var allTimeBest: [String: (value: Double, date: Date)] = [:]
        var sessionsPerExercise: [String: Int] = [:]
        var firstSeen: [String: Date] = [:]
        var lastSeen: [String: Date] = [:]

        for session in sorted {
            var entry = SessionStats(session: session)

            for (name, sets) in session.logs.sorted(by: { $0.key < $1.key }) {
                let counted = sets.filter(AnalyticsMath.isCountedSet)
                guard !counted.isEmpty else { continue }

                let exercise = canonical(name)
                entry.countedSets += counted.count
                entry.volume += counted.compactMap(AnalyticsMath.setVolume).reduce(0, +)
                if let group = resolved(name)?.muscleGroup,
                   AnalyticsSnapshot.chartMuscleGroups.contains(group) {
                    entry.setsByGroup[group, default: 0] += counted.count
                }

                sessionsPerExercise[exercise, default: 0] += 1
                if firstSeen[exercise] == nil { firstSeen[exercise] = session.date }
                lastSeen[exercise] = session.date

                if let best = bestSet(in: counted) {
                    entry.bestSets.append(BestSet(exercise: exercise, set: best))
                }

                let sessionE1RM = counted.compactMap { set -> Double? in
                    guard let weight = AnalyticsMath.parseWeight(set.weight),
                          let reps = AnalyticsMath.parseReps(set.reps) else { return nil }
                    return AnalyticsMath.epleyOneRepMax(weight: weight, reps: reps)
                }.max()

                if let sessionE1RM {
                    if let previous = allTimeBest[exercise] {
                        if sessionE1RM > previous.value {
                            entry.prs.append("\(exercise) e1RM \(AnalyticsMath.formattedWeight(sessionE1RM))")
                            allTimeBest[exercise] = (sessionE1RM, session.date)
                        }
                    } else {
                        allTimeBest[exercise] = (sessionE1RM, session.date)
                    }
                }
            }

            stats.append(entry)
        }

        // Tier boundaries anchored to start of today so a day's sessions never
        // straddle a boundary.
        let startOfToday = calendar.startOfDay(for: now)
        let recentCutoff = calendar.date(byAdding: .day, value: -recentDays, to: startOfToday) ?? startOfToday
        let midCutoff = calendar.date(byAdding: .day, value: -midDays, to: startOfToday) ?? startOfToday

        let recent = stats.filter { $0.session.date >= recentCutoff }
        let mid = stats.filter { $0.session.date >= midCutoff && $0.session.date < recentCutoff }
        let old = stats.filter { $0.session.date < midCutoff }

        let recentEntries = recent.reversed().map { entry in
            recentMemory(for: entry, calendar: calendar)
        }
        memory.recentSessions = recentEntries.isEmpty ? nil : recentEntries
        memory.weeklySummaries = weeklySummaries(
            from: mid,
            firstSeen: firstSeen,
            lastSeen: lastSeen,
            sessionsPerExercise: sessionsPerExercise,
            recentCutoff: recentCutoff,
            calendar: calendar
        )
        memory.lifetime = lifetimeMemory(
            allStats: stats,
            oldStats: old,
            allTimeBest: allTimeBest,
            preferences: preferences,
            now: now,
            calendar: calendar
        )

        return capped(memory)
    }

    /// Serialize the way the digest is measured and persisted: sorted keys so
    /// identical inputs always produce identical bytes.
    static func encoded(_ memory: UserMemory) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(memory)
    }

    // MARK: Per-session working state

    private struct BestSet {
        var exercise: String
        var set: WorkoutSet
    }

    private struct SessionStats {
        var session: WorkoutSession
        var countedSets = 0
        var volume = 0.0
        var setsByGroup: [MuscleGroup: Int] = [:]
        var bestSets: [BestSet] = []
        var prs: [String] = []

        init(session: WorkoutSession) {
            self.session = session
        }
    }

    // MARK: Recent tier

    private static func recentMemory(for entry: SessionStats, calendar: Calendar) -> RecentSessionMemory {
        var memory = RecentSessionMemory(
            date: dayString(entry.session.date, calendar: calendar),
            routine: entry.session.routineName
        )
        memory.sets = entry.countedSets > 0 ? entry.countedSets : nil
        memory.volume = entry.volume > 0 ? Int(entry.volume.rounded()) : nil
        memory.durationMinutes = entry.session.durationSeconds.map { max(1, Int((Double($0) / 60).rounded())) }

        if let checkIn = entry.session.checkIn {
            memory.checkIn = outcomeText(checkIn.overall)
            if checkIn.hadPain {
                let note = checkIn.painNote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                memory.painNote = note.isEmpty ? "reported pain" : note
            }
        }

        let ranked = entry.bestSets.sorted { lhs, rhs in
            let lhsValue = setSortValue(lhs.set)
            let rhsValue = setSortValue(rhs.set)
            return lhsValue != rhsValue ? lhsValue > rhsValue : lhs.exercise < rhs.exercise
        }
        let lines = ranked.prefix(maxBestSetsPerSession).map { bestSetLine($0.exercise, $0.set) }
        memory.bestSets = lines.isEmpty ? nil : Array(lines)
        memory.prs = entry.prs.isEmpty ? nil : entry.prs.map { "PR: \($0)" }

        return memory
    }

    // MARK: Mid tier

    private static func weeklySummaries(
        from stats: [SessionStats],
        firstSeen: [String: Date],
        lastSeen: [String: Date],
        sessionsPerExercise: [String: Int],
        recentCutoff: Date,
        calendar: Calendar
    ) -> [WeeklySummaryMemory]? {
        guard !stats.isEmpty else { return nil }

        var byWeek: [Date: [SessionStats]] = [:]
        for entry in stats {
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: entry.session.date)?.start
                ?? calendar.startOfDay(for: entry.session.date)
            byWeek[weekStart, default: []].append(entry)
        }

        return byWeek.keys.sorted(by: >).map { weekStart -> WeeklySummaryMemory in
            let entries = byWeek[weekStart] ?? []
            let weekInterval = calendar.dateInterval(of: .weekOfYear, for: weekStart)

            func inWeek(_ date: Date) -> Bool {
                weekInterval?.contains(date)
                    ?? calendar.isDate(date, equalTo: weekStart, toGranularity: .weekOfYear)
            }

            var summary = WeeklySummaryMemory(
                weekOf: dayString(weekStart, calendar: calendar),
                sessions: entries.count
            )

            let sets = entries.map(\.countedSets).reduce(0, +)
            summary.sets = sets > 0 ? sets : nil
            let volume = entries.map(\.volume).reduce(0, +)
            summary.volume = volume > 0 ? Int(volume.rounded()) : nil
            summary.focus = focusGroups(entries.map(\.setsByGroup))

            let prs = entries.flatMap(\.prs)
            summary.prs = prs.isEmpty ? nil : prs

            let introduced = firstSeen
                .filter { inWeek($0.value) }
                .keys.sorted()
                .prefix(maxIntroducedPerWeek)
            summary.introduced = introduced.isEmpty ? nil : Array(introduced)

            // "Dropped" = an established exercise (3+ sessions) whose last-ever
            // appearance was this week — nothing since, including the recent tier.
            let dropped = lastSeen
                .filter { inWeek($0.value) && (sessionsPerExercise[$0.key] ?? 0) >= 3 }
                .keys.sorted()
                .prefix(maxIntroducedPerWeek)
            summary.dropped = dropped.isEmpty ? nil : Array(dropped)

            return summary
        }
    }

    // MARK: Lifetime tier

    private static func lifetimeMemory(
        allStats: [SessionStats],
        oldStats: [SessionStats],
        allTimeBest: [String: (value: Double, date: Date)],
        preferences: AIUserPreferences,
        now: Date,
        calendar: Calendar
    ) -> LifetimeMemory? {
        guard let first = allStats.first else { return nil }

        var lifetime = LifetimeMemory()
        lifetime.since = dayString(first.session.date, calendar: calendar)
        lifetime.totalSessions = allStats.count

        let totalVolume = allStats.map(\.volume).reduce(0, +)
        lifetime.totalVolume = totalVolume > 0 ? Int(totalVolume.rounded()) : nil

        let weeks = max(
            1,
            (calendar.dateComponents([.weekOfYear], from: first.session.date, to: now).weekOfYear ?? 0) + 1
        )
        lifetime.sessionsPerWeek = (Double(allStats.count) / Double(weeks) * 10).rounded() / 10
        lifetime.longestStreakWeeks = longestStreak(dates: allStats.map(\.session.date), calendar: calendar)

        let prs = allTimeBest
            .sorted { lhs, rhs in
                lhs.value.value != rhs.value.value
                    ? lhs.value.value > rhs.value.value
                    : lhs.key < rhs.key
            }
            .prefix(maxAllTimePRs)
            .map { "\($0.key) e1RM \(AnalyticsMath.formattedWeight($0.value.value)) (\(dayString($0.value.date, calendar: calendar)))" }
        lifetime.allTimePRs = prs.isEmpty ? nil : Array(prs)

        let pains = allStats
            .compactMap { entry -> String? in
                guard let checkIn = entry.session.checkIn, checkIn.hadPain else { return nil }
                let note = checkIn.painNote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let text = note.isEmpty ? "reported pain" : note
                return "\(dayString(entry.session.date, calendar: calendar)): \(text)"
            }
            .suffix(maxPainHistory)
            .reversed()
        lifetime.painHistory = pains.isEmpty ? nil : Array(pains)

        let limitations = preferences.limitations.trimmingCharacters(in: .whitespacesAndNewlines)
        lifetime.limitations = limitations.isEmpty ? nil : limitations

        lifetime.months = monthlySummaries(from: oldStats, calendar: calendar)

        return lifetime
    }

    private static func monthlySummaries(
        from stats: [SessionStats],
        calendar: Calendar
    ) -> [MonthlySummaryMemory]? {
        guard !stats.isEmpty else { return nil }

        var byMonth: [String: [SessionStats]] = [:]
        for entry in stats {
            byMonth[monthString(entry.session.date, calendar: calendar), default: []].append(entry)
        }

        var entries = byMonth.keys.sorted(by: >).map { month -> MonthlySummaryMemory in
            summaryEntry(label: month, entries: byMonth[month] ?? [])
        }

        // Months beyond the most recent `maxMonthlyEntries` collapse into year
        // rollups, so the digest stays bounded no matter how long the history is.
        if entries.count > maxMonthlyEntries {
            let overflow = entries[maxMonthlyEntries...]
            entries = Array(entries.prefix(maxMonthlyEntries))

            var byYear: [String: [MonthlySummaryMemory]] = [:]
            for entry in overflow {
                byYear[String(entry.month.prefix(4)), default: []].append(entry)
            }
            let yearEntries = byYear.keys.sorted(by: >).map { year -> MonthlySummaryMemory in
                let months = byYear[year] ?? []
                var rollup = MonthlySummaryMemory(
                    month: year,
                    sessions: months.map(\.sessions).reduce(0, +)
                )
                let volume = months.compactMap(\.volume).reduce(0, +)
                rollup.volume = volume > 0 ? volume : nil
                return rollup
            }
            entries.append(contentsOf: yearEntries)
        }

        return entries
    }

    private static func summaryEntry(label: String, entries: [SessionStats]) -> MonthlySummaryMemory {
        var summary = MonthlySummaryMemory(month: label, sessions: entries.count)
        let volume = entries.map(\.volume).reduce(0, +)
        summary.volume = volume > 0 ? Int(volume.rounded()) : nil
        summary.focus = focusGroups(entries.map(\.setsByGroup))
        return summary
    }

    // MARK: Size cap

    /// Trim the digest until its serialized form fits `maxEncodedBytes`.
    /// Deterministic: each pass drops the least valuable detail first; recent
    /// detail survives the longest, durable lifetime facts are never dropped.
    private static func capped(_ memory: UserMemory) -> UserMemory {
        var memory = memory

        func fits() -> Bool {
            (encoded(memory)?.count ?? 0) <= maxEncodedBytes
        }
        if fits() { return memory }

        // 1. Best-set lines shrink to 3 on all but the 6 newest sessions.
        if var recent = memory.recentSessions {
            for index in recent.indices where index >= 6 {
                recent[index].bestSets = recent[index].bestSets.map { Array($0.prefix(3)) }
            }
            memory.recentSessions = recent
            if fits() { return memory }
        }

        // 2. Weekly introduced/dropped detail goes.
        if var weeks = memory.weeklySummaries {
            for index in weeks.indices {
                weeks[index].introduced = nil
                weeks[index].dropped = nil
            }
            memory.weeklySummaries = weeks
            if fits() { return memory }
        }

        // 3. Monthly entries collapse harder: keep 12, roll the rest into years.
        if var lifetime = memory.lifetime, let months = lifetime.months {
            let monthly = months.filter { $0.month.count > 4 }
            if monthly.count > 12 {
                var byYear: [String: (sessions: Int, volume: Int)] = [:]
                for entry in monthly.dropFirst(12) + months.filter({ $0.month.count == 4 }) {
                    let year = String(entry.month.prefix(4))
                    var totals = byYear[year] ?? (0, 0)
                    totals.sessions += entry.sessions
                    totals.volume += entry.volume ?? 0
                    byYear[year] = totals
                }
                lifetime.months = Array(monthly.prefix(12)) + byYear.keys.sorted(by: >).map { year in
                    MonthlySummaryMemory(
                        month: year,
                        sessions: byYear[year]?.sessions ?? 0,
                        volume: (byYear[year]?.volume ?? 0) > 0 ? byYear[year]?.volume : nil
                    )
                }
                memory.lifetime = lifetime
                if fits() { return memory }
            }
        }

        // 4. Best-set lines drop entirely beyond the 6 newest sessions.
        if var recent = memory.recentSessions {
            for index in recent.indices where index >= 6 {
                recent[index].bestSets = nil
            }
            memory.recentSessions = recent
            if fits() { return memory }
        }

        // 5. Last resort: every best-set list goes; the tier structure survives.
        if var recent = memory.recentSessions {
            for index in recent.indices {
                recent[index].bestSets = nil
            }
            memory.recentSessions = recent
        }

        return memory
    }

    // MARK: Shared helpers

    private static func bestSet(in sets: [WorkoutSet]) -> WorkoutSet? {
        sets.max { setSortValue($0) < setSortValue($1) }
    }

    /// Ranking value for "best" set: e1RM when both fields parse, else weight,
    /// else reps (scaled far below any real weight).
    private static func setSortValue(_ set: WorkoutSet) -> Double {
        let weight = AnalyticsMath.parseWeight(set.weight)
        let reps = AnalyticsMath.parseReps(set.reps)
        if let weight, let reps {
            return AnalyticsMath.epleyOneRepMax(weight: weight, reps: reps)
        }
        if let weight { return weight }
        if let reps { return Double(reps) / 1000 }
        return 0
    }

    private static func bestSetLine(_ exercise: String, _ set: WorkoutSet) -> String {
        let weight = AnalyticsMath.parseWeight(set.weight)
        let reps = AnalyticsMath.parseReps(set.reps)

        if let weight, let reps {
            let e1RM = AnalyticsMath.epleyOneRepMax(weight: weight, reps: reps)
            return "\(exercise) \(AnalyticsMath.formattedWeight(weight))x\(reps) (e1RM \(AnalyticsMath.formattedWeight(e1RM)))"
        }
        if let weight {
            return "\(exercise) \(AnalyticsMath.formattedWeight(weight)) lb"
        }
        if let reps {
            return "\(exercise) x\(reps)"
        }
        return exercise
    }

    private static func focusGroups(_ groupCounts: [[MuscleGroup: Int]]) -> [String]? {
        var totals: [MuscleGroup: Int] = [:]
        for counts in groupCounts {
            for (group, count) in counts {
                totals[group, default: 0] += count
            }
        }
        guard !totals.isEmpty else { return nil }

        let ranked = totals
            .sorted { lhs, rhs in
                lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key.rawValue < rhs.key.rawValue
            }
            .prefix(maxFocusGroups)
            .map(\.key.rawValue)
        return Array(ranked)
    }

    private static func longestStreak(dates: [Date], calendar: Calendar) -> Int {
        var weekStarts = Set<Date>()
        for date in dates {
            if let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start {
                weekStarts.insert(start)
            }
        }
        guard !weekStarts.isEmpty else { return 0 }

        var longest = 0
        for start in weekStarts {
            // Only count from streak heads so the walk stays linear-ish.
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: start),
                  !weekStarts.contains(previous) else { continue }
            var length = 0
            var cursor: Date? = start
            while let week = cursor, weekStarts.contains(week) {
                length += 1
                cursor = calendar.date(byAdding: .weekOfYear, value: 1, to: week)
            }
            longest = max(longest, length)
        }
        return longest
    }

    private static func outcomeText(_ outcome: CheckInOutcome) -> String {
        outcome.label.lowercased()
    }

    private static func dayString(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static func monthString(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }
}

// MARK: - Store

/// Owns the persisted digest. Reads the SAME raw keys the rest of the app
/// writes (`"workoutSessions"` + preferences) strictly read-only — the digest
/// is a derived layer, never a second persistence path for raw data.
enum UserMemoryStore {

    static let storageKey = "userMemoryDigestV1"

    /// Maps logged exercise names to library exercises so the digest can name
    /// muscle-group focus. Installed once at the app root from the shared
    /// `ExerciseStore`; the default resolver simply omits group info.
    static var exerciseResolver: (String) -> Exercise? = { _ in nil }

    static func load(defaults: UserDefaults = .standard) -> UserMemory? {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(UserMemory.self, from: data) else {
            return nil
        }
        return decoded
    }

    static func save(_ memory: UserMemory, defaults: UserDefaults = .standard) {
        guard let encoded = UserMemoryBuilder.encoded(memory) else { return }
        defaults.set(encoded, forKey: storageKey)
    }

    static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storageKey)
    }

    /// Rebuild the digest from the raw stored data and persist it. Call after
    /// a session is saved or a check-in recorded. Cheap: the whole history is
    /// a pure date-bucketed pass.
    @discardableResult
    static func refresh(now: Date = Date(), defaults: UserDefaults = .standard) -> UserMemory {
        let memory = UserMemoryBuilder.build(
            sessions: rawSessions(defaults: defaults),
            preferences: AIUserPreferencesStore.load(),
            resolve: exerciseResolver,
            now: now
        )
        save(memory, defaults: defaults)
        return memory
    }

    /// Digest for an AI request. Returns the stored digest when fresh; rebuilds
    /// when it is missing, from an earlier day (tier boundaries move daily), or
    /// out of sync with the raw session count. nil when there is no history.
    static func current(now: Date = Date(), defaults: UserDefaults = .standard) -> UserMemory? {
        let sessionCount = rawSessions(defaults: defaults).count
        guard sessionCount > 0 else { return nil }

        if let stored = load(defaults: defaults),
           stored.sourceSessionCount == sessionCount,
           let generatedAt = stored.generatedAt,
           Calendar.current.isDate(generatedAt, inSameDayAs: now) {
            return stored
        }

        let rebuilt = refresh(now: now, defaults: defaults)
        return rebuilt.isEmpty ? nil : rebuilt
    }

    // Same legacy key `WorkoutStore` reads/writes; a literal here keeps this
    // callable off the main actor without touching the @MainActor store type.
    private static let rawSessionsKey = "workoutSessions"

    private static func rawSessions(defaults: UserDefaults) -> [WorkoutSession] {
        guard let data = defaults.data(forKey: rawSessionsKey),
              let decoded = try? JSONDecoder().decode([WorkoutSession].self, from: data) else {
            return []
        }
        return decoded
    }
}
