import SwiftUI
import Charts
import Combine

/// The definitive analytics page: interactive exercise progression, training
/// calendar, muscle-distribution radar, 30-day muscle split and rep ranges —
/// all derived once per data change in `AnalyticsSnapshot`.
struct AnalyticsView: View {
    @EnvironmentObject private var store: WorkoutStore
    @EnvironmentObject private var exerciseStore: ExerciseStore
    @State private var snapshot: AnalyticsSnapshot = .empty

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    if snapshot.totalSessions == 0 {
                        emptyState
                    } else {
                        if let headline = snapshot.headline {
                            headlineStrip(headline)
                        }
                        ProgressionCard(snapshot: snapshot)
                        CalendarCard(snapshot: snapshot, exercises: exerciseStore.exercises)
                        MuscleDistributionCard(sessions: store.sessions, exercises: exerciseStore.exercises)
                        MuscleDonutCard(donut: snapshot.donut, insight: snapshot.donutInsight)
                        if !snapshot.repBins.isEmpty {
                            repRangeCard
                        }
                    }
                }
                .padding(.horizontal, AppTheme.screenPadding)
                .padding(.vertical, 20)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            rebuild(with: store.sessions)
        }
        .onReceive(store.$sessions) { sessions in
            rebuild(with: sessions)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            if snapshot.totalSessions > 0 {
                Text("\(snapshot.totalSessions) sessions logged")
                    .font(.footnote.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Text("Progress")
                .font(.system(size: 34, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(AppTheme.textPrimary)
        }
        .padding(.bottom, 4)
    }

    private func rebuild(with sessions: [WorkoutSession]) {
        let exercises = exerciseStore.exercises
        snapshot = AnalyticsSnapshot.build(
            sessions: sessions,
            resolve: { exercises.resolvedExercise(named: $0) }
        )
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(AppTheme.primary.opacity(0.8))

            Text("Nothing to chart yet")
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            Text("Log a workout and Lokt will map your strength, consistency and muscle balance here.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 28)
        .padding(.vertical, 56)
        .glassCard()
    }

    // MARK: - Headline strip

    private func headlineStrip(_ headline: AnalyticsSnapshot.Headline) -> some View {
        HStack(spacing: 10) {
            statTile(
                label: "Sessions",
                value: "\(headline.thisWeekSessions)",
                detail: "this week"
            )

            if headline.volumeIsMeaningful {
                statTile(
                    label: "Volume",
                    value: AnalyticsFormat.compact(headline.thisWeekVolume),
                    detail: "lbs this week",
                    delta: headline.volumeDeltaPercent.map { delta in
                        (text: AnalyticsFormat.signedPercent(delta) + " vs avg", isPositive: delta >= 0)
                    }
                )
            } else {
                statTile(
                    label: "Sets",
                    value: "\(headline.thisWeekSets)",
                    detail: "this week"
                )
            }

            statTile(
                label: "Streak",
                value: headline.streakWeeks == 0 ? "—" : "\(headline.streakWeeks) wk",
                detail: headline.streakWeeks == 0 ? "train to start one" : "in a row"
            )
        }
    }

    private func statTile(
        label: String,
        value: String,
        detail: String,
        delta: (text: String, isPositive: Bool)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .microLabel()

            Text(value)
                .font(.system(size: 26, weight: .bold))
                .monospacedDigit()
                .tracking(-0.5)
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if let delta {
                Text(delta.text)
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(delta.isPositive ? AppTheme.success : AppTheme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassCard()
    }

    // MARK: - Rep ranges

    private var repRangeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("REP RANGES\(snapshot.repWindowIsRecent ? " · 60D" : "")")
                .microLabel()

            repHistogram

            repZoneLegend

            if let insight = snapshot.repInsight {
                insightLine(insight)
            }
        }
        .padding(AppTheme.cardPadding)
        .glassCard()
    }

    private var repHistogram: some View {
        Chart(snapshot.repBins) { bin in
            BarMark(
                x: .value("Reps", Double(bin.reps)),
                y: .value("Sets", bin.count),
                width: .fixed(9)
            )
            .foregroundStyle(RepPalette.zoneColor(bin.zone))
            .cornerRadius(2)
        }
        .chartXScale(domain: 0.3...21.2)
        .chartXAxis {
            AxisMarks(values: [1.0, 5.0, 10.0, 15.0, 20.0]) { value in
                AxisValueLabel {
                    if let reps = value.as(Double.self) {
                        Text(reps >= 20 ? "20+" : "\(Int(reps))")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.textTertiary)
                            .fixedSize()
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                    .foregroundStyle(AppTheme.cardBorder)
                AxisValueLabel()
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textTertiary)
            }
        }
        .frame(height: 130)
    }

    private var repZoneLegend: some View {
        HStack(alignment: .top, spacing: 16) {
            ForEach(RepZone.allCases) { zone in
                HStack(alignment: .top, spacing: 6) {
                    Circle()
                        .fill(RepPalette.zoneColor(zone))
                        .frame(width: 8, height: 8)
                        .padding(.top, 3)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(zone.label)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                        Text("\(zone.rangeText) · \(zonePercent(zone))")
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                }
            }
        }
    }

    private func zonePercent(_ zone: RepZone) -> String {
        let share = snapshot.repZoneShares[zone] ?? 0
        return "\(Int((share * 100).rounded()))%"
    }

    private func insightLine(_ text: String) -> some View {
        AnalyticsInsightLine(text: text)
    }
}

// MARK: - Muscle palette
//
// Fixed muscle -> series color mapping for the donut (color follows the
// entity — filtering never repaints survivors). Slots come from
// `AppTheme.chartCategorical`; anything outside the six core groups is
// neutral gray.
enum MusclePalette {
    static func color(for group: String) -> Color {
        switch group {
        case MuscleGroup.legs.rawValue: return AppTheme.chartCategorical[0]      // volt
        case MuscleGroup.back.rawValue: return AppTheme.chartCategorical[1]      // teal
        case MuscleGroup.shoulders.rawValue: return AppTheme.chartCategorical[2] // gold
        case MuscleGroup.core.rawValue: return AppTheme.chartCategorical[3]      // green
        case MuscleGroup.arms.rawValue: return AppTheme.chartCategorical[4]      // orange
        case MuscleGroup.chest.rawValue: return AppTheme.chartCategorical[5]     // coral
        default: return AppTheme.chartNeutral
        }
    }
}

// MARK: - Shared formatting

private enum AnalyticsFormat {
    static func compact(_ value: Double) -> String {
        if value >= 100_000 {
            return String(format: "%.0fk", value / 1000)
        }
        if value >= 10_000 {
            return String(format: "%.1fk", value / 1000)
        }
        return value.formatted(.number.precision(.fractionLength(0)))
    }

    static func signedPercent(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        let prefix = rounded > 0 ? "+" : ""
        if rounded == rounded.rounded() {
            return "\(prefix)\(Int(rounded))%"
        }
        return "\(prefix)\(rounded.formatted(.number.precision(.fractionLength(1))))%"
    }

    static func axisValue(_ value: Double) -> String {
        if abs(value) >= 10_000 {
            return String(format: "%.0fk", value / 1000)
        }
        if abs(value) >= 1_000 {
            let compact = value / 1000
            return compact == compact.rounded()
                ? String(format: "%.0fk", compact)
                : String(format: "%.1fk", compact)
        }
        return "\(Int(value.rounded()))"
    }
}

private struct AnalyticsInsightLine: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "sparkles")
                .font(.caption2)
                .foregroundStyle(AppTheme.textTertiary)
            Text(text)
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Chart 1 · Exercise progression

private struct ProgressionCard: View {
    let snapshot: AnalyticsSnapshot

    struct MetricPoint: Identifiable, Equatable {
        var id: Date { date }
        var date: Date
        var value: Double
    }

    @State private var selectedExercise: String?
    @State private var metric: ProgressionMetric = .estOneRepMax
    @State private var timeframe: AnalyticsTimeframe = .threeMonths
    @State private var points: [MetricPoint] = []
    @State private var enabledTimeframes: Set<AnalyticsTimeframe> = []
    @State private var scrub: MetricPoint?
    @State private var tooltipSize: CGSize = .zero
    @Namespace private var metricNamespace

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if snapshot.exerciseOptions.isEmpty {
                placeholder
            } else {
                exerciseMenu
                heroRow
                metricPicker
                timeframeRow
                chart
            }
        }
        .padding(AppTheme.cardPadding)
        .glassCard()
        .onAppear { syncSelection() }
        .onChange(of: snapshot.exerciseOptions.map(\.name)) { _, _ in syncSelection() }
        .sensoryFeedback(.selection, trigger: scrub?.date)
    }

    private var placeholder: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PROGRESSION")
                .microLabel()
            Text("Log weight and reps to chart your strength over time.")
                .font(.footnote)
                .foregroundStyle(AppTheme.textTertiary)
                .padding(.vertical, 24)
        }
    }

    // MARK: Selection & caching

    private func syncSelection() {
        let names = snapshot.exerciseOptions.map(\.name)
        if selectedExercise == nil || !names.contains(selectedExercise ?? "") {
            selectedExercise = names.first
        }
        refreshTimeframes()
        if !enabledTimeframes.contains(timeframe) {
            timeframe = enabledTimeframes.contains(.threeMonths) ? .threeMonths : .all
        }
        rebuildPoints(animated: false)
    }

    private func fullSeries(for metric: ProgressionMetric) -> [MetricPoint] {
        guard let name = selectedExercise,
              let series = snapshot.progression[name] else { return [] }
        return series.compactMap { point in
            point.value(for: metric).map { MetricPoint(date: point.date, value: $0) }
        }
    }

    private func windowed(_ series: [MetricPoint], timeframe: AnalyticsTimeframe) -> [MetricPoint] {
        guard let start = timeframe.startDate(now: Date(), calendar: .current) else { return series }
        return series.filter { $0.date >= start }
    }

    private func refreshTimeframes() {
        let series = fullSeries(for: metric)
        var enabled: Set<AnalyticsTimeframe> = []
        for frame in AnalyticsTimeframe.allCases {
            let count = windowed(series, timeframe: frame).count
            if frame == .all ? count >= 1 : count >= 2 {
                enabled.insert(frame)
            }
        }
        enabledTimeframes = enabled
    }

    private func rebuildPoints(animated: Bool) {
        let newPoints = windowed(fullSeries(for: metric), timeframe: timeframe)
        if animated {
            withAnimation(.easeInOut(duration: 0.35)) {
                points = newPoints
            }
        } else {
            points = newPoints
        }
        scrub = nil
    }

    private func select(metric newMetric: ProgressionMetric) {
        guard newMetric != metric else { return }
        metric = newMetric
        refreshTimeframes()
        if !enabledTimeframes.contains(timeframe) {
            timeframe = .all
        }
        rebuildPoints(animated: true)
    }

    private func select(timeframe newTimeframe: AnalyticsTimeframe) {
        guard newTimeframe != timeframe, enabledTimeframes.contains(newTimeframe) else { return }
        timeframe = newTimeframe
        rebuildPoints(animated: true)
    }

    private func select(exercise name: String) {
        guard name != selectedExercise else { return }
        selectedExercise = name
        refreshTimeframes()
        if !enabledTimeframes.contains(timeframe) {
            timeframe = enabledTimeframes.contains(.threeMonths) ? .threeMonths : .all
        }
        rebuildPoints(animated: true)
    }

    // MARK: Header pieces

    private var exerciseMenu: some View {
        Menu {
            ForEach(snapshot.exerciseOptions) { option in
                Button {
                    select(exercise: option.name)
                } label: {
                    if option.name == selectedExercise {
                        Label(option.name, systemImage: "checkmark")
                    } else {
                        Text(option.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(selectedExercise ?? "")
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }

    private var heroRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(heroValueText)
                .font(.system(size: 34, weight: .bold))
                .monospacedDigit()
                .tracking(-1)
                .foregroundStyle(AppTheme.textPrimary)
                .contentTransition(.numericText())

            Text("lb")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)

            Spacer(minLength: 8)

            if let delta = windowDeltaPercent {
                deltaBadge(delta)
            }
        }
    }

    private var heroValueText: String {
        guard let latest = points.last else { return "—" }
        return AnalyticsFormat.compact(latest.value)
    }

    private var windowDeltaPercent: Double? {
        guard let first = points.first, let last = points.last,
              points.count >= 2, first.value > 0 else { return nil }
        return (last.value - first.value) / first.value * 100
    }

    private func deltaBadge(_ delta: Double) -> some View {
        let direction: (icon: String, color: Color)
        if delta > 1.5 {
            direction = ("arrow.up.right", AppTheme.success)
        } else if delta < -1.5 {
            direction = ("arrow.down.right", AppTheme.danger)
        } else {
            direction = ("minus", AppTheme.textSecondary)
        }

        return HStack(spacing: 3) {
            Image(systemName: direction.icon)
                .font(.system(size: 8, weight: .bold))
            Text(AnalyticsFormat.signedPercent(delta))
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
        }
        .foregroundStyle(direction.color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(direction.color.opacity(0.14))
        .clipShape(Capsule())
    }

    private var metricPicker: some View {
        HStack(spacing: 4) {
            ForEach(ProgressionMetric.allCases) { candidate in
                Button {
                    select(metric: candidate)
                } label: {
                    Text(candidate.shortLabel)
                        .font(.caption2.weight(.semibold))
                        .tracking(0.8)
                        .foregroundStyle(candidate == metric ? AppTheme.textPrimary : AppTheme.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background {
                            if candidate == metric {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(AppTheme.surfaceElevated)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(AppTheme.cardBorder, lineWidth: 1)
                                    }
                                    .matchedGeometryEffect(id: "metric", in: metricNamespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(AppTheme.mutedFill)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .animation(.easeInOut(duration: 0.22), value: metric)
    }

    private var timeframeRow: some View {
        HStack(spacing: 8) {
            ForEach(AnalyticsTimeframe.allCases) { frame in
                let isEnabled = enabledTimeframes.contains(frame)
                Button {
                    select(timeframe: frame)
                } label: {
                    Text(frame.rawValue)
                        .font(.caption2.weight(.semibold))
                        .tracking(0.8)
                        .monospacedDigit()
                        .foregroundStyle(
                            frame == timeframe
                                ? AppTheme.textPrimary
                                : (isEnabled ? AppTheme.textTertiary : AppTheme.textTertiary.opacity(0.4))
                        )
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background {
                            if frame == timeframe {
                                Capsule().fill(AppTheme.surfaceElevated)
                                    .overlay { Capsule().stroke(AppTheme.cardBorder, lineWidth: 1) }
                            }
                        }
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled)
            }
            Spacer()
        }
    }

    // MARK: Chart

    private var yDomain: ClosedRange<Double> {
        let values = points.map(\.value)
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        let span = max(high - low, max(high * 0.05, 1))
        let lower = max(0, low - span * 0.18)
        // Generous headroom doubles as the scrub tooltip's landing zone.
        let upper = high + span * 0.42
        return lower...upper
    }

    private var chart: some View {
        Chart(points) { point in
            LineMark(
                x: .value("Date", point.date),
                y: .value(metric.label, point.value)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(AppTheme.primary)
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

            // Latest value gets an end-dot with a card-colored ring.
            if point.date == points.last?.date {
                PointMark(
                    x: .value("Date", point.date),
                    y: .value(metric.label, point.value)
                )
                .symbolSize(120)
                .foregroundStyle(AppTheme.card)

                PointMark(
                    x: .value("Date", point.date),
                    y: .value(metric.label, point.value)
                )
                .symbolSize(52)
                .foregroundStyle(AppTheme.primary)
            }
        }
        .chartYScale(domain: yDomain)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                    .foregroundStyle(AppTheme.cardBorder)
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(AnalyticsFormat.axisValue(number))
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textTertiary)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(scrubGesture(proxy: proxy, geo: geo))

                if let scrub {
                    scrubIndicator(for: scrub, proxy: proxy, geo: geo)
                }
            }
        }
        .frame(height: 240)
    }

    private func scrubGesture(proxy: ChartProxy, geo: GeometryProxy) -> some Gesture {
        LongPressGesture(minimumDuration: 0.15)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
            .onChanged { value in
                guard case .second(true, let drag) = value, let drag else { return }
                updateScrub(at: drag.location, proxy: proxy, geo: geo)
            }
            .onEnded { _ in
                withAnimation(.easeOut(duration: 0.18)) { scrub = nil }
            }
    }

    private func updateScrub(at location: CGPoint, proxy: ChartProxy, geo: GeometryProxy) {
        guard !points.isEmpty,
              let plotAnchor = proxy.plotFrame else { return }
        let plotFrame = geo[plotAnchor]
        let xInPlot = location.x - plotFrame.minX
        guard let date = proxy.value(atX: xInPlot, as: Date.self) else { return }

        // Snap to the nearest data point — never interpolate a fake value.
        let nearest = points.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }
        if nearest != scrub {
            scrub = nearest
        }
    }

    @ViewBuilder
    private func scrubIndicator(for point: MetricPoint, proxy: ChartProxy, geo: GeometryProxy) -> some View {
        if let plotAnchor = proxy.plotFrame,
           let xPos = proxy.position(forX: point.date),
           let yPos = proxy.position(forY: point.value) {
            let plotFrame = geo[plotAnchor]
            let x = plotFrame.minX + xPos
            let y = plotFrame.minY + yPos

            // Vertical indicator line.
            Rectangle()
                .fill(AppTheme.textTertiary)
                .frame(width: 1, height: plotFrame.height)
                .position(x: x, y: plotFrame.midY)

            // Matching dot with a card-colored ring.
            Circle()
                .fill(AppTheme.primary)
                .frame(width: 9, height: 9)
                .background {
                    Circle()
                        .fill(AppTheme.card)
                        .frame(width: 15, height: 15)
                }
                .position(x: x, y: y)

            // Tooltip pinned in the headroom above the line, clamped horizontally.
            let halfWidth = max(tooltipSize.width, 60) / 2
            let halfHeight = max(tooltipSize.height, 30) / 2
            let clampedX = min(max(x, halfWidth), geo.size.width - halfWidth)
            scrubTooltip(for: point)
                .position(x: clampedX, y: halfHeight + 1)
        }
    }

    private func scrubTooltip(for point: MetricPoint) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(point.date.formatted(.dateTime.month(.abbreviated).day().year()))
                .font(.caption2)
                .foregroundStyle(AppTheme.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(AnalyticsFormat.compact(point.value))
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.textPrimary)
                Text("lb")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(AppTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        }
        .fixedSize()
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            tooltipSize = size
        }
    }
}

// MARK: - Chart 4 · Training calendar

private struct CalendarCard: View {
    let snapshot: AnalyticsSnapshot
    let exercises: [Exercise]

    private struct DaySelection: Identifiable {
        var id: Date { date }
        var date: Date
    }

    @State private var monthAnchor = Date()
    @State private var selectedDay: DaySelection?

    private var calendar: Calendar { .current }

    private var month: AnalyticsSnapshot.CalendarMonth {
        AnalyticsSnapshot.calendarMonth(
            containing: monthAnchor,
            sessionsByDay: snapshot.sessionsByDay,
            now: Date(),
            calendar: calendar
        )
    }

    private var currentMonthStart: Date {
        calendar.dateInterval(of: .month, for: Date())?.start ?? Date()
    }

    private var firstMonthStart: Date {
        guard let first = snapshot.firstSessionDate,
              let start = calendar.dateInterval(of: .month, for: first)?.start else {
            return currentMonthStart
        }
        return start
    }

    private var canGoBack: Bool { month.monthStart > firstMonthStart }
    private var canGoForward: Bool { month.monthStart < currentMonthStart }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            weekdayHeader
            dayGrid
        }
        .padding(AppTheme.cardPadding)
        .glassCard()
        .sheet(item: $selectedDay) { selection in
            DaySummarySheet(
                date: selection.date,
                sessions: snapshot.sessionsByDay[selection.date] ?? [],
                exercises: exercises,
                scorecard: AnalyticsSnapshot.dayScorecard(
                    day: selection.date,
                    sessionsByDay: snapshot.sessionsByDay,
                    resolve: { exercises.resolvedExercise(named: $0) }
                )
            )
        }
    }

    private var header: some View {
        HStack {
            Text(month.monthStart.formatted(.dateTime.month(.wide).year()))
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)
                .monospacedDigit()
                .contentTransition(.numericText())

            Spacer()

            pagerButton(systemName: "chevron.left", enabled: canGoBack) {
                page(by: -1)
            }
            pagerButton(systemName: "chevron.right", enabled: canGoForward) {
                page(by: 1)
            }
        }
    }

    private func pagerButton(systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(enabled ? AppTheme.textPrimary : AppTheme.textTertiary.opacity(0.5))
                .frame(width: 30, height: 30)
                .background(enabled ? AppTheme.surfaceElevated : AppTheme.mutedFill)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func page(by delta: Int) {
        guard let next = calendar.date(byAdding: .month, value: delta, to: month.monthStart) else { return }
        let clamped = min(max(next, firstMonthStart), currentMonthStart)
        withAnimation(.easeInOut(duration: 0.2)) {
            monthAnchor = clamped
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 6) {
            ForEach(Array(AnalyticsSnapshot.weekdayHeaderLabels(calendar: calendar).enumerated()), id: \.offset) { _, label in
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(AppTheme.textTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var dayGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(0..<month.leadingBlanks, id: \.self) { _ in
                Color.clear.frame(height: 38)
            }
            ForEach(month.days) { day in
                dayCell(day)
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ day: AnalyticsSnapshot.CalendarDayCell) -> some View {
        if day.sessionCount > 0 {
            Button {
                selectedDay = DaySelection(date: day.date)
            } label: {
                ZStack {
                    Circle()
                        .fill(AppTheme.primary)
                        .frame(width: 36, height: 36)
                    Text("\(day.day)")
                        .font(.system(size: 14, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.backgroundTop)
                }
                .frame(height: 38)
            }
            .buttonStyle(.plain)
        } else {
            ZStack {
                if day.isToday {
                    Circle()
                        .stroke(AppTheme.textTertiary, lineWidth: 1)
                        .frame(width: 36, height: 36)
                }
                Text("\(day.day)")
                    .font(.system(size: 14, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(
                        day.isFuture
                            ? AppTheme.textTertiary.opacity(0.35)
                            : AppTheme.textTertiary
                    )
            }
            .frame(height: 38)
        }
    }
}

// MARK: Day summary sheet

private struct DaySummarySheet: View {
    let date: Date
    let sessions: [WorkoutSession]
    let exercises: [Exercise]
    let scorecard: AnalyticsSnapshot.DayScorecard

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        scorecardCard
                        ForEach(sessions) { session in
                            sessionCard(session)
                        }
                    }
                    .padding(.horizontal, AppTheme.screenPadding)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle(date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(AppTheme.backgroundTop)
    }

    // MARK: Day scorecard

    private var scorecardCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                heroMetric(label: "Volume", value: AnalyticsMath.compactVolume(scorecard.volume) + " lbs")
                heroMetric(label: "Sets", value: "\(scorecard.completedSets)")
                if let seconds = scorecard.durationSeconds {
                    heroMetric(label: "Duration", value: AnalyticsMath.durationText(seconds: seconds))
                }
            }

            if let delta = scorecard.volumeDeltaPercent {
                deltaLine(delta)
            }

            if !scorecard.prs.isEmpty {
                Divider().overlay(AppTheme.cardBorder)
                prSection
            }

            if let checkIn = scorecard.checkIn {
                Divider().overlay(AppTheme.cardBorder)
                checkInLine(checkIn)
            }
        }
        .padding(16)
        .glassCard()
    }

    private func heroMetric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .microLabel()

            Text(value)
                .font(.system(size: 26, weight: .bold))
                .monospacedDigit()
                .tracking(-0.5)
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Volume vs the typical training day. Down is a lighter day, not an
    /// error — never red.
    private func deltaLine(_ delta: Double) -> some View {
        let direction: (icon: String, color: Color)
        if delta > 1.5 {
            direction = ("arrow.up", AppTheme.success)
        } else if delta < -1.5 {
            direction = ("arrow.down", AppTheme.textSecondary)
        } else {
            direction = ("minus", AppTheme.textSecondary)
        }

        return HStack(spacing: 4) {
            Image(systemName: direction.icon)
                .font(.system(size: 9, weight: .bold))
            Text(AnalyticsFormat.signedPercent(delta) + " vs typical day")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
        .foregroundStyle(direction.color)
    }

    private var prSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("PRS · E1RM")
                .microLabel()

            VStack(spacing: 0) {
                ForEach(Array(scorecard.prs.enumerated()), id: \.element.id) { index, pr in
                    prRow(pr)
                    if index < scorecard.prs.count - 1 {
                        Divider().overlay(AppTheme.cardBorder)
                    }
                }
            }
        }
    }

    private func prRow(_ pr: AnalyticsSnapshot.DayScorecard.PR) -> some View {
        ExerciseTextNavigationLink(exerciseName: pr.exercise, exercises: exercises) {
            HStack(spacing: 8) {
                Text(pr.exercise)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 8)

                Text("\(AnalyticsMath.formattedWeight(pr.e1RM)) lb")
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.primary)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AppTheme.textTertiary)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
    }

    private func checkInLine(_ checkIn: SessionCheckIn) -> some View {
        Text("Felt \(checkIn.overall.label.lowercased())\(checkIn.hadPain ? " · pain flagged" : "")")
            .font(.footnote)
            .foregroundStyle(checkIn.hadPain ? AppTheme.secondary : AppTheme.textSecondary)
    }

    // MARK: Session cards

    private func sessionCard(_ session: WorkoutSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(session.routineName)
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                Text(session.date.formatted(.dateTime.hour().minute()))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.textTertiary)
            }

            VStack(spacing: 0) {
                let names = session.logs.keys.sorted()
                ForEach(Array(names.enumerated()), id: \.element) { index, name in
                    exerciseRow(name: name, sets: session.logs[name] ?? [])
                    if index < names.count - 1 {
                        Divider().overlay(AppTheme.cardBorder)
                    }
                }
            }
        }
        .padding(16)
        .glassCard()
    }

    private func exerciseRow(name: String, sets: [WorkoutSet]) -> some View {
        ExerciseTextNavigationLink(exerciseName: name, exercises: exercises) {
            HStack(spacing: 8) {
                Text(name)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 8)

                Text(AnalyticsMath.setSummary(for: sets))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AppTheme.textTertiary)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
    }
}

