import SwiftUI

struct AIWorkoutGeneratorView: View {
    private struct SmartSwapIndex: Identifiable {
        let index: Int
        var id: Int { index }
    }

    var onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage(AIBackendConfiguration.userDefaultsKey) private var aiBackendBaseURL = AIBackendConfiguration.defaultBaseURLString
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
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
        }
        .navigationTitle("Generate with AI")
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

    private var promptContent: some View {
        Group {
            headerSection
            promptSection

            if let errorMessage {
                messageCard(title: "Generation Needs Attention", text: errorMessage, tint: AppTheme.secondary)
            }
        }
    }

    private var headerSection: some View {
        Text("Describe the workout you want.")
            .font(.system(size: 30, weight: .bold))
            .tracking(-0.5)
            .foregroundStyle(AppTheme.textPrimary)
    }

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("YOUR PROMPT")
                .microLabel()

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AppTheme.fieldBackground)

                if prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Make me a 45-minute push day with dumbbells only")
                        .font(.body)
                        .foregroundStyle(AppTheme.textSecondary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                }

                TextEditor(text: $prompt)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .frame(minHeight: 170)
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

            Button("Generate Workout") {
                generateWorkout()
            }
            .buttonStyle(PrimaryButtonStyle(fill: AppTheme.primary))
            .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).count < 8)
            .opacity(prompt.trimmingCharacters(in: .whitespacesAndNewlines).count < 8 ? 0.6 : 1)
        }
        .padding(20)
        .glassCard()
    }

    private var generatingContent: some View {
        VStack(spacing: 18) {
            Text("Building your routine...")
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
            if let generatedRoutine {
                VStack(alignment: .leading, spacing: 20) {
                    if let errorMessage {
                        messageCard(title: "Couldn’t Update the Workout Yet", text: errorMessage, tint: AppTheme.secondary)
                    }

                    reviewHeader(for: generatedRoutine)
                    revisionSection(for: generatedRoutine)
                    exerciseSection(for: generatedRoutine)
                    reviewActions(for: generatedRoutine)
                }
            }
        }
    }

    private func reviewHeader(for generatedRoutine: AIGeneratedRoutineDraft) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Review your workout")
                .font(.system(size: 30, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(AppTheme.textPrimary)

            reviewSummaryBanner(for: generatedRoutine)

            RoutinePlainExplanationSection(draft: generatedRoutine)

            VStack(alignment: .leading, spacing: 10) {
                Text("ROUTINE TITLE")
                    .microLabel()

                TrackerTextField("Workout Title", text: titleBinding)
                    .textFieldStyle(TrackerTextFieldStyle())
            }

            HStack(spacing: 10) {
                statPill(title: "\(generatedRoutine.exercises.count)", subtitle: "Exercises")
                statPill(title: "\(generatedRoutine.totalSets)", subtitle: "Sets")
                statPill(title: "\(matchedLibraryExerciseCount(for: generatedRoutine))", subtitle: "Known")
            }
        }
        .padding(20)
        .glassCard()
    }

    private func revisionSection(for generatedRoutine: AIGeneratedRoutineDraft) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("COACH CHAT")
                    .microLabel()

                Spacer()

                if isApplyingRevision {
                    ProgressView()
                        .tint(AppTheme.textSecondary)
                }
            }

            if !conversationMessages.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(conversationMessages) { message in
                            conversationBubble(for: message)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 240)
                .padding(4)
                .surfaceCard(cornerRadius: AppTheme.controlCornerRadius)
            }

            if let latestCoachChangeSummary = nonEmptyText(latestCoachChangeSummary) {
                coachChangeCard(summary: latestCoachChangeSummary)
            }

            TrackerTextField("Try: swap barbell squat for something easier on my knees", text: $revisionPrompt, axis: .vertical)
                .textFieldStyle(TrackerTextFieldStyle())
                .lineLimit(2...4)

            Button(isApplyingRevision ? "Talking to Coach..." : "Send to Coach") {
                applyRevision(to: generatedRoutine)
            }
            .buttonStyle(PrimaryButtonStyle(fill: AppTheme.surfaceElevated))
            .disabled(isApplyingRevision || revisionPrompt.trimmingCharacters(in: .whitespacesAndNewlines).count < 8)
            .opacity(isApplyingRevision || revisionPrompt.trimmingCharacters(in: .whitespacesAndNewlines).count < 8 ? 0.6 : 1)
        }
        .padding(20)
        .glassCard()
    }

    private func exerciseSection(for generatedRoutine: AIGeneratedRoutineDraft) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ROUTINE PREVIEW")
                .microLabel()

            if isDiscoveryNudgeVisible {
                DiscoveryNudgeLine {
                    withAnimation(.easeOut(duration: 0.2)) {
                        isDiscoveryNudgeVisible = false
                    }
                }
            }

            ForEach(Array(generatedRoutine.exercises.enumerated()), id: \.element.id) { item in
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

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                Text("EXERCISE \(index + 1)")
                    .microLabel()
                    .monospacedDigit()

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

            if matchedExercise == nil {
                aiStatusChip(title: "Check Name", color: AppTheme.secondary)
            }

            if let reasoning = nonEmptyText(exercise.reasoning) {
                Text(reasoning)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let tip = nonEmptyText(exercise.tip) {
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
                    Text("SETS")
                        .microLabel()

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
        .glassCard()
    }

    private func reviewActions(for generatedRoutine: AIGeneratedRoutineDraft) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("Save Routine") {
                saveGeneratedRoutine()
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isApplyingRevision || !canSave(generatedRoutine))
            .opacity(!isApplyingRevision && canSave(generatedRoutine) ? 1 : 0.6)

            Button("Try a Different Prompt") {
                self.generatedRoutine = nil
                conversationMessages = []
                latestCoachChangeSummary = nil
                revisionPrompt = ""
                errorMessage = nil
                stage = .prompt
            }
            .buttonStyle(PrimaryButtonStyle(fill: AppTheme.surfaceElevated))
        }
    }

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
        AIWorkoutRoutineSaver.save(generatedRoutine)
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

    private func coachChangeCard(summary: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "wand.and.stars")
                .font(.headline)
                .foregroundStyle(AppTheme.textSecondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("Draft updated")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text(summary)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(14)
        .surfaceCard(cornerRadius: AppTheme.controlCornerRadius)
    }

    private func nonEmptyText(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
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

    private func reviewSummaryBanner(for generatedRoutine: AIGeneratedRoutineDraft) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: canSave(generatedRoutine) ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(canSave(generatedRoutine) ? AppTheme.success : AppTheme.secondary)

            Text(canSave(generatedRoutine) ? "Draft looks ready to save" : "A few details still need review")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)

            Spacer()
        }
        .padding(14)
        .surfaceCard()
    }

    private func conversationBubble(for message: AIWorkoutConversationMessage) -> some View {
        let isUser = message.role == .user

        return HStack {
            if isUser {
                Spacer(minLength: 32)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(isUser ? "YOU" : "LOKT COACH")
                    .microLabel()

                Text(message.text)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isUser ? AppTheme.mutedFill : AppTheme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            }

            if !isUser {
                Spacer(minLength: 32)
            }
        }
    }

    private func aiStatusChip(title: String, color: Color) -> some View {
        Text(title)
            .font(.caption.weight(.bold))
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
        .padding(20)
        .background(tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        }
    }
}
