import SwiftUI

struct CreateRoutineView: View {
    let routineToEdit: Routine?
    var onSave: () -> Void

    @Environment(\.dismiss) private var dismiss

    @StateObject private var exerciseStore = ExerciseStore()
    @State private var routineName = ""
    @State private var selectedExercises: [String] = []
    @State private var preferredSetCounts: [String: Int] = [:]
    @State private var searchText = ""
    @State private var selectedMuscleGroup = "All"
    @State private var selectedEquipment = "All"
    @State private var selectedMovementPattern = "All"
    @State private var suggestedLibraryPattern: MovementPattern?
    @State private var navigateToExerciseLibrary = false
    @State private var hasLoadedRoutine = false
    @State private var draggedExercise: String?

    init(routineToEdit: Routine? = nil, onSave: @escaping () -> Void) {
        self.routineToEdit = routineToEdit
        self.onSave = onSave
    }

    private var isEditing: Bool {
        routineToEdit != nil
    }

    private var saveButtonTitle: String {
        isEditing ? "Save Changes" : "Save Routine"
    }

    private var canSaveRoutine: Bool {
        !trimmedRoutineName.isEmpty && !selectedExercises.isEmpty
    }

    private var saveBlockedMessage: String? {
        if trimmedRoutineName.isEmpty {
            return "Add a routine name to save."
        }

        if selectedExercises.isEmpty {
            return "Add at least one exercise to save."
        }

        return nil
    }

