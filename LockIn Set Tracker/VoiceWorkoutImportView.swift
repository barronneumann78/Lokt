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
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .dismissKeyboardOnTap()
        .keyboardDoneBar()
        .navigationTitle("Import by Voice")
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

            trustSection
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Talk through the workout you want.")
                .font(.system(size: 30, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(AppTheme.textPrimary)

            Text("List exercises or describe the workout you want. You’ll review the matched routine before saving.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(20)
        .glassCard()
    }

    private var recorderSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("RECORD A VOICE NOTE")
                .microLabel()

            VStack(spacing: 16) {
                Button {
                    toggleRecording()
                } label: {
                    VStack(spacing: 12) {
                        Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(AppTheme.backgroundTop)
                            .frame(width: 84, height: 84)
                            .background(recorder.isRecording ? AppTheme.secondary : AppTheme.primary)
                            .clipShape(Circle())

                        Text(recorder.isRecording ? "Stop Recording" : "Start Recording")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(AppTheme.textPrimary)

                        Text(recorder.isRecording ? "Speak normally, then tap stop when you are done." : "Examples: Bench press, incline dumbbell press, lateral raises. Or: Make me a dumbbell-only pull day.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .padding(.horizontal, 18)
                    .background(AppTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .buttonStyle(.plain)

                if recorder.isRecording {
                    Text("Recording is live. The routine will not be saved automatically when you stop.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondary)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("LIVE TRANSCRIPT")
                            .microLabel()

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
        .padding(20)
        .glassCard()
    }

    private var processingContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Turning your voice note into a workout...")
                    .font(.system(size: 30, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(AppTheme.textPrimary)

                Text("Lokt is transcribing, matching exercises, and preparing a review draft.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .padding(20)
            .glassCard()

            VStack(spacing: 18) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(AppTheme.primary)
                    .scaleEffect(1.2)

                Text(processingMessage)
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
                    .multilineTextAlignment(.center)

                Text("You’ll get a full review screen before the routine is created.")
                    .font(.subheadline)
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
                .font(.system(size: 30, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(AppTheme.textPrimary)

            Text("Quickly check names and any missing details, then save the routine.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)

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
        .padding(20)
        .glassCard()
    }

    private func revisionSection(for importedWorkout: ImportedWorkoutDraft) -> some View {
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

            if let latestCoachChangeSummary = latestCoachChangeSummary?.nilIfEmpty {
                coachChangeCard(summary: latestCoachChangeSummary)
            }

            TrackerTextField("Try: take out pull-ups and add something easier", text: $revisionPrompt, axis: .vertical)
                .textFieldStyle(TrackerTextFieldStyle())
                .lineLimit(2...4)

            Button(isApplyingRevision ? "Talking to Coach..." : "Send to Coach") {
                applyRevision(to: importedWorkout)
            }
            .buttonStyle(PrimaryButtonStyle(fill: AppTheme.surfaceElevated))
            .disabled(isApplyingRevision || revisionPrompt.trimmingCharacters(in: .whitespacesAndNewlines).count < 8)
            .opacity(isApplyingRevision || revisionPrompt.trimmingCharacters(in: .whitespacesAndNewlines).count < 8 ? 0.6 : 1)
        }
        .padding(20)
        .glassCard()
    }

    private func transcriptSection(for importedWorkout: ImportedWorkoutDraft) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TRANSCRIPT")
                .microLabel()

            Text(importedWorkout.sourceText)
                .font(.body)
                .foregroundStyle(AppTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .surfaceCard()
        }
        .padding(20)
        .glassCard()
    }

    private func daySection(for importedWorkout: ImportedWorkoutDraft) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ROUTINE PREVIEW")
                .microLabel()

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
        .padding(20)
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
                                .font(.headline.weight(.bold))
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
                    .font(.caption.weight(.bold))
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
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.secondary.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            HStack(spacing: 10) {
                Button("Edit") {
                    editorTarget = ImportedExerciseEditorTarget(dayIndex: dayIndex, exerciseIndex: exerciseIndex)
                }
                .buttonStyle(SecondaryButtonStyle())

                Menu("Swap") {
                    ForEach(exercise.matchCandidates.prefix(5)) { candidate in
                        Button(candidate.name) {
                            applyMatchedExercise(named: candidate.name, to: ImportedExerciseEditorTarget(dayIndex: dayIndex, exerciseIndex: exerciseIndex))
                        }
                    }
                }
                .buttonStyle(SecondaryButtonStyle())

                Button("Smart Swap") {
                    smartSwapTarget = ImportedExerciseEditorTarget(dayIndex: dayIndex, exerciseIndex: exerciseIndex)
                }
                .buttonStyle(SecondaryButtonStyle())

                Button("Remove") {
                    removeExercise(at: ImportedExerciseEditorTarget(dayIndex: dayIndex, exerciseIndex: exerciseIndex))
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(16)
        .exerciseDetailDisclosureTapArea(id: exercise.id, expandedIDs: $expandedDetailIDs, enabled: tip != nil)
        .surfaceCard(border: AppTheme.cardBorder.opacity(0.75))
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
                            .buttonStyle(SecondaryButtonStyle())
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
            .buttonStyle(PrimaryButtonStyle(fill: AppTheme.surfaceElevated))
        }
    }

    private var trustSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WHAT VOICE IMPORT HANDLES")
                .microLabel()

            Text("Works with exercise lists like Bench press, incline dumbbell press, lateral raises, or requests like Make me a dumbbell-only pull day. Nothing saves until you review it.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(20)
        .glassCard()
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

    private func importStat(title: String, subtitle: String) -> some View {
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
            .font(.caption.weight(.bold))
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

    private func detailTagWrap(values: [String]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(values, id: \.self) { value in
                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(reviewMutedText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppTheme.surfaceElevated)
                    .clipShape(Capsule())
                    .overlay {
                        Capsule()
                            .stroke(AppTheme.cardBorder.opacity(0.65), lineWidth: 1)
                }
            }
        }
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
        .padding(20)
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

            TrackerTextField("Search existing exercises to swap", text: $searchText)
                .textFieldStyle(TrackerTextFieldStyle())

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
        .padding(20)
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
        .padding(20)
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
