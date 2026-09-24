import SwiftUI

struct CreateRoutineView: View {
    let routineToEdit: Routine?
    var onSave: () -> Void

    @Environment(\.dismiss) private var dismiss

    @EnvironmentObject private var exerciseStore: ExerciseStore
    @EnvironmentObject private var workoutStore: WorkoutStore
    @ObservedObject private var hints = DiscoveryHints.shared
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
    @State private var askTarget: ExerciseAskContext?
    @State private var showRoutineCoach = false

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
                    screenHeader

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
                .padding(.horizontal, AppTheme.screenPadding)
                .padding(.vertical, 20)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .dismissKeyboardOnTap()
        // The screen carries its own 26pt title; the in-card search capsule
        // is the one search input (it was also bound to the nav-bar search).
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: configureFormIfNeeded)
        // Cheap safety net: pick up custom exercises saved elsewhere.
        .onAppear(perform: exerciseStore.reloadCustomExercises)
        .sheet(item: $askTarget) { context in
            ExerciseAskCoachSheet(context: context) { suggestion in
                switchExercise(context.name, to: suggestion.exerciseName)
            }
        }
        .sheet(isPresented: $showRoutineCoach) {
            RoutineEditorCoachSheet(snapshot: routineCoachSnapshot)
        }
    }

    // MARK: - Header

    private var screenHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(screenTitle)
                .font(.system(size: 26, weight: .bold))
                .tracking(-0.3)
                .foregroundStyle(AppTheme.textPrimary)

            Text("\(selectedExercises.count) exercise\(selectedExercises.count == 1 ? "" : "s") • \(totalPreferredSets) sets")
                .font(.system(size: 13))
                .monospacedDigit()
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(.bottom, 2)
    }

    // MARK: - Setup card
    // ROUTINE NAME field over THE gradient pill of the screen. The block
    // reason (empty name / no exercises) is one quiet line, not a box.

    private var routineSetupSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("ROUTINE NAME")
                    .microLabel()

                TrackerTextField("Push Day, Pull Day, Legs...", text: $routineName)
                    .textFieldStyle(TrackerTextFieldStyle())
            }

            Button(saveButtonTitle) {
                saveRoutine()
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!canSaveRoutine)
            .opacity(canSaveRoutine ? 1 : 0.6)

            if let saveBlockedMessage {
                Text(saveBlockedMessage)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textTertiary)
            }
        }
        .padding(AppTheme.cardPadding)
        .glassCard()
    }

    // MARK: - Selected exercises
    // Numbered mono rows on the elevated row surface: name link, set/pattern
    // chips, the ask button, then the reorder controls and the set stepper.

    private var selectedExercisesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("SELECTED EXERCISES")
                    .microLabel(AppTheme.textSecondary)

                Spacer()

                TagChip(title: "\(selectedExercises.count) total")
            }

            if selectedExercises.isEmpty {
                Text("No exercises selected yet. Tap exercises below to build the routine.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.vertical, 12)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(Array(selectedExercises.enumerated()), id: \.element) { item in
                        selectedExerciseRow(item.element, index: item.offset)
                    }
                }
            }
        }
        .padding(AppTheme.cardPadding)
        .glassCard()
    }

    private func selectedExerciseRow(_ exercise: String, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Text("\(index + 1).")
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.textTertiary)
                    .frame(width: 22, alignment: .leading)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 8) {
                    ExerciseTextNavigationLink(
                        exerciseName: exercise,
                        exercises: exerciseStore.exercises,
                        primaryAddAction: detailAddAction
                    ) {
                        Text(exercise)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 8) {
                        TagChip(title: "\(preferredSetCount(for: exercise)) sets")

                        if let detail = selectedExerciseDetails.first(where: { $0.name == exercise }) {
                            TagChip(title: detail.movementPattern.rawValue)
                        }
                    }
                }

                ExerciseAskButton(
                    context: ExerciseAskContext(
                        name: exercise,
                        sets: preferredSetCount(for: exercise)
                    ),
                    askTarget: $askTarget,
                    font: .subheadline,
                    hinted: hints.showAskHint(sessionCount: workoutStore.sessions.count)
                )
            }

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
                .buttonStyle(GhostButtonStyle(isCompact: true))
            }

            TrackerStepper(
                value: preferredSetBinding(for: exercise),
                range: 1...12,
                valueText: "Sets \(preferredSetCount(for: exercise))"
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(AppTheme.rowPadding)
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

    // MARK: - Filters

    private var filterSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("FILTERS")
                    .microLabel(AppTheme.textSecondary)

                Spacer()

                TagChip(title: "\(filteredExercises.count) matches")
            }

            HStack(spacing: 12) {
                filterPicker(title: "Muscle", selection: $selectedMuscleGroup, options: muscleGroupOptions)
                filterPicker(title: "Equipment", selection: $selectedEquipment, options: equipmentOptions)
            }

            filterPicker(title: "Movement", selection: $selectedMovementPattern, options: movementPatternOptions)
        }
        .padding(AppTheme.cardPadding)
        .glassCard()
    }

    // MARK: - Builder feedback
    // Hairline-separated lines instead of boxes inside the card.

    private var suggestionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("BUILDER FEEDBACK")
                .microLabel(AppTheme.textSecondary)

            ForEach(Array(workoutSuggestions.enumerated()), id: \.element.id) { item in
                if item.offset > 0 {
                    hairline
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(item.element.message)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let pattern = item.element.recommendedPattern {
                        Button("View \(pattern.rawValue) Exercises") {
                            suggestedLibraryPattern = pattern
                            navigateToExerciseLibrary = true
                        }
                        .buttonStyle(GhostButtonStyle(isCompact: true))
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(AppTheme.cardPadding)
        .glassCard()
    }

    // MARK: - Library
    // Search capsule, the Ask Coach ghost, then hairline rows: name link +
    // one tag chip, and an Add / Added chip on the right.

    private var exerciseLibrarySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("EXERCISES")
                    .microLabel(AppTheme.textSecondary)

                Spacer()

                TagChip(title: "\(selectedExercises.count) selected")
            }

            TrackerSearchField("Search this exercise list", text: $searchText)

            Button {
                askCoachAboutRoutine()
            } label: {
                Label("Ask Coach about this workout", systemImage: "message")
            }
            .buttonStyle(GhostButtonStyle())
            .disabled(selectedExercises.isEmpty)
            .opacity(selectedExercises.isEmpty ? 0.55 : 1)

            if filteredExercises.isEmpty {
                Text("No exercises match those filters.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.vertical, 12)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(filteredExercises.enumerated()), id: \.element.id) { item in
                        if item.offset > 0 {
                            hairline
                        }

                        libraryRow(item.element)
                    }
                }
            }
        }
        .padding(AppTheme.cardPadding)
        .glassCard()
    }

    private func libraryRow(_ exercise: Exercise) -> some View {
        let isAdded = selectedExercises.contains(exercise.name)

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                ExerciseTextNavigationLink(
                    exerciseName: exercise.name,
                    exercises: exerciseStore.exercises,
                    primaryAddAction: detailAddAction
                ) {
                    Text(exercise.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .multilineTextAlignment(.leading)
                }

                if let primaryTag = routineLibraryTags(for: exercise).first {
                    TagChip(title: primaryTag)
                }
            }

            Spacer()

            Button {
                toggleSelection(exercise.name)
            } label: {
                TagChip(
                    title: isAdded ? "Added" : "Add",
                    isActive: isAdded,
                    systemImage: isAdded ? "checkmark" : "plus"
                )
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isAdded ? "Remove \(exercise.name)" : "Add \(exercise.name)")
        }
        .padding(.vertical, 12)
    }

    private var hairline: some View {
        Rectangle()
            .fill(AppTheme.cardBorder)
            .frame(height: 1)
    }

    private var trimmedRoutineName: String {
        routineName.trimmingCharacters(in: .whitespacesAndNewlines)
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
                .font(.caption.weight(.bold))
                .foregroundStyle(disabled ? AppTheme.textTertiary : AppTheme.textPrimary)
                .frame(width: 34, height: 34)
                .background(AppTheme.surfaceElevated)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(AppTheme.cardBorder, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
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

    /// Replaces the selected exercise in place, retaining its set target and
    /// order. If the suggested alternative already exists, keep that one and
    /// remove the source rather than creating a duplicate exercise row.
    private func switchExercise(_ currentExercise: String, to alternative: String) {
        guard currentExercise != alternative,
              let sourceIndex = selectedExercises.firstIndex(of: currentExercise) else { return }

        let sourceSetCount = preferredSetCount(for: currentExercise)
        if selectedExercises.contains(alternative) {
            selectedExercises.remove(at: sourceIndex)
            preferredSetCounts.removeValue(forKey: currentExercise)
        } else {
            selectedExercises[sourceIndex] = alternative
            preferredSetCounts.removeValue(forKey: currentExercise)
            preferredSetCounts[alternative] = sourceSetCount
        }
    }

    private func askCoachAboutRoutine() {
        guard !selectedExercises.isEmpty else { return }
        showRoutineCoach = true
    }

    private var routineCoachSnapshot: CoachRoutineSnapshot {
        CoachRoutineSnapshot(
            routineID: routineToEdit?.id,
            routineName: trimmedRoutineName.isEmpty ? "Routine in progress" : trimmedRoutineName,
            exercises: selectedExercises
        )
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

        workoutStore.upsertRoutine(routine)

        onSave()
        dismiss()
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