    private var screenTitle: String {
        isEditing ? "Edit Routine" : "Create Routine"
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

    private var selectedExerciseDetails: [Exercise] {
        selectedExercises.compactMap { selectedName in
            exerciseStore.exercises.first { $0.name == selectedName }
        }
    }

    private var detailAddAction: ExerciseDetailPrimaryAddAction {
        ExerciseDetailPrimaryAddAction(title: "Add to This Routine") { exercise in
            addExerciseFromDetail(exercise.name)
        }
    }

    private var workoutSuggestions: [WorkoutSuggestion] {
        let patterns = selectedExerciseDetails.map(\.movementPattern)
        let movementCounts = Dictionary(grouping: patterns, by: { $0 }).mapValues(\.count)
        let patternSet = Set(patterns)
        let pushPatterns: Set<MovementPattern> = [.horizontalPush, .verticalPush]
        var suggestions: [WorkoutSuggestion] = []

        for (pattern, count) in movementCounts.sorted(by: { $0.value > $1.value }) where count >= 2 {
            suggestions.append(
                WorkoutSuggestion(
                    message: "You already have multiple similar \(pattern.rawValue.lowercased()) movements."
                )
            )
        }

        if !patternSet.isDisjoint(with: pushPatterns) && !patternSet.contains(.verticalPull) {
            suggestions.append(
                WorkoutSuggestion(
                    message: "Consider adding a vertical pull for balance.",
                    recommendedPattern: .verticalPull
                )
            )
        }

        if !patternSet.isDisjoint(with: pushPatterns) && !patternSet.contains(.horizontalPull) {
            suggestions.append(
                WorkoutSuggestion(
                    message: "A horizontal pull could help round out this workout.",
                    recommendedPattern: .horizontalPull
                )
            )
        }

        if patternSet.contains(.squat) && !patternSet.contains(.hinge) {
            suggestions.append(
                WorkoutSuggestion(
                    message: "Consider adding a hinge movement to balance your lower-body work.",
                    recommendedPattern: .hinge
                )
            )
        } else if patternSet.contains(.hinge) && !patternSet.contains(.squat) {
            suggestions.append(
                WorkoutSuggestion(
                    message: "Consider adding a squat pattern for more complete leg coverage.",
                    recommendedPattern: .squat
                )
            )
        } else if selectedExerciseDetails.count >= 4 && !patternSet.contains(.squat) && !patternSet.contains(.hinge) {
            suggestions.append(
                WorkoutSuggestion(
                    message: "You may want a squat or hinge movement for lower-body balance.",
                    recommendedPattern: .squat
                )
            )
        }

        return Array(suggestions.prefix(3))
    }

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection
                    routineSetupSection

                    NavigationLink(
                        destination: ExerciseLibraryView(initialMovementPattern: suggestedLibraryPattern),
                        isActive: $navigateToExerciseLibrary
                    ) {
                        EmptyView()
                    }

                    selectedExercisesSection

                    if !selectedExercises.isEmpty && !workoutSuggestions.isEmpty {
                        suggestionSection
                    }

                    filterSection

                    exerciseLibrarySection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
        }
        .navigationTitle(screenTitle)
        .searchable(text: $searchText, prompt: "Search Exercises")
        .onAppear(perform: configureFormIfNeeded)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isEditing ? "Update your routine without losing the structure you already use." : "Create a routine that feels effortless to start.")
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)

            Text("Name it, add exercises, then drag to set the order.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
        }
    }

    private var routineSetupSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Routine Name")
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)

                TextField("Push Day, Pull Day, Legs...", text: $routineName)
                    .textFieldStyle(TrackerTextFieldStyle())
            }

            HStack(spacing: 10) {
                summaryChip(title: "\(selectedExercises.count) exercises", systemImage: "list.bullet")
                summaryChip(title: "\(totalPreferredSets) sets", systemImage: "number")
            }

            Button(saveButtonTitle) {
                saveRoutine()
            }
            .buttonStyle(PrimaryButtonStyle(fill: AppTheme.success))
            .disabled(!canSaveRoutine)
            .opacity(canSaveRoutine ? 1 : 0.6)

            if let saveBlockedMessage {
                Label(saveBlockedMessage, systemImage: "info.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.mutedFill)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
            }
        }
        .padding(20)
        .glassCard()
    }

    private var selectedExercisesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Selected Exercises")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppTheme.textPrimary)

                Spacer()

                Text("\(selectedExercises.count) total")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AppTheme.mutedFill)
                    .clipShape(Capsule())
            }

            Text("Drag to reorder, adjust sets, or remove anything you do not need.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)

            if selectedExercises.isEmpty {
                Text("No exercises selected yet. Tap exercises below to build the routine.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.vertical, 12)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(Array(selectedExercises.enumerated()), id: \.element) { item in
                        let index = item.offset
                        let exercise = item.element

                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    ExerciseTextNavigationLink(
                                        exerciseName: exercise,
                                        exercises: exerciseStore.exercises,
                                        primaryAddAction: detailAddAction
                                    ) {
                                        Text("\(index + 1). \(exercise)")
                                            .font(.headline)
                                            .foregroundStyle(AppTheme.textPrimary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }

                                    HStack(spacing: 8) {
                                        compactMetaChip(title: "\(preferredSetCount(for: exercise)) sets")

                                        if let detail = selectedExerciseDetails.first(where: { $0.name == exercise }) {
                                            compactMetaChip(title: detail.movementPattern.rawValue)
                                        }
                                    }
                                }
                            }

                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 8) {
                                    ExerciseDragHandle(exerciseName: exercise, draggedExercise: $draggedExercise)

                                    reorderButton(systemImage: "arrow.up", disabled: index == 0) {
                                        moveExercise(from: index, offset: -1)
                                    }

                                    reorderButton(systemImage: "arrow.down", disabled: index == selectedExercises.count - 1) {
                                        moveExercise(from: index, offset: 1)
                                    }

                                    Spacer(minLength: 0)

                                    Button("Remove") {
                                        toggleSelection(exercise)
                                    }
                                    .buttonStyle(SecondaryButtonStyle())
                                }

                                TrackerStepper(
                                    value: preferredSetBinding(for: exercise),
                                    range: 1...12,
                                    valueText: "Sets \(preferredSetCount(for: exercise))"
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(16)
                        .surfaceCard()
                        .onDrop(
                            of: [.plainText],
                            delegate: ExerciseReorderDropDelegate(
                                targetExercise: exercise,
                                exercises: $selectedExercises,
                                draggedExercise: $draggedExercise
                            )
                        )
                    }
                }
            }
        }
        .padding(20)
        .glassCard()
    }

    private var filterSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Filters")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppTheme.textPrimary)

                Spacer()

                Text("\(filteredExercises.count) matches")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AppTheme.mutedFill)
                    .clipShape(Capsule())
            }

            Text("Narrow the list when you want a faster add flow.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)

            HStack(spacing: 12) {
                filterPicker(title: "Muscle", selection: $selectedMuscleGroup, options: muscleGroupOptions)
                filterPicker(title: "Equipment", selection: $selectedEquipment, options: equipmentOptions)
            }

            filterPicker(title: "Movement", selection: $selectedMovementPattern, options: movementPatternOptions)
        }
        .padding(20)
        .glassCard()
    }

    private var suggestionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(AppTheme.secondary)

                Text("Builder Feedback")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppTheme.textPrimary)
            }

            Text("These are just optional hints to help keep the workout balanced.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)

            ForEach(workoutSuggestions) { suggestion in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "sparkles")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.primary)
                            .padding(.top, 3)

                        Text(suggestion.message)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let pattern = suggestion.recommendedPattern {
                        Button("View \(pattern.rawValue) Exercises") {
                            suggestedLibraryPattern = pattern
                            navigateToExerciseLibrary = true
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .surfaceCard(cornerRadius: AppTheme.controlCornerRadius)
            }
        }
        .padding(20)
        .glassCard()
    }

    private var exerciseLibrarySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Exercises")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppTheme.textPrimary)

                Spacer()

                Text("\(selectedExercises.count) selected")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AppTheme.mutedFill)
                    .clipShape(Capsule())
            }

            if filteredExercises.isEmpty {
                Text("No exercises match those filters.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.vertical, 12)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(filteredExercises) { exercise in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 8) {
                                ExerciseTextNavigationLink(
                                    exerciseName: exercise.name,
                                    exercises: exerciseStore.exercises,
                                    primaryAddAction: detailAddAction
                                ) {
                                    Text(exercise.name)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(AppTheme.textPrimary)
                                }

                                if let primaryTag = routineLibraryTags(for: exercise).first {
                                    exerciseTag(primaryTag)
                                }
                            }

                            Spacer()

                            Button {
                                toggleSelection(exercise.name)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: selectedExercises.contains(exercise.name) ? "checkmark.circle.fill" : "plus.circle.fill")
                                        .font(.headline)

                                    Text(selectedExercises.contains(exercise.name) ? "Added" : "Add")
                                        .font(.subheadline.weight(.semibold))
                                }
                                .foregroundStyle(selectedExercises.contains(exercise.name) ? AppTheme.success : AppTheme.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(selectedExercises.contains(exercise.name) ? AppTheme.success.opacity(0.12) : AppTheme.mutedFill)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(16)
                        .background(selectedExercises.contains(exercise.name) ? AppTheme.primary.opacity(0.18) : AppTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.rowCornerRadius, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: AppTheme.rowCornerRadius, style: .continuous)
                                .stroke(selectedExercises.contains(exercise.name) ? AppTheme.primary.opacity(0.35) : AppTheme.cardBorder, lineWidth: 1)
                        }
                    }
                }
            }
        }
        .padding(20)
        .glassCard()
    }

    private var trimmedRoutineName: String {
        routineName.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private func exerciseTag(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.medium))
            .foregroundStyle(AppTheme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppTheme.mutedFill)
            .clipShape(Capsule())
    }

    private func routineLibraryTags(for exercise: Exercise) -> [String] {
        let prioritizedTags = exercise.summaryTags.filter { !$0.isEmpty }
        if !prioritizedTags.isEmpty {
            return Array(prioritizedTags.prefix(1))
        }

        return [exercise.equipment.rawValue]
    }

    private func reorderButton(systemImage: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .foregroundStyle(disabled ? AppTheme.textSecondary.opacity(0.45) : AppTheme.primary)
                .padding(10)
                .background(AppTheme.surfaceElevated)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func summaryChip(title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))

            Text(title)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(AppTheme.textSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppTheme.mutedFill)
        .clipShape(Capsule())
    }

    private func compactMetaChip(title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(AppTheme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(AppTheme.mutedFill)
            .clipShape(Capsule())
    }

    private var totalPreferredSets: Int {
        selectedExercises.reduce(0) { $0 + preferredSetCount(for: $1) }
    }

    private func configureFormIfNeeded() {
        guard !hasLoadedRoutine else { return }

        if let routineToEdit {
            routineName = routineToEdit.name
            selectedExercises = routineToEdit.exercises
            preferredSetCounts = selectedExercises.reduce(into: [:]) { counts, exercise in
                counts[exercise] = routineToEdit.preferredSetCount(for: exercise)
            }
        }

        hasLoadedRoutine = true
    }

    private func preferredSetBinding(for exercise: String) -> Binding<Int> {
        Binding(
            get: { preferredSetCount(for: exercise) },
            set: { preferredSetCounts[exercise] = max(1, $0) }
        )
    }

    private func preferredSetCount(for exercise: String) -> Int {
        max(1, preferredSetCounts[exercise] ?? routineToEdit?.preferredSetCount(for: exercise) ?? 3)
    }

    private func moveExercise(from index: Int, offset: Int) {
        let newIndex = index + offset
        guard selectedExercises.indices.contains(index), selectedExercises.indices.contains(newIndex) else { return }
        let exercise = selectedExercises.remove(at: index)
        selectedExercises.insert(exercise, at: newIndex)
    }

    private func toggleSelection(_ exercise: String) {
        if let index = selectedExercises.firstIndex(of: exercise) {
            selectedExercises.remove(at: index)
            preferredSetCounts.removeValue(forKey: exercise)
        } else {
            selectedExercises.append(exercise)
            preferredSetCounts[exercise] = preferredSetCount(for: exercise)
        }
    }

    private func addExerciseFromDetail(_ exercise: String) -> AddExerciseResult {
        guard !selectedExercises.contains(exercise) else {
            return AddExerciseResult(message: "\(exercise) is already in this routine.", didMutate: false)
        }

        selectedExercises.append(exercise)
        preferredSetCounts[exercise] = preferredSetCount(for: exercise)
        return AddExerciseResult(message: "Added \(exercise) to this routine.", didMutate: true)
    }

    private func saveRoutine() {
        guard !trimmedRoutineName.isEmpty, !selectedExercises.isEmpty else { return }

        var historyNames = routineToEdit?.allKnownNames ?? []
        if let existingName = routineToEdit?.name {
            historyNames.append(existingName)
        }
        historyNames.append(trimmedRoutineName)

        let preferredCounts = selectedExercises.reduce(into: [String: Int]()) { counts, exercise in
            counts[exercise] = preferredSetCount(for: exercise)
        }

        let routine = Routine(
            id: routineToEdit?.id ?? UUID(),
            name: trimmedRoutineName,
            exercises: selectedExercises,
            preferredSetCounts: preferredCounts,
            historyNames: historyNames,
            importContext: syncedImportContext(using: selectedExercises, preferredCounts: preferredCounts)
        )

        var routines = loadSavedRoutines()
        if let index = routines.firstIndex(where: { $0.id == routine.id }) {
            routines[index] = routine
        } else {
            routines.append(routine)
        }

        if let encoded = try? JSONEncoder().encode(routines) {
            UserDefaults.standard.set(encoded, forKey: "routines")
        }

        onSave()
        dismiss()
    }

    private func loadSavedRoutines() -> [Routine] {
        if let data = UserDefaults.standard.data(forKey: "routines"),
           let decoded = try? JSONDecoder().decode([Routine].self, from: data) {
            return decoded
        }

        return []
    }

    private func syncedImportContext(using exercises: [String], preferredCounts: [String: Int]) -> RoutineImportContext? {
        guard let importContext = routineToEdit?.importContext else { return nil }

        let planLookup = Dictionary(uniqueKeysWithValues: importContext.exercisePlans.map { ($0.exerciseName.lowercased(), $0) })
        let updatedPlans = exercises.map { exerciseName -> RoutineImportedExercisePlan in
            var plan = planLookup[exerciseName.lowercased()] ?? RoutineImportedExercisePlan(
                exerciseName: exerciseName,
                sourceText: exerciseName,
                targetSets: preferredCounts[exerciseName],
                targetReps: nil,
                restSeconds: nil,
                notes: nil,
                intensityNotes: [],
                matchedExerciseName: exerciseName,
                isCustomExercise: false
            )
            plan.exerciseName = exerciseName
            plan.targetSets = preferredCounts[exerciseName]
            return plan
        }

        return RoutineImportContext(
            sourceKind: importContext.sourceKind,
            importedAt: importContext.importedAt,
            originalText: importContext.originalText,
            dayName: trimmedRoutineName,
            exercisePlans: updatedPlans
        )
    }
}

private struct WorkoutSuggestion: Identifiable {
    let message: String
    var recommendedPattern: MovementPattern? = nil

    var id: String { message }
}
