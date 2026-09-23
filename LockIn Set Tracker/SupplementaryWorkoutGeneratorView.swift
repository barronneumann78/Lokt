import SwiftUI

struct SupplementaryWorkoutGeneratorView: View {
    private struct SmartSwapIndex: Identifiable {
        let index: Int
        var id: Int { index }
    }

    var onSave: () -> Void
    var addToCurrentWorkout: ((AIGeneratedRoutineDraft) -> AddExerciseResult)? = nil
    var currentWorkoutTitle: String? = nil

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var exerciseStore: ExerciseStore
    @EnvironmentObject private var workoutStore: WorkoutStore
    @ObservedObject private var hints = DiscoveryHints.shared

    @State private var stage: AIWorkoutGenerationStage = .prompt
    @State private var isDiscoveryNudgeVisible = false
    @State private var prompt = ""
    @State private var generatedBlock: AIGeneratedRoutineDraft?
    @State private var errorMessage: String?
    @State private var destinationMessage: String?
    @State private var showDestinationSheet = false
    @State private var smartSwapIndex: SmartSwapIndex?
    @State private var askTarget: ExerciseAskContext?
    /// Exercise ids whose reasoning/tip block is open. Fresh blocks decode new
    /// ids, so cards naturally start collapsed.
    @State private var expandedDetailIDs: Set<UUID> = []

