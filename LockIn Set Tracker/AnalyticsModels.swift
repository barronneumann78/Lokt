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
    /// Purely about the numbers — completion is `isCountedSet`'s job.
    static func isMeaningfulSet(_ set: WorkoutSet) -> Bool {
        parseWeight(set.weight) != nil || parseReps(set.reps) != nil
    }

    /// A set that actually happened for counting purposes: checked off in the
    /// logger (legacy nil flag counts) AND carrying parseable numbers.
    static func isCountedSet(_ set: WorkoutSet) -> Bool {
        set.isCompleted && isMeaningfulSet(set)
    }

    /// Tonnage for one set, when the set is completed and both fields parse.
    static func setVolume(_ set: WorkoutSet) -> Double? {
        guard set.isCompleted,
              let weight = parseWeight(set.weight), let reps = parseReps(set.reps) else { return nil }
        return weight * Double(reps)
    }

    /// Best Epley e1RM across a group of sets — completed sets where both
    /// weight and reps parse. The shared "best lift" ranking the strength
    /// chart, the PR digest and the day scorecard all agree on.
    static func bestE1RM(in sets: [WorkoutSet]) -> Double? {
        sets.compactMap { set -> Double? in
            guard set.isCompleted,
                  let weight = parseWeight(set.weight),
                  let reps = parseReps(set.reps) else { return nil }
            return epleyOneRepMax(weight: weight, reps: reps)
        }.max()
    }

    /// Compact "sets × reps · weight" line for a day-summary row.
    /// "3 × 8–10 · 145 lb", "3 × 12" (bodyweight), "2 sets · 145 lb" (no reps).
    static func setSummary(for sets: [WorkoutSet]) -> String {
        let meaningful = sets.filter(isCountedSet)
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

    /// k/M-abbreviated tonnage for the distribution stat tiles ("489k", "1.2M").
    static func compactVolume(_ value: Double) -> String {
        if value >= 10_000_000 {
            return String(format: "%.0fM", value / 1_000_000)
        }
        if value >= 1_000_000 {
            let compact = value / 1_000_000
            return compact == compact.rounded()
                ? String(format: "%.0fM", compact)
                : String(format: "%.1fM", compact)
        }
        if value >= 100_000 {
            return String(format: "%.0fk", value / 1000)
        }
        if value >= 10_000 {
            return String(format: "%.1fk", value / 1000)
        }
        return value.formatted(.number.precision(.fractionLength(0)))
    }

    /// "20h 46min" / "46min", rounded to whole minutes.
    static func durationText(seconds: Int) -> String {
        let totalMinutes = Int((Double(max(0, seconds)) / 60).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)h \(minutes)min" : "\(minutes)min"
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

// MARK: - Progression metric & window

/// What the progression line plots. Raw values are persisted (`@AppStorage`)
/// — keep them stable; the case order is the metric switch's order.
enum ProgressionMetric: String, CaseIterable, Identifiable {
    case estOneRepMax
    case maxWeight
    case volume

    var id: String { rawValue }

    var label: String {
        switch self {
        case .estOneRepMax: return "e1RM"
        case .maxWeight: return "Top set"
        case .volume: return "Volume"
        }
    }
}

/// Rolling window behind every Analytics control: the last `days` LOCAL
/// calendar days, today included (`.thirtyDays` on a Wednesday = 29 days ago
/// through today — the same rule as Home's SESSIONS · 7D), or everything.
/// Raw values are persisted (`@AppStorage`) — keep them stable.
enum AnalyticsWindow: String, CaseIterable, Identifiable {
    case sevenDays
    case thirtyDays
    case ninetyDays
    case all

    var id: String { rawValue }

    var days: Int? {
        switch self {
        case .sevenDays: return 7
        case .thirtyDays: return 30
        case .ninetyDays: return 90
        case .all: return nil
        }
    }

    /// Control text: "7d" … "All".
    var label: String {
        switch self {
        case .sevenDays: return "7d"
        case .thirtyDays: return "30d"
        case .ninetyDays: return "90d"
        case .all: return "All"
        }
    }

    /// Micro-label suffix: "SETS · 30D", "SETS · ALL".
    var suffix: String {
        switch self {
        case .sevenDays: return "7D"
        case .thirtyDays: return "30D"
        case .ninetyDays: return "90D"
        case .all: return "ALL"
        }
    }

    /// Start of the window — the start of the local day `days - 1` days
    /// before `now`'s day; nil means unbounded.
    func start(now: Date, calendar: Calendar) -> Date? {
        guard let days else { return nil }
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -(days - 1), to: today)
    }

    /// End of a bounded window: the start of tomorrow, so all of today counts.
    func end(now: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: 1, to: today) ?? now
    }

    /// Half-open membership for bounded windows; "All" takes everything.
    func contains(_ date: Date, now: Date, calendar: Calendar) -> Bool {
        guard let start = start(now: now, calendar: calendar) else { return true }
        return date >= start && date < end(now: now, calendar: calendar)
    }

    /// The windows each control offers.
    static let progression: [AnalyticsWindow] = allCases
    static let muscle: [AnalyticsWindow] = [.thirtyDays, .ninetyDays, .all]
    static let prs: [AnalyticsWindow] = [.thirtyDays, .ninetyDays, .all]
}

