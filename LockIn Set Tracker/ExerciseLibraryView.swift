import SwiftUI

struct ExerciseLibraryView: View {
    @EnvironmentObject private var exerciseStore: ExerciseStore
    @State private var searchText = ""
    @State private var selectedMuscleGroup = "All"
    @State private var selectedEquipment = "All"
    @State private var selectedMovementPattern = "All"

    init(initialMovementPattern: MovementPattern? = nil) {
        _selectedMovementPattern = State(initialValue: initialMovementPattern?.rawValue ?? "All")
    }

    private var filteredExercises: [Exercise] {
        let exercises = exerciseStore.exercises
        let searchKeys = exerciseStore.searchKeys

        // Per-keystroke work happens ONCE here, not per exercise: fold the
        // query, collect alias targets ("pec deck" -> Machine Chest Fly, live
        // while typing via prefix), and take the fuzzy matcher's verdict
        // (memoized) so slang and hyphen mismatches still surface their target.
        let query = ExerciseAliases.searchFold(searchText)
        var aliasTargets: Set<String> = []
        var fuzzyTargetName: String?
        if !query.isEmpty {
            aliasTargets = ExerciseAliases.canonicalNames(matchingPrefix: searchText)
            fuzzyTargetName = exercises.resolvedExercise(named: searchText)?.name
        }

        var result: [Exercise] = []
        for (index, exercise) in exercises.enumerated() {
            guard selectedMuscleGroup == "All" || exercise.muscleGroup.rawValue == selectedMuscleGroup else { continue }
            guard selectedEquipment == "All" || exercise.equipment.rawValue == selectedEquipment else { continue }
            guard selectedMovementPattern == "All" || exercise.movementPattern.rawValue == selectedMovementPattern else { continue }

            let matchesSearch = query.isEmpty
                || (index < searchKeys.count && searchKeys[index].contains(query))
                || aliasTargets.contains(exercise.name)
                || exercise.name == fuzzyTargetName
            if matchesSearch {
                result.append(exercise)
            }
        }
        return result
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
                    filterSection
                    librarySection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .dismissKeyboardOnTap()
        .navigationTitle("Exercise Library")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search Exercises")
        // Cheap safety net: pick up custom exercises saved elsewhere.
        .onAppear(perform: exerciseStore.reloadCustomExercises)
    }

    private var filterSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("FILTERS")
                .microLabel()

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
            HStack(alignment: .firstTextBaseline) {
                Text("EXERCISES")
                    .microLabel()

                Spacer()

                Text("\(filteredExercises.count)")
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.textSecondary)
            }

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
    }

    private func filterPicker(title: String, selection: Binding<String>, options: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .microLabel()

            Picker(title, selection: selection) {
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .pickerStyle(.menu)
            .tint(AppTheme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(AppTheme.fieldBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