// MARK: - Chart 2 · Muscle distribution radar

private struct MuscleDistributionCard: View {
    let sessions: [WorkoutSession]
    let exercises: [Exercise]

    @State private var timeframe: DistributionTimeframe = .month

    var body: some View {
        let distribution = AnalyticsSnapshot.muscleDistribution(
            sessions: sessions,
            resolve: { exercises.resolvedExercise(named: $0) },
            days: timeframe.days
        )

        VStack(alignment: .leading, spacing: 14) {
            Text("MUSCLE DISTRIBUTION")
                .microLabel()

            timeframeMenu

            if distribution.currentGroupCount >= 2 {
                RadarChart(
                    labels: distribution.axes.map(\.group),
                    current: distribution.currentFractions,
                    previous: distribution.previousFractions
                )
                .frame(height: 240)

                legend
            } else {
                Text("Not enough training in this window.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 44)
            }

            tileGrid(distribution)
        }
        .padding(AppTheme.cardPadding)
        .glassCard()
    }

    // MARK: Timeframe

    private var timeframeMenu: some View {
        Menu {
            ForEach(DistributionTimeframe.allCases) { option in
                Button {
                    select(option)
                } label: {
                    if option == timeframe {
                        Label(option.rawValue, systemImage: "checkmark")
                    } else {
                        Text(option.rawValue)
                    }
                }
            }
        } label: {
            HStack {
                Text(timeframe.rawValue)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(AppTheme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            }
        }
    }

    private func select(_ option: DistributionTimeframe) {
        guard option != timeframe else { return }
        withAnimation(.easeInOut(duration: 0.35)) {
            timeframe = option
        }
    }

    // MARK: Legend

    private var legend: some View {
        HStack(spacing: 14) {
            Spacer()
            legendItem(color: AppTheme.primary, label: "Current")
            legendItem(color: AppTheme.textTertiary, label: "Previous")
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
        }
    }

    // MARK: Stat tiles

    private struct TileDelta {
        var text: String
        /// +1 up (green), 0 flat (no arrow), -1 down (neutral — not an error).
        var direction: Int
    }

    private func tileGrid(_ distribution: AnalyticsSnapshot.MuscleDistribution) -> some View {
        let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        return LazyVGrid(columns: columns, spacing: 10) {
            tile(
                label: "Workouts",
                value: "\(distribution.currentWorkouts)",
                delta: countDelta(distribution.currentWorkouts - distribution.previousWorkouts)
            )
            tile(
                label: "Duration",
                value: distribution.currentDurationSeconds.map { AnalyticsMath.durationText(seconds: $0) } ?? "—",
                delta: durationDelta(distribution)
            )
            tile(
                label: "Volume",
                value: AnalyticsMath.compactVolume(distribution.currentVolume) + " lbs",
                delta: volumeDelta(distribution)
            )
            tile(
                label: "Sets",
                value: "\(distribution.currentSets)",
                delta: countDelta(distribution.currentSets - distribution.previousSets)
            )
        }
    }

    private func countDelta(_ diff: Int) -> TileDelta {
        TileDelta(text: "\(abs(diff))", direction: diff.signum())
    }

    private func volumeDelta(_ distribution: AnalyticsSnapshot.MuscleDistribution) -> TileDelta {
        let diff = distribution.currentVolume - distribution.previousVolume
        return TileDelta(
            text: AnalyticsMath.compactVolume(abs(diff)) + " lbs",
            direction: diff > 0 ? 1 : (diff < 0 ? -1 : 0)
        )
    }

    /// Comparable only when both windows recorded time; legacy sessions carry none.
    private func durationDelta(_ distribution: AnalyticsSnapshot.MuscleDistribution) -> TileDelta? {
        guard let current = distribution.currentDurationSeconds,
              let previous = distribution.previousDurationSeconds else { return nil }
        let diff = current - previous
        return TileDelta(
            text: AnalyticsMath.durationText(seconds: abs(diff)),
            direction: diff.signum()
        )
    }

    private func tile(label: String, value: String, delta: TileDelta?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text(label.uppercased())
                    .microLabel()
                Spacer(minLength: 6)
                if let delta {
                    deltaView(delta)
                }
            }

            Text(value)
                .font(.system(size: 26, weight: .bold))
                .monospacedDigit()
                .tracking(-0.5)
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .surfaceCard()
    }

    private func deltaView(_ delta: TileDelta) -> some View {
        HStack(spacing: 3) {
            if delta.direction != 0 {
                Image(systemName: delta.direction > 0 ? "arrow.up" : "arrow.down")
                    .font(.system(size: 8, weight: .bold))
            }
            Text(delta.text)
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
        }
        .foregroundStyle(delta.direction > 0 ? AppTheme.success : AppTheme.textSecondary)
    }
}

// MARK: Radar chart (custom — Swift Charts has no radar mark)

/// Fixed 6-axis spider chart. Axis order is `AnalyticsSnapshot.radarMuscleOrder`,
/// clockwise from top-right; both polygons share one normalization ceiling so
/// current vs previous is a like-for-like comparison.
private struct RadarChart: View {
    let labels: [String]
    let current: [Double]
    let previous: [Double]

