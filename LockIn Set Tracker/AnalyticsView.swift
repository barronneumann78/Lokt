import SwiftUI
import Charts
import Combine

/// Insight-dense analytics: training consistency, estimated-1RM trends with PR
/// markers, muscle-group balance and rep-range distribution — all derived once
/// per data change in `AnalyticsSnapshot` (see AnalyticsModels.swift).
struct AnalyticsView: View {
    @EnvironmentObject private var store: WorkoutStore
    @StateObject private var exerciseStore = ExerciseStore()
    @State private var snapshot: AnalyticsSnapshot = .empty

    private let secondaryText = Color.white.opacity(0.84)
    private let mutedText = Color.white.opacity(0.62)

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    if snapshot.totalSessions == 0 {
                        emptyState
                    } else {
                        if let headline = snapshot.headline {
                            headlineStrip(headline)
                        }
                        consistencyCard
                        strengthCard
                        if !snapshot.muscleShares.isEmpty {
                            balanceCard
                        }
                        if !snapshot.repBins.isEmpty {
                            repRangeCard
                        }
                    }
                }
                .padding(.horizontal, AppTheme.screenPadding)
                .padding(.vertical, 20)
            }
        }
        .navigationTitle("Analytics")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Pick up sessions written directly by screens not yet on the store.
            store.reload()
        }
        .onReceive(store.$sessions) { sessions in
            rebuild(with: sessions)
        }
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

            Text("Log a workout and Lokt will map your consistency, strength gains and muscle balance here.")
                .font(.subheadline)
                .foregroundStyle(secondaryText)
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
                    value: compactNumber(headline.thisWeekVolume),
                    detail: "lbs this week",
                    delta: headline.volumeDeltaPercent.map { delta in
                        (text: signedPercent(delta) + " vs avg", isPositive: delta >= 0)
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
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.7)
                .foregroundStyle(mutedText)

            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if let delta {
                Text(delta.text)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(delta.isPositive ? AppTheme.success : AppTheme.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(mutedText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .surfaceCard(cornerRadius: AppTheme.controlCornerRadius)
    }

    // MARK: - Consistency heatmap

    private var consistencyCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(
                title: "Consistency",
                caption: "Sessions over the last \(AnalyticsSnapshot.heatmapWeekCount) weeks"
            )

            ConsistencyHeatmapGrid(model: snapshot.heatmap)

            HStack(alignment: .center) {
                if let insight = snapshot.heatmapInsight {
                    insightLine(insight)
                }
                Spacer(minLength: 12)
                heatmapLegend
            }
        }
        .padding(16)
        .glassCard()
    }

    private var heatmapLegend: some View {
        HStack(spacing: 3) {
            Text("Less")
                .font(.system(size: 9))
                .foregroundStyle(mutedText)
            ForEach(0..<5) { level in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(AnalyticsPalette.heatLevel(level))
                    .frame(width: 8, height: 8)
            }
            Text("More")
                .font(.system(size: 9))
                .foregroundStyle(mutedText)
        }
    }

    // MARK: - Strength trends

    private var strengthCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(
                title: "Strength trend",
                caption: "Estimated 1RM from your best set — orange dots mark new PRs"
            )

            if snapshot.trends.isEmpty {
                Text("Log an exercise three or more times with weight and reps to unlock strength trends.")
                    .font(.footnote)
                    .foregroundStyle(mutedText)
                    .padding(.vertical, 16)
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(snapshot.trends) { trend in
                        trendPanel(trend)
                    }
                }

                if let insight = snapshot.trendInsight {
                    insightLine(insight)
                }
            }
        }
        .padding(AppTheme.cardPadding)
        .glassCard()
    }

    private func trendPanel(_ trend: AnalyticsSnapshot.ExerciseTrend) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                ExerciseTextNavigationLink(exerciseName: trend.name, exercises: exerciseStore.exercises) {
                    HStack(spacing: 4) {
                        Text(trend.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(mutedText)
                    }
                }

                Spacer(minLength: 8)

                Text("\(Int(trend.currentE1RM.rounded())) lbs")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.textPrimary)

                if let delta = trend.windowDeltaPercent {
                    deltaBadge(delta)
                }
            }

            trendChart(trend)

            if let first = trend.points.first, let last = trend.points.last {
                HStack {
                    Text(shortDate(first.date))
                    Spacer()
                    Text(shortDate(last.date))
                }
                .font(.system(size: 9))
                .foregroundStyle(mutedText)
            }
        }
    }

    private func trendChart(_ trend: AnalyticsSnapshot.ExerciseTrend) -> some View {
        let values = trend.points.map(\.e1RM)
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        let pad = max((high - low) * 0.18, 2)

        return Chart(trend.points) { point in
            AreaMark(
                x: .value("Date", point.date),
                y: .value("e1RM", point.e1RM)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(
                LinearGradient(
                    colors: [AppTheme.primary.opacity(0.16), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            LineMark(
                x: .value("Date", point.date),
                y: .value("e1RM", point.e1RM)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(AppTheme.primary)
            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

            if point.isPR {
                // Surface ring under the PR dot keeps it legible on the line.
                PointMark(
                    x: .value("Date", point.date),
                    y: .value("e1RM", point.e1RM)
                )
                .symbolSize(96)
                .foregroundStyle(AppTheme.card)

                PointMark(
                    x: .value("Date", point.date),
                    y: .value("e1RM", point.e1RM)
                )
                .symbolSize(42)
                .foregroundStyle(AppTheme.secondary)
            }
        }
        .chartYScale(domain: (low - pad)...(high + pad))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 64)
    }

    private func deltaBadge(_ delta: Double) -> some View {
        let direction: (icon: String, color: Color)
        if delta > 1.5 {
            direction = ("arrow.up.right", AppTheme.success)
        } else if delta < -1.5 {
            direction = ("arrow.down.right", AppTheme.secondary)
        } else {
            direction = ("minus", AppTheme.textSecondary)
        }

        return HStack(spacing: 3) {
            Image(systemName: direction.icon)
                .font(.system(size: 8, weight: .bold))
            Text(signedPercent(delta))
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(direction.color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(direction.color.opacity(0.14))
        .clipShape(Capsule())
    }

    // MARK: - Muscle balance

    private var balanceCard: some View {
        let showDeltas = snapshot.muscleShares.contains { $0.deltaPoints != nil }
        let caption: String
        if snapshot.muscleWindowIsRecent {
            caption = showDeltas
                ? "Share of sets — last 4 weeks vs the 4 before"
                : "Share of sets — last 4 weeks"
        } else {
            caption = "Share of sets — all time"
        }

        return VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title: "Muscle balance", caption: caption)

            VStack(spacing: 10) {
                ForEach(displayedMuscleShares) { share in
                    muscleRow(share, showDeltas: showDeltas)
                }
            }

            if let insight = snapshot.balanceInsight {
                insightLine(insight)
            }
        }
        .padding(AppTheme.cardPadding)
        .glassCard()
    }

    /// Cap the ranked list at 7 rows; anything past that folds into "Other".
    private var displayedMuscleShares: [AnalyticsSnapshot.MuscleShare] {
        let shares = snapshot.muscleShares
        guard shares.count > 7 else { return shares }

        var kept = Array(shares.prefix(6))
        let tail = shares.dropFirst(6)
        let tailSets = tail.reduce(0) { $0 + $1.sets }
        let tailShare = tail.reduce(0.0) { $0 + $1.share }

        if let otherIndex = kept.firstIndex(where: { $0.group == MuscleGroup.other.rawValue }) {
            kept[otherIndex].sets += tailSets
            kept[otherIndex].share += tailShare
            kept[otherIndex].deltaPoints = nil
        } else {
            kept.append(AnalyticsSnapshot.MuscleShare(
                group: MuscleGroup.other.rawValue,
                sets: tailSets,
                share: tailShare,
                deltaPoints: nil
            ))
        }
        return kept
    }

    private func muscleRow(_ share: AnalyticsSnapshot.MuscleShare, showDeltas: Bool) -> some View {
        HStack(spacing: 10) {
            Text(share.group)
                .font(.footnote.weight(.medium))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: 82, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.white.opacity(0.05))

                    UnevenRoundedRectangle(
                        cornerRadii: RectangleCornerRadii(
                            topLeading: 1,
                            bottomLeading: 1,
                            bottomTrailing: 4,
                            topTrailing: 4
                        ),
                        style: .continuous
                    )
                    .fill(AppTheme.primary)
                    .frame(width: max(3, geo.size.width * share.share))
                }
            }
            .frame(height: 10)

            Text("\(Int((share.share * 100).rounded()))%")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(AppTheme.textPrimary)
                .frame(width: 38, alignment: .trailing)

            if showDeltas {
                muscleDelta(share.deltaPoints)
                    .frame(width: 32, alignment: .trailing)
            }
        }
    }

    @ViewBuilder
    private func muscleDelta(_ deltaPoints: Double?) -> some View {
        if let delta = deltaPoints, abs(delta) >= 1 {
            HStack(spacing: 2) {
                Image(systemName: delta > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                    .font(.system(size: 6))
                Text("\(Int(abs(delta).rounded()))")
                    .font(.caption2)
                    .monospacedDigit()
            }
            .foregroundStyle(mutedText)
        } else {
            Text("")
        }
    }

    // MARK: - Rep ranges

    private var repRangeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(
                title: "Rep ranges",
                caption: snapshot.repWindowIsRecent
                    ? "Where your sets land — last 60 days"
                    : "Where your sets land — all time"
            )

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
            .foregroundStyle(AnalyticsPalette.zoneColor(bin.zone))
            .cornerRadius(2)
        }
        .chartXScale(domain: 0.3...21.2)
        .chartXAxis {
            AxisMarks(values: [1.0, 5.0, 10.0, 15.0, 20.0]) { value in
                AxisValueLabel {
                    if let reps = value.as(Double.self) {
                        Text(reps >= 20 ? "20+" : "\(Int(reps))")
                            .font(.caption2)
                            .foregroundStyle(mutedText)
                            .fixedSize()
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                    .foregroundStyle(Color.white.opacity(0.08))
                AxisValueLabel()
                    .font(.caption2)
                    .foregroundStyle(mutedText)
            }
        }
        .frame(height: 130)
    }

    private var repZoneLegend: some View {
        HStack(alignment: .top, spacing: 16) {
            ForEach(RepZone.allCases) { zone in
                HStack(spacing: 6) {
                    Circle()
                        .fill(AnalyticsPalette.zoneColor(zone))
                        .frame(width: 8, height: 8)
                        .padding(.top, 3)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(zone.label)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                        Text("\(zone.rangeText) · \(zonePercent(zone))")
                            .font(.caption2)
                            .foregroundStyle(mutedText)
                    }
                }
            }
        }
    }

    private func zonePercent(_ zone: RepZone) -> String {
        let share = snapshot.repZoneShares[zone] ?? 0
        return "\(Int((share * 100).rounded()))%"
    }

    // MARK: - Shared pieces

    private func sectionHeader(title: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)
            Text(caption)
                .font(.caption)
                .foregroundStyle(mutedText)
        }
    }

    private func insightLine(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "sparkles")
                .font(.caption2)
                .foregroundStyle(AppTheme.accent)
            Text(text)
                .font(.footnote)
                .foregroundStyle(secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func signedPercent(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        let prefix = rounded > 0 ? "+" : ""
        if rounded == rounded.rounded() {
            return "\(prefix)\(Int(rounded))%"
        }
        return "\(prefix)\(rounded.formatted(.number.precision(.fractionLength(1))))%"
    }

    private func compactNumber(_ value: Double) -> String {
        if value >= 100_000 {
            return String(format: "%.0fk", value / 1000)
        }
        if value >= 10_000 {
            return String(format: "%.1fk", value / 1000)
        }
        return value.formatted(.number.precision(.fractionLength(0)))
    }

    private func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }
}

