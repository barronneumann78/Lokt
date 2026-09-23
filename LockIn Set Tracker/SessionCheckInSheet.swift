import SwiftUI

/// Identifies the just-saved session for the post-workout check-in sheet.
struct SessionCheckInPrompt: Identifiable {
    let sessionID: UUID
    let routineID: UUID
    let routineName: String
    let exercises: [String]

    var id: UUID { sessionID }
}

/// M4's end-of-workout check-in: one ultra-light sheet. Two taps on the happy
/// path (difficulty chip → "No"), a visible skip. Answers persist through
/// `WorkoutStore.recordCheckIn`; a clean check-in offers a constrained
/// next-session nudge (applied only on the explicit Apply tap — review-before-
/// save holds); pain or repeated too-hard routes to a real coach conversation
/// instead of a silent adjustment (spine §6).
struct SessionCheckInSheet: View {
    let prompt: SessionCheckInPrompt

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: WorkoutStore
    @EnvironmentObject private var coachRouter: CoachRouter

    private enum Phase {
        case asking
        case loading
        case nudge(WorkoutNudge)
        case settled(String?)
        case safety(SessionCheckIn)
        case failed(String)
    }

    @State private var phase: Phase = .asking
    @State private var selectedOutcome: CheckInOutcome?
    @State private var painAnswer: Bool?
    @State private var painExercise: String?
    @State private var painNoteText = ""

    @State private var didCountShown = false
    @State private var didSubmit = false
    @State private var nudgeOffered = false
    @State private var nudgeApplied = false

