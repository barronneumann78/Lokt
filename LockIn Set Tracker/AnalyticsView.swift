import SwiftUI
import Charts
import Combine

/// The Progress screen: headline tiles, the exercise progression line, the
/// PR board, the muscle-split donut, the training calendar, the muscle
/// distribution radar and rep ranges — all derived once per data change in
/// `AnalyticsSnapshot`. Each chart carries its own small controls (exercise,
/// metric, window) persisted through `@AppStorage` (`AnalyticsControls`) so
/// they survive relaunch.
struct AnalyticsView: View {
    @EnvironmentObject private var store: WorkoutStore
    @EnvironmentObject private var exerciseStore: ExerciseStore
    @State private var snapshot: AnalyticsSnapshot = .empty
    /// Shared with `ProgressionCard`: a PR row tap writes it, the chart reads it.
    @AppStorage(AnalyticsControls.progressionExerciseKey) private var progressionExercise = ""
    /// Owned here because the PRs headline tile follows the PR board's window.
    @AppStorage(AnalyticsControls.prWindowKey) private var prWindow = AnalyticsControls.defaultPRWindow

    private enum Anchor: Hashable {
        case progression
    }

    var body: some View {
        ZStack {
            AppBackground()

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        header

                        if snapshot.totalSessions == 0 {
                            emptyState
                        } else {
                            if let headline = snapshot.headline {
                                headlineStrip(headline)
                            }
                            ProgressionCard(snapshot: snapshot)
                                .id(Anchor.progression)
                            PRCard(
                                records: snapshot.prRecords,
                                window: $prWindow,
                                chartable: chartableExercises
                            ) { exercise in
                                drillDown(to: exercise, proxy: proxy)
                            }
                            MuscleDonutCard(snapshot: snapshot)
                            CalendarCard(
                                snapshot: snapshot,
                                exercises: exerciseStore.exercises,
                                routineOrders: routineOrders
                            )
                            MuscleDistributionCard(snapshot: snapshot)
                            if !snapshot.repBins.isEmpty {
                                repRangeCard
                            }
                            ExerciseOrderCard(profiles: snapshot.exerciseOrderProfiles)
                        }
                    }
                    .padding(.horizontal, AppTheme.screenPadding)
                    .padding(.vertical, 20)
                }
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
        .onReceive(store.$routines) { _ in
            // Routine order is the position fallback for legacy sessions.
            rebuild(with: store.sessions)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Progress")
                .font(.system(size: 26, weight: .bold))
                .tracking(-0.3)
                .foregroundStyle(AppTheme.textPrimary)

            if snapshot.totalSessions > 0 {
                Text("\(snapshot.totalSessions) sessions logged")
                    .font(.system(size: 13))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(.bottom, 2)
    }

    private var routineOrders: [UUID: [String]] {
        ExercisePositionLogic.routineOrders(from: store.routines)
    }

    /// Lifts the progression chart can show — the PR rows that drill down.
    private var chartableExercises: Set<String> {
        Set(snapshot.progressionPickerOptions.map(\.name))
    }

    /// PRs · e1RM: records that beat an earlier one, in the PR board's window.
    private var prCount: Int {
        AnalyticsSnapshot.prRecords(snapshot.prRecords, in: prWindow, now: Date(), calendar: .current)
            .filter(\.isPR)
            .count
    }

    private func rebuild(with sessions: [WorkoutSession]) {
        let exercises = exerciseStore.exercises
        snapshot = AnalyticsSnapshot.build(
            sessions: sessions,
            resolve: { exercises.resolvedExercise(named: $0) },
            routineOrders: routineOrders
        )
    }

    /// One tap on a PR row: the progression chart switches to that lift and
    /// scrolls into view.
    private func drillDown(to exercise: String, proxy: ScrollViewProxy) {
        progressionExercise = exercise
        withAnimation(.easeInOut(duration: 0.35)) {
            proxy.scrollTo(Anchor.progression, anchor: .top)
        }
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
        HStack(spacing: 8) {
            statTile(label: "VOLUME · 7D", value: AnalyticsFormat.compact(headline.volumeLast7Days))
            statTile(label: "SETS · 30D", value: "\(headline.setsLast30Days)")
            statTile(label: "PRs · e1RM", value: "\(prCount)", accent: true)
        }
    }

    /// Concept tile: 16pt card, 10pt micro label, 22pt mono number — the PR
    /// count in the accent. The three keep the phase-1 hero glow.
    private func statTile(label: String, value: String, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(AppTheme.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Text(value)
                .font(.system(size: 22, weight: .bold))
                .monospacedDigit()
                .tracking(-0.5)
                .foregroundStyle(accent ? AppTheme.primary : AppTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
                .heroGlow()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .glassCard(cornerRadius: 16)
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

// MARK: - Card controls

/// Window switch: small text tabs ("30d  90d  All"), the selected one bright.
/// Windows without enough data (`enabled`) are dimmed and inert.
private struct WindowSwitch: View {
    @Binding var selection: AnalyticsWindow
    let options: [AnalyticsWindow]
    var enabled: Set<AnalyticsWindow>? = nil

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { window in
                let isEnabled = enabled?.contains(window) ?? true
                let isOn = window == selection
                Button {
                    guard isEnabled, !isOn else { return }
                    withAnimation(.easeInOut(duration: 0.3)) {
                        selection = window
                    }
                } label: {
                    Text(window.label)
                        .font(.caption2.weight(isOn ? .bold : .semibold))
                        .monospacedDigit()
                        .foregroundStyle(isOn ? AppTheme.textPrimary : AppTheme.textTertiary)
                        .opacity(isEnabled ? 1 : 0.4)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled)
            }
        }
    }
}

/// Metric switch: three hairline capsules, the selected one accent-tinted
/// (`accentChipFill` + `accentHairline`) — the one accent chrome in the card.
private struct MetricSwitch: View {
    @Binding var selection: ProgressionMetric

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ProgressionMetric.allCases) { metric in
                let isOn = metric == selection
                Button {
                    guard !isOn else { return }
                    withAnimation(.easeInOut(duration: 0.3)) {
                        selection = metric
                    }
                } label: {
                    Text(metric.label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(isOn ? AppTheme.accent : AppTheme.textSecondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(isOn ? AppTheme.accentChipFill : Color.clear)
                        .clipShape(Capsule())
                        .overlay {
                            Capsule()
                                .stroke(isOn ? AppTheme.accentHairline : AppTheme.cardBorder, lineWidth: 1)
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
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

/// Concept: accent line over a soft accent fill, a hollow accent dot on the
/// latest point, a hairline baseline, month labels bottom-left and the
/// latest value bottom-right. Everything shown derives from the snapshot and
/// three persisted picks (exercise / metric / window); the picker lists lifts
/// with at least two e1RM points, most-trained first.
private struct ProgressionCard: View {
    let snapshot: AnalyticsSnapshot

    private typealias MetricPoint = AnalyticsSnapshot.MetricPoint

    @AppStorage(AnalyticsControls.progressionExerciseKey) private var storedExercise = ""
    @AppStorage(AnalyticsControls.progressionMetricKey) private var metric = AnalyticsControls.defaultMetric
    @AppStorage(AnalyticsControls.progressionWindowKey) private var storedWindow = AnalyticsControls.defaultProgressionWindow
    @State private var scrub: MetricPoint?
    @State private var tooltipSize: CGSize = .zero

    private var calendar: Calendar { .current }

    private var options: [AnalyticsSnapshot.ExerciseOption] {
        snapshot.progressionPickerOptions
    }

    private var exercise: String? {
        AnalyticsSnapshot.progressionExercise(stored: storedExercise, options: options)
    }

    private var series: [AnalyticsSnapshot.ProgressionPoint] {
        exercise.flatMap { snapshot.progression[$0] } ?? []
    }

    private var enabledWindows: Set<AnalyticsWindow> {
        AnalyticsSnapshot.enabledWindows(series, metric: metric, now: Date(), calendar: calendar)
    }

    private var window: AnalyticsWindow {
        AnalyticsSnapshot.effectiveWindow(stored: storedWindow, enabled: enabledWindows)
    }

    private var points: [MetricPoint] {
        AnalyticsSnapshot.progressionPoints(series, metric: metric, window: window, now: Date(), calendar: calendar)
    }

    /// Shows the window actually drawn; a tap stores the pick.
    private var windowBinding: Binding<AnalyticsWindow> {
        Binding(get: { window }, set: { storedWindow = $0 })
    }

    var body: some View {
        let points = points

        VStack(alignment: .leading, spacing: 12) {
            if let exercise {
                headerRow(exercise)
                chart(points)
                footerRow(points)
                controls
            } else {
                placeholder
            }
        }
        .padding(AppTheme.cardPadding)
        .glassCard()
        .onChange(of: points) { _, _ in scrub = nil }
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

    // MARK: Header, footer, controls

    private func headerRow(_ exercise: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("PROGRESSION")
                .microLabel()

            Spacer(minLength: 12)

            Menu {
                ForEach(options) { option in
                    Button {
                        storedExercise = option.name
                    } label: {
                        if option.name == exercise {
                            Label(option.name, systemImage: "checkmark")
                        } else {
                            Text(option.name)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("\(exercise) · \(metric.label)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(AppTheme.textTertiary)
                }
            }
        }
    }

    private func footerRow(_ points: [MetricPoint]) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(timeline(points))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(AppTheme.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 12)

            Text(latestText(points))
                .font(.system(size: 15, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(AppTheme.primary)
                .contentTransition(.numericText())
        }
    }

    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                MetricSwitch(selection: $metric)
                Spacer(minLength: 8)
                WindowSwitch(selection: windowBinding, options: AnalyticsWindow.progression, enabled: enabledWindows)
            }
            VStack(alignment: .leading, spacing: 10) {
                MetricSwitch(selection: $metric)
                WindowSwitch(selection: windowBinding, options: AnalyticsWindow.progression, enabled: enabledWindows)
            }
        }
    }

    private func timeline(_ points: [MetricPoint]) -> String {
        guard let first = points.first, let last = points.last else { return "" }
        return AnalyticsSnapshot.timelineLabels(from: first.date, to: last.date, calendar: calendar)
            .joined(separator: " · ")
    }

    private func latestText(_ points: [MetricPoint]) -> String {
        guard let latest = points.last else { return "—" }
        return AnalyticsFormat.compact(latest.value) + " lb"
    }

    // MARK: Chart

    private func yDomain(_ points: [MetricPoint]) -> ClosedRange<Double> {
        let values = points.map(\.value)
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        let span = max(high - low, max(high * 0.05, 1))
        let lower = max(0, low - span * 0.18)
        // Generous headroom doubles as the scrub tooltip's landing zone.
        let upper = high + span * 0.42
        return lower...upper
    }

    private func chart(_ points: [MetricPoint]) -> some View {
        Chart {
            ForEach(points) { point in
                AreaMark(
                    x: .value("Date", point.date),
                    y: .value(metric.label, point.value)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(AppTheme.chartFill)

                LineMark(
                    x: .value("Date", point.date),
                    y: .value(metric.label, point.value)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(AppTheme.primary)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }

            // Latest value: a hollow accent dot on the card surface.
            if let last = points.last {
                PointMark(
                    x: .value("Date", last.date),
                    y: .value(metric.label, last.value)
                )
                .symbol {
                    Circle()
                        .fill(AppTheme.card)
                        .overlay {
                            Circle().stroke(AppTheme.primary, lineWidth: 2.5)
                        }
                        .frame(width: 10, height: 10)
                }
            }
        }
        .chartYScale(domain: yDomain(points))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartPlotStyle { plot in
            plot.overlay(alignment: .bottom) {
                Rectangle()
                    .fill(AppTheme.cardBorder)
                    .frame(height: 1)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(scrubGesture(points, proxy: proxy, geo: geo))

                if let scrub {
                    scrubIndicator(for: scrub, proxy: proxy, geo: geo)
                }
            }
        }
        .frame(height: 150)
        .animation(.easeInOut(duration: 0.35), value: points)
    }

    private func scrubGesture(_ points: [MetricPoint], proxy: ChartProxy, geo: GeometryProxy) -> some Gesture {
        LongPressGesture(minimumDuration: 0.15)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
            .onChanged { value in
                guard case .second(true, let drag) = value, let drag else { return }
                updateScrub(points, at: drag.location, proxy: proxy, geo: geo)
            }
            .onEnded { _ in
                withAnimation(.easeOut(duration: 0.18)) { scrub = nil }
            }
    }

    private func updateScrub(_ points: [MetricPoint], at location: CGPoint, proxy: ChartProxy, geo: GeometryProxy) {
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

// MARK: - PR board

/// "Exercise …… 225 lb ↑ 10": standing e1RM records set inside the window,
/// most recent first. The gain over the previous record is green; a
/// first-ever record (nothing to beat) shows its value plain. Tapping a row
/// whose lift the progression chart can draw drills down to it.
private struct PRCard: View {
    let records: [AnalyticsSnapshot.PRRecord]
    @Binding var window: AnalyticsWindow
    let chartable: Set<String>
    let onSelect: (String) -> Void

    @State private var expanded = false

    private static let foldCount = 6

    var body: some View {
        let rows = AnalyticsSnapshot.prRecords(records, in: window, now: Date(), calendar: .current)
        let visible = expanded ? rows : Array(rows.prefix(Self.foldCount))

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("PRs · e1RM")
                    .microLabel()
                Spacer()
                WindowSwitch(selection: $window, options: AnalyticsWindow.prs)
            }

            if rows.isEmpty {
                Text(emptyText)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.textTertiary)
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, record in
                        row(record)
                        if index < visible.count - 1 {
                            Divider().overlay(AppTheme.cardBorder)
                        }
                    }
                }

                if rows.count > Self.foldCount {
                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            expanded.toggle()
                        }
                    } label: {
                        Text(expanded ? "Show less" : "+ \(rows.count - Self.foldCount) more")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(AppTheme.textSecondary)
                            .padding(.top, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(AppTheme.cardPadding)
        .glassCard()
    }

    private var emptyText: String {
        if let days = window.days {
            return "No PRs in the last \(days) days."
        }
        return "No PRs yet."
    }

    private func row(_ record: AnalyticsSnapshot.PRRecord) -> some View {
        let canDrill = chartable.contains(record.exercise)

        return Button {
            onSelect(record.exercise)
        } label: {
            HStack(spacing: 8) {
                Text(record.exercise)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 8)

                Text("\(AnalyticsMath.formattedWeight(record.e1RM)) lb")
                    .font(.system(size: 14, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(record.delta == nil ? AppTheme.textSecondary : AppTheme.textPrimary)

                if let delta = record.delta {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 9, weight: .bold))
                        Text(AnalyticsMath.formattedWeight(delta))
                            .font(.system(size: 13, weight: .semibold))
                            .monospacedDigit()
                    }
                    .foregroundStyle(AppTheme.success)
                }
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canDrill)
    }
}

// MARK: - Chart 4 · Training calendar

private struct CalendarCard: View {
    let snapshot: AnalyticsSnapshot
    let exercises: [Exercise]
    var routineOrders: [UUID: [String]] = [:]

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
                    resolve: { exercises.resolvedExercise(named: $0) },
                    routineOrders: routineOrders
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
    /// Advanced analytics on → PR rows carry their position in the session.
    @AppStorage(AnalyticsAdvanced.storageKey) private var showPositions = false

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

                if showPositions, let position = pr.position {
                    Text("\(ExercisePositionLogic.ordinal(position)) in session")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.textTertiary)
                        .fixedSize()
                }

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

/// Kept from the previous layout, same card vocabulary: micro label, the
/// window switch in the header (30d / 90d / All — precomputed per window in
/// the snapshot), the radar, the stat tiles. "All" has no previous window,
/// so its previous polygon, legend and deltas are hidden.
private struct MuscleDistributionCard: View {
    let snapshot: AnalyticsSnapshot

    @AppStorage(AnalyticsControls.distributionWindowKey) private var window = AnalyticsControls.defaultDistributionWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("MUSCLE DISTRIBUTION")
                    .microLabel()
                Spacer()
                WindowSwitch(selection: $window, options: AnalyticsWindow.muscle)
            }

            if let distribution = snapshot.distributions[window] {
                if distribution.currentGroupCount >= 2 {
                    RadarChart(
                        labels: distribution.axes.map(\.group),
                        current: distribution.currentFractions,
                        previous: distribution.hasPrevious ? distribution.previousFractions : nil
                    )
                    .frame(height: 240)

                    if distribution.hasPrevious {
                        legend
                    }
                } else {
                    Text("Not enough training in this window.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 44)
                }

                tileGrid(distribution)
            }
        }
        .padding(AppTheme.cardPadding)
        .glassCard()
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
        let compare = distribution.hasPrevious
        return LazyVGrid(columns: columns, spacing: 10) {
            tile(
                label: "Workouts",
                value: "\(distribution.currentWorkouts)",
                delta: compare ? countDelta(distribution.currentWorkouts - distribution.previousWorkouts) : nil
            )
            tile(
                label: "Duration",
                value: distribution.currentDurationSeconds.map { AnalyticsMath.durationText(seconds: $0) } ?? "—",
                delta: compare ? durationDelta(distribution) : nil
            )
            tile(
                label: "Volume",
                value: AnalyticsMath.compactVolume(distribution.currentVolume) + " lbs",
                delta: compare ? volumeDelta(distribution) : nil
            )
            tile(
                label: "Sets",
                value: "\(distribution.currentSets)",
                delta: compare ? countDelta(distribution.currentSets - distribution.previousSets) : nil
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
                .contentTransition(.numericText())
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
    /// Nil for the "All" window — nothing to compare against.
    let previous: [Double]?

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
                if let previous {
                    RadarPolygonShape(fractions: RadarVector(previous), inset: labelClearance)
                        .fill(AppTheme.textTertiary.opacity(0.14))
                    RadarPolygonShape(fractions: RadarVector(previous), inset: labelClearance)
                        .stroke(AppTheme.textTertiary, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                }

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

// MARK: - Chart 3 · Muscle split donut

/// Concept: the donut on the left with the set count (22pt mono) and
/// "SETS · 30D" in its center, the legend on the right — color dot, group,
/// share. The window switch (30d / 90d / All) picks one of the snapshot's
/// precomputed donuts and relabels the center.
private struct MuscleDonutCard: View {
    let snapshot: AnalyticsSnapshot

    @AppStorage(AnalyticsControls.splitWindowKey) private var window = AnalyticsControls.defaultSplitWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("MUSCLE SPLIT")
                    .microLabel()
                Spacer()
                WindowSwitch(selection: $window, options: AnalyticsWindow.muscle)
            }

            if let donut = snapshot.donuts[window] {
                HStack(alignment: .center, spacing: 18) {
                    ring(donut)
                    legend(donut)
                }
            } else {
                Text(emptyText)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.textTertiary)
                    .padding(.vertical, 24)
            }
        }
        .padding(AppTheme.cardPadding)
        .glassCard()
    }

    private var emptyText: String {
        if let days = window.days {
            return "No sets in the last \(days) days."
        }
        return "No sets logged yet."
    }

    private func ring(_ donut: AnalyticsSnapshot.DonutModel) -> some View {
        ZStack {
            Chart(donut.segments) { segment in
                SectorMark(
                    angle: .value("Sets", segment.sets),
                    innerRadius: .ratio(0.74),
                    angularInset: 1.4
                )
                .cornerRadius(3)
                .foregroundStyle(MusclePalette.color(for: segment.group))
            }

            VStack(spacing: 2) {
                Text("\(donut.totalSets)")
                    .font(.system(size: 22, weight: .bold))
                    .monospacedDigit()
                    .tracking(-0.5)
                    .foregroundStyle(AppTheme.textPrimary)
                    .contentTransition(.numericText())
                Text("SETS · \(window.suffix)")
                    .font(.system(size: 8, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(AppTheme.textTertiary)
            }
        }
        .frame(width: 120, height: 120)
    }

    private func legend(_ donut: AnalyticsSnapshot.DonutModel) -> some View {
        VStack(spacing: 7) {
            ForEach(donut.segments) { segment in
                HStack(spacing: 8) {
                    Circle()
                        .fill(MusclePalette.color(for: segment.group))
                        .frame(width: 8, height: 8)

                    Text(segment.group)
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text("\(Int((segment.share * 100).rounded()))%")
                        .font(.system(size: 13))
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Advanced · Exercise order

/// The one switch for the advanced layer. Off by default — exercise-order
/// analytics are for people who want them. The same flag shows the position
/// tag on PR rows in the day sheet.
private enum AnalyticsAdvanced {
    static let storageKey = "analyticsAdvancedV1"
}

/// Position-in-session analytics: where each exercise usually sits and how
/// its best e1RM splits between early (1–2) and late (3+) slots — the fatigue
/// effect as numbers. A collapsed disclosure at the bottom of Analytics.
private struct ExerciseOrderCard: View {
    let profiles: [ExercisePositionLogic.ExerciseProfile]

    @AppStorage(AnalyticsAdvanced.storageKey) private var isOn = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    isOn.toggle()
                }
            } label: {
                HStack {
                    Text("ADVANCED")
                        .microLabel()
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .rotationEffect(.degrees(isOn ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOn {
                Text("EXERCISE ORDER · BEST E1RM")
                    .microLabel()

                if profiles.isEmpty {
                    Text("Needs \(ExercisePositionLogic.minimumSessions)+ sessions of an exercise.")
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.textTertiary)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(profiles.enumerated()), id: \.element.id) { index, profile in
                            row(profile)
                            if index < profiles.count - 1 {
                                Divider().overlay(AppTheme.cardBorder)
                            }
                        }
                    }
                }
            }
        }
        .padding(AppTheme.cardPadding)
        .glassCard()
    }

    private func row(_ profile: ExercisePositionLogic.ExerciseProfile) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(profile.exercise)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 8)

                Text("usually \(ExercisePositionLogic.ordinal(profile.typicalPosition))")
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.textPrimary)
                    .fixedSize()
            }

            HStack(alignment: .firstTextBaseline, spacing: 14) {
                bucket(label: "1–2", best: profile.earlyBest, count: profile.earlyCount)
                bucket(label: "3+", best: profile.lateBest, count: profile.lateCount)

                if let delta = profile.lateVsEarlyPercent {
                    Text(AnalyticsFormat.signedPercent(delta))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.textSecondary)
                }

                Spacer(minLength: 8)

                if let pr = profile.prPosition {
                    Text("PR \(ExercisePositionLogic.ordinal(pr))")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.textTertiary)
                        .fixedSize()
                }
            }
        }
        .padding(.vertical, 10)
    }

    /// "1–2  245 lb (4)" — the bucket's best e1RM and how many sessions fed it.
    private func bucket(label: String, best: Double?, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .tracking(0.5)
                .monospacedDigit()
                .foregroundStyle(AppTheme.textTertiary)

            Text(best.map { "\(AnalyticsMath.formattedWeight($0)) lb" } ?? "—")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(AppTheme.textSecondary)

            if count > 0 {
                Text("(\(count))")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.textTertiary)
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