// MARK: - Heatmap grid

/// GitHub-style calendar: columns are weeks (oldest → newest), rows are weekdays.
/// Cell intensity is a quartile of the user's own non-zero daily set counts.
private struct ConsistencyHeatmapGrid: View {
    let model: AnalyticsSnapshot.HeatmapModel

    @State private var availableWidth: CGFloat = 0

    private let gap: CGFloat = 3
    private let gutter: CGFloat = 20

    var body: some View {
        let columns = max(model.weeks.count, 1)
        let rawCell = (availableWidth - gutter - gap * CGFloat(columns - 1)) / CGFloat(columns)
        let cell = max(6, min(18, rawCell.isFinite ? rawCell : 6))

        VStack(alignment: .leading, spacing: 4) {
            monthLabelRow(cell: cell)

            HStack(alignment: .top, spacing: gap) {
                weekdayGutter(cell: cell)

                ForEach(Array(model.weeks.enumerated()), id: \.offset) { _, week in
                    VStack(spacing: gap) {
                        ForEach(week) { day in
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(day.isFuture ? Color.clear : AnalyticsPalette.heatLevel(day.level))
                                .frame(width: cell, height: cell)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            availableWidth = width
        }
    }

    private func monthLabelRow(cell: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(height: 12)

            ForEach(model.monthLabels, id: \.weekIndex) { item in
                Text(item.label)
                    .font(.system(size: 9))
                    .foregroundStyle(Color.white.opacity(0.62))
                    .fixedSize()
                    .offset(x: gutter + gap + CGFloat(item.weekIndex) * (cell + gap))
            }
        }
    }

    private func weekdayGutter(cell: CGFloat) -> some View {
        VStack(spacing: gap) {
            ForEach(0..<7, id: \.self) { row in
                Text(row % 2 == 1 ? weekdayLabel(row) : "")
                    .font(.system(size: 8))
                    .foregroundStyle(Color.white.opacity(0.62))
                    .frame(width: gutter, height: cell, alignment: .leading)
            }
        }
    }

    private func weekdayLabel(_ row: Int) -> String {
        guard model.weekdayLabels.indices.contains(row) else { return "" }
        return model.weekdayLabels[row]
    }
}

// MARK: - Palette
//
// Validated with the dataviz six-checks validator against the card surface
// (#171A1C, dark mode): both ramps pass monotone lightness, step gaps and
// light-end contrast. Single hue (the app's primary blue) — magnitude is
// carried by lightness, never by extra hues.
private enum AnalyticsPalette {
    // Sequential heat ramp, low -> high activity.
    private static let heatRamp: [Color] = [
        Color.white.opacity(0.05),                       // rest day
        Color(red: 0.165, green: 0.322, blue: 0.522),    // #2A5285
        Color(red: 0.208, green: 0.420, blue: 0.690),    // #356BB0
        Color(red: 0.251, green: 0.522, blue: 0.847),    // #4085D8
        AppTheme.primary                                 // #4A9EFF
    ]

    static func heatLevel(_ level: Int) -> Color {
        heatRamp[max(0, min(heatRamp.count - 1, level))]
    }

    // Ordinal ramp across the ordered rep zones (strength -> endurance).
    static func zoneColor(_ zone: RepZone) -> Color {
        switch zone {
        case .strength: return Color(red: 0.165, green: 0.353, blue: 0.561)     // #2A5A8F
        case .hypertrophy: return Color(red: 0.227, green: 0.486, blue: 0.769)  // #3A7CC4
        case .endurance: return AppTheme.primary                                // #4A9EFF
        }
    }
}
