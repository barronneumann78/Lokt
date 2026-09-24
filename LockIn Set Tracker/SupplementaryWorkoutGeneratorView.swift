import SwiftUI

/// Add-On Block. Look v2: the same vocabulary as Generate Workout — 26pt
/// title, prompt composer with hairline quick-idea chips under the one
/// gradient pill; the review stage is the draft card (BLOCK PREVIEW micro
/// label, editable title field, exercises • sets meta line with the LIVE chip
/// when a workout is in progress, numbered mono rows folded behind "+ N
/// more" that open into their fields) with Add This Block as THE gradient
/// pill and Try a Different Request as a ghost. Bindings, the client and
/// the destination sheet's routine-library calls are untouched.
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
    /// Exercise ids whose row is open (reasoning/tip plus the edit fields).
    /// Fresh blocks decode new ids, so rows start collapsed.
    @State private var expandedDetailIDs: Set<UUID> = []
    @State private var isDraftListExpanded = false

    private let client = SupplementaryWorkoutClient()
    private let promptSuggestions = [
        "Add a 10-minute ab finisher",
        "Give me a rear delt burnout after pull day",
        "Add a short warm-up for push day",
        "Give me a quick recovery block for sore legs"
    ]

    private static let foldedExerciseCount = 4
    private static let exerciseIndexWidth: CGFloat = 22

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
                .padding(.horizontal, AppTheme.screenPadding)
                .padding(.vertical, 20)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .dismissKeyboardOnTap()
        .keyboardDoneBar()
        .navigationTitle("")
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

    // MARK: - Prompt stage

    private var promptContent: some View {
        Group {
            screenTitle("Build a small extra block.")
            promptSection

            if let errorMessage {
                messageCard(title: "Add-On Needs Attention", text: errorMessage, tint: AppTheme.secondary)
            }
        }
    }

    private func screenTitle(_ title: String, subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 26, weight: .bold))
                .tracking(-0.3)
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 13))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(.bottom, 2)
    }

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("YOUR REQUEST")
                .microLabel()

            TrackerTextEditor(
                "Add a 10-minute ab finisher",
                text: $prompt,
                minHeight: 150,
                cornerRadius: 18
            )

            VStack(alignment: .leading, spacing: 12) {
                Text("QUICK IDEAS")
                    .microLabel()

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(promptSuggestions, id: \.self) { suggestion in
                            promptChip(suggestion) {
                                prompt = suggestion
                            }
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
        .padding(AppTheme.cardPadding)
        .glassCard()
    }

    private func promptChip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.caption.weight(.medium))
            .foregroundStyle(AppTheme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppTheme.surfaceElevated)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            }
    }

    // MARK: - Generating stage

    private var generatingContent: some View {
        VStack(spacing: 18) {
            Text("Building your add-on...")
                .font(.system(size: 26, weight: .bold))
                .tracking(-0.3)
                .foregroundStyle(AppTheme.textPrimary)
                .multilineTextAlignment(.center)

            ProgressView()
                .progressViewStyle(.circular)
                .tint(AppTheme.primary)
                .scaleEffect(1.2)

            Text(prompt)
                .font(.system(size: 15))
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .glassCard()
    }

    // MARK: - Review stage

    private var reviewContent: some View {
        Group {
            if let generatedBlock {
                VStack(alignment: .leading, spacing: 20) {
                    screenTitle(
                        "Review your add-on block",
                        subtitle: "\(generatedBlock.exercises.count) exercises • \(generatedBlock.totalSets) sets"
                    )

                    if let errorMessage {
                        messageCard(title: "Couldn’t Build the Add-On Yet", text: errorMessage, tint: AppTheme.secondary)
                    }

                    if let destinationMessage {
                        messageCard(title: "Add-On Ready", text: destinationMessage, tint: AppTheme.success)
                    }

                    draftCard(for: generatedBlock)
                }
            }
        }
    }

    private func draftCard(for generatedBlock: AIGeneratedRoutineDraft) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                Text("BLOCK PREVIEW")
                    .microLabel(AppTheme.accent)

                Spacer(minLength: 8)

                if let currentWorkoutTitle {
                    TagChip(title: "LIVE · \(currentWorkoutTitle)", isActive: true, systemImage: "bolt.fill")
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("BLOCK TITLE")
                    .microLabel()

                TrackerTextField("Block title", text: titleBinding)
                    .textFieldStyle(TrackerTextFieldStyle())
            }

            Text("\(generatedBlock.exercises.count) exercises • \(generatedBlock.totalSets) sets")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(AppTheme.textSecondary)

            RoutinePlainExplanationSection(draft: generatedBlock)

            hairline

            if isDiscoveryNudgeVisible {
                DiscoveryNudgeLine {
                    withAnimation(.easeOut(duration: 0.2)) {
                        isDiscoveryNudgeVisible = false
                    }
                }
            }

            draftExerciseList(for: generatedBlock)

            draftActions(for: generatedBlock)
        }
        .padding(18)
        .glassCard()
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                .stroke(AppTheme.accentHairline, lineWidth: 1)
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

    private var hairline: some View {
        Rectangle()
            .fill(AppTheme.cardBorder)
            .frame(height: 1)
    }

    private func draftExerciseList(for generatedBlock: AIGeneratedRoutineDraft) -> some View {
        let rows = Array(generatedBlock.exercises.enumerated())
        let hiddenCount = rows.count - Self.foldedExerciseCount
        let isFolded = hiddenCount > 0 && !isDraftListExpanded
        let visibleRows = isFolded ? Array(rows.prefix(Self.foldedExerciseCount)) : rows

        return VStack(alignment: .leading, spacing: 12) {
            ForEach(visibleRows, id: \.element.id) { item in
                draftExerciseRow(item.element, index: item.offset)
            }

            if isFolded {
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        isDraftListExpanded = true
                    }
                } label: {
                    Text("+ \(hiddenCount) more")
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.textTertiary)
                        .padding(.leading, Self.exerciseIndexWidth + 10)
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show \(hiddenCount) more exercises")
            }
        }
    }

    private func draftExerciseRow(_ exercise: AIGeneratedExercise, index: Int) -> some View {
        let matchedExercise = exerciseStore.exercises.resolvedExercise(named: exercise.name)
        let trimmedReasoning = exercise.reasoning?.trimmingCharacters(in: .whitespacesAndNewlines)
        let reasoning = (trimmedReasoning?.isEmpty == false) ? trimmedReasoning : nil
        let trimmedTip = exercise.tip?.trimmingCharacters(in: .whitespacesAndNewlines)
        let tip = (trimmedTip?.isEmpty == false) ? trimmedTip : nil
        let isExpanded = expandedDetailIDs.contains(exercise.id)
        let trimmedName = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)

        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(index + 1).")
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(AppTheme.textTertiary)
                .frame(width: Self.exerciseIndexWidth, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(trimmedName.isEmpty ? "Exercise name" : trimmedName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(trimmedName.isEmpty ? AppTheme.textTertiary : AppTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    ExerciseDetailDisclosureChevron(
                        id: exercise.id,
                        expandedIDs: $expandedDetailIDs,
                        font: .caption
                    )

                    Spacer(minLength: 8)

                    Text("\(max(1, exercise.sets)) sets • \(exercise.reps)")
                        .font(.system(.caption, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize()

                    ExerciseAskButton(
                        context: ExerciseAskContext(draft: exercise),
                        askTarget: $askTarget,
                        font: .footnote,
                        hinted: hints.showAskHint(sessionCount: workoutStore.sessions.count)
                    )

                    if let matchedExercise {
                        ExerciseInfoButton(
                            exercise: matchedExercise,
                            hinted: hints.showInfoHint(sessionCount: workoutStore.sessions.count)
                        )
                    }
                }

                if !isExpanded,
                   let recommendedSets = exercise.recommendedSets,
                   recommendedSets != max(1, exercise.sets) {
                    RecommendedSetsChip(
                        recommended: recommendedSets,
                        count: setBinding(for: index),
                        font: .caption
                    )
                }

                if isExpanded {
                    expandedRowDetails(exercise, index: index, reasoning: reasoning, tip: tip)
                }
            }
        }
        .exerciseDetailDisclosureTapArea(id: exercise.id, expandedIDs: $expandedDetailIDs, enabled: true)
    }

    private func expandedRowDetails(
        _ exercise: AIGeneratedExercise,
        index: Int,
        reasoning: String?,
        tip: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let reasoning {
                Text(reasoning)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let tip {
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
                                count: setBinding(for: index),
                                font: .caption
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

            HStack(spacing: 8) {
                Spacer()

                Button("Smart Swap") {
                    smartSwapIndex = SmartSwapIndex(index: index)
                }
                .buttonStyle(GhostButtonStyle(isCompact: true))

                Button("Remove") {
                    removeExercise(at: index)
                }
                .buttonStyle(GhostButtonStyle(isCompact: true))
            }
        }
        .padding(.top, 4)
    }

    /// THE gradient pill — Add This Block — over a ghost Try a Different Request.
    private func draftActions(for generatedBlock: AIGeneratedRoutineDraft) -> some View {
        VStack(spacing: 8) {
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
                isDraftListExpanded = false
                stage = .prompt
            }
            .buttonStyle(GhostButtonStyle())
        }
        .padding(.top, 2)
    }

    // MARK: - Bindings (unchanged)

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

    // MARK: - Generation (unchanged)

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

    private func messageCard(title: String, text: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(AppTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        }
    }
}

