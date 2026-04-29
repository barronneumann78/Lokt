import SwiftUI
import Charts

struct AnalyticsView: View {
    @StateObject private var exerciseStore = ExerciseStore()
    @State private var workoutSessions: [WorkoutSession] = []
    @State private var selectedExercise = ""
    private let analyticsSecondaryText = Color.white.opacity(0.84)
    private let analyticsMutedText = Color.white.opacity(0.70)
    private let chartGridColor = Color.white.opacity(0.12)

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    headerSection
                    exercisePickerSection
                    chartSection
                }
                .padding(.horizontal, AppTheme.screenPadding)
                .padding(.vertical, 20)
            }
        }
        .navigationTitle("Analytics")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadWorkoutSessions)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Analytics")
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)

            Text("Follow your best weight and your recent trend for one exercise.")
                .font(.subheadline)
                .foregroundStyle(analyticsSecondaryText)
        }
        .padding(AppTheme.cardPadding)
        .glassCard()
    }

    private var exercisePickerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Exercise")
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            if exerciseNames.isEmpty {
                Text("No saved exercise history yet.")
                    .font(.subheadline)
                    .foregroundStyle(analyticsSecondaryText)
            } else {
                Picker("Exercise", selection: $selectedExercise) {
                    ForEach(exerciseNames, id: \.self) { exercise in
                        Text(exercise).tag(exercise)
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .tint(AppTheme.textPrimary)
                .surfaceCard(cornerRadius: AppTheme.controlCornerRadius, border: AppTheme.cardBorder.opacity(0.9))

                if let selectedExerciseDetail {
                    NavigationLink(destination: ExerciseDetailView(exercise: selectedExerciseDetail)) {
                        Label("Open Exercise Details", systemImage: "info.circle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .surfaceCard(cornerRadius: AppTheme.controlCornerRadius)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(AppTheme.cardPadding)
        .glassCard()
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Best Weight Over Time")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text("Your top set each time you logged this exercise.")
                        .font(.subheadline)
                        .foregroundStyle(analyticsSecondaryText)
                }

                Spacer()

                if !chartData.isEmpty {
                    Text("\(chartData.count) logs")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AppTheme.mutedFill)
                        .clipShape(Capsule())
                        .overlay {
                            Capsule()
                                .stroke(AppTheme.cardBorder.opacity(0.8), lineWidth: 1)
                        }
                }
            }

            if chartData.isEmpty {
                Text("Log a few workouts for this exercise to see progress here.")
                    .font(.subheadline)
                    .foregroundStyle(analyticsSecondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 36)
            } else {
                HStack(spacing: 12) {
                    analyticsStatCard(
                        title: "Best",
                        value: formattedWeight(bestWeight),
                        caption: "All-time top set",
                        accent: AppTheme.primary
                    )
                    analyticsStatCard(
                        title: "Latest",
                        value: formattedWeight(latestWeight),
                        caption: latestWeightCaption,
                        accent: Color.white
                    )
                    analyticsStatCard(
                        title: progressLabel,
                        value: progressValueText,
                        caption: progressCaption,
                        accent: progressAccent
                    )
                }
                .frame(minHeight: 96)

                performanceContextCard

                Chart(chartData) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Weight", point.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(AppTheme.primary)
                    .lineStyle(StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))

                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Weight", point.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AppTheme.primary.opacity(0.28), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    if isLatestPoint(point) {
                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("Weight", point.value)
                        )
                        .symbolSize(110)
                        .foregroundStyle(AppTheme.textPrimary)
                    }

                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Weight", point.value)
                    )
                    .symbolSize(isLatestPoint(point) ? 44 : 26)
                    .foregroundStyle(isLatestPoint(point) ? AppTheme.primary : AppTheme.secondary)
                }
                .frame(height: 300)
                .chartPlotStyle { plot in
                    plot
                        .background(AppTheme.surfaceElevated.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(AppTheme.cardBorder.opacity(0.85), lineWidth: 1)
                        }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic) {
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                            .foregroundStyle(chartGridColor)
                        AxisTick()
                            .foregroundStyle(chartGridColor)
                        AxisValueLabel()
                            .foregroundStyle(analyticsSecondaryText)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) {
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                            .foregroundStyle(chartGridColor)
                        AxisTick()
                            .foregroundStyle(chartGridColor)
                        AxisValueLabel()
                            .foregroundStyle(analyticsSecondaryText)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 20)
        .glassCard()
    }

    private var performanceContextCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: performanceIconName)
                .font(.headline.weight(.bold))
                .foregroundStyle(performanceIconColor)
                .frame(width: 34, height: 34)
                .background(performanceIconColor.opacity(0.16))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(performanceContextTitle)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text(performanceContextBody)
                    .font(.caption)
                    .foregroundStyle(analyticsSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .surfaceCard(border: performanceIconColor.opacity(0.22))
    }

    private var exerciseNames: [String] {
        let names = workoutSessions.flatMap { Array($0.logs.keys) }
        return Array(Set(names)).sorted()
    }

    private var selectedExerciseDetail: Exercise? {
        exerciseStore.exercises.exercise(named: selectedExercise)
    }

    private var chartData: [AnalyticsPoint] {
        guard !selectedExercise.isEmpty else { return [] }

        return workoutSessions
            .compactMap { session -> AnalyticsPoint? in
                guard let sets = session.logs[selectedExercise] else { return nil }

                let weights = sets.compactMap { parseWeight($0.weight) }
                guard let bestWeight = weights.max() else { return nil }

                return AnalyticsPoint(date: session.date, value: bestWeight)
            }
            .sorted { $0.date < $1.date }
    }

    private var bestWeight: Double {
        chartData.map(\.value).max() ?? 0
    }

    private var latestWeight: Double {
        chartData.last?.value ?? 0
    }

    private var latestWeightCaption: String {
        guard let latestDate = chartData.last?.date else { return "Most recent session" }
        return "Logged \(formattedShortDate(latestDate))"
    }

    private var progressLabel: String {
        overallChange == nil ? "Progress" : "Change"
    }

    private var progressValueText: String {
        guard let overallChange else { return "--" }
        return formattedDelta(overallChange)
    }

    private var progressCaption: String {
        overallChange == nil ? "Need more history" : "Since first logged set"
    }

    private var progressAccent: Color {
        guard let overallChange else { return AppTheme.textSecondary }
        return overallChange >= 0 ? AppTheme.success : AppTheme.secondary
    }

    private var overallChange: Double? {
        guard let first = chartData.first, let latest = chartData.last, chartData.count >= 2 else { return nil }
        return latest.value - first.value
    }

    private var performanceIconName: String {
        guard let overallChange else { return "sparkles" }
        return overallChange >= 0 ? "arrow.up.right" : "arrow.down.right"
    }

    private var performanceIconColor: Color {
        guard let overallChange else { return AppTheme.primary }
        return overallChange >= 0 ? AppTheme.success : AppTheme.secondary
    }

    private var performanceContextTitle: String {
        guard let overallChange else { return "One more log unlocks your trend" }

        if overallChange > 0 {
            return "Trending up \(formattedDelta(overallChange))"
        } else if overallChange < 0 {
            return "Down \(formattedWeight(abs(overallChange))) from your first log"
        } else {
            return "Holding steady"
        }
    }

    private var performanceContextBody: String {
        guard let first = chartData.first, let latest = chartData.last, chartData.count >= 2 else {
            return "Log this exercise again and Lokt will compare your latest top set against your first one."
        }

        return "From \(formattedShortDate(first.date)) to \(formattedShortDate(latest.date)), your latest top set is \(formattedWeight(latest.value))."
    }

    private func loadWorkoutSessions() {
        if let data = UserDefaults.standard.data(forKey: "workoutSessions"),
           let decoded = try? JSONDecoder().decode([WorkoutSession].self, from: data) {
            workoutSessions = decoded
            if selectedExercise.isEmpty {
                selectedExercise = Array(Set(decoded.flatMap { Array($0.logs.keys) })).sorted().first ?? ""
            }
        } else {
            workoutSessions = []
            selectedExercise = ""
        }
    }

    private func parseWeight(_ value: String) -> Double? {
        let cleaned = value.filter { "0123456789.".contains($0) }
        return Double(cleaned)
    }

    private func formattedWeight(_ value: Double) -> String {
        guard value > 0 else { return "--" }

        if value.rounded() == value {
            return "\(Int(value)) lbs"
        }

        return "\(value.formatted(.number.precision(.fractionLength(1)))) lbs"
    }

    private func formattedDelta(_ value: Double) -> String {
        let prefix = value > 0 ? "+" : ""
        if value.rounded() == value {
            return "\(prefix)\(Int(value)) lbs"
        }

        return "\(prefix)\(value.formatted(.number.precision(.fractionLength(1)))) lbs"
    }

    private func formattedShortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    private func isLatestPoint(_ point: AnalyticsPoint) -> Bool {
        guard let latest = chartData.last else { return false }
        return latest.date == point.date && latest.value == point.value
    }

    private func analyticsStatCard(title: String, value: String, caption: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(accent)
                    .frame(width: 8, height: 8)

                Text(title.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(analyticsMutedText)
            }

            Text(value)
                .font(.title3.weight(.black))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(caption)
                .font(.caption)
                .foregroundStyle(analyticsSecondaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                .stroke(accent.opacity(0.20), lineWidth: 1)
        }
    }
}

private struct AnalyticsPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}
