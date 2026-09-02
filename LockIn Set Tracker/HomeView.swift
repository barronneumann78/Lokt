import SwiftUI

// Overview only: greeting, this week's numbers, a recent-activity glance, and
// the dive into full Analytics. Creating and starting workouts lives on the
// Workout tab.
struct HomeView: View {
    @EnvironmentObject private var store: WorkoutStore
    @EnvironmentObject private var coachRouter: CoachRouter
    @State private var navigateToSettings = false
    @State private var navigateToAnalytics = false
    @State private var navigateToExerciseLibrary = false

    var body: some View {
        NavigationView {
            ZStack {
                AppBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        headerSection

                        if store.sessions.isEmpty {
                            emptyState
                        } else {
                            weekSection
                            analyticsButton
                            recentSection
                        }

                        NavigationLink(destination: SettingsView(), isActive: $navigateToSettings) {
                            EmptyView()
                        }

                        NavigationLink(destination: AnalyticsView(), isActive: $navigateToAnalytics) {
                            EmptyView()
                        }

                        NavigationLink(destination: ExerciseLibraryView(), isActive: $navigateToExerciseLibrary) {
                            EmptyView()
                        }
                    }
                    .padding(.horizontal, AppTheme.screenPadding)
                    .padding(.top, 20)
                    .padding(.bottom, 32)
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                store.reload()
            }
        }
        .tint(AppTheme.textPrimary)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(dateLine)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)

                Text("Ready to lift")
                    .font(.system(size: 34, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(AppTheme.textPrimary)
            }

            Spacer()

            HStack(spacing: 10) {
                Button {
                    navigateToExerciseLibrary = true
                } label: {
                    Image(systemName: "books.vertical")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .frame(width: 42, height: 42)
                        .background(AppTheme.surfaceElevated)
                        .clipShape(Circle())
                }

                Button {
                    navigateToSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .frame(width: 42, height: 42)
                        .background(AppTheme.surfaceElevated)
                        .clipShape(Circle())
                }
            }
        }
    }

    // MARK: - This week hero

    private var weekSection: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("VOLUME THIS WEEK")
                    .microLabel()

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(weekVolumeParts.value)
                        .font(.system(size: 56, weight: .bold))
                        .monospacedDigit()
                        .tracking(-1.5)
                        .foregroundStyle(AppTheme.textPrimary)

                    Text(weekVolumeParts.unit)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                }

                if let delta = weekVolumeDeltaPercent {
                    Text("\(delta >= 0 ? "↑" : "↓") \(abs(Int(delta.rounded())))% vs last week")
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(delta >= 0 ? AppTheme.success : AppTheme.textSecondary)
                } else {
                    Text("Across \(sessionsThisWeek) session\(sessionsThisWeek == 1 ? "" : "s")")
                        .font(.footnote.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppTheme.cardPadding)
            .glassCard()

            HStack(spacing: 12) {
                metricTile(label: "SESSIONS", value: "\(sessionsThisWeek)", unit: "this wk")
                metricTile(label: "STREAK", value: streakWeeks == 0 ? "—" : "\(streakWeeks)", unit: streakWeeks == 0 ? "" : "wks")
            }
        }
    }

    private func metricTile(label: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .microLabel()

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 30, weight: .bold))
                    .monospacedDigit()
                    .tracking(-0.5)
                    .foregroundStyle(AppTheme.textPrimary)

                if !unit.isEmpty {
                    Text(unit)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.rowPadding)
        .glassCard()
    }

    // MARK: - Analytics dive

    private var analyticsButton: some View {
        Button {
            navigateToAnalytics = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.headline.weight(.bold))

                Text("View Analytics")
            }
        }
        .buttonStyle(PrimaryButtonStyle())
    }

    // MARK: - Recent activity

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("RECENT")
                .microLabel()
                .padding(.bottom, 4)

            ForEach(Array(recentSessions.enumerated()), id: \.element.id) { index, session in
                VStack(spacing: 0) {
                    if index > 0 {
                        hairline
                    }

                    // Tappable: pushes the correction editor for this session.
                    NavigationLink {
                        SessionEditView(session: session)
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(session.routineName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.textPrimary)
                                    .lineLimit(1)

                                Text(session.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.textTertiary)
                            }

                            Spacer()

                            Text(volumeText(for: session))
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(AppTheme.textSecondary)

                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(AppTheme.textTertiary)
                        }
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, AppTheme.cardPadding)
        .padding(.vertical, AppTheme.rowPadding)
        .glassCard()
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("No sessions yet")
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)

            Text("Your numbers land here after your first workout.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)

            Button("Start Your First Workout") {
                coachRouter.selectedTab = .workout
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.cardPadding)
        .glassCard()
    }

    private var hairline: some View {
        Rectangle()
            .fill(AppTheme.cardBorder)
            .frame(height: 1)
    }

    // MARK: - Derived data

    private var dateLine: String {
        Date().formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    private var calendar: Calendar { Calendar.current }

    private var recentSessions: [WorkoutSession] {
        Array(store.sessions.sorted { $0.date > $1.date }.prefix(3))
    }

    private var sessionsThisWeek: Int {
        sessions(inWeekOffset: 0).count
    }

    private var weekVolumeParts: (value: String, unit: String) {
        let volume = totalVolume(for: sessions(inWeekOffset: 0))
        if volume >= 1000 {
            return (String(format: "%.1f", volume / 1000), "k lb")
        }
        return ("\(Int(volume))", "lb")
    }

    private var weekVolumeDeltaPercent: Double? {
        let current = totalVolume(for: sessions(inWeekOffset: 0))
        let previous = totalVolume(for: sessions(inWeekOffset: -1))
        guard previous > 0, current > 0 else { return nil }
        return (current - previous) / previous * 100
    }

    private var streakWeeks: Int {
        let weeks = Set(store.sessions.compactMap { session in
            calendar.dateInterval(of: .weekOfYear, for: session.date)?.start
        })
        guard !weeks.isEmpty,
              var cursor = calendar.dateInterval(of: .weekOfYear, for: Date())?.start else {
            return 0
        }

        // The streak may still be alive if this week has no session yet.
        if !weeks.contains(cursor) {
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) else { return 0 }
            cursor = previous
        }

        var streak = 0
        while weeks.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    private func sessions(inWeekOffset offset: Int) -> [WorkoutSession] {
        guard let currentWeek = calendar.dateInterval(of: .weekOfYear, for: Date()),
              let weekStart = calendar.date(byAdding: .weekOfYear, value: offset, to: currentWeek.start),
              let week = calendar.dateInterval(of: .weekOfYear, for: weekStart) else {
            return []
        }
        return store.sessions.filter { week.contains($0.date) }
    }

    private func totalVolume(for sessions: [WorkoutSession]) -> Double {
        sessions.reduce(0) { total, session in
            total + session.logs.values.reduce(0) { exerciseTotal, sets in
                exerciseTotal + sets.reduce(0) { setTotal, set in
                    guard set.isCompleted,
                          let weight = Double(set.weight.replacingOccurrences(of: ",", with: "")),
                          let reps = Double(set.reps) else { return setTotal }
                    return setTotal + weight * reps
                }
            }
        }
    }

    private func volumeText(for session: WorkoutSession) -> String {
        let volume = totalVolume(for: [session])
        guard volume > 0 else { return "—" }
        if volume >= 1000 {
            return String(format: "%.1fk lb", volume / 1000)
        }
        return "\(Int(volume)) lb"
    }
}
