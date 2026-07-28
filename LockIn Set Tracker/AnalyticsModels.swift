import Foundation

// MARK: - Parsing & strength math
//
// Weights and reps are stored as free-text Strings. Everything here parses
// defensively: empty, non-numeric, "bodyweight" etc. simply yield nil and the
// set is skipped for that metric (it can still count as activity elsewhere).

enum AnalyticsMath {

    /// First numeric token in a free-text weight ("135", "135.5 lbs", "bw" -> nil).
    static func parseWeight(_ raw: String) -> Double? {
        guard let value = firstNumber(in: raw), value > 0 else { return nil }
        return value
    }

    /// First integer in a free-text rep count ("8", "8-10" -> 8, "" -> nil).
    static func parseReps(_ raw: String) -> Int? {
        guard let value = firstNumber(in: raw) else { return nil }
        let reps = Int(value)
        return reps > 0 ? reps : nil
    }

    /// Epley estimated 1RM: weight x (1 + reps/30).
    /// Reps are capped at 12 — the formula loses meaning for high-rep sets.
    static func epleyOneRepMax(weight: Double, reps: Int) -> Double {
        guard reps > 1 else { return weight }
        return weight * (1.0 + Double(min(reps, 12)) / 30.0)
    }

    /// A set that carries any usable signal (weight or reps parse).
    /// Placeholder rows saved with both fields empty do not count as activity.
    static func isMeaningfulSet(_ set: WorkoutSet) -> Bool {
        parseWeight(set.weight) != nil || parseReps(set.reps) != nil
    }

    /// Tonnage for one set, when both fields parse.
    static func setVolume(_ set: WorkoutSet) -> Double? {
        guard let weight = parseWeight(set.weight), let reps = parseReps(set.reps) else { return nil }
        return weight * Double(reps)
    }

    /// Compact "sets × reps · weight" line for a day-summary row.
    /// "3 × 8–10 · 145 lb", "3 × 12" (bodyweight), "2 sets · 145 lb" (no reps).
    static func setSummary(for sets: [WorkoutSet]) -> String {
        let meaningful = sets.filter(isMeaningfulSet)
        guard !meaningful.isEmpty else { return "Logged" }

        let reps = meaningful.compactMap { parseReps($0.reps) }
        let topWeight = meaningful.compactMap { parseWeight($0.weight) }.max()

        var parts: [String] = []
        if let low = reps.min(), let high = reps.max() {
            let range = low == high ? "\(low)" : "\(low)–\(high)"
            parts.append("\(meaningful.count) × \(range)")
        } else {
            parts.append("\(meaningful.count) set\(meaningful.count == 1 ? "" : "s")")
        }
        if let topWeight {
            parts.append("\(formattedWeight(topWeight)) lb")
        }
        return parts.joined(separator: " · ")
    }

    static func formattedWeight(_ weight: Double) -> String {
        weight == weight.rounded()
            ? "\(Int(weight))"
            : String(format: "%.1f", weight)
    }

    private static func firstNumber(in raw: String) -> Double? {
        let scanner = Scanner(string: raw)
        scanner.charactersToBeSkipped = CharacterSet(charactersIn: "0123456789.").inverted
        guard let value = scanner.scanDouble(), value.isFinite else { return nil }
        return value
    }
}

// MARK: - Rep zones

enum RepZone: String, CaseIterable, Identifiable {
    case strength
    case hypertrophy
    case endurance

    var id: String { rawValue }

    var label: String {
        switch self {
        case .strength: return "Strength"
        case .hypertrophy: return "Hypertrophy"
        case .endurance: return "Endurance"
        }
    }

    var rangeText: String {
        switch self {
        case .strength: return "1–5"
        case .hypertrophy: return "6–12"
        case .endurance: return "13+"
        }
    }

    static func zone(forReps reps: Int) -> RepZone {
        switch reps {
        case ..<6: return .strength
        case 6...12: return .hypertrophy
        default: return .endurance
        }
    }
}

// MARK: - Progression metric & timeframe

enum ProgressionMetric: String, CaseIterable, Identifiable {
    case estOneRepMax
    case volume
    case maxWeight