    private let client = SupplementaryWorkoutClient()
    private let promptSuggestions = [
        "Add a 10-minute ab finisher",
        "Give me a rear delt burnout after pull day",
        "Add a short warm-up for push day",
        "Give me a quick recovery block for sore legs"
    ]

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    switch stage {
                    case .prompt:
                        promptContent
                    case .generating:
                        generatingContent
                    case .review:
                        reviewContent
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .dismissKeyboardOnTap()
        .keyboardDoneBar()
        .navigationTitle("Add-On Block")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $smartSwapIndex) { target in
            if let exercise = generatedBlock?.exercises[safe: target.index] {
                ExerciseSwapSheet(
                    target: ExerciseSwapTarget(
                        exerciseName: exercise.name,
                        sourceNote: "Find a replacement that keeps this add-on block pointed at the same job."
                    ),
                    exercises: exerciseStore.exercises
                ) { suggestion in
                    applySmartSwap(suggestion, at: target.index)
                }
            }
        }
        .sheet(isPresented: $showDestinationSheet) {
            if let generatedBlock {
                SupplementaryWorkoutDestinationSheet(
                    draft: generatedBlock,
                    currentWorkoutTitle: currentWorkoutTitle,
                    addToCurrentWorkout: addToCurrentWorkout,
                    onComplete: handleDestinationResult
                )
            }
        }
        .sheet(item: $askTarget) { context in
            ExerciseAskCoachSheet(context: context)
        }
    }

    private var promptContent: some View {
        Group {
            headerSection
            promptSection

            if let errorMessage {
                messageCard(title: "Add-On Needs Attention", text: errorMessage, tint: AppTheme.secondary)
            }
        }
    }

    private var headerSection: some View {
        Text("Build a small extra block.")
            .font(.system(size: 30, weight: .bold))
            .tracking(-0.5)
            .foregroundStyle(AppTheme.textPrimary)
    }

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("YOUR REQUEST")
                .microLabel()

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AppTheme.fieldBackground)

                if prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Add a 10-minute ab finisher")
                        .font(.body)
                        .foregroundStyle(AppTheme.textSecondary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                }

                TextEditor(text: $prompt)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .frame(minHeight: 150)
                    .trackerTextEditorStyle()
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("QUICK IDEAS")
                    .microLabel()

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(promptSuggestions, id: \.self) { suggestion in
                            Button(suggestion) {
                                prompt = suggestion
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Button("Generate Add-On") {
                generateBlock()
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).count < 8)
            .opacity(prompt.trimmingCharacters(in: .whitespacesAndNewlines).count < 8 ? 0.6 : 1)
        }
        .padding(20)
        .glassCard()
    }

    private var generatingContent: some View {
        VStack(spacing: 18) {
            Text("Building your add-on...")
                .font(.system(size: 30, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(AppTheme.textPrimary)
                .multilineTextAlignment(.center)

            ProgressView()
                .progressViewStyle(.circular)
                .tint(AppTheme.primary)
                .scaleEffect(1.2)

            Text(prompt)
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .glassCard()
    }

    private var reviewContent: some View {
        Group {
            if let generatedBlock {
                VStack(alignment: .leading, spacing: 20) {
                    if let errorMessage {
                        messageCard(title: "Couldn’t Build the Add-On Yet", text: errorMessage, tint: AppTheme.secondary)
                    }

                    if let destinationMessage {
                        messageCard(title: "Add-On Ready", text: destinationMessage, tint: AppTheme.success)
                    }

                    reviewHeader(for: generatedBlock)
                    exerciseSection(for: generatedBlock)
                    reviewActions(for: generatedBlock)
                }
            }
        }
    }

    private func reviewHeader(for generatedBlock: AIGeneratedRoutineDraft) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Review your add-on block")
                .font(.system(size: 30, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(AppTheme.textPrimary)

            HStack(spacing: 10) {
                statPill(title: "\(generatedBlock.exercises.count)", subtitle: "Exercises")
                statPill(title: "\(generatedBlock.totalSets)", subtitle: "Sets")
                if let currentWorkoutTitle {
                    statPill(title: "Live", subtitle: currentWorkoutTitle)
                }
            }

            RoutinePlainExplanationSection(draft: generatedBlock)

            VStack(alignment: .leading, spacing: 10) {
                Text("BLOCK TITLE")
                    .microLabel()

                TrackerTextField("Block title", text: titleBinding)
                    .textFieldStyle(TrackerTextFieldStyle())
            }
        }
        .padding(20)
        .glassCard()
    }

    private func exerciseSection(for generatedBlock: AIGeneratedRoutineDraft) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("BLOCK PREVIEW")
                .microLabel()

            if isDiscoveryNudgeVisible {
                DiscoveryNudgeLine {
                    withAnimation(.easeOut(duration: 0.2)) {
                        isDiscoveryNudgeVisible = false
                    }
                }
            }

            ForEach(Array(generatedBlock.exercises.enumerated()), id: \.element.id) { item in
                exerciseCard(index: item.offset, exercise: item.element)
            }
        }
        .onAppear {
            guard hints.shouldOfferNudge(sessionCount: workoutStore.sessions.count) else { return }
            isDiscoveryNudgeVisible = true
            hints.markNudgeSeen()
        }
        .onChange(of: hints.interactionCount) {
            withAnimation(.easeOut(duration: 0.2)) {
                isDiscoveryNudgeVisible = false
            }
        }
    }

    private func exerciseCard(index: Int, exercise: AIGeneratedExercise) -> some View {
        let matchedExercise = exerciseStore.exercises.resolvedExercise(named: exercise.name)
        let trimmedReasoning = exercise.reasoning?.trimmingCharacters(in: .whitespacesAndNewlines)
        let reasoning = (trimmedReasoning?.isEmpty == false) ? trimmedReasoning : nil
        let trimmedTip = exercise.tip?.trimmingCharacters(in: .whitespacesAndNewlines)
        let tip = (trimmedTip?.isEmpty == false) ? trimmedTip : nil
        let hasDisclosure = reasoning != nil || tip != nil
        let isExpanded = expandedDetailIDs.contains(exercise.id)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                HStack(spacing: 8) {
                    Text("EXERCISE \(index + 1)")
                        .microLabel()
                        .monospacedDigit()

                    if hasDisclosure {
                        ExerciseDetailDisclosureChevron(id: exercise.id, expandedIDs: $expandedDetailIDs)
                    }
                }

                Spacer()

                ExerciseAskButton(
                    context: ExerciseAskContext(draft: exercise),
                    askTarget: $askTarget,
                    hinted: hints.showAskHint(sessionCount: workoutStore.sessions.count)
                )

                if let matchedExercise {
                    ExerciseInfoButton(
                        exercise: matchedExercise,
                        hinted: hints.showInfoHint(sessionCount: workoutStore.sessions.count)
                    )
                }
            }

            if isExpanded, let reasoning {
                Text(reasoning)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isExpanded, let tip {
                Text(tip)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("EXERCISE NAME")
                    .microLabel()

                TrackerTextField("Exercise name", text: nameBinding(for: index))
                    .textFieldStyle(TrackerTextFieldStyle())
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("SETS")
                            .microLabel()

                        if let recommendedSets = exercise.recommendedSets {
                            RecommendedSetsChip(
                                recommended: recommendedSets,
                                count: setBinding(for: index)
                            )
                        }
                    }

                    TrackerStepper(
                        value: setBinding(for: index),
                        range: 1...8,
                        valueText: "\(max(1, exercise.sets)) sets"
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("REPS / TIME")
                        .microLabel()

                    TrackerTextField("Reps or time", text: repsBinding(for: index))
                        .textFieldStyle(TrackerTextFieldStyle())
                }
            }

            HStack(spacing: 10) {
                Spacer()

                Button("Smart Swap") {
                    smartSwapIndex = SmartSwapIndex(index: index)
                }
                .buttonStyle(SecondaryButtonStyle())

                Button("Remove") {
                    removeExercise(at: index)
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(18)
        .exerciseDetailDisclosureTapArea(id: exercise.id, expandedIDs: $expandedDetailIDs, enabled: hasDisclosure)
        .glassCard()
    }

    private func reviewActions(for generatedBlock: AIGeneratedRoutineDraft) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("Add This Block") {
                showDestinationSheet = true
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!canSave(generatedBlock))
            .opacity(canSave(generatedBlock) ? 1 : 0.6)

            Button("Try a Different Request") {
                self.generatedBlock = nil
                destinationMessage = nil
                errorMessage = nil
                expandedDetailIDs = []
                stage = .prompt
            }
            .buttonStyle(PrimaryButtonStyle(fill: AppTheme.surfaceElevated))
        }
    }

    private var titleBinding: Binding<String> {
        Binding(
            get: { generatedBlock?.title ?? "" },
            set: { newValue in
                guard var generatedBlock else { return }
                generatedBlock.title = newValue
                self.generatedBlock = generatedBlock
            }
        )
    }

    private func nameBinding(for index: Int) -> Binding<String> {
        Binding(
            get: { generatedBlock?.exercises[safe: index]?.name ?? "" },
            set: { newValue in
                guard var generatedBlock,
                      generatedBlock.exercises.indices.contains(index) else { return }
                generatedBlock.exercises[index].name = newValue
                self.generatedBlock = generatedBlock
            }
        )
    }

    private func repsBinding(for index: Int) -> Binding<String> {
        Binding(
            get: { generatedBlock?.exercises[safe: index]?.reps ?? "" },
            set: { newValue in
                guard var generatedBlock,
                      generatedBlock.exercises.indices.contains(index) else { return }
                generatedBlock.exercises[index].reps = newValue
                self.generatedBlock = generatedBlock
            }
        )
    }

    private func setBinding(for index: Int) -> Binding<Int> {
        Binding(
            get: { max(1, generatedBlock?.exercises[safe: index]?.sets ?? 3) },
            set: { newValue in
                guard var generatedBlock,
                      generatedBlock.exercises.indices.contains(index) else { return }
                generatedBlock.exercises[index].sets = max(1, newValue)
                self.generatedBlock = generatedBlock
            }
        )
    }

    private func removeExercise(at index: Int) {
        guard var generatedBlock,
              generatedBlock.exercises.indices.contains(index) else { return }
        generatedBlock.exercises.remove(at: index)
        self.generatedBlock = generatedBlock
    }

    private func applySmartSwap(_ suggestion: ExerciseSwapSuggestion, at index: Int) {
        guard var generatedBlock,
              generatedBlock.exercises.indices.contains(index) else { return }

        generatedBlock.exercises[index].name = suggestion.exerciseName
        self.generatedBlock = generatedBlock
    }

    private func canSave(_ generatedBlock: AIGeneratedRoutineDraft) -> Bool {
        let trimmedTitle = generatedBlock.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !generatedBlock.exercises.isEmpty else { return false }

        return generatedBlock.exercises.allSatisfy { exercise in
            !exercise.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !exercise.reps.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func generateBlock() {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedPrompt.count >= 8 else {
            errorMessage = SupplementaryWorkoutError.invalidPrompt.localizedDescription
            return
        }

        errorMessage = nil
        destinationMessage = nil
        stage = .generating

        Task {
            do {
                let block = try await client.generateBlock(from: trimmedPrompt)
                generatedBlock = block
                stage = .review
            } catch {
                errorMessage = error.localizedDescription
                stage = .prompt
            }
        }
    }

    private func handleDestinationResult(_ message: String) {
        destinationMessage = message
        onSave()
        dismiss()
    }

    private func statPill(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 26, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(AppTheme.textPrimary)

            Text(subtitle.uppercased())
                .microLabel()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .surfaceCard()
    }

    private func messageCard(title: String, text: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(20)
        .background(tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        }
    }
}

private struct SupplementaryWorkoutDestinationSheet: View {
    let draft: AIGeneratedRoutineDraft
    var currentWorkoutTitle: String?
    var addToCurrentWorkout: ((AIGeneratedRoutineDraft) -> AddExerciseResult)?
    var onComplete: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var workoutStore: WorkoutStore
    @State private var routines: [Routine] = []

    var body: some View {
        NavigationView {
            ZStack {
                AppBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        headerCard

                        if let addToCurrentWorkout, let currentWorkoutTitle {
                            currentWorkoutSection(addToCurrentWorkout: addToCurrentWorkout, currentWorkoutTitle: currentWorkoutTitle)
                        }

                        existingRoutineSection
                        createRoutineSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle("Add Block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            routines = workoutStore.routines
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(draft.title)
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)

            Text("\(draft.exercises.count) exercises • \(draft.totalSets) sets")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(20)
        .glassCard()
    }

    private func currentWorkoutSection(addToCurrentWorkout: @escaping (AIGeneratedRoutineDraft) -> AddExerciseResult, currentWorkoutTitle: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CURRENT WORKOUT")
                .microLabel()

            Button {
                let result = addToCurrentWorkout(draft)
                if result.didMutate {
                    onComplete(result.message)
                    dismiss()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "bolt.horizontal.circle.fill")
                        .font(.title3)
                        .foregroundStyle(AppTheme.primary)

                    Text("Add to \(currentWorkoutTitle)")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Spacer()
                }
                .padding(16)
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .glassCard()
    }

    @ViewBuilder
    private var existingRoutineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("EXISTING ROUTINES")
                .microLabel()

            if routines.isEmpty {
                Text("You don’t have any saved routines yet.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.vertical, 6)
            } else {
                ForEach(routines) { routine in
                    Button {
                        let result = RoutineLibrary.addExercises(
                            from: draft,
                            toRoutineID: routine.id,
                            in: workoutStore
                        )
                        if result.didMutate {
                            onComplete(result.message)
                            dismiss()
                        }
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(routine.name)
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(AppTheme.textPrimary)

                                Text("\(routine.exercises.count) exercises")
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(AppTheme.textSecondary)
                            }

                            Spacer()

                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(AppTheme.textPrimary)
                        }
                        .padding(16)
                        .background(AppTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(20)
        .glassCard()
    }

    private var createRoutineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NEW ROUTINE")
                .microLabel()

            Button {
                if let routine = RoutineLibrary.createRoutine(from: draft, in: workoutStore) {
                    onComplete("Created \(routine.name).")
                    dismiss()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus.square.on.square")
                        .font(.title3)
                        .foregroundStyle(AppTheme.textPrimary)

                    Text("Create a New Routine")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Spacer()
                }
                .padding(16)
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .glassCard()
    }
}
