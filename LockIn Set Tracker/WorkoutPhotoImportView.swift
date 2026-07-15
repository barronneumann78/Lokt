import PhotosUI
import SwiftUI
import UIKit

struct WorkoutPhotoImportView: View {
    var onSave: () -> Void

    @Environment(\.dismiss) private var dismiss

    @StateObject private var exerciseStore = ExerciseStore()
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
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
        }
        .navigationTitle("Import from Photo")
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

            trustSection
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Turn a photo into a routine.")
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)

            Text("Import a screenshot, typed plan, split sheet, or clear handwritten workout. You’ll review the routine before saving.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(20)
        .glassCard()
    }

    private var imageSelectionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Pick a Photo")
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)

            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(AppTheme.surface)

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
                            .foregroundStyle(AppTheme.secondary)

                        Text("Use the clearest crop you can")
                            .font(.headline)
                            .foregroundStyle(AppTheme.textPrimary)

                        Text("Portrait screenshots and close photos of your routine usually parse best.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(24)
                }
            }
            .frame(height: 260)
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            }

            HStack(spacing: 12) {
                Button("Take Photo") {
                    showCamera = true
                }
                .buttonStyle(PrimaryButtonStyle(fill: AppTheme.secondary))

                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Text("Upload Image")
                }
                .buttonStyle(PrimaryButtonStyle(fill: AppTheme.surfaceElevated))
            }
        }
        .padding(20)
        .glassCard()
    }

    private var processingContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Importing your workout...")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)

                Text("Lokt is reading the image, matching exercises, and flagging anything unclear.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .padding(20)
            .glassCard()

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
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
                    .multilineTextAlignment(.center)
            }
            .padding(20)
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
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)

            Text("Nothing saves until you confirm. Review the matches, fix anything unclear, and keep custom exercises only when they really belong.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)

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
        .padding(20)
        .glassCard()
    }

    private func revisionSection(for importedWorkout: ImportedWorkoutDraft) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Coach Chat")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text("Keep refining the imported plan with follow-up requests before you save it.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                }

                Spacer()

                if isApplyingRevision {
                    ProgressView()
                        .tint(AppTheme.primary)
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

            TextField("Try: replace barbell work with easier machine exercises", text: $revisionPrompt, axis: .vertical)
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

    private func recognizedTextSection(for importedWorkout: ImportedWorkoutDraft) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Extracted Text")
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)

            Text(importedWorkout.sourceText)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .surfaceCard()
        }
        .padding(20)
        .glassCard()
    }

    private func reviewDaysSection(for importedWorkout: ImportedWorkoutDraft) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Routine Preview")
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)

            ForEach(importedWorkout.days.indices, id: \.self) { dayIndex in
                reviewDayCard(dayIndex: dayIndex)
            }
        }
    }

    private func reviewDayCard(dayIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("Day Name", text: dayNameBinding(for: dayIndex))
                .textFieldStyle(TrackerTextFieldStyle())

            if let notes = importedWorkout?.days[dayIndex].notes, !notes.isEmpty {
                Text(notes.joined(separator: " • "))
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
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
        .padding(20)
        .glassCard()
    }

    private func reviewExerciseRow(dayIndex: Int, exerciseIndex: Int, exercise: ImportedExerciseDraft) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    ExerciseTextNavigationLink(exerciseName: exercise.resolvedExerciseName, exercises: exerciseStore.exercises) {
                        Text(exercise.resolvedExerciseName)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(AppTheme.textPrimary)
                    }

                    Text("Source: \(exercise.sourceText)")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

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
                    .font(.caption.weight(.bold))
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
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.secondary.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            HStack(spacing: 10) {
                Button("Edit Details") {
                    editorTarget = ImportedExerciseEditorTarget(dayIndex: dayIndex, exerciseIndex: exerciseIndex)
                }
                .buttonStyle(SecondaryButtonStyle())

                Menu("Swap Match") {
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
        .surfaceCard(border: statusTint(for: exercise).opacity(0.22))
    }

    private func reviewActions(for importedWorkout: ImportedWorkoutDraft) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("Save \(importedWorkout.days.count) Routine\(importedWorkout.days.count == 1 ? "" : "s")") {
                saveImportedWorkout()
            }
            .buttonStyle(PrimaryButtonStyle(fill: AppTheme.success))
            .disabled(isApplyingRevision || importedWorkout.totalExercises == 0)
            .opacity(!isApplyingRevision && importedWorkout.totalExercises > 0 ? 1 : 0.6)

            Button("Import Another Photo") {
                resetImportFlow()
            }
            .buttonStyle(PrimaryButtonStyle(fill: AppTheme.surfaceElevated))
        }
    }

    private var trustSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What the importer handles")
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            Text("Works with typed routines, shorthand like DB Bench 3x10, split names like Push/Pull/Legs, and clear handwritten notes. Nothing saves until you review it.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(20)
        .glassCard()
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
        ImportedWorkoutSaver.save(importedWorkout)
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

    private func coachChangeCard(summary: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "wand.and.stars")
                .font(.headline)
                .foregroundStyle(AppTheme.primary)

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
        .surfaceCard(cornerRadius: AppTheme.controlCornerRadius, border: AppTheme.primary.opacity(0.35))
    }

    private func importStat(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.weight(.heavy))
                .foregroundStyle(AppTheme.textPrimary)

            Text(subtitle.uppercased())
                .font(.caption.weight(.bold))
                .tracking(1)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .surfaceCard()
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
            return AppTheme.accent
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
                return AppTheme.accent
            }
        }()

        return Text(exercise.confidence.title)
            .font(.caption.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func detailTagWrap(values: [String]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(values, id: \.self) { value in
                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppTheme.mutedFill)
                    .clipShape(Capsule())
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
                Text(isUser ? "You" : "Lokt Coach")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isUser ? AppTheme.primary : AppTheme.textSecondary)

                Text(message.text)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isUser ? AppTheme.primary.opacity(0.12) : AppTheme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isUser ? AppTheme.primary.opacity(0.18) : AppTheme.cardBorder.opacity(0.7), lineWidth: 1)
            }

            if !isUser {
                Spacer(minLength: 32)
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
            }
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
            Text("Source Text")
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

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
            Text(draft.isCustomExercise ? "Custom Imported Exercise" : "Matched Exercise")
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            if draft.isCustomExercise {
                TextField("Custom exercise name", text: $customName)
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

            TextField("Search existing exercises to swap", text: $searchText)
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
                                .foregroundStyle(selectedExerciseName == exercise.name ? AppTheme.success : AppTheme.textSecondary.opacity(0.4))
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
            Text("Programming Details")
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            HStack(spacing: 12) {
                TextField("Sets", text: $setCountText)
                    .keyboardType(.numberPad)
                    .textFieldStyle(TrackerTextFieldStyle())

                TextField("Reps", text: $repText)
                    .textFieldStyle(TrackerTextFieldStyle())
            }

            TextField("Rest (seconds)", text: $restText)
                .keyboardType(.numberPad)
                .textFieldStyle(TrackerTextFieldStyle())

            TextField("Notes", text: $notesText, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(TrackerTextFieldStyle())

            TextField("Intensity notes (comma separated)", text: $intensityText, axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(TrackerTextFieldStyle())
        }
        .padding(20)
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