    var id: String { rawValue }

    var label: String {
        switch self {
        case .estOneRepMax: return "Est 1RM"
        case .volume: return "Volume"
        case .maxWeight: return "Max Weight"
        }
    }

    var shortLabel: String {
        switch self {
        case .estOneRepMax: return "EST 1RM"
        case .volume: return "VOLUME"
        case .maxWeight: return "MAX WT"
        }
    }
}

enum AnalyticsTimeframe: String, CaseIterable, Identifiable {
    case threeMonths = "3M"
    case sixMonths = "6M"
    case oneYear = "1Y"
    case all = "ALL"

    var id: String { rawValue }

    var months: Int? {
        switch self {
        case .threeMonths: return 3
        case .sixMonths: return 6
        case .oneYear: return 12
        case .all: return nil
        }
    }

    func startDate(now: Date, calendar: Calendar) -> Date? {
        guard let months else { return nil }
        return calendar.date(byAdding: .month, value: -months, to: now)
    }
}

// MARK: - Snapshot

/// All derived analytics, computed once per data change (never per chart mark).
struct AnalyticsSnapshot {

    // MARK: Headline

    struct Headline {
        var thisWeekSessions: Int
        var thisWeekVolume: Double
        /// Mean weekly tonnage over up to 8 prior weeks (nil until a prior week exists).
        var weeklyAverageVolume: Double?
        var volumeDeltaPercent: Double?
        var streakWeeks: Int
        /// False for all-bodyweight histories, where tonnage is meaningless.
        var volumeIsMeaningful: Bool
        var thisWeekSets: Int
    }

    // MARK: Exercise progression (chart 1)

    struct ExerciseOption: Identifiable {
        var id: String { name }
        /// Canonical (library-resolved) exercise name.
        var name: String
        /// Number of sessions with usable data for this exercise.
        var sessionCount: Int
    }

    struct ProgressionPoint: Identifiable {
        var id: Date { date }
        var date: Date
        /// Best Epley e1RM across the session's sets (needs weight + reps).
        var e1RM: Double?
        /// Session tonnage for this exercise (sum of weight × reps).
        var volume: Double?
        /// Heaviest successfully loaded single set (needs weight).
        var maxWeight: Double?

        func value(for metric: ProgressionMetric) -> Double? {
            switch metric {
            case .estOneRepMax: return e1RM
            case .volume: return volume
            case .maxWeight: return maxWeight
            }
        }
    }

    // MARK: Weekly sets per muscle (chart 2)

    struct WeekPoint: Identifiable {
        var id: Date { weekStart }
        var weekStart: Date
        var sets: Int
    }

    struct MuscleSeries: Identifiable {
        var id: String { group }
        /// Display muscle group ("Chest", ..., "Other").
        var group: String
        /// Zero-filled weekly set counts, oldest first, through the current week.
        var points: [WeekPoint]
        var totalSets: Int
    }

    // MARK: Muscle distribution donut (chart 3)

    struct DonutSegment: Identifiable {
        var id: String { group }
        var group: String
        var sets: Int
        /// 0...1 share of all sets in the window.
        var share: Double
    }

    struct DonutModel {
        /// Ranked by sets desc, "Other" always last. At most 6 segments.
        var segments: [DonutSegment]
        var totalSets: Int
    }

    // MARK: Training calendar (chart 4)

    struct CalendarDayCell: Identifiable {
        var id: Date { date }
        var date: Date
        var day: Int
        var sessionCount: Int
        var isToday: Bool
        var isFuture: Bool
    }

    struct CalendarMonth {
        var monthStart: Date
        /// Empty grid slots before day 1 (calendar column alignment).
        var leadingBlanks: Int
        var days: [CalendarDayCell]
    }

    // MARK: Rep distribution

    struct RepBin: Identifiable {
        var id: Int { reps }
        /// 1...20 where 20 means "20+".
        var reps: Int
        var count: Int
        var zone: RepZone
    }

    // MARK: Stored results

