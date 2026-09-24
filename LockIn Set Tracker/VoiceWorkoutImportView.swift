import SwiftUI

struct VoiceWorkoutImportView: View {
    var onSave: () -> Void

    @Environment(\.dismiss) private var dismiss

    @EnvironmentObject private var exerciseStore: ExerciseStore
    @EnvironmentObject private var workoutStore: WorkoutStore
    @StateObject private var recorder = VoiceWorkoutRecorder()
    @State private var stage: VoiceWorkoutImportStage = .input
    @State private var importedWorkout: ImportedWorkoutDraft?
    @State private var processingMessage = "Getting ready..."
    @State private var errorMessage: String?
    @State private var editorTarget: ImportedExerciseEditorTarget?
    @State private var smartSwapTarget: ImportedExerciseEditorTarget?
    @State private var revisionPrompt = ""
    @State private var conversationMessages: [AIWorkoutConversationMessage] = []
    @State private var latestCoachChangeSummary: String?
    @State private var isApplyingRevision = false
    /// Imported exercise ids whose tip line is open. New extractions and
    /// revisions decode fresh ids, so rows naturally start collapsed.
    @State private var expandedDetailIDs: Set<UUID> = []
    @FocusState private var revisionFocused: Bool
    @State private var showFilteredPhrases = false

    private let reviewSecondaryText = AppTheme.textSecondary
    private let reviewMutedText = AppTheme.textSecondary

    private let pipeline = VoiceWorkoutImportPipeline()
    private let revisionService = ImportedWorkoutRevisionService()

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    switch stage {
                    case .input:
                        inputContent
                    case .processing:
                        processingContent
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
        .sheet(item: $editorTarget) { target in
            if let draft = draftForEditor(target) {
                VoiceExerciseEditorSheet(
                    draft: draft,
                    allExercises: exerciseStore.exercises
                ) { updated in
                    updateDraft(updated, at: target)
                }
            }
        }
        .sheet(item: $smartSwapTarget) { target in
            if let draft = draftForEditor(target) {
                ExerciseSwapSheet(
                    target: ExerciseSwapTarget(
                        exerciseName: draft.resolvedExerciseName,
                        sourceNote: "Heard: \(draft.sourceText)"
                    ),
                    exercises: exerciseStore.exercises
                ) { suggestion in
                    applySmartSwap(suggestion, to: target)
                }
            }
        }
    }

    private var inputContent: some View {
        Group {
            headerSection
            recorderSection

            if let errorMessage {
                messageCard(title: "Voice Import Couldn’t Finish", text: errorMessage, tint: AppTheme.secondary)
            }
        }
    }

    /// 26pt screen title; the explainer captions that sat under it and in
    /// the old WHAT VOICE IMPORT HANDLES card are gone (look v2).
    private var headerSection: some View {
        Text("Talk through the workout you want.")
            .font(.system(size: 26, weight: .bold))
            .tracking(-0.3)
            .foregroundStyle(AppTheme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 2)
    }

    private var recorderSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("RECORD A VOICE NOTE")
                .microLabel(AppTheme.textSecondary)

