import SwiftUI

struct HomeView: View {
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
                        heroSection
                        primaryActionSection
                        coreFlowsSection

                        if routines.isEmpty {
                            emptyState
                        } else {
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
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 32)
                }
            }
            .navigationBarHidden(true)
            .onAppear(perform: loadRoutines)
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
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Lokt")
                        .font(.system(size: 38, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text("Tell Lokt what you want, get a workout fast, and keep the rest of your training easy to manage.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                }

                Spacer()

                HStack(spacing: 10) {
                    Button {
                        navigateToAnalytics = true
                    } label: {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.headline)
                            .foregroundStyle(AppTheme.textPrimary)
                            .padding(14)
                            .background(AppTheme.surfaceElevated)
                            .clipShape(Circle())
                    }

                    Button {
                        navigateToSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.headline)
                            .foregroundStyle(AppTheme.textPrimary)
                            .padding(14)
                            .background(AppTheme.surfaceElevated)
                            .clipShape(Circle())
                    }
                }
            }

            HStack(spacing: 12) {
                statPill(title: "\(routines.count)", subtitle: "Routines")
                statPill(title: "\(totalExercises)", subtitle: "Exercises")
            }
        }
    }

    private var primaryActionSection: some View {
        Group {
            if let quickStartRoutine {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Start Workout")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(AppTheme.textPrimary)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(quickStartRoutine.name)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(AppTheme.textPrimary)

                        Text("\(quickStartRoutine.exercises.count) exercises ready to go")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textSecondary)
                    }

                    Button("Start Routine") {
                        selectedRoutine = quickStartRoutine
                        navigateToLogger = true
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    HStack(spacing: 10) {
                        Text("Want something different today?")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textSecondary)

                    Button("Ask Lokt") {
                            navigateToCreate = true
                        }
                        .buttonStyle(TertiaryButtonStyle())
                    }
                }
                .padding(20)
                .glassCard()
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Start with Lokt")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text("Describe the workout you want and Lokt can build the first draft for you.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)

                    Button("Ask Lokt for a Workout") {
                        navigateToCreate = true
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    Button("Create Manually") {
                        navigateToEdit = true
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                .padding(20)
                .glassCard()
            }
        }
    }

    private var coreFlowsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Plan with Lokt")
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)

            Button {
                navigateToCreate = true
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "sparkles")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(AppTheme.accent)
                        .padding(12)
                        .background(AppTheme.accent.opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ask Lokt for a Workout")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)

                        Text("Use text, voice, photo, or add-on tools to let Lokt build the draft.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .padding(18)
                .surfaceCard(cornerRadius: 20, border: AppTheme.accent.opacity(0.28))
            }
            .buttonStyle(.plain)

            Button {
                navigateToEdit = true
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "square.and.pencil")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .padding(12)
                        .background(AppTheme.mutedFill)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Create Manually")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)

                        Text("Pick exercises and build the routine yourself.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .padding(18)
                .surfaceCard(cornerRadius: 20)
            }
            .buttonStyle(.plain)

            HStack(spacing: 12) {
                compactFlowButton(
                    title: "Explore Exercises",
                    icon: "books.vertical.fill"
                ) {
                    navigateToExerciseLibrary = true
                }

                compactFlowButton(
                    title: "Review Progress",
                    icon: "chart.line.uptrend.xyaxis"
                ) {
                    navigateToAnalytics = true
                }
            }

            HStack(spacing: 10) {
                Text("Want less setup?")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)

                Button("Start with a Plan") {
                    navigateToPresetGenerator = true
                }
                .buttonStyle(TertiaryButtonStyle())
            }
        }
        .padding(20)
        .glassCard()
    }

    private var routineSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Saved Routines")
                .font(.title2.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)

            ForEach(routines) { routine in
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(routine.name)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(AppTheme.textPrimary)

                            Text("\(routine.exercises.count) exercises")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.textSecondary)
                        }

                        Spacer()

                        HStack(spacing: 10) {
                            Button {
                                routineToEdit = routine
                                navigateToEdit = true
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(AppTheme.textPrimary)
                                    .padding(10)
                                    .background(AppTheme.surfaceElevated)
                                    .clipShape(Circle())
                            }

                            Button {
                                routinePendingDelete = routine
                            } label: {
                                Image(systemName: "trash")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.red.opacity(0.8))
                                    .padding(10)
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
                    .buttonStyle(PrimaryButtonStyle())
                }
                .padding(18)
                .glassCard()
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 30))
                .foregroundStyle(AppTheme.secondary)

            Text("Build your first routine")
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)

            Text("Ask Lokt for a workout or create one manually so your next session is ready to go.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(22)
        .glassCard()
    }

    private var quickStartRoutine: Routine? {
        routines.first
    }

    private func statPill(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.weight(.heavy))
                .foregroundStyle(AppTheme.textPrimary)

            Text(subtitle.uppercased())
                .font(.caption.weight(.bold))
                .tracking(1)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .glassCard()
    }

    private func tertiaryActionButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline.weight(.bold))

            Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(AppTheme.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .surfaceCard()
        }
        .buttonStyle(.plain)
    }

    private func compactFlowButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: icon)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .padding(12)
                    .background(AppTheme.mutedFill)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(title == "Explore Exercises" ? "Browse and add exercises fast." : "See trends, lifts, and progress.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 136, alignment: .topLeading)
            .padding(16)
            .surfaceCard(cornerRadius: 20)
        }
        .buttonStyle(.plain)
    }

    private var totalExercises: Int {
        routines.reduce(0) { $0 + $1.exercises.count }
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