/// Persisted control state for the Analytics cards — `@AppStorage` keys and
/// their defaults, in one place so `harness/logic-checks/analytics-controls`
/// can pin them. Each card owns its own window; the progression exercise is
/// shared with the PR board's tap-to-drill-down.
enum AnalyticsControls {
    static let progressionExerciseKey = "analyticsProgressionExercise"
    static let progressionMetricKey = "analyticsProgressionMetric"
    static let progressionWindowKey = "analyticsProgressionWindow"
    static let prWindowKey = "analyticsPRWindow"
    static let splitWindowKey = "analyticsSplitWindow"
    static let distributionWindowKey = "analyticsDistributionWindow"

    static let defaultMetric: ProgressionMetric = .estOneRepMax
    static let defaultProgressionWindow: AnalyticsWindow = .ninetyDays
    static let defaultPRWindow: AnalyticsWindow = .thirtyDays
    static let defaultSplitWindow: AnalyticsWindow = .thirtyDays
    static let defaultDistributionWindow: AnalyticsWindow = .thirtyDays
}

// MARK: - Snapshot

/// All derived analytics, computed once per data change (never per chart mark).
struct AnalyticsSnapshot {

    // MARK: Headline

    /// The headline tiles. Rolling local-day windows (`AnalyticsWindow`),
    /// completed sets only.
    struct Headline {
        /// Tonnage over the last 7 days, today included.
        var volumeLast7Days: Double
        /// Checked-off sets with usable numbers over the last 30 days.
        var setsLast30Days: Int
    }

    // MARK: Exercise progression (chart 1)

    struct ExerciseOption: Identifiable {
        var id: String { name }
        /// Canonical (library-resolved) exercise name.
        var name: String
        /// Number of sessions with usable data for this exercise.
        var sessionCount: Int
        /// Sessions with an e1RM (weight AND reps) — the picker's currency.
        var e1RMCount: Int
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

    /// One plotted point of the progression line, for the chosen metric.
    struct MetricPoint: Identifiable, Equatable {
        var id: Date { date }
        var date: Date
        var value: Double
    }

    // MARK: Muscle distribution radar (chart 2)

    struct MuscleDistribution {
        struct Axis: Identifiable {
            var id: String { group }
            /// Display muscle group ("Chest" ... "Back") — the six named groups only.
            var group: String
            var currentSets: Int
            var previousSets: Int
        }

        /// Fixed radar order, clockwise from top-right:
        /// Chest, Core, Shoulders, Arms, Legs, Back.
        var axes: [Axis]
        /// Max set count on any axis across BOTH periods — the shared
        /// normalization ceiling, so the two polygons are directly comparable.
        var maxAxisSets: Int