    @State private var labelSizes: [Int: CGSize] = [:]

    /// Space reserved beyond the spoke ends for the axis labels.
    private let labelClearance: CGFloat = 26

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = max(0, min(geo.size.width, geo.size.height) / 2 - labelClearance)

            ZStack {
                RadarGridShape(inset: labelClearance)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)

                // Previous period — dim, behind.
                RadarPolygonShape(fractions: RadarVector(previous), inset: labelClearance)
                    .fill(AppTheme.textTertiary.opacity(0.14))
                RadarPolygonShape(fractions: RadarVector(previous), inset: labelClearance)
                    .stroke(AppTheme.textTertiary, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))

                // Current period — volt, on top.
                RadarPolygonShape(fractions: RadarVector(current), inset: labelClearance)
                    .fill(AppTheme.primary.opacity(0.22))
                RadarPolygonShape(fractions: RadarVector(current), inset: labelClearance)
                    .stroke(AppTheme.primary, style: StrokeStyle(lineWidth: 2, lineJoin: .round))

                Circle()
                    .fill(AppTheme.textTertiary)
                    .frame(width: 4, height: 4)
                    .position(center)

                ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                    Text(label)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize()
                        .onGeometryChange(for: CGSize.self) { proxy in
                            proxy.size
                        } action: { size in
                            labelSizes[index] = size
                        }
                        .position(labelPosition(index, center: center, radius: radius))
                }
            }
        }
    }

    /// Centers each label just past its spoke end, pushed outward along the
    /// axis by half its own size so the near edge keeps a constant gap.
    private func labelPosition(_ index: Int, center: CGPoint, radius: CGFloat) -> CGPoint {
        let angle = RadarGeometry.angle(forAxis: index)
        let unit = CGPoint(x: cos(angle), y: sin(angle))
        let size = labelSizes[index] ?? .zero
        let base = radius + 8
        return CGPoint(
            x: center.x + unit.x * base + unit.x * size.width / 2,
            y: center.y + unit.y * base + unit.y * size.height / 2
        )
    }
}

