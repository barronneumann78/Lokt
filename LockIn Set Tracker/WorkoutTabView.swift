import SwiftUI

// The action hub: create and start workouts. Owns the routine library and every
// create-flow entry; the logger is pushed from here.
struct WorkoutTabView: View {
    @EnvironmentObject private var store: WorkoutStore
    @StateObject private var exerciseStore = ExerciseStore()
    @State private var routines: [Routine] = []
    @State private var selectedRoutine: Routine?
    @State private var routineToEdit: Routine?
    @State private var navigateToLogger = false
    @State private var navigateToEdit = false
    @State private var navigateToCreate = false
    @State private var navigateToPresetGenerator = false
    @State private var routinePendingDelete: Routine?

    var body: some View {
        NavigationView {
            ZStack {
                AppBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        headerSection

                        if let quickStartRoutine {
                            heroRoutineCard(quickStartRoutine)
                        } else {
                            emptyHero
                        }

                        if routines.count > 1 {
                            routineSection
                        }

                        createSection

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
        VStack(alignment: .leading, spacing: 4) {
            Text(routines.isEmpty ? "NO ROUTINES YET" : "\(routines.count) ROUTINE\(routines.count == 1 ? "" : "S") READY")
                .microLabel()

            Text("Workout")
                .font(.system(size: 34, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(AppTheme.textPrimary)
        }
    }

    // MARK: - Hero: next routine + Start CTA

    private func heroRoutineCard(_ routine: Routine) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("UP NEXT · \(routine.name.uppercased())")
                    .microLabel(AppTheme.textSecondary)
                    .lineLimit(1)

                Spacer()

                Text("\(routine.exercises.count) exercises")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.textTertiary)
            }
            .padding(.bottom, 14)

            hairline

            VStack(spacing: 0) {
                ForEach(routine.exercises, id: \.self) { exercise in
                    ExerciseTextNavigationLink(exerciseName: exercise, exercises: exerciseStore.exercises) {
                        HStack {
                            Text(exercise)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.textPrimary)
                                .lineLimit(1)

                            Spacer()

                            Text("× \(routine.preferredSetCount(for: exercise))")
                                .font(.subheadline)
                                .monospacedDigit()
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        .padding(.vertical, 11)
                    }

                    if exercise != routine.exercises.last {
                        hairline
                    }
                }
            }

            Button("Start Workout") {
                selectedRoutine = routine
                navigateToLogger = true
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top, 14)

            HStack {
                Button("Edit") {
                    routineToEdit = routine
                    navigateToEdit = true
                }
                .buttonStyle(TertiaryButtonStyle())

                Button("Delete") {
                    routinePendingDelete = routine
                }
                .buttonStyle(TertiaryButtonStyle())

                Spacer()
            }
            .padding(.top, 10)
        }
        .padding(AppTheme.cardPadding)
        .glassCard()
    }

    private var emptyHero: some View {
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
                routineToEdit = nil
                navigateToEdit = true
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding(AppTheme.cardPadding)
        .glassCard()
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

    // MARK: - Create flows

    private var createSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("CREATE")
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

            createRow(title: "Create Manually", icon: "square.and.pencil") {
                routineToEdit = nil
                navigateToEdit = true
            }

            createRow(title: "Start with a Preset Plan", icon: "list.bullet.rectangle", isLast: true) {
                navigateToPresetGenerator = true
            }
        }
        .padding(.horizontal, AppTheme.cardPadding)
        .padding(.vertical, AppTheme.rowPadding)
        .glassCard()
    }

    private func createRow(title: String, icon: String, isLast: Bool = false, action: @escaping () -> Void) -> some View {
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

    private var hairline: some View {
        Rectangle()
            .fill(AppTheme.cardBorder)
            .frame(height: 1)
    }

    // MARK: - Data

    private var quickStartRoutine: Routine? {
        routines.first
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
