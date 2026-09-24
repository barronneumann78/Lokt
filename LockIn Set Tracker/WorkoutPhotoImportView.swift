import PhotosUI
import SwiftUI
import UIKit

struct WorkoutPhotoImportView: View {
    var onSave: () -> Void

    @Environment(\.dismiss) private var dismiss

    @EnvironmentObject private var exerciseStore: ExerciseStore
    @EnvironmentObject private var workoutStore: WorkoutStore
    @State private var stage: WorkoutPhotoImportStage = .input
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var importedWorkout: ImportedWorkoutDraft?
    @State private var processingMessage = "Uploading your image..."
    @State private var errorMessage: String?
    @State private var showCamera = false
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

    private let pipeline = WorkoutPhotoImportPipeline()
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
        .onChange(of: selectedPhotoItem) { _, item in
            guard let item else { return }
            loadPhotoPickerItem(item)
        }
        .sheet(isPresented: $showCamera) {
            PhotoImportCameraPicker { image in
                showCamera = false
                guard let image else { return }
                process(image: image)
            }
            .ignoresSafeArea()
        }
        .sheet(item: $editorTarget) { target in
            if let draft = draftForEditor(target) {
                ImportedExerciseEditorSheet(
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
                        sourceNote: "Source: \(draft.sourceText)"
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
            imageSelectionSection

            if let errorMessage {
                messageCard(title: "Photo Import Couldn’t Finish", text: errorMessage, tint: AppTheme.secondary)
            }
        }
    }

    /// 26pt screen title; the explainer captions that sat under it and in
    /// the old WHAT THE IMPORTER HANDLES card are gone (look v2).
    private var headerSection: some View {
        Text("Turn a photo into a routine.")
            .font(.system(size: 26, weight: .bold))
            .tracking(-0.3)
            .foregroundStyle(AppTheme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 2)
    }

    private var imageSelectionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("PICK A PHOTO")
                .microLabel(AppTheme.textSecondary)

            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AppTheme.fieldBackground)

                if let selectedImage {
                    Image(uiImage: selectedImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .padding(16)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 34))
                            .foregroundStyle(AppTheme.textTertiary)