        var currentWorkouts: Int
        var previousWorkouts: Int
        var currentSets: Int
        var previousSets: Int
        var currentVolume: Double
        var previousVolume: Double
        /// Summed over sessions that recorded a duration; nil when none did.
        var currentDurationSeconds: Int?
        var previousDurationSeconds: Int?
        /// False for the "All" window — there is no equal-length window
        /// before everything, so the previous polygon and deltas are hidden.
        var hasPrevious: Bool

        /// 0...1 polygon radii in axis order; zero-set axes sit at center.
        var currentFractions: [Double] {
            axes.map { maxAxisSets > 0 ? Double($0.currentSets) / Double(maxAxisSets) : 0 }
        }

        var previousFractions: [Double] {
            axes.map { maxAxisSets > 0 ? Double($0.previousSets) / Double(maxAxisSets) : 0 }
        }

        /// Radar needs at least two current-window groups to draw a real shape.
        var currentGroupCount: Int {
            axes.filter { $0.currentSets > 0 }.count
        }
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

    // MARK: PR board

    /// An exercise's standing e1RM record: the all-time best, the local day
    /// it was FIRST reached (a later tie keeps the original day) and the
    /// best that stood before that day — nil when the record is the
    /// exercise's first-ever e1RM (nothing to beat, so not a PR: the same
    /// seeding rule as the day scorecard and Home's PRs · 30D).
    struct PRRecord: Identifiable {
        var id: String { exercise }
        /// Canonical (library-resolved) exercise name.
        var exercise: String
        var e1RM: Double
        var day: Date
        var previousBest: Double?

        /// Gain over the previous record; nil for a first-ever record.
        var delta: Double? { previousBest.map { e1RM - $0 } }
        /// A record that beat an earlier one — what the PRs tile counts.
        var isPR: Bool { previousBest != nil }
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
    /// Every exercise with a plotted point, sorted by session count desc.
    /// The picker shows the `progressionPickerOptions` subset.
    var exerciseOptions: [ExerciseOption]
    /// Canonical exercise name -> per-session progression points, oldest first.
    var progression: [String: [ProgressionPoint]]
    /// Muscle-split donut per window (`AnalyticsWindow.muscle`); a window
    /// with no counted sets has no entry.
    var donuts: [AnalyticsWindow: DonutModel]
    /// Radar + stat tiles per window (`AnalyticsWindow.muscle`).
    var distributions: [AnalyticsWindow: MuscleDistribution]
    /// Standing e1RM records, most recent first — see `PRRecord`.
    var prRecords: [PRRecord]
    /// Start-of-day -> that day's sessions (for the calendar + day sheet).
    var sessionsByDay: [Date: [WorkoutSession]]
    var firstSessionDate: Date?
    var repBins: [RepBin]
    var repZoneShares: [RepZone: Double]
    var repWindowIsRecent: Bool
    var repInsight: String?
    /// Advanced: per-exercise position-in-session profiles, most-trained
    /// first. Empty until an exercise has enough positioned history.
    var exerciseOrderProfiles: [ExercisePositionLogic.ExerciseProfile]

    /// Exercises the progression picker offers: at least this many e1RM
    /// points (one point is a dot, not a line), most-trained first.
    static let pickerMinimumPoints = 2

    var progressionPickerOptions: [ExerciseOption] {
        exerciseOptions.filter { $0.e1RMCount >= Self.pickerMinimumPoints }
    }

    static let empty = AnalyticsSnapshot(
        totalSessions: 0,
        headline: nil,
        exerciseOptions: [],
        progression: [:],
        donuts: [:],
        distributions: [:],
        prRecords: [],
        sessionsByDay: [:],
        firstSessionDate: nil,
        repBins: [],
        repZoneShares: [:],
        repWindowIsRecent: false,
        repInsight: nil,
        exerciseOrderProfiles: []
    )