private enum RadarGeometry {
    static let axisCount = 6

    /// Screen-space angle (y down) for each axis, clockwise from top-right:
    /// -60° Chest, 0° Core, 60° Shoulders, 120° Arms, 180° Legs, 240° Back.
    static func angle(forAxis index: Int) -> CGFloat {
        CGFloat(Double(index) * 60 - 60) * .pi / 180
    }

    static func point(center: CGPoint, radius: CGFloat, axis: Int, fraction: Double) -> CGPoint {
        let angle = angle(forAxis: axis)
        return CGPoint(
            x: center.x + radius * CGFloat(fraction) * cos(angle),
            y: center.y + radius * CGFloat(fraction) * sin(angle)
        )
    }
}

/// Hairline spokes plus the outer boundary hexagon.
private struct RadarGridShape: Shape {
    var inset: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = max(0, min(rect.width, rect.height) / 2 - inset)
        var path = Path()

        for axis in 0..<RadarGeometry.axisCount {
            path.move(to: center)
            path.addLine(to: RadarGeometry.point(center: center, radius: radius, axis: axis, fraction: 1))
        }

        for axis in 0..<RadarGeometry.axisCount {
            let point = RadarGeometry.point(center: center, radius: radius, axis: axis, fraction: 1)
            if axis == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()

        return path
    }
}