    private let nudgeService = WorkoutNudgeService()

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    switch phase {
                    case .asking:
                        askingSection
                    case .loading:
                        loadingSection
                    case .nudge(let nudge):
                        nudgeSection(nudge)
                    case .settled(let note):
                        settledSection(note)
                    case .safety(let checkIn):
                        safetySection(checkIn)
                    case .failed(let message):
                        failedSection(message)
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .dismissKeyboardOnTap()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .onAppear {
            guard !didCountShown else { return }
            didCountShown = true
            AdaptationMetrics.increment(.checkInShown)
        }
        .onDisappear {
            if !didSubmit {
                AdaptationMetrics.increment(.checkInSkipped)
            }
            if nudgeOffered && !nudgeApplied {
                AdaptationMetrics.increment(.nudgeDismissed)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            Text(headerTitle)
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textTertiary)
                    .frame(width: 36, height: 36)
                    .background(AppTheme.mutedFill)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var headerTitle: String {
        switch phase {
        case .asking: return "How was it?"
        case .loading, .nudge: return "Next time"
        case .settled: return "Locked in"
        case .safety: return "Worth a real look"
        case .failed: return "Next time"
        }
    }

    // MARK: - Asking

    private var askingSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 8) {
                ForEach(CheckInOutcome.allCases) { outcome in
                    selectChip(outcome.label, isSelected: selectedOutcome == outcome) {
                        selectedOutcome = outcome
                        maybeAutoSubmit()
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("ANYTHING HURT?")
                    .microLabel()

                HStack(spacing: 8) {
                    selectChip("No", isSelected: painAnswer == false) {
                        painAnswer = false
                        painExercise = nil
                        painNoteText = ""
                        maybeAutoSubmit()
                    }

                    selectChip("Yes", isSelected: painAnswer == true) {
                        painAnswer = true
                    }

                    Spacer()
                }
            }

            if painAnswer == true {
                painDetailSection
            }
        }
    }

    private var painDetailSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 130), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(prompt.exercises, id: \.self) { exercise in
                    selectChip(exercise, isSelected: painExercise == exercise) {
                        painExercise = (painExercise == exercise) ? nil : exercise
                    }
                }
            }

            TrackerTextField("Where it hurt — optional", text: $painNoteText)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(AppTheme.mutedFill)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Button("Continue") {
                submit()
            }
            .buttonStyle(PrimaryButtonStyle(fill: AppTheme.surfaceElevated))
            .disabled(selectedOutcome == nil)
            .opacity(selectedOutcome == nil ? 0.55 : 1)
        }
    }

    private func selectChip(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? AppTheme.backgroundTop : AppTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(isSelected ? AppTheme.textPrimary : AppTheme.surfaceElevated)
                .clipShape(Capsule())
                .overlay {
                    Capsule()
                        .stroke(AppTheme.cardBorder, lineWidth: isSelected ? 0 : 1)
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Loading / settled / failed

    private var loadingSection: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(AppTheme.textSecondary)

            Text("Sizing up your next session")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(.vertical, 12)
    }

    private func settledSection(_ note: String?) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(AppTheme.success)

                Text(note ?? "Your targets are working. No changes.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("Done") {
                dismiss()
            }
            .buttonStyle(PrimaryButtonStyle(fill: AppTheme.surfaceElevated))
        }
    }

    private func failedSection(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Done") {
                dismiss()
            }
            .buttonStyle(PrimaryButtonStyle(fill: AppTheme.surfaceElevated))
        }
    }

    // MARK: - Nudge

    private func nudgeSection(_ nudge: WorkoutNudge) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 0) {
                ForEach(Array(nudge.changedItems.enumerated()), id: \.element.name) { index, item in
                    nudgeRow(item)

                    if index < nudge.changedItems.count - 1 {
                        Rectangle()
                            .fill(AppTheme.cardBorder)
                            .frame(height: 1)
                    }
                }
            }
            .padding(.horizontal, 16)
            .surfaceCard(cornerRadius: AppTheme.rowCornerRadius)

            if let overallNote = nudge.overallNote {
                Text(overallNote)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("Apply") {
                applyNudge(nudge)
            }
            .buttonStyle(PrimaryButtonStyle())

            Button("Not now") {
                dismiss()
            }
            .buttonStyle(.plain)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.textSecondary)
            .frame(maxWidth: .infinity)
        }
    }

    private func nudgeRow(_ item: WorkoutNudgeItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 12)

                Text(targetLine(for: item))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
            }

            if let whyNote = item.whyNote {
                Text(whyNote)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 12)
    }

    private func targetLine(for item: WorkoutNudgeItem) -> String {
        let routine = store.routine(withID: prompt.routineID)
        let sets = item.setCount ?? routine?.preferredSetCount(for: item.name)
        var pieces: [String] = []

        if let sets, let reps = item.repText {
            pieces.append("\(sets)×\(reps)")
        } else if item.setCount != nil, let sets {
            pieces.append("\(sets) sets")
        } else if let reps = item.repText {
            pieces.append("\(reps) reps")
        }

        if let weight = item.suggestedWeightText {
            pieces.append(weight)
        }

        return pieces.joined(separator: " · ")
    }

    // MARK: - Safety branch (spine §6)

    private func safetySection(_ checkIn: SessionCheckIn) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(safetyLine(for: checkIn))
                .font(.subheadline)
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Talk It Through with Coach") {
                openCoach(with: checkIn)
            }
            .buttonStyle(PrimaryButtonStyle())

            Button("Not now") {
                dismiss()
            }
            .buttonStyle(.plain)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.textSecondary)
            .frame(maxWidth: .infinity)
        }
    }

    private func safetyLine(for checkIn: SessionCheckIn) -> String {
        if checkIn.hadPain {
            if let exercise = checkIn.painExercise {
                return "Pain at \(exercise). That's not a load problem to push through."
            }
            return "Pain isn't a load problem to push through."
        }
        return "That's a few too-hard sessions in a row. Adding weight isn't the answer."
    }

    private func openCoach(with checkIn: SessionCheckIn) {
        guard let routine = store.routine(withID: prompt.routineID) else {
            dismiss()
            return
        }

        coachRouter.openActiveWorkout(
            routine: routine,
            nextExercise: nil,
            checkInNote: coachCheckInNote(for: checkIn)
        )
        dismiss()
    }

    /// Compact fragment describing what the check-in said (routine identity
    /// rides along in the snapshot). Consumers frame it: the coach opener and
    /// the backend context line both lead with it so the first reply addresses
    /// the pain or the repeated too-hard directly.
    private func coachCheckInNote(for checkIn: SessionCheckIn) -> String {
        var parts = ["felt \(checkIn.overall.label.lowercased())"]

        if checkIn.hadPain {
            var pain = "pain"
            if let exercise = checkIn.painExercise {
                pain += " at \(exercise)"
            }
            if let note = checkIn.painNote, !note.isEmpty {
                pain += " (\(note))"
            }
            parts.append(pain)
        } else {
            parts.append("too hard several sessions running")
        }

        return parts.joined(separator: "; ")
    }

    // MARK: - Submit

    private func maybeAutoSubmit() {
        guard selectedOutcome != nil, painAnswer == false else { return }
        submit()
    }

    private func submit() {
        guard !didSubmit, let outcome = selectedOutcome, let hadPain = painAnswer else { return }

        let trimmedNote = painNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        let checkIn = SessionCheckIn(
            overall: outcome,
            hadPain: hadPain,
            painNote: hadPain && !trimmedNote.isEmpty ? trimmedNote : nil,
            painExercise: hadPain ? painExercise : nil
        )

        didSubmit = true
        AdaptationMetrics.increment(.checkInAnswered)

        store.recordCheckIn(checkIn, forSessionID: prompt.sessionID)

        if checkIn.hadPain || routineNeedsRealCheckIn {
            phase = .safety(checkIn)
        } else {
            requestNudge(with: checkIn)
        }
    }

    /// True when any exercise in the routine has tripped the spine §6 gate
    /// (open pain flag or repeated too-hard) after this check-in was folded in.
    private var routineNeedsRealCheckIn: Bool {
        guard let routine = store.routine(withID: prompt.routineID) else { return false }
        let progression = routine.progression ?? [:]
        return routine.exercises.contains { progression[$0]?.needsRealCheckIn == true }
    }

    private func requestNudge(with checkIn: SessionCheckIn) {
        guard let routine = store.routine(withID: prompt.routineID) else {
            phase = .settled(nil)
            return
        }

        phase = .loading

        Task { @MainActor in
            do {
                let nudge = try await nudgeService.fetchNudge(for: routine, checkIn: checkIn)

                if nudge.hasChanges {
                    nudgeOffered = true
                    AdaptationMetrics.increment(.nudgeOffered)
                    phase = .nudge(nudge)
                } else {
                    phase = .settled(nudge.overallNote)
                }
            } catch WorkoutNudgeError.safetyRefused {
                // Defense in depth: the server saw something the client missed.
                phase = .safety(checkIn)
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private func applyNudge(_ nudge: WorkoutNudge) {
        guard let routine = store.routine(withID: prompt.routineID) else {
            dismiss()
            return
        }

        // The explicit Apply tap is the save — review-before-save holds.
        store.upsertRoutine(nudge.applied(to: routine))
        nudgeApplied = true
        AdaptationMetrics.increment(.nudgeApplied)
        dismiss()
    }
}