            VStack(spacing: 16) {
                // The mic circle is the input stage's one gradient (its
                // primary action); recording swaps it for the logger's red
                // dot under `.recordingGlow()`.
                Button {
                    toggleRecording()
                } label: {
                    VStack(spacing: 12) {
                        ZStack {
                            if recorder.isRecording {
                                Circle()
                                    .fill(AppTheme.danger)
                                    .frame(width: 84, height: 84)
                                    .recordingGlow()
                            } else {
                                Circle()
                                    .fill(AppTheme.primaryGradient)
                                    .frame(width: 84, height: 84)
                            }

                            Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                                .font(.system(size: 34, weight: .bold))
                                .foregroundStyle(AppTheme.backgroundTop)
                        }

                        Text(recorder.isRecording ? "Stop Recording" : "Start Recording")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .padding(.horizontal, 18)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(recorder.isRecording ? "Stop Recording" : "Start Recording")

                if recorder.isRecording {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(AppTheme.danger)
                                .frame(width: 7, height: 7)
                                .recordingGlow()

                            Text("LIVE TRANSCRIPT")
                                .microLabel()
                        }

                        Text(
                            recorder.liveTranscript.isEmpty
                                ? (recorder.isLivePreviewAvailable
                                    ? "Listening..."
                                    : "Live preview is unavailable, but the final transcript will still be created after you stop recording.")
                                : recorder.liveTranscript
                        )
                        .font(.body)
                        .foregroundStyle(recorder.liveTranscript.isEmpty ? AppTheme.textSecondary : AppTheme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .surfaceCard(cornerRadius: AppTheme.controlCornerRadius)
                    }
                }
            }
        }
        .padding(AppTheme.cardPadding)
        .glassCard()
    }

    private var processingContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Turning your voice note into a workout...")
                .font(.system(size: 26, weight: .bold))
                .tracking(-0.3)
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 18) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(AppTheme.primary)
                    .scaleEffect(1.2)

                Text(processingMessage)
                    .font(.system(size: 15))
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .glassCard()
        }
    }

    private var reviewContent: some View {
        Group {
            if let importedWorkout {
                VStack(alignment: .leading, spacing: 20) {
                    if let errorMessage {
                        messageCard(title: "Couldn’t Update the Routine Yet", text: errorMessage, tint: AppTheme.secondary)
                    }

                    reviewHeader(for: importedWorkout)
                    revisionSection(for: importedWorkout)
                    transcriptSection(for: importedWorkout)
                    daySection(for: importedWorkout)
                    filteredSection(for: importedWorkout)
                    reviewActions(for: importedWorkout)
                }
            }
        }
    }

    private func reviewHeader(for importedWorkout: ImportedWorkoutDraft) -> some View {
        let unresolvedCount = unresolvedExerciseCount(for: importedWorkout)

        return VStack(alignment: .leading, spacing: 12) {
            Text("Review the voice workout")
                .font(.system(size: 26, weight: .bold))
                .tracking(-0.3)
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            reviewReadinessCard(
                title: unresolvedCount == 0 ? "Ready to save" : "\(unresolvedCount) quick check\(unresolvedCount == 1 ? "" : "s") left",
                text: unresolvedCount == 0
                    ? "You can still edit anything, but the routine is ready."
                    : "Use Edit or Swap on the items marked for review.",
                tint: unresolvedCount == 0 ? AppTheme.success : AppTheme.secondary,
                symbolName: unresolvedCount == 0 ? "checkmark.shield.fill" : "exclamationmark.triangle.fill"
            )

            HStack(spacing: 10) {
                importStat(title: "\(importedWorkout.totalExercises)", subtitle: "Exercises")
                importStat(title: "\(readyExerciseCount(for: importedWorkout))", subtitle: "Ready")
                importStat(title: "\(unresolvedCount)", subtitle: "Check")
            }
        }
    }

    private func revisionSection(for importedWorkout: ImportedWorkoutDraft) -> some View {
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
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(conversationMessages) { message in
                            conversationBubble(for: message)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 240)
            }

            if let latestCoachChangeSummary = latestCoachChangeSummary?.nilIfEmpty {
                coachChangeCard(summary: latestCoachChangeSummary)
            }

            revisionComposer(placeholder: "Try: take out pull-ups and add something easier") {
                applyRevision(to: importedWorkout)
            }
        }
        .padding(AppTheme.cardPadding)
        .glassCard()
    }

    private func transcriptSection(for importedWorkout: ImportedWorkoutDraft) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TRANSCRIPT")
                .microLabel(AppTheme.textSecondary)

            Text(importedWorkout.sourceText)
                .font(.body)
                .foregroundStyle(AppTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .surfaceCard()
        }
        .padding(AppTheme.cardPadding)
        .glassCard()
    }

    private func daySection(for importedWorkout: ImportedWorkoutDraft) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ROUTINE PREVIEW")
                .microLabel(AppTheme.textSecondary)

            ForEach(importedWorkout.days.indices, id: \.self) { dayIndex in
                dayCard(dayIndex: dayIndex)
            }
        }
    }

    private func dayCard(dayIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            TrackerTextField("Routine Name", text: dayNameBinding(for: dayIndex))
                .textFieldStyle(TrackerTextFieldStyle())
                .foregroundStyle(AppTheme.textPrimary)

            if let notes = importedWorkout?.days[dayIndex].notes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(notes.enumerated()), id: \.offset) { note in
                        Text(note.element)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .surfaceCard(cornerRadius: AppTheme.controlCornerRadius)
            }

            LazyVStack(spacing: 12) {
                ForEach(Array((importedWorkout?.days[dayIndex].exercises ?? []).enumerated()), id: \.element.id) { item in
                    exerciseRow(dayIndex: dayIndex, exerciseIndex: item.offset, exercise: item.element)
                }
            }
        }
        .padding(AppTheme.cardPadding)
        .glassCard()
    }

    private func exerciseRow(dayIndex: Int, exerciseIndex: Int, exercise: ImportedExerciseDraft) -> some View {
        let trimmedTip = exercise.tip?.trimmingCharacters(in: .whitespacesAndNewlines)
        let tip = (trimmedTip?.isEmpty == false) ? trimmedTip : nil
        let isExpanded = expandedDetailIDs.contains(exercise.id)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        ExerciseTextNavigationLink(exerciseName: exercise.resolvedExerciseName, exercises: exerciseStore.exercises) {
                            Text(exercise.resolvedExerciseName)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(AppTheme.textPrimary)
                        }

                        if tip != nil {
                            ExerciseDetailDisclosureChevron(
                                id: exercise.id,
                                expandedIDs: $expandedDetailIDs,
                                font: .footnote
                            )
                        }
                    }

                    Text("Heard: \(exercise.sourceText)")
                        .font(.caption)
                        .foregroundStyle(reviewSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    if isExpanded, let tip {
                        Text(tip)
                            .font(.footnote)
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let statusLine = importStatusLine(for: exercise) {
                        Text(statusLine)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(statusTint(for: exercise))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer()

                confidenceChip(for: exercise)
            }

            if exercise.isCustomExercise {
                Text("Custom")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppTheme.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppTheme.secondary.opacity(0.12))
                    .clipShape(Capsule())
            }

            detailTagWrap(values: exercise.detailSummary)

            if let warningText = voiceWarningText(for: exercise) {
                Text(warningText)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Button("Edit") {
                    editorTarget = ImportedExerciseEditorTarget(dayIndex: dayIndex, exerciseIndex: exerciseIndex)
                }
                .buttonStyle(GhostButtonStyle(isCompact: true))

                Menu("Swap") {
                    ForEach(exercise.matchCandidates.prefix(5)) { candidate in
                        Button(candidate.name) {
                            applyMatchedExercise(named: candidate.name, to: ImportedExerciseEditorTarget(dayIndex: dayIndex, exerciseIndex: exerciseIndex))
                        }
                    }
                }
                .buttonStyle(GhostButtonStyle(isCompact: true))

                Button("Smart Swap") {
                    smartSwapTarget = ImportedExerciseEditorTarget(dayIndex: dayIndex, exerciseIndex: exerciseIndex)
                }
                .buttonStyle(GhostButtonStyle(isCompact: true))

                Button("Remove") {
                    removeExercise(at: ImportedExerciseEditorTarget(dayIndex: dayIndex, exerciseIndex: exerciseIndex))
                }
                .buttonStyle(GhostButtonStyle(isCompact: true))
            }
        }
        .padding(16)
        .exerciseDetailDisclosureTapArea(id: exercise.id, expandedIDs: $expandedDetailIDs, enabled: tip != nil)
        .surfaceCard()
    }

    /// One compact row for phrases the parse left out (non-exercise talk or
    /// unresolved low-confidence mentions). Collapsed by default; expanding
    /// offers a per-phrase Add so a mishearing can be rescued.
    @ViewBuilder
    private func filteredSection(for importedWorkout: ImportedWorkoutDraft) -> some View {
        if let phrases = importedWorkout.filteredPhrases, !phrases.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showFilteredPhrases.toggle()
                    }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("Didn't sound like exercises: \(phrases.map(\.sourceText).joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(showFilteredPhrases ? nil : 1)

                        Spacer(minLength: 8)

                        Image(systemName: showFilteredPhrases ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                }
                .buttonStyle(.plain)

                if showFilteredPhrases {
                    ForEach(phrases) { phrase in
                        HStack(spacing: 10) {
                            Text(phrase.suggestedName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.textPrimary)

                            Spacer()

                            Button("Add") {
                                rescueFilteredPhrase(phrase)
                            }
                            .buttonStyle(GhostButtonStyle(isCompact: true))
                        }
                    }
                }
            }
            .padding(16)
            .surfaceCard()
        }
    }

    private func rescueFilteredPhrase(_ phrase: VoiceFilteredPhrase) {
        guard var importedWorkout else { return }

        let draft = ImportedExerciseDraft(
            sourceText: phrase.sourceText,
            exerciseName: phrase.suggestedName,
            matchedExerciseName: nil,
            matchCandidates: phrase.matchCandidates,
            setCount: phrase.setCount,
            repText: phrase.repText,
            notes: "",
            restSeconds: nil,
            intensityNotes: [],
            confidence: .low,
            isCustomExercise: true,
            customExercise: nil,
            weightText: phrase.weightText
        )

        if importedWorkout.days.isEmpty {
            importedWorkout.days = [
                ImportedWorkoutDayDraft(name: "Voice Workout", sourceHeading: nil, notes: [], exercises: [draft])
            ]
        } else {
            importedWorkout.days[0].exercises.append(draft)
        }

        let remaining = (importedWorkout.filteredPhrases ?? []).filter { $0.id != phrase.id }
        importedWorkout.filteredPhrases = remaining.isEmpty ? nil : remaining
        self.importedWorkout = importedWorkout
    }

    private func reviewActions(for importedWorkout: ImportedWorkoutDraft) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("Save Routine") {
                saveImportedWorkout()
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isApplyingRevision || importedWorkout.totalExercises == 0)
            .opacity(!isApplyingRevision && importedWorkout.totalExercises > 0 ? 1 : 0.6)

            Button("Record Again") {
                resetImportFlow()
            }
            .buttonStyle(GhostButtonStyle())
        }
    }

    private func toggleRecording() {
        if recorder.isRecording {
            stopAndProcessRecording()
        } else {
            Task {
                do {
                    errorMessage = nil
                    try await recorder.startRecording()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func stopAndProcessRecording() {
        do {
            let recordingURL = try recorder.stopRecording()
            processRecording(at: recordingURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func processRecording(at recordingURL: URL) {
        if exerciseStore.exercises.isEmpty {
            exerciseStore.loadExercises()
        }

        errorMessage = nil
        conversationMessages = []
        showFilteredPhrases = false
        stage = .processing
        processingMessage = "Uploading your recording..."

        Task {
            defer {
                try? FileManager.default.removeItem(at: recordingURL)
            }

            do {
                let importedWorkout = try await pipeline.importWorkout(
                    from: recordingURL,
                    exercises: exerciseStore.exercises
                ) { message in
                    processingMessage = message
                }

                self.importedWorkout = importedWorkout
                latestCoachChangeSummary = nil
                conversationMessages = initialConversation(for: importedWorkout)
                stage = .review
            } catch {
                errorMessage = error.localizedDescription
                stage = .input
            }
        }
    }

    private func unresolvedExerciseCount(for importedWorkout: ImportedWorkoutDraft) -> Int {
        importedWorkout.days
            .flatMap(\.exercises)
            .filter(\.needsReview)
            .count
    }

    private func readyExerciseCount(for importedWorkout: ImportedWorkoutDraft) -> Int {
        importedWorkout.days
            .flatMap(\.exercises)
            .filter { !$0.needsReview }
            .count
    }

    private func dayNameBinding(for dayIndex: Int) -> Binding<String> {
        Binding(
            get: { importedWorkout?.days[safe: dayIndex]?.name ?? "" },
            set: { newValue in
                guard var importedWorkout, importedWorkout.days.indices.contains(dayIndex) else { return }
                importedWorkout.days[dayIndex].name = newValue
                self.importedWorkout = importedWorkout
            }
        )
    }

    private func draftForEditor(_ target: ImportedExerciseEditorTarget) -> ImportedExerciseDraft? {
        importedWorkout?.days[safe: target.dayIndex]?.exercises[safe: target.exerciseIndex]
    }

    private func updateDraft(_ draft: ImportedExerciseDraft, at target: ImportedExerciseEditorTarget) {
        guard var importedWorkout,
              importedWorkout.days.indices.contains(target.dayIndex),
              importedWorkout.days[target.dayIndex].exercises.indices.contains(target.exerciseIndex) else {
            return
        }

        importedWorkout.days[target.dayIndex].exercises[target.exerciseIndex] = draft
        self.importedWorkout = importedWorkout
    }

    private func applyMatchedExercise(named exerciseName: String, to target: ImportedExerciseEditorTarget) {
        guard var exercise = draftForEditor(target) else { return }
        exercise.matchedExerciseName = exerciseName
        exercise.exerciseName = exerciseName
        exercise.isCustomExercise = false
        exercise.customExercise = nil
        exercise.confidence = .medium
        updateDraft(exercise, at: target)
    }

    private func removeExercise(at target: ImportedExerciseEditorTarget) {
        guard var importedWorkout,
              importedWorkout.days.indices.contains(target.dayIndex),
              importedWorkout.days[target.dayIndex].exercises.indices.contains(target.exerciseIndex) else {
            return
        }

        importedWorkout.days[target.dayIndex].exercises.remove(at: target.exerciseIndex)
        self.importedWorkout = importedWorkout
    }

    private func applySmartSwap(_ suggestion: ExerciseSwapSuggestion, to target: ImportedExerciseEditorTarget) {
        guard var draft = draftForEditor(target) else { return }
        draft.matchedExerciseName = suggestion.exerciseName
        draft.exerciseName = suggestion.exerciseName
        draft.isCustomExercise = false
        draft.customExercise = nil
        draft.confidence = .medium
        updateDraft(draft, at: target)
    }

    private func saveImportedWorkout() {
        guard let importedWorkout else { return }
        ImportedWorkoutSaver.save(importedWorkout, to: workoutStore)
        // The save may have added custom exercises; refresh the shared library.
        exerciseStore.reloadCustomExercises()
        onSave()
        dismiss()
    }

    private func resetImportFlow() {
        recorder.cancelRecording()
        importedWorkout = nil
        errorMessage = nil
        editorTarget = nil
        smartSwapTarget = nil
        conversationMessages = []
        latestCoachChangeSummary = nil
        revisionPrompt = ""
        isApplyingRevision = false
        expandedDetailIDs = []
        showFilteredPhrases = false
        stage = .input
    }

    private func applyRevision(to importedWorkout: ImportedWorkoutDraft) {
        let trimmedPrompt = revisionPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedPrompt.count >= 8 else {
            errorMessage = ImportedWorkoutRevisionError.invalidPrompt.localizedDescription
            return
        }

        errorMessage = nil
        isApplyingRevision = true
        let userMessage = AIWorkoutConversationMessage.user(trimmedPrompt)
        conversationMessages.append(userMessage)

        Task { @MainActor in
            do {
                let revisionResult = try await revisionService.revise(
                    draft: importedWorkout,
                    instruction: trimmedPrompt,
                    exercises: exerciseStore.exercises,
                    conversation: conversationMessages
                )

                if revisionResult.action.changedDraft {
                    // Revisions rebuild the draft from the backend extraction;
                    // carry the filtered (rescuable) phrases across so they
                    // stay available after a coach edit.
                    var revisedDraft = revisionResult.draft
                    revisedDraft.filteredPhrases = self.importedWorkout?.filteredPhrases
                    self.importedWorkout = revisedDraft
                }
                latestCoachChangeSummary = revisionResult.changeSummary?.nilIfEmpty
                conversationMessages.append(.assistant(revisionAssistantReply(for: revisionResult)))
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

    private func initialConversation(for importedWorkout: ImportedWorkoutDraft) -> [AIWorkoutConversationMessage] {
        let exerciseCount = importedWorkout.totalExercises
        let unresolvedCount = unresolvedExerciseCount(for: importedWorkout)
        let opening = unresolvedCount == 0
            ? "I turned your voice note into a \(exerciseCount)-exercise draft. Ask for any swaps, easier options, or finishing work."
            : "I turned your voice note into a draft and flagged \(unresolvedCount) item\(unresolvedCount == 1 ? "" : "s") to double-check. Ask for changes and I’ll keep updating it."

        return [.assistant(opening)]
    }

    private func revisionAssistantReply(for result: ImportedWorkoutRevisionResult) -> String {
        if let assistantReply = result.assistantReply?.nilIfEmpty {
            return assistantReply
        }

        if result.action.changedDraft {
            return result.changeSummary?.nilIfEmpty ?? "I updated the draft and kept the review flow intact."
        }

        return "I can keep helping you think through this before we change the draft."
    }


    private func voiceWarningText(for exercise: ImportedExerciseDraft) -> String? {
        if exercise.isCustomExercise {
            let suggestions = exercise.matchCandidates.prefix(2).map(\.name)
            if suggestions.count == 2 {
                return "Try swapping to \(suggestions[0]) or \(suggestions[1])."
            }

            return nil
        }

        guard exercise.confidence == .low else { return nil }

        let suggestions = exercise.matchCandidates.prefix(2).map(\.name)
        guard suggestions.count == 2 else { return nil }
        return "Try \(suggestions[0]) or \(suggestions[1])."
    }

    private func importStatusLine(for exercise: ImportedExerciseDraft) -> String? {
        if exercise.isCustomExercise {
            return "Custom for now"
        }

        switch exercise.confidence {
        case .high:
            if exercise.missingProgrammingDetails.isEmpty {
                return "Ready"
            }
            return "Add \(exercise.missingProgrammingDetails.lowercased())"
        case .medium:
            return "Quick check"
        case .low:
            return "Needs review"
        }
    }

    private func statusTint(for exercise: ImportedExerciseDraft) -> Color {
        switch exercise.confidence {
        case .high:
            return exercise.isCustomExercise ? AppTheme.secondary : AppTheme.success
        case .medium:
            return AppTheme.secondary
        case .low:
            return AppTheme.danger
        }
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

    private func reviewReadinessCard(title: String, text: String, tint: Color, symbolName: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbolName)
                .font(.headline)
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text(text)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(14)
        .surfaceCard(border: tint.opacity(0.24))
    }

    private func confidenceChip(for exercise: ImportedExerciseDraft) -> some View {
        let color: Color = {
            switch exercise.confidence {
            case .high:
                return AppTheme.success
            case .medium:
                return AppTheme.secondary
            case .low:
                return AppTheme.danger
            }
        }()

        return Text(confidenceChipTitle(for: exercise))
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(color.opacity(0.95))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.18))
            .clipShape(Capsule())
    }

    private func confidenceChipTitle(for exercise: ImportedExerciseDraft) -> String {
        if exercise.isCustomExercise {
            return "Custom"
        }

        switch exercise.confidence {
        case .high:
            return "Ready"
        case .medium:
            return "Check"
        case .low:
            return "Review"
        }
    }


    /// COACH CHAT composer: a 50pt field-fill capsule holding the revision
    /// field and a hairline send circle — not the gradient, which the Save
    /// pill owns on this screen. The accent hairline follows focus.
    private func revisionComposer(placeholder: String, action: @escaping () -> Void) -> some View {
        let canRevise = !isApplyingRevision && revisionPrompt.trimmingCharacters(in: .whitespacesAndNewlines).count >= 8

        return HStack(spacing: 6) {
            TrackerTextField(placeholder, text: $revisionPrompt, axis: .vertical)
                .font(.system(size: 15))
                .foregroundStyle(AppTheme.textPrimary)
                .tint(AppTheme.primary)
                .lineLimit(1...4)
                .focused($revisionFocused)
                .padding(.leading, 12)
                .padding(.vertical, 8)

            Button(action: action) {
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
    /// Coach: plain 14pt text.
    @ViewBuilder
    private func conversationBubble(for message: AIWorkoutConversationMessage) -> some View {
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

    /// 16pt stat tile: micro label over a 22pt mono number (the exercise
    /// page's BEST / e1RM / LAST row).
    private func importStat(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(subtitle.uppercased())
                .microLabel()

            Text(title)
                .font(.system(size: 22, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(AppTheme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassCard(cornerRadius: 16)
    }

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

    private func detailTagWrap(values: [String]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(values, id: \.self) { value in
                TagChip(title: value)
            }
        }
    }

}

private struct VoiceExerciseEditorSheet: View {
    let draft: ImportedExerciseDraft
    let allExercises: [Exercise]
    var onSave: (ImportedExerciseDraft) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var selectedExerciseName: String
    @State private var customName: String
    @State private var setCountText: String
    @State private var repText: String
    @State private var notesText: String
    @State private var searchText = ""

    init(draft: ImportedExerciseDraft, allExercises: [Exercise], onSave: @escaping (ImportedExerciseDraft) -> Void) {
        self.draft = draft
        self.allExercises = allExercises
        self.onSave = onSave
        _selectedExerciseName = State(initialValue: draft.matchedExerciseName ?? draft.resolvedExerciseName)
        _customName = State(initialValue: draft.resolvedExerciseName)
        _setCountText = State(initialValue: draft.setCount.map(String.init) ?? "")
        _repText = State(initialValue: draft.repText ?? "")
        _notesText = State(initialValue: draft.notes)
    }

    private var searchResults: [Exercise] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let candidateNames = [draft.matchedExerciseName] + draft.matchCandidates.map(\.name)
            let names = Set(candidateNames.compactMap { $0 })
            return Array(allExercises.filter { names.contains($0.name) }.prefix(8))
        }

        return allExercises
            .filter { $0.name.localizedCaseInsensitiveContains(searchText) }
            .prefix(10)
            .map { $0 }
    }

    var body: some View {
        NavigationView {
            ZStack {
                AppBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        sourceCard
                        exerciseChoiceCard
                        programmingCard
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .dismissKeyboardOnTap()
            .keyboardDoneBar()
            .navigationTitle("Review Voice Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saveChanges()
                    }
                }
            }
        }
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("VOICE PHRASE")
                .microLabel()

            Text(draft.sourceText)
                .font(.body)
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppTheme.cardPadding)
        .glassCard()
    }

    private var exerciseChoiceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(draft.isCustomExercise ? "UNMATCHED PHRASE" : "MATCHED EXERCISE")
                .microLabel()

            if draft.isCustomExercise {
                TrackerTextField("Exercise name", text: $customName)
                    .textFieldStyle(TrackerTextFieldStyle())
            } else {
                Text(selectedExerciseName)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.fieldBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            TrackerSearchField("Search existing exercises to swap", text: $searchText)

            LazyVStack(spacing: 10) {
                ForEach(searchResults) { exercise in
                    Button {
                        selectedExerciseName = exercise.name
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(exercise.name)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(AppTheme.textPrimary)

                                Text("\(exercise.muscleGroup.rawValue) • \(exercise.equipment.rawValue)")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.textSecondary)
                            }

                            Spacer()

                            Image(systemName: selectedExerciseName == exercise.name ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedExerciseName == exercise.name ? AppTheme.textPrimary : AppTheme.textTertiary)
                        }
                        .padding(14)
                        .background(AppTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(AppTheme.cardPadding)
        .glassCard()
    }

    private var programmingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("ROUTINE DETAILS")
                .microLabel()

            HStack(spacing: 12) {
                TrackerTextField("Sets", text: $setCountText)
                    .keyboardType(.numberPad)
                    .textFieldStyle(TrackerTextFieldStyle())

                TrackerTextField("Reps", text: $repText)
                    .textFieldStyle(TrackerTextFieldStyle())
            }

            TrackerTextField("Notes", text: $notesText, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(TrackerTextFieldStyle())
        }
        .padding(AppTheme.cardPadding)
        .glassCard()
    }

    private func saveChanges() {
        var updated = draft
        updated.setCount = Int(setCountText.trimmingCharacters(in: .whitespacesAndNewlines))
        updated.repText = repText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        updated.notes = notesText.trimmingCharacters(in: .whitespacesAndNewlines)

        if draft.isCustomExercise {
            let resolvedName = customName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? draft.resolvedExerciseName
            updated.exerciseName = resolvedName

            if allExercises.contains(where: { $0.name == selectedExerciseName }) {
                updated.isCustomExercise = false
                updated.matchedExerciseName = selectedExerciseName
                updated.exerciseName = selectedExerciseName
                updated.confidence = .medium
            }
        } else if allExercises.contains(where: { $0.name == selectedExerciseName }) {
            updated.matchedExerciseName = selectedExerciseName
            updated.exerciseName = selectedExerciseName
            updated.isCustomExercise = false
        }

        onSave(updated)
        dismiss()
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
