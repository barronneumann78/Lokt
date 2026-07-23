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

    // MARK: Consistency heatmap

    struct DayCell: Identifiable {
        var id: Date { date }
        var date: Date
        var sets: Int
        /// 0 = rest day, 1...4 = quartile of the user's own non-zero daily set counts.
        var level: Int
        var isFuture: Bool
    }

    struct HeatmapModel {
        /// Oldest week first; each week has exactly 7 day cells (calendar row order).
        var weeks: [[DayCell]]
        /// Column index -> short month label, only where the month changes.
        var monthLabels: [(weekIndex: Int, label: String)]
        var weekdayLabels: [String]
    }

    // MARK: Strength trends

    struct TrendPoint: Identifiable {
        var id: Date { date }
        var date: Date
        var e1RM: Double
        var isPR: Bool
    }

    enum Momentum {
        case climbing
        case steady
        case declining
    }

    struct ExerciseTrend: Identifiable {
        var id: String { name }
        var name: String
        var points: [TrendPoint]
        var currentE1RM: Double
        /// Percent change first shown point -> latest.
        var windowDeltaPercent: Double?
        /// Recent direction: mean of last 3 points vs the 3 before them.
        var recentMomentum: Momentum
        var recentDeltaPercent: Double?
    }

    // MARK: Muscle balance

    struct MuscleShare: Identifiable {
        var id: String { group }
        var group: String
        var sets: Int
        /// 0...1 share of all sets in the window.
        var share: Double
        /// Change vs the prior window, in percentage points (nil without prior data).
        var deltaPoints: Double?
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
    var heatmap: HeatmapModel
    var heatmapInsight: String?
    var trends: [ExerciseTrend]
    var trendInsight: String?
    var muscleShares: [MuscleShare]
    var muscleWindowIsRecent: Bool
    var balanceInsight: String?
    var repBins: [RepBin]
    var repZoneShares: [RepZone: Double]
    var repWindowIsRecent: Bool
    var repInsight: String?

    static let empty = AnalyticsSnapshot(
        totalSessions: 0,
        headline: nil,
        heatmap: HeatmapModel(weeks: [], monthLabels: [], weekdayLabels: []),
        heatmapInsight: nil,
        trends: [],
        trendInsight: nil,
        muscleShares: [],
        muscleWindowIsRecent: false,
        balanceInsight: nil,
        repBins: [],
        repZoneShares: [:],
        repWindowIsRecent: false,
        repInsight: nil
    )

    // MARK: - Build

    static let heatmapWeekCount = 17
    static let maxTrendExercises = 3
    static let maxTrendPoints = 15

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
        let (heatmap, heatmapInsight) = buildHeatmap(
            sorted: sorted,
            currentWeek: currentWeek,
            streakWeeks: headline.streakWeeks,
            now: now,
            calendar: calendar
        )
        let (trends, trendInsight) = buildTrends(sorted: sorted, resolved: resolved)
        let (muscleShares, muscleRecent, balanceInsight) = buildMuscleBalance(
            sorted: sorted,
            resolved: resolved,
            now: now
        )
        let (repBins, zoneShares, repRecent, repInsight) = buildRepDistribution(sorted: sorted, now: now)

        return AnalyticsSnapshot(
            totalSessions: sorted.count,
            headline: headline,
            heatmap: heatmap,
            heatmapInsight: heatmapInsight,
            trends: trends,
            trendInsight: trendInsight,
            muscleShares: muscleShares,
            muscleWindowIsRecent: muscleRecent,
            balanceInsight: balanceInsight,
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

    // MARK: Consistency heatmap

    private static func buildHeatmap(
        sorted: [WorkoutSession],
        currentWeek: DateInterval,
        streakWeeks: Int,
        now: Date,
        calendar: Calendar
    ) -> (HeatmapModel, String?) {
        guard let firstColumnStart = calendar.date(
            byAdding: .weekOfYear,
            value: -(heatmapWeekCount - 1),
            to: currentWeek.start
        ) else {
            return (HeatmapModel(weeks: [], monthLabels: [], weekdayLabels: []), nil)
        }

        // Sets per day and sessions per weekday within the window.
        var setsPerDay: [Date: Int] = [:]
        var sessionsPerWeekday: [Int: Int] = [:]
        var sessionsInWindow = 0
        for session in sorted where session.date >= firstColumnStart {
            let day = calendar.startOfDay(for: session.date)
            let sets = session.logs.values
                .flatMap { $0 }
                .filter(AnalyticsMath.isMeaningfulSet)
                .count
            setsPerDay[day, default: 0] += max(sets, 1) // a logged session is activity even if sets didn't parse
            sessionsPerWeekday[calendar.component(.weekday, from: session.date), default: 0] += 1
            sessionsInWindow += 1
        }

        // Intensity levels are quartiles of the user's own non-zero days, so the
        // scale adapts to how they actually train.
        let nonZero = setsPerDay.values.sorted()
        func quantile(_ q: Double) -> Int {
            guard !nonZero.isEmpty else { return 0 }
            let index = min(nonZero.count - 1, Int(Double(nonZero.count) * q))
            return nonZero[index]
        }
        let q1 = quantile(0.25), q2 = quantile(0.5), q3 = quantile(0.75)
        func level(forSets sets: Int) -> Int {
            guard sets > 0 else { return 0 }
            if sets <= q1 { return 1 }
            if sets <= q2 { return 2 }
            if sets <= q3 { return 3 }
            return 4
        }

        var weeks: [[DayCell]] = []
        var monthLabels: [(weekIndex: Int, label: String)] = []
        var lastLabeledMonth = -1
        var lastLabelColumn = -10

        for weekIndex in 0..<heatmapWeekCount {
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: weekIndex, to: firstColumnStart) else { continue }

            let month = calendar.component(.month, from: weekStart)
            if month != lastLabeledMonth, weekIndex - lastLabelColumn >= 3 {
                monthLabels.append((weekIndex, calendar.shortMonthSymbols[month - 1]))
                lastLabeledMonth = month
                lastLabelColumn = weekIndex
            }

            var cells: [DayCell] = []
            for dayOffset in 0..<7 {
                guard let date = calendar.date(byAdding: .day, value: dayOffset, to: weekStart) else { continue }
                let day = calendar.startOfDay(for: date)
                let sets = setsPerDay[day] ?? 0
                cells.append(DayCell(
                    date: day,
                    sets: sets,
                    level: level(forSets: sets),
                    isFuture: day > now
                ))
            }
            weeks.append(cells)
        }

        // Weekday labels in calendar row order (rotated by firstWeekday).
        let symbols = calendar.veryShortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        let weekdayLabels = (0..<7).map { symbols[(first + $0) % 7] }

        // One short insight: streak, favorite training day, or a count.
        var favoriteDay: String?
        if let (weekday, count) = sessionsPerWeekday.max(by: { $0.value < $1.value }), count >= 3 {
            favoriteDay = calendar.weekdaySymbols[weekday - 1]
        }
        var insight: String?
        if streakWeeks >= 2, let day = favoriteDay {
            insight = "\(streakWeeks)-week streak — \(day)s are your day"
        } else if streakWeeks >= 2 {
            insight = "\(streakWeeks) weeks in a row without missing"
        } else if let day = favoriteDay {
            insight = "You show up most on \(day)s"
        } else if sessionsInWindow > 0 {
            insight = "\(sessionsInWindow) session\(sessionsInWindow == 1 ? "" : "s") in the last \(heatmapWeekCount) weeks"
        }

        let model = HeatmapModel(weeks: weeks, monthLabels: monthLabels, weekdayLabels: weekdayLabels)
        return (model, insight)
    }

    // MARK: Strength trends

    private static func buildTrends(
        sorted: [WorkoutSession],
        resolved: (String) -> Exercise?
    ) -> ([ExerciseTrend], String?) {
        // Best estimated 1RM per exercise per session. Logged aliases collapse
        // onto the library name ("DB Bench" and "Dumbbell Bench Press" merge).
        var history: [String: [(date: Date, e1RM: Double)]] = [:]
        for session in sorted {
            for (name, sets) in session.logs {
                let best = sets.compactMap { set -> Double? in
                    guard let weight = AnalyticsMath.parseWeight(set.weight),
                          let reps = AnalyticsMath.parseReps(set.reps) else { return nil }
                    return AnalyticsMath.epleyOneRepMax(weight: weight, reps: reps)
                }.max()
                guard let best else { continue }
                let canonical = resolved(name)?.name ?? name
                history[canonical, default: []].append((session.date, best))
            }
        }

        let top = history
            .filter { $0.value.count >= 3 }
            .sorted { lhs, rhs in
                if lhs.value.count != rhs.value.count { return lhs.value.count > rhs.value.count }
                return (lhs.value.map(\.e1RM).max() ?? 0) > (rhs.value.map(\.e1RM).max() ?? 0)
            }
            .prefix(maxTrendExercises)

        var trends: [ExerciseTrend] = []
        for (name, rawPoints) in top {
            let ordered = rawPoints.sorted { $0.date < $1.date }

            // PR flags computed over the FULL history so an old best isn't
            // re-announced inside a trimmed window.
            var runningMax = -Double.infinity
            var flagged: [TrendPoint] = []
            for (index, point) in ordered.enumerated() {
                let isPR = index > 0 && point.e1RM > runningMax
                runningMax = max(runningMax, point.e1RM)
                flagged.append(TrendPoint(date: point.date, e1RM: point.e1RM, isPR: isPR))
            }

            let shown = Array(flagged.suffix(maxTrendPoints))
            guard let firstShown = shown.first, let last = shown.last else { continue }

            var windowDelta: Double?
            if firstShown.e1RM > 0 {
                windowDelta = (last.e1RM - firstShown.e1RM) / firstShown.e1RM * 100
            }

            // Recent momentum: mean of the last 3 points vs the 3 before them.
            var momentum: Momentum = .steady
            var recentDelta: Double?
            if shown.count >= 6 {
                let lastThree = shown.suffix(3).map(\.e1RM)
                let priorThree = shown.dropLast(3).suffix(3).map(\.e1RM)
                let recentMean = lastThree.reduce(0, +) / 3
                let priorMean = priorThree.reduce(0, +) / 3
                if priorMean > 0 {
                    let delta = (recentMean - priorMean) / priorMean * 100
                    recentDelta = delta
                    momentum = delta > 1.5 ? .climbing : (delta < -1.5 ? .declining : .steady)
                }
            } else if let delta = windowDelta {
                recentDelta = delta
                momentum = delta > 1.5 ? .climbing : (delta < -1.5 ? .declining : .steady)
            }

            trends.append(ExerciseTrend(
                name: name,
                points: shown,
                currentE1RM: last.e1RM,
                windowDeltaPercent: windowDelta,
                recentMomentum: momentum,
                recentDeltaPercent: recentDelta
            ))
        }

        // One line: a lift that climbed overall but has gone flat is the most
        // actionable thing to say; otherwise name the fastest climber.
        var insight: String?
        if let stalled = trends.first(where: { trend in
            (trend.windowDeltaPercent ?? 0) > 4 && trend.recentMomentum != .climbing && trend.points.count >= 6
        }) {
            insight = "\(stalled.name) has gone flat after a strong run — time to change the stimulus?"
        } else if let best = trends
            .filter({ $0.recentMomentum == .climbing })
            .max(by: { ($0.recentDeltaPercent ?? 0) < ($1.recentDeltaPercent ?? 0) }) {
            insight = "\(best.name) is your fastest climber right now"
        } else if trends.contains(where: { $0.recentMomentum == .declining }) {
            insight = "Recent sessions are trending down — check sleep and recovery"
        } else if !trends.isEmpty {
            insight = "Holding steady across your top lifts"
        }

        return (trends, insight)
    }

    // MARK: Muscle balance

    private static func buildMuscleBalance(
        sorted: [WorkoutSession],
        resolved: (String) -> Exercise?,
        now: Date
    ) -> ([MuscleShare], Bool, String?) {
        let day: TimeInterval = 86_400
        let windowStart = now.addingTimeInterval(-28 * day)
        let priorStart = now.addingTimeInterval(-56 * day)

        func groupCounts(from start: Date, to end: Date) -> [String: Int] {
            var counts: [String: Int] = [:]
            for session in sorted where session.date >= start && session.date < end {
                for (name, sets) in session.logs {
                    let meaningful = sets.filter(AnalyticsMath.isMeaningfulSet).count
                    guard meaningful > 0 else { continue }
                    let group = resolved(name)?.muscleGroup.rawValue ?? MuscleGroup.other.rawValue
                    counts[group, default: 0] += meaningful
                }
            }
            return counts
        }

        var current = groupCounts(from: windowStart, to: now.addingTimeInterval(day))
        var currentTotal = current.values.reduce(0, +)
        var isRecent = true
        var prior: [String: Int] = [:]

        if currentTotal >= 10 {
            prior = groupCounts(from: priorStart, to: windowStart)
        } else {
            // Sparse recent data: fall back to all time so the chart stays useful.
            current = groupCounts(from: .distantPast, to: now.addingTimeInterval(day))
            currentTotal = current.values.reduce(0, +)
            isRecent = false
        }

        guard currentTotal > 0 else { return ([], isRecent, nil) }

        let priorTotal = prior.values.reduce(0, +)
        let shares = current
            .map { group, sets -> MuscleShare in
                let share = Double(sets) / Double(currentTotal)
                var delta: Double?
                if priorTotal >= 10 {
                    let priorShare = Double(prior[group] ?? 0) / Double(priorTotal)
                    delta = (share - priorShare) * 100
                }
                return MuscleShare(group: group, sets: sets, share: share, deltaPoints: delta)
            }
            .sorted { lhs, rhs in
                if lhs.sets != rhs.sets { return lhs.sets > rhs.sets }
                return lhs.group < rhs.group
            }

        // Neglect check across the core groups a balanced program should touch.
        var insight: String?
        if currentTotal >= 15 {
            let coreGroups = [
                MuscleGroup.legs, .back, .chest, .core, .shoulders, .arms
            ].map(\.rawValue)
            let shareByGroup = Dictionary(uniqueKeysWithValues: shares.map { ($0.group, $0.share) })
            if let weakest = coreGroups
                .map({ (group: $0, share: shareByGroup[$0] ?? 0) })
                .min(by: { $0.share < $1.share }) {
                if weakest.share < 0.08 {
                    let pct = Int((weakest.share * 100).rounded())
                    insight = pct == 0
                        ? "\(weakest.group) hasn't been trained in this window"
                        : "\(weakest.group) is getting just \(pct)% of your sets"
                } else {
                    insight = "Volume is spread evenly — no muscle group is falling behind"
                }
            }
        }

        return (shares, isRecent, insight)
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
