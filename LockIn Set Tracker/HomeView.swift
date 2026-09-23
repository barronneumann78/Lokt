import SwiftUI

// Overview only: greeting, this week's numbers, a recent-activity glance, and
// the dive into full Analytics. Starting and creating workouts live on the
// Workout tab — Home names the up-next routine in its subtitle but carries no
// start control (owner feedback on build 3: starting an exercise from Home
// felt wrong). No gradient pill on this screen.
struct HomeView: View {
    @EnvironmentObject private var store: WorkoutStore
    @EnvironmentObject private var exerciseStore: ExerciseStore
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
                            statRow
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
                    .padding(.bottom, 16)
                }
            }
            .navigationBarHidden(true)
        }
        .tint(AppTheme.textPrimary)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Ready to lift")
                    .font(.system(size: 34, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(AppTheme.textPrimary)

                Text(contextLine)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
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
        let volume = HomeInsights.volumeLabel(thisWeekVolume)

        return VStack(alignment: .leading, spacing: 12) {
            Text("VOLUME THIS WEEK")
                .microLabel()

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(volume.value)
                    .font(.system(size: 56, weight: .bold))
                    .monospacedDigit()
                    .tracking(-1.5)
                    .foregroundStyle(AppTheme.textPrimary)
                    .heroGlow()

                Text(volume.unit)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)

                if let delta = weekVolumeDeltaPercent {
                    deltaChip(delta)
                }
            }

            weekStrip
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.cardPadding)
        .glassCard()
    }

    private func deltaChip(_ delta: Double) -> some View {
        let rounded = Int(delta.rounded())
        return Text("\(rounded >= 0 ? "+" : "−")\(abs(rounded))% vs last")
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(rounded >= 0 ? AppTheme.success : AppTheme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppTheme.mutedFill)
            .clipShape(Capsule())
    }

    // MARK: Week strip — seven bars Mon–Sun, today lit

    private let barMaxHeight: CGFloat = 48
    private let barMinHeight: CGFloat = 4

    private var weekStrip: some View {
        let days = weekStripDays
        let peak = days.map(\.volume).max() ?? 0

        return HStack(alignment: .bottom, spacing: 8) {
            ForEach(days) { day in
                VStack(spacing: 8) {
                    bar(for: day, peak: peak)

                    Text(day.letter)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(day.isToday ? AppTheme.primary : AppTheme.textTertiary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func bar(for day: HomeInsights.DayVolume, peak: Double) -> some View {
        let height = peak > 0
            ? max(barMinHeight, barMaxHeight * CGFloat(day.volume / peak))
            : barMinHeight

        return VStack(spacing: 0) {
            Spacer(minLength: 0)

            let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(barStyle(for: day))
                .frame(height: height)

            if day.isToday {
                shape.barGlow()
            } else {
                shape
            }
        }
        .frame(height: barMaxHeight)
    }

    /// Today: the primary gradient. Other lifting days: the neutral series
    /// color (data encoding, not chrome). Quiet days: the muted fill.
    private func barStyle(for day: HomeInsights.DayVolume) -> AnyShapeStyle {
        if day.isToday {
            return AnyShapeStyle(AppTheme.primaryGradient)
        }
        if day.volume > 0 {
            return AnyShapeStyle(AppTheme.chartNeutral)
        }
        return AnyShapeStyle(AppTheme.mutedFill)
    }

    // MARK: - Stat row

    private var statRow: some View {
        HStack(spacing: 0) {
            statTile(label: "SESSIONS · 7D", value: "\(sessionsLast7Days)")

            verticalHairline

            statTile(label: "PRs · 30D", value: "\(prsLast30Days)", accent: true)

            verticalHairline

            statTile(
                label: "STREAK",
                value: streakWeeks == 0 ? "—" : "\(streakWeeks)",
                unit: streakWeeks == 0 ? "" : "wk"
            )
        }
        .padding(.vertical, AppTheme.rowPadding)
        .glassCard()
    }

    private func statTile(label: String, value: String, unit: String = "", accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .microLabel()
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 28, weight: .bold))
                    .monospacedDigit()
                    .tracking(-0.5)
                    .foregroundStyle(accent ? AppTheme.primary : AppTheme.textPrimary)

                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppTheme.rowPadding)
    }

    private var verticalHairline: some View {
        Rectangle()
            .fill(AppTheme.cardBorder)
            .frame(width: 1)
    }

    // MARK: - Recent activity

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("RECENT")
                    .microLabel()

                Spacer()

                Button {
                    navigateToAnalytics = true
                } label: {
                    HStack(spacing: 3) {
                        Text("View Analytics")

                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.primary)
                }
                .buttonStyle(.plain)
            }
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
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(session.routineName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.textPrimary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)

                                Text(recentSubtitle(for: session))
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(AppTheme.textTertiary)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 12)

                            Text(recentMetrics(for: session))
                                .font(.footnote.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(AppTheme.textSecondary)
                                .lineLimit(1)
                                .layoutPriority(1)

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
    // No call to action here: creating a routine lives on the Workout tab.

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No sessions yet")
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)

            Text("Your numbers land here after your first workout.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
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

    // MARK: - Derived data (math lives in HomeInsights; this is wiring)

    private var now: Date { Date() }

    /// Mon–Sun week in the user's own time zone and locale.
    private var calendar: Calendar { HomeInsights.weekCalendar(.current) }

    /// "Wednesday · Up next: Push Day" — "Up next" leads so a long routine
    /// name truncating at the tail never takes the meaning with it. The full
    /// date when nothing is queued.
    private var contextLine: String {
        guard let next = nextRoutine else {
            return now.formatted(.dateTime.weekday(.wide).month(.wide).day())
        }
        return "\(now.formatted(.dateTime.weekday(.wide))) · Up next: \(next.name)"
    }

    private var nextRoutine: Routine? {
        HomeInsights.nextRoutine(routines: store.routines, groups: store.routineGroups, sessions: store.sessions)
    }

    private var recentSessions: [WorkoutSession] {
        Array(store.sessions.sorted { $0.date > $1.date }.prefix(3))
    }

    private var weekStripDays: [HomeInsights.DayVolume] {
        HomeInsights.weekStrip(sessions: store.sessions, now: now, calendar: calendar)
    }

    private var thisWeekVolume: Double {
        HomeInsights.totalVolume(HomeInsights.sessions(store.sessions, inWeekOffset: 0, now: now, calendar: calendar))
    }

    private var weekVolumeDeltaPercent: Double? {
        let previous = HomeInsights.totalVolume(
            HomeInsights.sessions(store.sessions, inWeekOffset: -1, now: now, calendar: calendar)
        )
        return HomeInsights.volumeDeltaPercent(current: thisWeekVolume, previous: previous)
    }

    private var sessionsLast7Days: Int {
        HomeInsights.sessions(store.sessions, inLastDays: 7, now: now, calendar: calendar).count
    }

    private var prsLast30Days: Int {
        let exercises = exerciseStore.exercises
        return HomeInsights.prCount(
            sessions: store.sessions,
            lastDays: 30,
            now: now,
            calendar: calendar,
            resolve: { exercises.resolvedExercise(named: $0) }
        )
    }

    private var streakWeeks: Int {
        HomeInsights.streakWeeks(sessions: store.sessions, now: now, calendar: calendar)
    }

    /// "Wednesday · 52min" inside the last week, "Sep 3 · 52min" beyond it.
    private func recentSubtitle(for session: WorkoutSession) -> String {
        let isRecent = HomeInsights.sessions([session], inLastDays: 7, now: now, calendar: calendar).isEmpty == false
        let when = isRecent
            ? session.date.formatted(.dateTime.weekday(.wide))
            : session.date.formatted(.dateTime.month(.abbreviated).day())
        guard let seconds = session.durationSeconds, seconds > 0 else { return when }
        return "\(when) · \(AnalyticsMath.durationText(seconds: seconds))"
    }

    /// "24 sets · 12.4k lb"; the tonnage drops out when nothing parsed.
    private func recentMetrics(for session: WorkoutSession) -> String {
        let sets = HomeInsights.countedSets(session)
        let setsText = "\(sets) set\(sets == 1 ? "" : "s")"
        let volume = HomeInsights.sessionVolume(session)
        guard volume > 0 else { return setsText }
        let label = HomeInsights.volumeLabel(volume)
        return "\(setsText) · \(label.value)\(label.unit == "lb" ? " lb" : label.unit)"
    }
}