    var totalSessions: Int
    var headline: Headline?
    /// Sorted by session count desc — first entry is the default picker selection.
    var exerciseOptions: [ExerciseOption]
    /// Canonical exercise name -> per-session progression points, oldest first.
    var progression: [String: [ProgressionPoint]]
    var weeklyMuscle: [MuscleSeries]
    var donut: DonutModel?
    var donutInsight: String?
    /// Start-of-day -> that day's sessions (for the calendar + day sheet).
    var sessionsByDay: [Date: [WorkoutSession]]
    var firstSessionDate: Date?
    var repBins: [RepBin]
    var repZoneShares: [RepZone: Double]
    var repWindowIsRecent: Bool
    var repInsight: String?

    static let empty = AnalyticsSnapshot(
        totalSessions: 0,
        headline: nil,
        exerciseOptions: [],
        progression: [:],
        weeklyMuscle: [],
        donut: nil,
        donutInsight: nil,
        sessionsByDay: [:],
        firstSessionDate: nil,
        repBins: [],
        repZoneShares: [:],
        repWindowIsRecent: false,
        repInsight: nil
    )

    // MARK: - Build

    /// Weeks of history shown by the weekly-sets chart (including the current week).
    static let weeklyMuscleWeekCount = 13
    /// Days covered by the muscle-distribution donut.
    static let donutWindowDays = 30

    /// The six groups that get their own series color; everything else folds
    /// into "Other" so the palette never has to invent a seventh hue.
    static let chartMuscleGroups: [MuscleGroup] = [.chest, .back, .shoulders, .arms, .legs, .core]

    static func chartGroup(for group: MuscleGroup?) -> String {
        guard let group, chartMuscleGroups.contains(group) else {
            return MuscleGroup.other.rawValue
        }
        return group.rawValue
    }