/// One period's polygon. Animatable so timeframe switches morph the shape.
private struct RadarPolygonShape: Shape {
    var fractions: RadarVector
    var inset: CGFloat

    var animatableData: RadarVector {
        get { fractions }
        set { fractions = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = max(0, min(rect.width, rect.height) / 2 - inset)
        var path = Path()
        let values = fractions.values
        guard values.count == RadarGeometry.axisCount else { return path }

        for (axis, fraction) in values.enumerated() {
            let point = RadarGeometry.point(center: center, radius: radius, axis: axis, fraction: fraction)
            if axis == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

/// Fixed-length value vector so a radar polygon can interpolate per-axis.
private struct RadarVector: VectorArithmetic {
    var values: [Double]

    init(_ values: [Double]) {
        self.values = values
    }

    static var zero: RadarVector {
        RadarVector(Array(repeating: 0, count: RadarGeometry.axisCount))
    }

    static func + (lhs: RadarVector, rhs: RadarVector) -> RadarVector {
        RadarVector(zip(lhs.padded, rhs.padded).map(+))
    }

    static func - (lhs: RadarVector, rhs: RadarVector) -> RadarVector {
        RadarVector(zip(lhs.padded, rhs.padded).map(-))
    }

    mutating func scale(by rhs: Double) {
        values = values.map { $0 * rhs }
    }

    var magnitudeSquared: Double {
        values.reduce(0) { $0 + $1 * $1 }
    }

    private var padded: [Double] {
        values.count >= RadarGeometry.axisCount
            ? values
            : values + Array(repeating: 0, count: RadarGeometry.axisCount - values.count)
    }
}

// MARK: - Chart 3 · Muscle distribution donut

private struct MuscleDonutCard: View {
    let donut: AnalyticsSnapshot.DonutModel?
    let insight: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("MUSCLE SPLIT")
                .microLabel()

            if let donut {
                ring(donut)
                legend(donut)
                if let insight {
                    AnalyticsInsightLine(text: insight)
                }
            } else {
                Text("No sets in the last 30 days.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textTertiary)
                    .padding(.vertical, 24)
            }
        }
        .padding(AppTheme.cardPadding)
        .glassCard()
    }

    private func ring(_ donut: AnalyticsSnapshot.DonutModel) -> some View {
        ZStack {
            Chart(donut.segments) { segment in
                SectorMark(
                    angle: .value("Sets", segment.sets),
                    innerRadius: .ratio(0.7),
                    angularInset: 1.4
                )
                .cornerRadius(3)
                .foregroundStyle(MusclePalette.color(for: segment.group))
            }

            VStack(spacing: 3) {
                Text("\(donut.totalSets)")
                    .font(.system(size: 34, weight: .bold))
                    .monospacedDigit()
                    .tracking(-1)
                    .foregroundStyle(AppTheme.textPrimary)
                Text("SETS · 30D")
                    .microLabel()
            }
        }
        .frame(height: 200)
        .frame(maxWidth: .infinity)
    }

    private func legend(_ donut: AnalyticsSnapshot.DonutModel) -> some View {
        VStack(spacing: 9) {
            ForEach(donut.segments) { segment in
                HStack(spacing: 9) {
                    Circle()
                        .fill(MusclePalette.color(for: segment.group))
                        .frame(width: 8, height: 8)

                    Text(segment.group)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(AppTheme.textPrimary)

                    Spacer(minLength: 8)

                    Text("\(segment.sets) sets")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.textTertiary)

                    Text("\(Int((segment.share * 100).rounded()))%")
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.textPrimary)
                        .frame(width: 40, alignment: .trailing)
                }
            }
        }
    }
}

// MARK: - Rep-zone palette
//
// Ordinal neutral ramp across the ordered rep zones (strength -> endurance).
// Magnitude carried by lightness only — no hue spent on an ordered scale.
private enum RepPalette {
    static func zoneColor(_ zone: RepZone) -> Color {
        switch zone {
        case .strength: return AppTheme.textTertiary
        case .hypertrophy: return AppTheme.textSecondary
        case .endurance: return AppTheme.textPrimary
        }
    }
}
