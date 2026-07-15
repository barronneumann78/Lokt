import SwiftUI

struct ExerciseLibraryView: View {
    @StateObject private var exerciseStore = ExerciseStore()
    @State private var searchText = ""
    @State private var selectedMuscleGroup = "All"
    @State private var selectedEquipment = "All"
    @State private var selectedMovementPattern = "All"

    init(initialMovementPattern: MovementPattern? = nil) {
        _selectedMovementPattern = State(initialValue: initialMovementPattern?.rawValue ?? "All")
    }

    private var filteredExercises: [Exercise] {
        exerciseStore.exercises.filter { exercise in
            let matchesSearch = searchText.isEmpty || exercise.name.localizedCaseInsensitiveContains(searchText)
            let matchesMuscle = selectedMuscleGroup == "All" || exercise.muscleGroup.rawValue == selectedMuscleGroup
            let matchesEquipment = selectedEquipment == "All" || exercise.equipment.rawValue == selectedEquipment
            let matchesPattern = selectedMovementPattern == "All" || exercise.movementPattern.rawValue == selectedMovementPattern
            return matchesSearch && matchesMuscle && matchesEquipment && matchesPattern
        }
    }

    private var muscleGroupOptions: [String] {
        ["All"] + MuscleGroup.allCases.map(\.rawValue)
    }

    private var equipmentOptions: [String] {
        ["All"] + EquipmentType.allCases.map(\.rawValue)
    }

    private var movementPatternOptions: [String] {
        ["All"] + MovementPattern.allCases.map(\.rawValue)
    }

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection
                    filterSection
                    librarySection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
        }
        .navigationTitle("Exercise Library")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search Exercises")
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Exercise Library")
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)

            Text("Search fast, filter fast, and open any exercise for the details.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(20)
        .glassCard()
    }

    private var filterSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Filters")
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)

            HStack(spacing: 12) {
                filterPicker(title: "Muscle", selection: $selectedMuscleGroup, options: muscleGroupOptions)
                filterPicker(title: "Equipment", selection: $selectedEquipment, options: equipmentOptions)
            }

            filterPicker(title: "Movement", selection: $selectedMovementPattern, options: movementPatternOptions)
        }
        .padding(20)
        .glassCard()
    }

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Exercises")
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)

            if filteredExercises.isEmpty {
                Text("No exercises match those filters.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.vertical, 12)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(filteredExercises) { exercise in
                        NavigationLink(destination: ExerciseDetailView(exercise: exercise)) {
                            HStack(spacing: 14) {
                                ExerciseMediaView(
                                    imageName: exercise.imageName,
                                    placeholderSystemImageName: exercise.placeholderSystemImageName,
                                    height: 56,
                                    cornerRadius: 16,
                                    iconSize: 24,
                                    animateGIF: false,
                                    contentPadding: 6
                                )
                                .frame(width: 56)

                                VStack(alignment: .leading, spacing: 6) {
                                    Text(exercise.name)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(AppTheme.textPrimary)
                                        .multilineTextAlignment(.leading)

                                    if let displayTag = exercise.summaryTags.first {
                                        Text(displayTag)
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(AppTheme.textSecondary)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(AppTheme.mutedFill)
                                            .clipShape(Capsule())
                                    }
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                            .padding(16)
                            .surfaceCard()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(20)
        .glassCard()
    }

    private func filterPicker(title: String, selection: Binding<String>, options: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.textSecondary)

            Picker(title, selection: selection) {
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(AppTheme.fieldBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