/// Where the block goes. Look v2: 22pt sheet title over the meta line,
/// micro-label sections of hairline option cards (the current workout, each
/// saved routine), and Create a New Routine as the sheet's one gradient pill
/// — the add-to-routine sheet on the exercise page reads the same way.
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
                    VStack(alignment: .leading, spacing: 24) {
                        header

                        if let addToCurrentWorkout, let currentWorkoutTitle {
                            currentWorkoutSection(addToCurrentWorkout: addToCurrentWorkout, currentWorkoutTitle: currentWorkoutTitle)
                        }

                        existingRoutineSection
                        createRoutineSection
                    }
                    .padding(.horizontal, AppTheme.screenPadding)
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(draft.title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)

            Text("\(draft.exercises.count) exercises • \(draft.totalSets) sets")
                .font(.system(size: 13))
                .monospacedDigit()
                .foregroundStyle(AppTheme.textSecondary)
        }
    }

    private func currentWorkoutSection(addToCurrentWorkout: @escaping (AIGeneratedRoutineDraft) -> AddExerciseResult, currentWorkoutTitle: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CURRENT WORKOUT")
                .microLabel(AppTheme.textSecondary)

            Button {
                let result = addToCurrentWorkout(draft)
                if result.didMutate {
                    onComplete(result.message)
                    dismiss()
                }
            } label: {
                optionRow(title: "Add to \(currentWorkoutTitle)", subtitle: nil, systemImage: "bolt.fill", accent: true)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var existingRoutineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("EXISTING ROUTINES")
                .microLabel(AppTheme.textSecondary)

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
                        optionRow(
                            title: routine.name,
                            subtitle: "\(routine.exercises.count) exercise\(routine.exercises.count == 1 ? "" : "s")",
                            systemImage: "plus",
                            accent: false
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var createRoutineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("NEW ROUTINE")
                .microLabel(AppTheme.textSecondary)

            Button("Create a New Routine") {
                if let routine = RoutineLibrary.createRoutine(from: draft, in: workoutStore) {
                    onComplete("Created \(routine.name).")
                    dismiss()
                }
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    /// Hairline option card: 16pt title (+ mono subtitle), a trailing glyph —
    /// the accent only on the live-workout row.
    private func optionRow(title: String, subtitle: String?, systemImage: String, accent: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .multilineTextAlignment(.leading)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }

            Spacer()

            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(accent ? AppTheme.primary : AppTheme.textSecondary)
        }
        .padding(AppTheme.rowPadding)
        .contentShape(Rectangle())
        .glassCard(cornerRadius: 18)
    }
}
