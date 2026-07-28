import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: WorkoutStore
    @StateObject private var exerciseStore = ExerciseStore()
    @State private var routines: [Routine] = []
    @State private var navigateToCreate = false
    @State private var selectedRoutine: Routine?
    @State private var routineToEdit: Routine?
    @State private var navigateToLogger = false
    @State private var navigateToEdit = false
    @State private var navigateToSettings = false
    @State private var navigateToAnalytics = false
    @State private var navigateToExerciseLibrary = false
    @State private var navigateToPresetGenerator = false
    @State private var routinePendingDelete: Routine?

    var body: some View {
        NavigationView {
            ZStack {
                AppBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        headerSection

                        if !store.sessions.isEmpty {
                            weekSection
                        }

                        primaryActionSection
                        coreFlowsSection

                        if routines.isEmpty {
                            emptyState
                        } else if routines.count > 1 {
                            routineSection
                        }

                        NavigationLink(destination: CreateWorkoutOptionsView(entryMode: .aiTools, onSave: {
                            loadRoutines()
                        }), isActive: $navigateToCreate) {
                            EmptyView()
                        }

                        NavigationLink(destination: CreateRoutineView(routineToEdit: routineToEdit, onSave: {
                            loadRoutines()
                        }), isActive: $navigateToEdit) {
                            EmptyView()
                        }

                        NavigationLink(destination: WorkoutLoggerView(routine: selectedRoutine ?? Routine(name: "", exercises: [])), isActive: $navigateToLogger) {
                            EmptyView()
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

                        NavigationLink(destination: PresetWorkoutGeneratorView(onSave: {
                            loadRoutines()
                        }), isActive: $navigateToPresetGenerator) {
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
                loadRoutines()
                store.reload()
            }
            .alert("Delete routine?", isPresented: deleteAlertBinding) {
                Button("Cancel", role: .cancel) {
                    routinePendingDelete = nil
                }

                Button("Delete", role: .destructive) {
                    if let routinePendingDelete {
                        deleteRoutine(id: routinePendingDelete.id)
                    }
                    routinePendingDelete = nil
                }
            } message: {
                Text("This removes the routine, but your saved workout history stays intact.")
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
                    navigateToAnalytics = true
                } label: {
                    Image(systemName: "chart.line.uptrend.xyaxis")
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

    // MARK: - Primary action

    private var primaryActionSection: some View {
        Group {
            if let quickStartRoutine {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("UP NEXT · \(quickStartRoutine.name.uppercased())")
                            .microLabel(AppTheme.textSecondary)
                            .lineLimit(1)

                        Spacer()

                        Text("\(quickStartRoutine.exercises.count) exercises")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                    .padding(.bottom, 14)

                    hairline

                    VStack(spacing: 0) {
                        ForEach(quickStartRoutine.exercises, id: \.self) { exercise in
                            ExerciseTextNavigationLink(exerciseName: exercise, exercises: exerciseStore.exercises) {
                                HStack {
                                    Text(exercise)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(AppTheme.textPrimary)
                                        .lineLimit(1)

                                    Spacer()

                                    Text("× \(quickStartRoutine.preferredSetCount(for: exercise))")
                                        .font(.subheadline)
                                        .monospacedDigit()
                                        .foregroundStyle(AppTheme.textSecondary)
                                }
                                .padding(.vertical, 11)
                            }

                            if exercise != quickStartRoutine.exercises.last {
                                hairline
                            }
                        }
                    }

                    Button("Start Workout") {
                        selectedRoutine = quickStartRoutine
                        navigateToLogger = true
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 14)

                    HStack {
                        Button("Edit") {
                            routineToEdit = quickStartRoutine
                            navigateToEdit = true
                        }
                        .buttonStyle(TertiaryButtonStyle())

                        Button("Delete") {
                            routinePendingDelete = quickStartRoutine
                        }
                        .buttonStyle(TertiaryButtonStyle())

                        Spacer()
                    }
                    .padding(.top, 10)
                }
                .padding(AppTheme.cardPadding)
                .glassCard()
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    Text("START")
                        .microLabel()

                    Text("Build your first routine")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Button("Ask Lokt for a Workout") {
                        navigateToCreate = true
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    Button("Create Manually") {
                        navigateToEdit = true
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                .padding(AppTheme.cardPadding)
                .glassCard()
            }
        }
    }

    // MARK: - Plan flows

    private var coreFlowsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PLAN")
                .microLabel()
                .padding(.bottom, 12)

            Button {
                navigateToCreate = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text("Ask Lokt for a Workout")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.textTertiary)
                }
                .padding(.vertical, 16)
            }
            .buttonStyle(.plain)

            compactFlowRow(title: "Create Manually", icon: "square.and.pencil") {
                navigateToEdit = true
            }

            compactFlowRow(title: "Start with a Preset Plan", icon: "list.bullet.rectangle") {
                navigateToPresetGenerator = true
            }

            compactFlowRow(title: "Explore Exercises", icon: "books.vertical") {
                navigateToExerciseLibrary = true
            }

            compactFlowRow(title: "Review Progress", icon: "chart.line.uptrend.xyaxis", isLast: true) {
                navigateToAnalytics = true
            }
        }
        .padding(.horizontal, AppTheme.cardPadding)
        .padding(.vertical, AppTheme.rowPadding)
        .glassCard()
    }

    private func compactFlowRow(title: String, icon: String, isLast: Bool = false, action: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            hairline

            Button(action: action) {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(width: 22)

                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(AppTheme.textTertiary)
                }
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Saved routines (beyond the quick-start one)

    private var routineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SAVED ROUTINES")
                .microLabel()

            ForEach(routines.dropFirst()) { routine in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(routine.name)
                                .font(.headline.weight(.bold))
                                .foregroundStyle(AppTheme.textPrimary)

                            Text("\(routine.exercises.count) exercises")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(AppTheme.textSecondary)
                        }

                        Spacer()

                        HStack(spacing: 8) {
                            Button {
                                routineToEdit = routine
                                navigateToEdit = true
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .frame(width: 34, height: 34)
                                    .background(AppTheme.surfaceElevated)
                                    .clipShape(Circle())
                            }

                            Button {
                                routinePendingDelete = routine
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(AppTheme.danger.opacity(0.85))
                                    .frame(width: 34, height: 34)
                                    .background(AppTheme.surfaceElevated)
                                    .clipShape(Circle())
                            }
                        }
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(routine.exercises.prefix(5), id: \.self) { exercise in
                                ExerciseTextNavigationLink(exerciseName: exercise, exercises: exerciseStore.exercises) {
                                    Text(exercise)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(AppTheme.textSecondary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(AppTheme.mutedFill)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }

                    Button("Start Routine") {
                        selectedRoutine = routine
                        navigateToLogger = true
                    }
                    .buttonStyle(PrimaryButtonStyle(fill: AppTheme.surfaceElevated))
                }
                .padding(AppTheme.rowPadding)
                .glassCard()
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Nothing saved yet")
                .font(.headline.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)

            Text("Ask Lokt for a workout or create one manually so your next session is ready to go.")
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

    // MARK: - Derived data

    private var quickStartRoutine: Routine? {
        routines.first
    }

    private var dateLine: String {
        Date().formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    private var calendar: Calendar { Calendar.current }

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
                    guard let weight = Double(set.weight.replacingOccurrences(of: ",", with: "")),
                          let reps = Double(set.reps) else { return setTotal }
                    return setTotal + weight * reps
                }
            }
        }
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { routinePendingDelete != nil },
            set: { isPresented in
                if !isPresented {
                    routinePendingDelete = nil
                }
            }
        )
    }

    func loadRoutines() {
        if let data = UserDefaults.standard.data(forKey: "routines"),
           let decoded = try? JSONDecoder().decode([Routine].self, from: data) {
            routines = decoded
        } else {
            routines = []
        }
    }

    func deleteRoutine(id: UUID) {
        routines.removeAll { $0.id == id }
        if let encoded = try? JSONEncoder().encode(routines) {
            UserDefaults.standard.set(encoded, forKey: "routines")
        }
    }
}
