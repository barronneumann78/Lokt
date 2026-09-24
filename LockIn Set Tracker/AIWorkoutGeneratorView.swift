import SwiftUI

/// Generate Workout. Look v2: a 26pt title, the prompt composer on the field
/// fill with hairline quick-idea chips and the one gradient Generate pill;
/// the review stage is the Coach draft card — WORKOUT DRAFT micro label, the
/// editable title field, an exercises • sets meta line, every exercise as a
/// `DraftExerciseRow` (the name on its own line beside the 44pt info button,
/// sets • reps beneath; tap a row to open its reasoning and the name / sets /
/// reps / note fields with Smart Swap and Remove — no "+ N more" fold), then Save
/// Routine as THE gradient pill beside a Revise ghost that focuses the coach
/// composer below. Every binding, the revision service, the review-before-save
/// flow and `AIWorkoutRoutineSaver` are untouched.
struct AIWorkoutGeneratorView: View {
    private struct SmartSwapIndex: Identifiable {
        let index: Int
        var id: Int { index }
    }

    var onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var exerciseStore: ExerciseStore
    @EnvironmentObject private var workoutStore: WorkoutStore
    @ObservedObject private var hints = DiscoveryHints.shared

    @State private var stage: AIWorkoutGenerationStage = .prompt
    @State private var isDiscoveryNudgeVisible = false
    @State private var prompt = ""
    @State private var generatedRoutine: AIGeneratedRoutineDraft?
    @State private var errorMessage: String?
    @State private var revisionPrompt = ""
    @State private var conversationMessages: [AIWorkoutConversationMessage] = []
    @State private var latestCoachChangeSummary: String?
    @State private var smartSwapIndex: SmartSwapIndex?
    @State private var askTarget: ExerciseAskContext?
    @State private var isApplyingRevision = false
    /// Exercise ids whose row is open (reasoning/tip plus the edit fields).
    /// Fresh drafts and revisions decode new ids, so rows start collapsed.
    @State private var expandedDetailIDs: Set<UUID> = []
    @FocusState private var revisionFocused: Bool

