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
                    header

                    TrackerSearchField("Search Exercises", text: $searchText)

                    filterSection
                    librarySection
                }
                .padding(.horizontal, AppTheme.screenPadding)
                .padding(.vertical, 20)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .dismissKeyboardOnTap()
        // The screen carries its own 26pt title; the search capsule replaces
        // the nav-bar search field (same binding, same alias-aware filter).
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        // Cheap safety net: pick up custom exercises saved elsewhere.
        .onAppear(perform: exerciseStore.reloadCustomExercises)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Exercise Library")
                .font(.system(size: 26, weight: .bold))
                .tracking(-0.3)
                .foregroundStyle(AppTheme.textPrimary)

            Text("\(exerciseStore.exercises.count) exercises")
                .font(.system(size: 13))
                .monospacedDigit()
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(.bottom, 2)
    }

    private var filterSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("FILTERS")
                .microLabel(AppTheme.textSecondary)

            HStack(spacing: 12) {
                filterPicker(title: "Muscle", selection: $selectedMuscleGroup, options: muscleGroupOptions)
                filterPicker(title: "Equipment", selection: $selectedEquipment, options: equipmentOptions)
            }

            filterPicker(title: "Movement", selection: $selectedMovementPattern, options: movementPatternOptions)
        }
        .padding(AppTheme.cardPadding)
        .glassCard()
    }

    /// Hairline rows inside one card: thumbnail, 16pt name, one tag chip,
    /// chevron. Same row the routine editor's library uses.
    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("EXERCISES")
                    .microLabel(AppTheme.textSecondary)

                Spacer()

                TagChip(title: "\(filteredExercises.count)")
            }

            if filteredExercises.isEmpty {
                Text("No exercises match those filters.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.vertical, 12)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(filteredExercises.enumerated()), id: \.element.id) { item in
                        if item.offset > 0 {
                            Rectangle()
                                .fill(AppTheme.cardBorder)
                                .frame(height: 1)
                        }

                        NavigationLink(destination: ExerciseDetailView(exercise: item.element)) {
                            libraryRow(item.element)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(AppTheme.cardPadding)
        .glassCard()
    }

    private func libraryRow(_ exercise: Exercise) -> some View {
        HStack(spacing: 14) {
            ExerciseMediaView(
                imageName: exercise.imageName,
                placeholderSystemImageName: exercise.placeholderSystemImageName,
                height: 48,
                cornerRadius: 12,
                iconSize: 20,
                animateGIF: false,
                contentPadding: 6
            )
            .frame(width: 48)

            VStack(alignment: .leading, spacing: 6) {
                Text(exercise.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .multilineTextAlignment(.leading)

                if let displayTag = exercise.summaryTags.first {
                    TagChip(title: displayTag)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.textTertiary)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
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
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