    // MARK: - Build

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
    /// `routineOrders` (routine id → current exercise order) is the position
    /// fallback for sessions saved before `WorkoutSession.exerciseOrder`.
    static func build(
        sessions: [WorkoutSession],
        resolve: (String) -> Exercise?,
        routineOrders: [UUID: [String]] = [:],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> AnalyticsSnapshot {
        let sorted = sessions.sorted { $0.date < $1.date }
        guard !sorted.isEmpty else { return .empty }

        // Resolve each distinct logged name once.
        var resolutionCache: [String: Exercise?] = [:]
        func resolved(_ name: String) -> Exercise? {
            if let cached = resolutionCache[name] { return cached }
            let match = resolve(name)
            resolutionCache[name] = match
            return match
        }

        let headline = buildHeadline(sorted: sorted, now: now, calendar: calendar)
        let (options, progression) = buildProgression(sorted: sorted, resolved: resolved)
        var donuts: [AnalyticsWindow: DonutModel] = [:]
        var distributions: [AnalyticsWindow: MuscleDistribution] = [:]
        for window in AnalyticsWindow.muscle {
            donuts[window] = buildDonut(sorted: sorted, resolved: resolved, window: window, now: now, calendar: calendar)
            distributions[window] = muscleDistribution(
                sessions: sorted, resolve: resolved, window: window, now: now, calendar: calendar
            )
        }
        let (repBins, zoneShares, repRecent, repInsight) = buildRepDistribution(sorted: sorted, now: now)
        let orderProfiles = ExercisePositionLogic.profiles(
            sessions: sorted,
            routineOrders: routineOrders,
            canonical: { resolved($0)?.name ?? $0 }
        )

        var sessionsByDay: [Date: [WorkoutSession]] = [:]
        for session in sorted {
            sessionsByDay[calendar.startOfDay(for: session.date), default: []].append(session)
        }
        let records = prRecords(sessionsByDay: sessionsByDay, resolve: resolved)

        return AnalyticsSnapshot(
            totalSessions: sorted.count,
            headline: headline,
            exerciseOptions: options,
            progression: progression,
            donuts: donuts,
            distributions: distributions,
            prRecords: records,
            sessionsByDay: sessionsByDay,
            firstSessionDate: sorted.first?.date,
            repBins: repBins,
            repZoneShares: zoneShares,
            repWindowIsRecent: repRecent,
            repInsight: repInsight,
            exerciseOrderProfiles: orderProfiles
        )
    }

    // MARK: Headline

    private static func buildHeadline(
        sorted: [WorkoutSession],
        now: Date,
        calendar: Calendar
    ) -> Headline {
        func sets(in window: AnalyticsWindow) -> [WorkoutSet] {
            sorted
                .filter { window.contains($0.date, now: now, calendar: calendar) }
                .flatMap { $0.logs.values }
                .flatMap { $0 }
        }

        let volume = sets(in: .sevenDays).compactMap(AnalyticsMath.setVolume).reduce(0, +)
        let counted = sets(in: .thirtyDays).filter(AnalyticsMath.isCountedSet).count
        return Headline(volumeLast7Days: volume, setsLast30Days: counted)
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
                // Only checked-off sets feed progression; parsing below still
                // handles empty/free-text rows as before.
                perExercise[canonical, default: []].append(contentsOf: sets.filter(\.isCompleted))
            }

            for (canonical, sets) in perExercise {
                let e1RM = AnalyticsMath.bestE1RM(in: sets)

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
            .map { entry in
                ExerciseOption(
                    name: entry.key,
                    sessionCount: entry.value.count,
                    e1RMCount: entry.value.filter { $0.e1RM != nil }.count
                )
            }
            .sorted { lhs, rhs in
                if lhs.sessionCount != rhs.sessionCount { return lhs.sessionCount > rhs.sessionCount }
                return lhs.name < rhs.name
            }

        return (options, series)
    }

    // MARK: Muscle distribution radar

    /// Radar axis order, clockwise from top-right (matches the drawn layout:
    /// Chest top-right, Core right, Shoulders bottom-right, Arms bottom-left,
    /// Legs left, Back top-left).
    static let radarMuscleOrder: [MuscleGroup] = [.chest, .core, .shoulders, .arms, .legs, .back]

    /// Distribution for the radar + stat tiles. Current window is
    /// `window` (local days ending today); previous is the equal-length
    /// window immediately before it — none for "All". Pure — inject the
    /// resolver so the math stays testable.
    static func muscleDistribution(
        sessions: [WorkoutSession],
        resolve: (String) -> Exercise?,
        window: AnalyticsWindow,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> MuscleDistribution {
        let currentStart = window.start(now: now, calendar: calendar)
        let currentEnd = window.days == nil ? Date.distantFuture : window.end(now: now, calendar: calendar)
        let previousStart = currentStart.flatMap { start in
            window.days.flatMap { calendar.date(byAdding: .day, value: -$0, to: start) }
        }

        var resolutionCache: [String: Exercise?] = [:]
        func resolved(_ name: String) -> Exercise? {
            if let cached = resolutionCache[name] { return cached }
            let match = resolve(name)
            resolutionCache[name] = match
            return match
        }

        struct WindowTotals {
            var workouts = 0
            var sets = 0
            var volume = 0.0
            var durationSeconds: Int?
            var setsByGroup: [MuscleGroup: Int] = [:]
        }

        /// A nil `start` is unbounded.
        func totals(from start: Date?, to end: Date) -> WindowTotals {
            var totals = WindowTotals()
            for session in sessions where (start.map { session.date >= $0 } ?? true) && session.date < end {
                totals.workouts += 1
                if let duration = session.durationSeconds {
                    totals.durationSeconds = (totals.durationSeconds ?? 0) + duration
                }
                for (name, sets) in session.logs {
                    let counted = sets.filter(AnalyticsMath.isCountedSet).count
                    totals.volume += sets.compactMap(AnalyticsMath.setVolume).reduce(0, +)
                    guard counted > 0 else { continue }
                    totals.sets += counted
                    // Radar axes carry the six named groups only — everything
                    // else (cardio, full body, unresolved, ...) is excluded.
                    if let group = resolved(name)?.muscleGroup, chartMuscleGroups.contains(group) {
                        totals.setsByGroup[group, default: 0] += counted
                    }
                }
            }
            return totals
        }

        let current = totals(from: currentStart, to: currentEnd)
        let previous: WindowTotals
        if let previousStart, let currentStart {
            previous = totals(from: previousStart, to: currentStart)
        } else {
            previous = WindowTotals()
        }

        let axes = radarMuscleOrder.map { group in
            MuscleDistribution.Axis(
                group: group.rawValue,
                currentSets: current.setsByGroup[group] ?? 0,
                previousSets: previous.setsByGroup[group] ?? 0
            )
        }
        let maxAxisSets = axes.map { max($0.currentSets, $0.previousSets) }.max() ?? 0

        return MuscleDistribution(
            axes: axes,
            maxAxisSets: maxAxisSets,
            currentWorkouts: current.workouts,
            previousWorkouts: previous.workouts,
            currentSets: current.sets,
            previousSets: previous.sets,
            currentVolume: current.volume,
            previousVolume: previous.volume,
            currentDurationSeconds: current.durationSeconds,
            previousDurationSeconds: previous.durationSeconds,
            hasPrevious: previousStart != nil
        )
    }

    // MARK: Muscle distribution donut

    private static func buildDonut(
        sorted: [WorkoutSession],
        resolved: (String) -> Exercise?,
        window: AnalyticsWindow,
        now: Date,
        calendar: Calendar
    ) -> DonutModel? {
        var counts: [String: Int] = [:]
        for session in sorted where window.contains(session.date, now: now, calendar: calendar) {
            for (name, sets) in session.logs {
                let counted = sets.filter(AnalyticsMath.isCountedSet).count
                guard counted > 0 else { continue }
                let group = chartGroup(for: resolved(name)?.muscleGroup)
                counts[group, default: 0] += counted
            }
        }

        let total = counts.values.reduce(0, +)
        guard total > 0 else { return nil }

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

        return DonutModel(segments: segments, totalSets: total)
    }

    // MARK: PR board

    /// Standing e1RM records per canonical exercise. Walks history by local
    /// day: a day's best beats the standing best → new record (the beaten
    /// value becomes `previousBest`); a tie keeps the earlier day. Aliases
    /// merge through `resolve`; only completed sets carry an e1RM
    /// (`AnalyticsMath.bestE1RM`). Most recent record first, then heaviest.
    static func prRecords(
        sessionsByDay: [Date: [WorkoutSession]],
        resolve: (String) -> Exercise?
    ) -> [PRRecord] {
        var resolutionCache: [String: String] = [:]
        func canonical(_ name: String) -> String {
            if let cached = resolutionCache[name] { return cached }
            let match = resolve(name)?.name ?? name
            resolutionCache[name] = match
            return match
        }

        var records: [String: PRRecord] = [:]
        for day in sessionsByDay.keys.sorted() {
            var dayBest: [String: Double] = [:]
            for session in sessionsByDay[day] ?? [] {
                for (name, sets) in session.logs {
                    guard let e1RM = AnalyticsMath.bestE1RM(in: sets) else { continue }
                    let exercise = canonical(name)
                    dayBest[exercise] = max(dayBest[exercise] ?? 0, e1RM)
                }
            }
            for (exercise, best) in dayBest {
                if let standing = records[exercise] {
                    if best > standing.e1RM {
                        records[exercise] = PRRecord(
                            exercise: exercise, e1RM: best, day: day, previousBest: standing.e1RM
                        )
                    }
                } else {
                    records[exercise] = PRRecord(exercise: exercise, e1RM: best, day: day, previousBest: nil)
                }
            }
        }

        return records.values.sorted { lhs, rhs in
            if lhs.day != rhs.day { return lhs.day > rhs.day }
            if lhs.e1RM != rhs.e1RM { return lhs.e1RM > rhs.e1RM }
            return lhs.exercise < rhs.exercise
        }
    }

    /// Records reached inside the window (by the day they were set), in the
    /// stored order.
    static func prRecords(
        _ records: [PRRecord],
        in window: AnalyticsWindow,
        now: Date,
        calendar: Calendar
    ) -> [PRRecord] {
        records.filter { window.contains($0.day, now: now, calendar: calendar) }
    }

    // MARK: Progression controls

    /// The metric's points for one exercise inside the window, oldest first.
    static func progressionPoints(
        _ series: [ProgressionPoint],
        metric: ProgressionMetric,
        window: AnalyticsWindow,
        now: Date,
        calendar: Calendar
    ) -> [MetricPoint] {
        series.compactMap { point in
            guard window.contains(point.date, now: now, calendar: calendar),
                  let value = point.value(for: metric) else { return nil }
            return MetricPoint(date: point.date, value: value)
        }
    }

    /// Windows worth offering for a series: two or more points make a line;
    /// "All" needs just one so a chartable lift is never blank.
    static func enabledWindows(
        _ series: [ProgressionPoint],
        metric: ProgressionMetric,
        now: Date,
        calendar: Calendar
    ) -> Set<AnalyticsWindow> {
        var enabled = Set<AnalyticsWindow>()
        for window in AnalyticsWindow.progression {
            let count = progressionPoints(series, metric: metric, window: window, now: now, calendar: calendar).count
            if window == .all ? count >= 1 : count >= 2 {
                enabled.insert(window)
            }
        }
        return enabled
    }

    /// The window the chart actually shows: the stored pick when it has a
    /// line, else the next wider window that does, else everything. The
    /// stored pick is left alone so it comes back once the data allows it.
    static func effectiveWindow(stored: AnalyticsWindow, enabled: Set<AnalyticsWindow>) -> AnalyticsWindow {
        let order = AnalyticsWindow.progression
        guard let index = order.firstIndex(of: stored) else { return .all }
        return order[index...].first { enabled.contains($0) } ?? .all
    }

    /// The exercise the progression chart shows: the stored pick while it is
    /// still chartable, else the most-trained chartable exercise — the same
    /// lift the chart opened on before the picker existed.
    static func progressionExercise(stored: String, options: [ExerciseOption]) -> String? {
        if !stored.isEmpty, options.contains(where: { $0.name == stored }) {
            return stored
        }
        return options.first?.name
    }

    /// Labels under the line: the months the points span when they cross two
    /// or more (with the year once a span passes twelve months; at most six
    /// labels, evenly spread), else the first and last dates.
    static func timelineLabels(from start: Date, to end: Date, calendar: Calendar) -> [String] {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = calendar.locale ?? .current

        guard let firstMonth = calendar.dateInterval(of: .month, for: start)?.start,
              let lastMonth = calendar.dateInterval(of: .month, for: end)?.start,
              firstMonth < lastMonth else {
            formatter.dateFormat = "MMM d"
            let first = formatter.string(from: start)
            let last = formatter.string(from: end)
            return first == last ? [first] : [first, last]
        }

        var months: [Date] = []
        var cursor = firstMonth
        while cursor <= lastMonth {
            months.append(cursor)
            guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }
        formatter.dateFormat = months.count > 12 ? "MMM ''yy" : "MMM"

        let limit = 6
        if months.count > limit {
            let step = Double(months.count - 1) / Double(limit - 1)
            months = (0..<limit).map { months[Int((Double($0) * step).rounded())] }
        }
        return months.map { formatter.string(from: $0) }
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

    // MARK: Day scorecard (calendar sheet)

    struct DayScorecard {
        struct PR: Identifiable {
            var id: String { exercise }
            /// Canonical (library-resolved) exercise name.
            var exercise: String
            /// The new all-time best Epley e1RM set that day.
            var e1RM: Double
            /// Where in its session the PR was lifted (1-based); nil when the
            /// session's order is unknown. Advanced-only surface.
            var position: Int? = nil
        }

        /// Total tonnage across the day's completed sets, all sessions.
        var volume: Double
        /// Checked-off sets with usable numbers, all sessions.
        var completedSets: Int
        /// Summed over the day's sessions that recorded a duration; nil when none did.
        var durationSeconds: Int?
        /// Median tonnage of the most recent prior lifting days (see
        /// `dayScorecard`); nil until enough history exists.
        var typicalDayVolume: Double?
        /// Exercises whose best lift that day beat all earlier history, best first.
        var prs: [PR]
        /// The day's check-in — a pain-flagged one wins, else the latest.
        var checkIn: SessionCheckIn?

        /// Volume vs a typical training day, in percent. Nil without a
        /// baseline or when the day itself logged no tonnage.
        var volumeDeltaPercent: Double? {
            guard let typical = typicalDayVolume, typical > 0, volume > 0 else { return nil }
            return (volume - typical) / typical * 100
        }
    }

    /// Prior lifting days feeding the "typical day" baseline.
    static let typicalDayWindow = 10
    /// Prior lifting days required before the comparison is shown.
    static let typicalDayMinimumHistory = 3

    /// Scorecard for one tapped calendar day, aggregated across its sessions.
    /// `sessionsByDay` is the snapshot's start-of-day bucketing, so day
    /// membership always matches the calendar cell that was tapped (late-night
    /// sessions land where the grid shows them).
    ///
    /// "Typical day" = median tonnage of the last `typicalDayWindow` days
    /// strictly before this one that logged any tonnage (median so one monster
    /// or deload day can't skew the baseline). PRs compare the day's best e1RM
    /// per exercise against full history strictly before the day, so a later,
    /// bigger lift never erases the flag; an exercise's first-ever day seeds
    /// the baseline without one (same rule as the user-memory digest).
    static func dayScorecard(
        day: Date,
        sessionsByDay: [Date: [WorkoutSession]],
        resolve: (String) -> Exercise?,
        routineOrders: [UUID: [String]] = [:]
    ) -> DayScorecard {
        var resolutionCache: [String: String] = [:]
        func canonical(_ name: String) -> String {
            if let cached = resolutionCache[name] { return cached }
            let match = resolve(name)?.name ?? name
            resolutionCache[name] = match
            return match
        }

        func tonnage(_ sessions: [WorkoutSession]) -> Double {
            sessions
                .flatMap { $0.logs.values }
                .flatMap { $0 }
                .compactMap(AnalyticsMath.setVolume)
                .reduce(0, +)
        }

        /// Best e1RM per canonical exercise across the given sessions.
        func bestByExercise(_ sessions: [WorkoutSession]) -> [String: Double] {
            var best: [String: Double] = [:]
            for session in sessions {
                for (name, sets) in session.logs {
                    guard let e1RM = AnalyticsMath.bestE1RM(in: sets) else { continue }
                    let exercise = canonical(name)
                    best[exercise] = max(best[exercise] ?? 0, e1RM)
                }
            }
            return best
        }

        let todays = sessionsByDay[day] ?? []
        let volume = tonnage(todays)
        let completedSets = todays
            .flatMap { $0.logs.values }
            .flatMap { $0 }
            .filter(AnalyticsMath.isCountedSet)
            .count

        var durationSeconds: Int?
        for session in todays {
            if let duration = session.durationSeconds {
                durationSeconds = (durationSeconds ?? 0) + duration
            }
        }

        var priorVolumes: [Double] = []
        for prior in sessionsByDay.keys.filter({ $0 < day }).sorted(by: >) {
            guard priorVolumes.count < typicalDayWindow else { break }
            let dayTonnage = tonnage(sessionsByDay[prior] ?? [])
            if dayTonnage > 0 { priorVolumes.append(dayTonnage) }
        }
        let typical = priorVolumes.count >= typicalDayMinimumHistory
            ? median(of: priorVolumes)
            : nil

        // The day's best per exercise, remembering where in its session it
        // was lifted (ties keep the earliest known slot).
        var dayBest: [String: (value: Double, position: Int?)] = [:]
        for session in todays {
            let slots = ExercisePositionLogic.positions(in: session, routineOrders: routineOrders)
            for (name, sets) in session.logs {
                guard let e1RM = AnalyticsMath.bestE1RM(in: sets) else { continue }
                let exercise = canonical(name)
                let slot = slots[name]
                if let existing = dayBest[exercise] {
                    if e1RM > existing.value {
                        dayBest[exercise] = (e1RM, slot)
                    } else if e1RM == existing.value {
                        dayBest[exercise] = (e1RM, [existing.position, slot].compactMap { $0 }.min())
                    }
                } else {
                    dayBest[exercise] = (e1RM, slot)
                }
            }
        }
        let priorBest = bestByExercise(
            sessionsByDay.filter { $0.key < day }.values.flatMap { $0 }
        )
        let prs = dayBest
            .compactMap { exercise, entry -> DayScorecard.PR? in
                guard let previous = priorBest[exercise], entry.value > previous else { return nil }
                return DayScorecard.PR(exercise: exercise, e1RM: entry.value, position: entry.position)
            }
            .sorted { lhs, rhs in
                if lhs.e1RM != rhs.e1RM { return lhs.e1RM > rhs.e1RM }
                return lhs.exercise < rhs.exercise
            }

        let checkIns = todays.sorted { $0.date < $1.date }.compactMap(\.checkIn)
        let checkIn = checkIns.first(where: \.hadPain) ?? checkIns.last

        return DayScorecard(
            volume: volume,
            completedSets: completedSets,
            durationSeconds: durationSeconds,
            typicalDayVolume: typical,
            prs: prs,
            checkIn: checkIn
        )
    }

    private static func median(of values: [Double]) -> Double {
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[mid - 1] + sorted[mid]) / 2
            : sorted[mid]
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
                .filter(\.isCompleted)
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