                        Text("Use the clearest crop you can")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .padding(24)
                }
            }
            .frame(height: 240)
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            }

            // THE gradient pill of the input stage beside a matching-height ghost.
            HStack(spacing: 10) {
                Button("Take Photo") {
                    showCamera = true
                }
                .buttonStyle(PrimaryButtonStyle(prominence: .ai))

                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Text("Upload Image")
                }
                .buttonStyle(GhostButtonStyle(verticalPadding: 17))
            }
        }
        .padding(AppTheme.cardPadding)
        .glassCard()
    }

    private var processingContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Importing your workout...")
                .font(.system(size: 26, weight: .bold))
                .tracking(-0.3)
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 18) {
                if let selectedImage {
                    Image(uiImage: selectedImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }

                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(AppTheme.primary)

                Text(processingMessage)
                    .font(.system(size: 15))
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(AppTheme.cardPadding)
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
                    recognizedTextSection(for: importedWorkout)
                    reviewDaysSection(for: importedWorkout)
                    reviewActions(for: importedWorkout)
                }
            }
        }
    }

    private func reviewHeader(for importedWorkout: ImportedWorkoutDraft) -> some View {
        let reviewCount = importedWorkout.uncertainExercises.count + importedWorkout.unmatchedExercises.count

        return VStack(alignment: .leading, spacing: 12) {
            Text("Review the imported routine")
                .font(.system(size: 26, weight: .bold))
                .tracking(-0.3)
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            reviewReadinessCard(
                title: reviewCount == 0 ? "Everything looks ready" : "\(reviewCount) item\(reviewCount == 1 ? "" : "s") still need review",
                text: reviewCount == 0
                    ? "The extracted plan looks clean. You can still tweak names or programming below."
                    : "Use Edit or Swap on any uncertain lines before you save the imported routine.",
                tint: reviewCount == 0 ? AppTheme.success : AppTheme.secondary,
                symbolName: reviewCount == 0 ? "checkmark.shield.fill" : "exclamationmark.triangle.fill"
            )

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], alignment: .leading, spacing: 10) {
                importStat(title: "\(importedWorkout.days.count)", subtitle: "Days")
                importStat(title: "\(importedWorkout.totalExercises)", subtitle: "Exercises")
                importStat(title: "\(importedWorkout.readyExercises.count)", subtitle: "Ready")
                importStat(title: "\(importedWorkout.uncertainExercises.count)", subtitle: "Check")
                importStat(title: "\(importedWorkout.unmatchedExercises.count)", subtitle: "Custom")
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

            revisionComposer(placeholder: "Try: replace barbell work with easier machine exercises") {
                applyRevision(to: importedWorkout)
            }
        }
        .padding(AppTheme.cardPadding)
        .glassCard()
    }

    private func recognizedTextSection(for importedWorkout: ImportedWorkoutDraft) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("EXTRACTED TEXT")
                .microLabel(AppTheme.textSecondary)

            Text(importedWorkout.sourceText)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .surfaceCard()
        }
        .padding(AppTheme.cardPadding)
        .glassCard()
    }

    private func reviewDaysSection(for importedWorkout: ImportedWorkoutDraft) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ROUTINE PREVIEW")
                .microLabel(AppTheme.textSecondary)

            ForEach(importedWorkout.days.indices, id: \.self) { dayIndex in
                reviewDayCard(dayIndex: dayIndex)
            }
        }
    }

    private func reviewDayCard(dayIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            TrackerTextField("Day Name", text: dayNameBinding(for: dayIndex))
                .textFieldStyle(TrackerTextFieldStyle())

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
                    reviewExerciseRow(dayIndex: dayIndex, exerciseIndex: item.offset, exercise: item.element)
                }
            }
        }
        .padding(AppTheme.cardPadding)
        .glassCard()
    }

    private func reviewExerciseRow(dayIndex: Int, exerciseIndex: Int, exercise: ImportedExerciseDraft) -> some View {
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

                    Text("Source: \(exercise.sourceText)")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if isExpanded, let tip {
                        Text(tip)
                            .font(.footnote)
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text(importStatusLine(for: exercise))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(statusTint(for: exercise))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                confidenceChip(for: exercise)
            }

            if exercise.isCustomExercise {
                Text("Custom Imported Exercise")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppTheme.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppTheme.secondary.opacity(0.12))
                    .clipShape(Capsule())
            }

            detailTagWrap(values: exercise.detailSummary)

            if let warningText = exercise.warningText {
                Text(warningText)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Button("Edit Details") {
                    editorTarget = ImportedExerciseEditorTarget(dayIndex: dayIndex, exerciseIndex: exerciseIndex)
                }
                .buttonStyle(GhostButtonStyle(isCompact: true))

                Menu("Swap Match") {
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
        .surfaceCard(border: statusTint(for: exercise).opacity(0.22))
    }

    private func reviewActions(for importedWorkout: ImportedWorkoutDraft) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("Save \(importedWorkout.days.count) Routine\(importedWorkout.days.count == 1 ? "" : "s")") {
                saveImportedWorkout()
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isApplyingRevision || importedWorkout.totalExercises == 0)
            .opacity(!isApplyingRevision && importedWorkout.totalExercises > 0 ? 1 : 0.6)

            Button("Import Another Photo") {
                resetImportFlow()
            }
            .buttonStyle(GhostButtonStyle())
        }
    }

    private func loadPhotoPickerItem(_ item: PhotosPickerItem) {
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    errorMessage = WorkoutPhotoImportError.unreadableImage.localizedDescription
                    return
                }

                process(image: image)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func process(image: UIImage) {
        if exerciseStore.exercises.isEmpty {
            exerciseStore.loadExercises()
        }

        selectedImage = image
        errorMessage = nil
        conversationMessages = []
        stage = .processing
        processingMessage = "Uploading your image..."

        Task {
            do {
                let importedWorkout = try await pipeline.importWorkout(
                    from: image,
                    sourceKind: "photo",
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
        selectedPhotoItem = nil
        selectedImage = nil
        importedWorkout = nil
        errorMessage = nil
        editorTarget = nil
        smartSwapTarget = nil
        conversationMessages = []
        latestCoachChangeSummary = nil
        revisionPrompt = ""
        isApplyingRevision = false
        expandedDetailIDs = []
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
                    self.importedWorkout = revisionResult.draft
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
        let reviewCount = importedWorkout.uncertainExercises.count + importedWorkout.unmatchedExercises.count
        let opening = reviewCount == 0
            ? "I imported a clean draft from your photo. Ask for any swaps, easier alternatives, or structural changes before you save it."
            : "I imported the plan and flagged \(reviewCount) item\(reviewCount == 1 ? "" : "s") for review. Ask for cleaner swaps or changes and I’ll keep updating the draft."

        return [.assistant(opening)]
    }

    private func revisionAssistantReply(for result: ImportedWorkoutRevisionResult) -> String {
        if let assistantReply = result.assistantReply?.nilIfEmpty {
            return assistantReply
        }

        if result.action.changedDraft {
            return result.changeSummary?.nilIfEmpty ?? "I updated the imported draft and kept the review flow intact."
        }

        return "I can keep helping you think through this before we change the draft."
    }



    private func importStatusLine(for exercise: ImportedExerciseDraft) -> String {
        if exercise.isCustomExercise {
            return "No strong library match yet. Keep it custom or swap it."
        }

        switch exercise.confidence {
        case .high:
            return exercise.missingProgrammingDetails.isEmpty
                ? "This looks like a clean match."
                : "The match looks good, but \(exercise.missingProgrammingDetails.lowercased())."
        case .medium:
            return "This is probably right, but it deserves a quick check."
        case .low:
            return "This match is unclear. Choose the exercise you actually meant."
        }
    }

    private func statusTint(for exercise: ImportedExerciseDraft) -> Color {
        if exercise.isCustomExercise {
            return AppTheme.secondary
        }

        switch exercise.confidence {
        case .high:
            return AppTheme.success
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

        return Text(exercise.confidence.title)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
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

private struct ImportedExerciseEditorSheet: View {
    let draft: ImportedExerciseDraft
    let allExercises: [Exercise]
    var onSave: (ImportedExerciseDraft) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var selectedExerciseName: String
    @State private var customName: String
    @State private var setCountText: String
    @State private var repText: String
    @State private var restText: String
    @State private var notesText: String
    @State private var intensityText: String
    @State private var searchText = ""

    init(draft: ImportedExerciseDraft, allExercises: [Exercise], onSave: @escaping (ImportedExerciseDraft) -> Void) {
        self.draft = draft
        self.allExercises = allExercises
        self.onSave = onSave
        _selectedExerciseName = State(initialValue: draft.matchedExerciseName ?? draft.resolvedExerciseName)
        _customName = State(initialValue: draft.resolvedExerciseName)
        _setCountText = State(initialValue: draft.setCount.map(String.init) ?? "")
        _repText = State(initialValue: draft.repText ?? "")
        _restText = State(initialValue: draft.restSeconds.map(String.init) ?? "")
        _notesText = State(initialValue: draft.notes)
        _intensityText = State(initialValue: draft.intensityNotes.joined(separator: ", "))
    }

    private var searchResults: [Exercise] {
        let pool = allExercises

        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let candidateNames = [draft.matchedExerciseName] + draft.matchCandidates.map(\.name)
            let names = Set(candidateNames.compactMap { $0 })
            let seeded = pool.filter { names.contains($0.name) }
            return Array(seeded.prefix(8))
        }

        return pool
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
            .navigationTitle("Review Exercise")
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
            Text("SOURCE TEXT")
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
            Text(draft.isCustomExercise ? "CUSTOM IMPORTED EXERCISE" : "MATCHED EXERCISE")
                .microLabel()

            if draft.isCustomExercise {
                TrackerTextField("Custom exercise name", text: $customName)
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
            Text("PROGRAMMING DETAILS")
                .microLabel()

            HStack(spacing: 12) {
                TrackerTextField("Sets", text: $setCountText)
                    .keyboardType(.numberPad)
                    .textFieldStyle(TrackerTextFieldStyle())

                TrackerTextField("Reps", text: $repText)
                    .textFieldStyle(TrackerTextFieldStyle())
            }

            TrackerTextField("Rest (seconds)", text: $restText)
                .keyboardType(.numberPad)
                .textFieldStyle(TrackerTextFieldStyle())

            TrackerTextField("Notes", text: $notesText, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(TrackerTextFieldStyle())

            TrackerTextField("Intensity notes (comma separated)", text: $intensityText, axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(TrackerTextFieldStyle())
        }
        .padding(AppTheme.cardPadding)
        .glassCard()
    }

    private func saveChanges() {
        var updated = draft
        updated.setCount = Int(setCountText.trimmingCharacters(in: .whitespacesAndNewlines))
        updated.repText = repText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        updated.restSeconds = Int(restText.trimmingCharacters(in: .whitespacesAndNewlines))
        updated.notes = notesText.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.intensityNotes = intensityText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if draft.isCustomExercise {
            let resolvedName = customName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? draft.resolvedExerciseName
            updated.exerciseName = resolvedName
            updated.customExercise?.name = resolvedName

            if selectedExerciseName != draft.resolvedExerciseName,
               allExercises.contains(where: { $0.name == selectedExerciseName }) {
                updated.isCustomExercise = false
                updated.matchedExerciseName = selectedExerciseName
                updated.exerciseName = selectedExerciseName
                updated.customExercise = nil
                updated.confidence = .medium
            }
        } else if allExercises.contains(where: { $0.name == selectedExerciseName }) {
            updated.matchedExerciseName = selectedExerciseName
            updated.exerciseName = selectedExerciseName
            updated.isCustomExercise = false
            updated.customExercise = nil
        }

        onSave(updated)
        dismiss()
    }
}

private struct PhotoImportCameraPicker: UIViewControllerRepresentable {
    var onComplete: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let onComplete: (UIImage?) -> Void

        init(onComplete: @escaping (UIImage?) -> Void) {
            self.onComplete = onComplete
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onComplete(nil)
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = info[.originalImage] as? UIImage
            onComplete(image)
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