    private let client = AIWorkoutGeneratorClient()
    private let promptSuggestions = [
        "Make me a 45-minute push day with dumbbells only",
        "Build a beginner upper body workout for a busy gym",
        "Give me a pull day focused on back thickness and biceps",
        "Create a full body workout for a small apartment gym"
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
            if let exercise = generatedRoutine?.exercises[safe: target.index] {
                ExerciseSwapSheet(
                    target: ExerciseSwapTarget(
                        exerciseName: exercise.name,
                        sourceNote: "Find a replacement that keeps the training intent of this draft."
                    ),
                    exercises: exerciseStore.exercises
                ) { suggestion in
                    applySmartSwap(suggestion, at: target.index)
                }
            }
        }
        .sheet(item: $askTarget) { context in
            ExerciseAskCoachSheet(context: context)
        }
    }

    // MARK: - Prompt stage

    private var promptContent: some View {
        Group {
            screenTitle("Describe the workout you want.")
            promptSection

            if let errorMessage {
                messageCard(title: "Generation Needs Attention", text: errorMessage, tint: AppTheme.secondary)
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
            Text("YOUR PROMPT")
                .microLabel()

            TrackerTextEditor(
                "Make me a 45-minute push day with dumbbells only",
                text: $prompt,
                minHeight: 170,
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

            Button("Generate Workout") {
                generateWorkout()
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).count < 8)
            .opacity(prompt.trimmingCharacters(in: .whitespacesAndNewlines).count < 8 ? 0.6 : 1)
        }
        .padding(AppTheme.cardPadding)
        .glassCard()
    }

    /// Prompt chip in the Coach tab's vocabulary: hairline capsule on the
    /// elevated surface; tapping drops the text into the composer.
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
            Text("Building your routine...")
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
            if let generatedRoutine {
                VStack(alignment: .leading, spacing: 20) {
                    screenTitle(
                        "Review your workout",
                        subtitle: "\(generatedRoutine.exercises.count) exercises • \(generatedRoutine.totalSets) sets"
                    )

                    if let errorMessage {
                        messageCard(title: "Couldn’t Update the Workout Yet", text: errorMessage, tint: AppTheme.secondary)
                    }

                    draftCard(for: generatedRoutine)
                    revisionSection(for: generatedRoutine)
                }
            }
        }
    }

    /// The Coach draft card: WORKOUT DRAFT micro label with the readiness
    /// line, the editable title field, an exercises • sets • known meta line,
    /// the plain-words explanation, a hairline, the numbered rows, then the
    /// action row. The accent hairline over `glassCard()` makes it the one
    /// accent-bordered card on the screen.
    private func draftCard(for generatedRoutine: AIGeneratedRoutineDraft) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                Text("WORKOUT DRAFT")
                    .microLabel(AppTheme.accent)

                Spacer(minLength: 8)

                readinessLine(for: generatedRoutine)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("ROUTINE TITLE")
                    .microLabel()

                TrackerTextField("Workout Title", text: titleBinding)
                    .textFieldStyle(TrackerTextFieldStyle())
            }

            Text("\(generatedRoutine.exercises.count) exercises • \(generatedRoutine.totalSets) sets • \(matchedLibraryExerciseCount(for: generatedRoutine)) known")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(AppTheme.textSecondary)

            RoutinePlainExplanationSection(draft: generatedRoutine)

            hairline

            if isDiscoveryNudgeVisible {
                DiscoveryNudgeLine {
                    withAnimation(.easeOut(duration: 0.2)) {
                        isDiscoveryNudgeVisible = false
                    }
                }
            }

            draftExerciseList(for: generatedRoutine)

            draftActions(for: generatedRoutine)
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

    /// The old readiness banner as one quiet line: a success check or an
    /// amber triangle beside the same words.
    private func readinessLine(for generatedRoutine: AIGeneratedRoutineDraft) -> some View {
        let ready = canSave(generatedRoutine)

        return HStack(spacing: 5) {
            Image(systemName: ready ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(ready ? AppTheme.success : AppTheme.secondary)

            Text(ready ? "Draft looks ready to save" : "A few details still need review")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(1)
        }
    }

    private var hairline: some View {
        Rectangle()
            .fill(AppTheme.cardBorder)
            .frame(height: 1)
    }

    // MARK: Draft exercise list

    private func draftExerciseList(for generatedRoutine: AIGeneratedRoutineDraft) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(generatedRoutine.exercises.enumerated()), id: \.element.id) { item in
                draftExerciseRow(item.element, index: item.offset)
            }
        }
    }

    /// One `DraftExerciseRow` (the shared name / info / sets • reps / chevron /
    /// ask row). Beneath it, this surface's own pieces: the Check Name chip
    /// for an unmatched name, the Recommended sets chip while the count
    /// differs and the row is closed, and — open — the coach's reasoning/tip
    /// with the name / sets / reps / note fields, Smart Swap and Remove: the
    /// same edits as before, one tap away.
    private func draftExerciseRow(_ exercise: AIGeneratedExercise, index: Int) -> some View {
        let matchedExercise = exerciseStore.exercises.resolvedExercise(named: exercise.name)
        let reasoning = nonEmptyText(exercise.reasoning)
        let tip = nonEmptyText(exercise.tip)
        let isExpanded = expandedDetailIDs.contains(exercise.id)

        return DraftExerciseRow(
            index: index,
            name: exercise.name,
            sets: exercise.sets,
            reps: exercise.reps,
            disclosureID: exercise.id,
            expandedIDs: $expandedDetailIDs,
            showsDisclosure: true,
            infoExercise: matchedExercise,
            askContext: ExerciseAskContext(draft: exercise),
            askTarget: $askTarget,
            askHinted: hints.showAskHint(sessionCount: workoutStore.sessions.count),
            infoHinted: hints.showInfoHint(sessionCount: workoutStore.sessions.count)
        ) {
            if matchedExercise == nil {
                aiStatusChip(title: "Check Name", color: AppTheme.secondary)
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
                        range: 1...10,
                        valueText: "\(max(1, exercise.sets)) sets"
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("REPS")
                        .microLabel()

                    TrackerTextField("Reps", text: repsBinding(for: index))
                        .textFieldStyle(TrackerTextFieldStyle())
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("NOTE")
                    .microLabel()

                TrackerTextField("Optional note", text: notesBinding(for: index), axis: .vertical)
                    .textFieldStyle(TrackerTextFieldStyle())
                    .lineLimit(1...3)
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

    // MARK: Draft actions

    /// THE gradient pill of the screen — Save Routine — beside a fixed-width
    /// Revise ghost that hands focus to the coach composer; Try a Different
    /// Prompt as a ghost pill beneath.
    private func draftActions(for generatedRoutine: AIGeneratedRoutineDraft) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Button("Save Routine") {
                    saveGeneratedRoutine()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isApplyingRevision || !canSave(generatedRoutine))
                .opacity(!isApplyingRevision && canSave(generatedRoutine) ? 1 : 0.6)

                Button("Revise") {
                    revisionFocused = true
                }
                .buttonStyle(GhostButtonStyle(verticalPadding: 17))
                .frame(width: 96)
            }

            Button("Try a Different Prompt") {
                self.generatedRoutine = nil
                conversationMessages = []
                latestCoachChangeSummary = nil
                revisionPrompt = ""
                errorMessage = nil
                expandedDetailIDs = []
                stage = .prompt
            }
            .buttonStyle(GhostButtonStyle())
        }
        .padding(.top, 2)
    }

    // MARK: Coach chat (revisions)

    /// COACH CHAT: the conversation in the Coach tab's vocabulary, the
    /// "Draft updated" line, and the composer — a 50pt card capsule with a
    /// hairline send circle (not the gradient: Save Routine owns it here).
    private func revisionSection(for generatedRoutine: AIGeneratedRoutineDraft) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("COACH CHAT")
                    .microLabel(AppTheme.textSecondary)

                Spacer()

                if isApplyingRevision {
                    ProgressView()
                        .tint(AppTheme.textSecondary)
                }
            }

            if !conversationMessages.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(conversationMessages) { message in
                            conversationMessageView(message)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 240)
            }

            if let latestCoachChangeSummary = nonEmptyText(latestCoachChangeSummary) {
                coachChangeCard(summary: latestCoachChangeSummary)
            }

            revisionComposer(for: generatedRoutine)
        }
        .padding(AppTheme.cardPadding)
        .glassCard()
    }

    private func revisionComposer(for generatedRoutine: AIGeneratedRoutineDraft) -> some View {
        let canRevise = !isApplyingRevision && revisionPrompt.trimmingCharacters(in: .whitespacesAndNewlines).count >= 8

        return HStack(spacing: 6) {
            TrackerTextField("Try: swap barbell squat for something easier on my knees", text: $revisionPrompt, axis: .vertical)
                .font(.system(size: 15))
                .foregroundStyle(AppTheme.textPrimary)
                .tint(AppTheme.primary)
                .lineLimit(1...4)
                .focused($revisionFocused)
                .padding(.leading, 12)
                .padding(.vertical, 8)

            Button {
                applyRevision(to: generatedRoutine)
            } label: {
                ZStack {
                    if isApplyingRevision {
                        ProgressView()
                            .tint(AppTheme.textPrimary)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(AppTheme.textPrimary)
                    }
                }
                .frame(width: 38, height: 38)
                .background(AppTheme.surfaceElevated)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(AppTheme.cardBorder, lineWidth: 1)
                }
                .opacity(canRevise || isApplyingRevision ? 1 : 0.4)
            }
            .buttonStyle(.plain)
            .disabled(!canRevise)
            .accessibilityLabel(isApplyingRevision ? "Talking to Coach" : "Send to Coach")
        }
        .padding(.horizontal, 6)
        .frame(minHeight: 50)
        .background(AppTheme.fieldBackground)
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(revisionFocused ? AppTheme.accentHairline : AppTheme.cardBorder, lineWidth: 1)
        }
    }

    /// Sent: hairline bubble on the elevated surface with the 4pt tail.
    /// Coach: plain 14pt text on the card.
    @ViewBuilder
    private func conversationMessageView(_ message: AIWorkoutConversationMessage) -> some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 44)

                Text(message.text)
                    .font(.system(size: 15))
                    .foregroundStyle(AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Self.sentBubbleShape.fill(AppTheme.surfaceElevated))
                    .overlay {
                        Self.sentBubbleShape
                            .stroke(AppTheme.cardBorder, lineWidth: 1)
                    }
            }
        } else {
            Text(message.text)
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.textPrimary)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.trailing, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private static var sentBubbleShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 18,
            bottomLeadingRadius: 18,
            bottomTrailingRadius: 4,
            topTrailingRadius: 18,
            style: .continuous
        )
    }

    // MARK: - Bindings (unchanged)

    private var titleBinding: Binding<String> {
        Binding(
            get: { generatedRoutine?.title ?? "" },
            set: { newValue in
                guard var generatedRoutine else { return }
                generatedRoutine.title = newValue
                self.generatedRoutine = generatedRoutine
            }
        )
    }

    private func nameBinding(for index: Int) -> Binding<String> {
        Binding(
            get: { generatedRoutine?.exercises[safe: index]?.name ?? "" },
            set: { newValue in
                guard var generatedRoutine,
                      generatedRoutine.exercises.indices.contains(index) else { return }
                generatedRoutine.exercises[index].name = newValue
                self.generatedRoutine = generatedRoutine
            }
        )
    }

    private func repsBinding(for index: Int) -> Binding<String> {
        Binding(
            get: { generatedRoutine?.exercises[safe: index]?.reps ?? "" },
            set: { newValue in
                guard var generatedRoutine,
                      generatedRoutine.exercises.indices.contains(index) else { return }
                generatedRoutine.exercises[index].reps = newValue
                self.generatedRoutine = generatedRoutine
            }
        )
    }

    private func notesBinding(for index: Int) -> Binding<String> {
        Binding(
            get: { generatedRoutine?.exercises[safe: index]?.notes ?? "" },
            set: { newValue in
                guard var generatedRoutine,
                      generatedRoutine.exercises.indices.contains(index) else { return }

                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                generatedRoutine.exercises[index].notes = trimmed.isEmpty ? nil : trimmed
                self.generatedRoutine = generatedRoutine
            }
        )
    }

    private func setBinding(for index: Int) -> Binding<Int> {
        Binding(
            get: { max(1, generatedRoutine?.exercises[safe: index]?.sets ?? 3) },
            set: { newValue in
                guard var generatedRoutine,
                      generatedRoutine.exercises.indices.contains(index) else { return }
                generatedRoutine.exercises[index].sets = max(1, newValue)
                self.generatedRoutine = generatedRoutine
            }
        )
    }

    private func removeExercise(at index: Int) {
        guard var generatedRoutine,
              generatedRoutine.exercises.indices.contains(index) else { return }
        generatedRoutine.exercises.remove(at: index)
        self.generatedRoutine = generatedRoutine
    }

    private func applySmartSwap(_ suggestion: ExerciseSwapSuggestion, at index: Int) {
        guard var generatedRoutine,
              generatedRoutine.exercises.indices.contains(index) else { return }

        generatedRoutine.exercises[index].name = suggestion.exerciseName
        self.generatedRoutine = generatedRoutine
    }

    private func canSave(_ generatedRoutine: AIGeneratedRoutineDraft) -> Bool {
        let trimmedTitle = generatedRoutine.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !generatedRoutine.exercises.isEmpty else { return false }

        return generatedRoutine.exercises.allSatisfy { exercise in
            !exercise.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !exercise.reps.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func matchedLibraryExerciseCount(for generatedRoutine: AIGeneratedRoutineDraft) -> Int {
        generatedRoutine.exercises.reduce(0) { count, exercise in
            count + (exerciseStore.exercises.resolvedExercise(named: exercise.name) == nil ? 0 : 1)
        }
    }

    // MARK: - Generation & revision (unchanged)

    private func generateWorkout() {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedPrompt.count >= 8 else {
            errorMessage = AIWorkoutGenerationError.invalidPrompt.localizedDescription
            return
        }

        errorMessage = nil
        conversationMessages = []
        latestCoachChangeSummary = nil
        stage = .generating

        Task {
            do {
                let routine = try await client.generateRoutine(from: trimmedPrompt)
                generatedRoutine = routine
                conversationMessages = initialConversation(for: routine)
                stage = .review
            } catch {
                errorMessage = error.localizedDescription
                stage = .prompt
            }
        }
    }

    private func saveGeneratedRoutine() {
        guard let generatedRoutine, canSave(generatedRoutine) else { return }
        AIWorkoutRoutineSaver.save(generatedRoutine, to: workoutStore)
        onSave()
        dismiss()
    }

    private func applyRevision(to generatedRoutine: AIGeneratedRoutineDraft) {
        let trimmedPrompt = revisionPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedPrompt.count >= 8 else {
            errorMessage = AIWorkoutGenerationError.invalidPrompt.localizedDescription
            return
        }

        errorMessage = nil
        isApplyingRevision = true
        let userMessage = AIWorkoutConversationMessage.user(trimmedPrompt)
        conversationMessages.append(userMessage)

        Task { @MainActor in
            do {
                let revisionResult = try await client.reviseRoutine(
                    generatedRoutine,
                    editPrompt: trimmedPrompt,
                    conversation: conversationMessages
                )
                if revisionResult.action.changedDraft {
                    self.generatedRoutine = revisionResult.routine
                }
                latestCoachChangeSummary = nonEmptyText(revisionResult.changeSummary)
                if let assistantReply = revisionAssistantReply(for: revisionResult) {
                    conversationMessages.append(.assistant(assistantReply))
                }
                revisionPrompt = ""
            } catch {
                if conversationMessages.last == userMessage {
                    conversationMessages.removeLast()
                }
                errorMessage = error.localizedDescription
            }

            isApplyingRevision = false
        }
    }

    private func initialConversation(for routine: AIGeneratedRoutineDraft) -> [AIWorkoutConversationMessage] {
        let opening = nonEmptyText(routine.rationale)
            ?? nonEmptyText(routine.summary)
            ?? "I built a first draft around your request. Ask for any swaps, shorter timing, or easier options."

        return [.assistant(opening)]
    }

    private func revisionAssistantReply(for result: AIWorkoutRevisionResult) -> String? {
        if let reply = nonEmptyText(result.assistantReply) {
            return reply
        }

        if result.action.changedDraft {
            return nonEmptyText(result.changeSummary) ?? nonEmptyText(result.routine.rationale)
        }

        return "I can keep talking through this with you before changing the draft."
    }

    // MARK: - Small pieces

    /// "Draft updated" as a hairline line under the chat, not a box.
    private func coachChangeCard(summary: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "wand.and.stars")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text("Draft updated")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text(summary)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }

    private func nonEmptyText(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func aiStatusChip(title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
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