    /// Pure builder — inject the exercise resolver so the math stays testable.
    /// `resolve` maps a logged (possibly abbreviated) name to a library exercise.
    static func build(
        sessions: [WorkoutSession],
        resolve: (String) -> Exercise?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> AnalyticsSnapshot {
        let sorted = sessions.sorted { $0.date < $1.date }
        guard !sorted.isEmpty,
              let currentWeek = calendar.dateInterval(of: .weekOfYear, for: now) else {
            return .empty
        }

        // Resolve each distinct logged name once.
        var resolutionCache: [String: Exercise?] = [:]
        func resolved(_ name: String) -> Exercise? {
            if let cached = resolutionCache[name] { return cached }
            let match = resolve(name)
            resolutionCache[name] = match
            return match
        }

        let headline = buildHeadline(sorted: sorted, currentWeek: currentWeek, calendar: calendar)
        let (options, progression) = buildProgression(sorted: sorted, resolved: resolved)
        let weeklyMuscle = buildWeeklyMuscle(
            sorted: sorted,
            resolved: resolved,
            currentWeek: currentWeek,
            calendar: calendar
        )
        let (donut, donutInsight) = buildDonut(sorted: sorted, resolved: resolved, now: now)
        let (repBins, zoneShares, repRecent, repInsight) = buildRepDistribution(sorted: sorted, now: now)

        var sessionsByDay: [Date: [WorkoutSession]] = [:]
        for session in sorted {
            sessionsByDay[calendar.startOfDay(for: session.date), default: []].append(session)
        }

        return AnalyticsSnapshot(
            totalSessions: sorted.count,
            headline: headline,
            exerciseOptions: options,
            progression: progression,
            weeklyMuscle: weeklyMuscle,
            donut: donut,
            donutInsight: donutInsight,
            sessionsByDay: sessionsByDay,
            firstSessionDate: sorted.first?.date,
            repBins: repBins,
            repZoneShares: zoneShares,
            repWindowIsRecent: repRecent,
            repInsight: repInsight
        )
    }

    // MARK: Headline

    private static func buildHeadline(
        sorted: [WorkoutSession],
        currentWeek: DateInterval,
        calendar: Calendar
    ) -> Headline {
        func sessionVolume(_ session: WorkoutSession) -> Double {
            session.logs.values
                .flatMap { $0 }
                .compactMap(AnalyticsMath.setVolume)
                .reduce(0, +)
        }

        func sessionSets(_ session: WorkoutSession) -> Int {
            session.logs.values
                .flatMap { $0 }
                .filter(AnalyticsMath.isMeaningfulSet)
                .count
        }

        let thisWeek = sorted.filter { currentWeek.contains($0.date) }
        let thisWeekVolume = thisWeek.map(sessionVolume).reduce(0, +)
        let thisWeekSets = thisWeek.map(sessionSets).reduce(0, +)

        // Average weekly tonnage over up to 8 full prior weeks (bounded by history).
        var weeklyAverage: Double?
        if let windowStart = calendar.date(byAdding: .weekOfYear, value: -8, to: currentWeek.start),
           let firstWeekStart = calendar.dateInterval(of: .weekOfYear, for: sorted[0].date)?.start {
            let effectiveStart = max(windowStart, firstWeekStart)
            if effectiveStart < currentWeek.start {
                let weeks = calendar.dateComponents([.weekOfYear], from: effectiveStart, to: currentWeek.start).weekOfYear ?? 0
                let priorVolume = sorted
                    .filter { $0.date >= effectiveStart && $0.date < currentWeek.start }
                    .map(sessionVolume)
                    .reduce(0, +)
                if weeks > 0 {
                    weeklyAverage = priorVolume / Double(weeks)
                }
            }
        }

        var deltaPercent: Double?
        if let average = weeklyAverage, average > 0 {
            deltaPercent = (thisWeekVolume - average) / average * 100
        }

        // Consecutive weeks with at least one session. A quiet current week does
        // not break the streak (the week is not over yet).
        var weekStarts = Set<Date>()
        for session in sorted {
            if let start = calendar.dateInterval(of: .weekOfYear, for: session.date)?.start {
                weekStarts.insert(start)
            }
        }
        var streak = 0
        var cursor: Date? = weekStarts.contains(currentWeek.start)
            ? currentWeek.start
            : calendar.date(byAdding: .weekOfYear, value: -1, to: currentWeek.start)
        while let week = cursor, weekStarts.contains(week) {
            streak += 1
            cursor = calendar.date(byAdding: .weekOfYear, value: -1, to: week)
        }

        let anyVolume = thisWeekVolume > 0 || (weeklyAverage ?? 0) > 0

        return Headline(
            thisWeekSessions: thisWeek.count,
            thisWeekVolume: thisWeekVolume,
            weeklyAverageVolume: weeklyAverage,
            volumeDeltaPercent: deltaPercent,
            streakWeeks: streak,
            volumeIsMeaningful: anyVolume,
            thisWeekSets: thisWeekSets
        )
    }

    // MARK: Exercise progression

    private static func buildProgression(
        sorted: [WorkoutSession],
        resolved: (String) -> Exercise?
    ) -> ([ExerciseOption], [String: [ProgressionPoint]]) {
        var series: [String: [ProgressionPoint]] = [:]

        for session in sorted {
            // Merge aliases that resolve to the same library exercise within a
            // session ("DB Bench" + "Dumbbell Bench Press" -> one point).
            var perExercise: [String: [WorkoutSet]] = [:]
            for (name, sets) in session.logs {
                let canonical = resolved(name)?.name ?? name
                perExercise[canonical, default: []].append(contentsOf: sets)
            }

            for (canonical, sets) in perExercise {
                let e1RM = sets.compactMap { set -> Double? in
                    guard let weight = AnalyticsMath.parseWeight(set.weight),
                          let reps = AnalyticsMath.parseReps(set.reps) else { return nil }
                    return AnalyticsMath.epleyOneRepMax(weight: weight, reps: reps)
                }.max()

                let volumes = sets.compactMap(AnalyticsMath.setVolume)
                let volume = volumes.isEmpty ? nil : volumes.reduce(0, +)
                let maxWeight = sets.compactMap { AnalyticsMath.parseWeight($0.weight) }.max()

                guard e1RM != nil || volume != nil || maxWeight != nil else { continue }
                series[canonical, default: []].append(ProgressionPoint(
                    date: session.date,
                    e1RM: e1RM,
                    volume: volume,
                    maxWeight: maxWeight
                ))
            }
        }

        let options = series
            .map { ExerciseOption(name: $0.key, sessionCount: $0.value.count) }
            .sorted { lhs, rhs in
                if lhs.sessionCount != rhs.sessionCount { return lhs.sessionCount > rhs.sessionCount }
                return lhs.name < rhs.name
            }

        return (options, series)
    }

    // MARK: Weekly sets per muscle

    private static func buildWeeklyMuscle(
        sorted: [WorkoutSession],
        resolved: (String) -> Exercise?,
        currentWeek: DateInterval,
        calendar: Calendar
    ) -> [MuscleSeries] {
        guard let windowStart = calendar.date(
            byAdding: .weekOfYear,
            value: -(weeklyMuscleWeekCount - 1),
            to: currentWeek.start
        ) else { return [] }

        // group -> weekStart -> sets
        var counts: [String: [Date: Int]] = [:]
        var earliestWeek: Date?
        for session in sorted where session.date >= windowStart {
            guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: session.date)?.start else { continue }
            earliestWeek = min(earliestWeek ?? weekStart, weekStart)
            for (name, sets) in session.logs {
                let meaningful = sets.filter(AnalyticsMath.isMeaningfulSet).count
                guard meaningful > 0 else { continue }
                let group = chartGroup(for: resolved(name)?.muscleGroup)
                counts[group, default: [:]][weekStart, default: 0] += meaningful
            }
        }

        guard let earliestWeek, !counts.isEmpty else { return [] }

        // Zero-filled week axis from the first trained week through the current one.
        var weekAxis: [Date] = []
        var cursor = earliestWeek
        while cursor <= currentWeek.start {
            weekAxis.append(cursor)
            guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: cursor) else { break }
            cursor = next
        }

        let order = chartMuscleGroups.map(\.rawValue) + [MuscleGroup.other.rawValue]
        return order.compactMap { group in
            guard let weekCounts = counts[group] else { return nil }
            let points = weekAxis.map { WeekPoint(weekStart: $0, sets: weekCounts[$0] ?? 0) }
            let total = weekCounts.values.reduce(0, +)
            guard total > 0 else { return nil }
            return MuscleSeries(group: group, points: points, totalSets: total)
        }
    }

    // MARK: Muscle distribution donut

    private static func buildDonut(
        sorted: [WorkoutSession],
        resolved: (String) -> Exercise?,
        now: Date
    ) -> (DonutModel?, String?) {
        let windowStart = now.addingTimeInterval(-Double(donutWindowDays) * 86_400)

        var counts: [String: Int] = [:]
        for session in sorted where session.date >= windowStart && session.date <= now {
            for (name, sets) in session.logs {
                let meaningful = sets.filter(AnalyticsMath.isMeaningfulSet).count
                guard meaningful > 0 else { continue }
                let group = chartGroup(for: resolved(name)?.muscleGroup)
                counts[group, default: 0] += meaningful
            }
        }

        let total = counts.values.reduce(0, +)
        guard total > 0 else { return (nil, nil) }

        let otherName = MuscleGroup.other.rawValue
        var ranked = counts
            .map { (group: $0.key, sets: $0.value) }
            .sorted { lhs, rhs in
                if lhs.sets != rhs.sets { return lhs.sets > rhs.sets }
                return lhs.group < rhs.group
            }

        // Fold tiny groups (<3%) and anything past the 5 biggest into "Other" so
        // the ring never carries more than 6 segments.
        var otherSets = 0
        if let otherIndex = ranked.firstIndex(where: { $0.group == otherName }) {
            otherSets = ranked.remove(at: otherIndex).sets
        }
        var kept: [(group: String, sets: Int)] = []
        for entry in ranked {
            let share = Double(entry.sets) / Double(total)
            if kept.count >= 5 || share < 0.03 {
                otherSets += entry.sets
            } else {
                kept.append(entry)
            }
        }
        if otherSets > 0 {
            kept.append((otherName, otherSets))
        }

        let segments = kept.map { entry in
            DonutSegment(group: entry.group, sets: entry.sets, share: Double(entry.sets) / Double(total))
        }

        // One line: name the biggest imbalance across the core groups.
        var insight: String?
        if total >= 15 {
            let shareByGroup = Dictionary(uniqueKeysWithValues: segments.map { ($0.group, $0.share) })
            if let weakest = chartMuscleGroups
                .map({ (group: $0.rawValue, share: shareByGroup[$0.rawValue] ?? 0) })
                .min(by: { $0.share < $1.share }) {
                if weakest.share < 0.08 {
                    let pct = Int((weakest.share * 100).rounded())
                    insight = pct == 0
                        ? "\(weakest.group) hasn't been trained in the last \(donutWindowDays) days"
                        : "\(weakest.group) is getting just \(pct)% of your sets"
                } else {
                    insight = "Volume is spread evenly — no muscle group is falling behind"
                }
            }
        }

        return (DonutModel(segments: segments, totalSets: total), insight)
    }

    // MARK: Training calendar

    /// Month grid for the calendar card. `sessionsByDay` is keyed by start-of-day.
    static func calendarMonth(
        containing anchor: Date,
        sessionsByDay: [Date: [WorkoutSession]],
        now: Date,
        calendar: Calendar
    ) -> CalendarMonth {
        guard let monthInterval = calendar.dateInterval(of: .month, for: anchor),
              let dayRange = calendar.range(of: .day, in: .month, for: anchor) else {
            return CalendarMonth(monthStart: anchor, leadingBlanks: 0, days: [])
        }

        let monthStart = monthInterval.start
        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let leadingBlanks = (firstWeekday - calendar.firstWeekday + 7) % 7
        let today = calendar.startOfDay(for: now)

        var days: [CalendarDayCell] = []
        for day in dayRange {
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) else { continue }
            let dayStart = calendar.startOfDay(for: date)
            days.append(CalendarDayCell(
                date: dayStart,
                day: day,
                sessionCount: sessionsByDay[dayStart]?.count ?? 0,
                isToday: dayStart == today,
                isFuture: dayStart > today
            ))
        }

        return CalendarMonth(monthStart: monthStart, leadingBlanks: leadingBlanks, days: days)
    }

    /// Weekday header labels in calendar column order (respects firstWeekday).
    static func weekdayHeaderLabels(calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return (0..<7).map { symbols[(first + $0) % 7] }
    }

    // MARK: Rep distribution

    private static func buildRepDistribution(
        sorted: [WorkoutSession],
        now: Date
    ) -> ([RepBin], [RepZone: Double], Bool, String?) {
        let day: TimeInterval = 86_400

        func repCounts(from start: Date) -> [Int] {
            sorted
                .filter { $0.date >= start }
                .flatMap { $0.logs.values }
                .flatMap { $0 }
                .compactMap { AnalyticsMath.parseReps($0.reps) }
        }

        var reps = repCounts(from: now.addingTimeInterval(-60 * day))
        var isRecent = true
        if reps.count < 20 {
            reps = repCounts(from: .distantPast)
            isRecent = false
        }
        guard !reps.isEmpty else { return ([], [:], isRecent, nil) }

        var counts: [Int: Int] = [:]
        var zoneCounts: [RepZone: Int] = [:]
        for value in reps {
            counts[min(value, 20), default: 0] += 1
            zoneCounts[RepZone.zone(forReps: value), default: 0] += 1
        }

        let bins = (1...20).map { rep in
            RepBin(reps: rep, count: counts[rep] ?? 0, zone: RepZone.zone(forReps: rep))
        }

        let total = Double(reps.count)
        var zoneShares: [RepZone: Double] = [:]
        for zone in RepZone.allCases {
            zoneShares[zone] = Double(zoneCounts[zone] ?? 0) / total
        }

        var insight: String?
        if let dominant = zoneShares.max(by: { $0.value < $1.value }), dominant.value > 0 {
            let pct = Int((dominant.value * 100).rounded())
            switch dominant.key {
            case .strength:
                insight = "\(pct)% of your sets are heavy 1–5s — you're training for strength"
            case .hypertrophy:
                insight = "\(pct)% of your sets land in 6–12 — squarely building muscle"
            case .endurance:
                insight = "\(pct)% of your sets are 13+ reps — mostly endurance work"
            }
        }

        return (bins, zoneShares, isRecent, insight)
    }
}
