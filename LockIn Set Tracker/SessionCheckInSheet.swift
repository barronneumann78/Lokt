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
/// path (difficulty tile → "No"), a visible skip. Answers persist through
/// `WorkoutStore.recordCheckIn`; a clean check-in offers a constrained
/// next-session nudge (applied only on the explicit Apply tap — review-before-
/// save holds); pain or repeated too-hard routes to a real coach conversation
/// instead of a silent adjustment (spine §6).
///
/// Look (v2, "Check-in — two taps, then a nudge"): a card-colored sheet with
/// 28pt corners and a hairline, 64pt effort tiles, 52pt pain tiles, and the
/// NEXT SESSION card whose rows carry the payload's targets verbatim.
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

    private let sheetCornerRadius: CGFloat = 28
    private let tileCornerRadius: CGFloat = 16
    private let nudgeCardCornerRadius: CGFloat = 18

    var body: some View {
        VStack(spacing: 0) {
            handle

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
                .padding(.horizontal, AppTheme.screenPadding)
                .padding(.top, 16)
                .padding(.bottom, AppTheme.screenPadding)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .dismissKeyboardOnTap()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(sheetCornerRadius)
        .presentationBackground {
            AppTheme.card
                .overlay {
                    RoundedRectangle(cornerRadius: sheetCornerRadius, style: .continuous)
                        .strokeBorder(AppTheme.cardBorder, lineWidth: 1)
                }
        }
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

    // MARK: - Chrome

    private var handle: some View {
        Capsule()
            .fill(AppTheme.textTertiary)
            .frame(width: 40, height: 4)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("SESSION CHECK-IN")
                    .microLabel()

                Text(headerTitle)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)
            }

            Spacer(minLength: 0)

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
                    choiceTile(outcome.label, height: 64, isSelected: selectedOutcome == outcome) {
                        selectedOutcome = outcome
                        maybeAutoSubmit()
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("ANYTHING HURT?")
                    .microLabel()

                HStack(spacing: 8) {
                    choiceTile("No", height: 52, isSelected: painAnswer == false) {
                        painAnswer = false
                        painExercise = nil
                        painNoteText = ""
                        maybeAutoSubmit()
                    }

                    choiceTile("Yes, something", height: 52, isSelected: painAnswer == true) {
                        painAnswer = true
                    }
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
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(AppTheme.fieldBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
                        .stroke(AppTheme.cardBorder, lineWidth: 1)
                }

            Button("Continue") {
                submit()
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(selectedOutcome == nil)
            .opacity(selectedOutcome == nil ? 0.55 : 1)
        }
    }

    /// The board's answer tile: `surfaceElevated` under a hairline at rest;
    /// selected = `accentChipFill` + `accentHairline` + accent label (the
    /// app's selected-chip vocabulary — state encoding, not chrome).
    private func choiceTile(_ label: String, height: CGFloat, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isSelected ? AppTheme.accent : AppTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(isSelected ? AppTheme.accentChipFill : AppTheme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: tileCornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: tileCornerRadius, style: .continuous)
                        .stroke(isSelected ? AppTheme.accentHairline : AppTheme.cardBorder, lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: tileCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// Capsule chip for the pain quick-pick — same selected vocabulary as the tiles.
    private func selectChip(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? AppTheme.accent : AppTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(isSelected ? AppTheme.accentChipFill : AppTheme.surfaceElevated)
                .clipShape(Capsule())
                .overlay {
                    Capsule()
                        .stroke(isSelected ? AppTheme.accentHairline : AppTheme.cardBorder, lineWidth: 1)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Loading / settled / failed

    /// Holds the nudge card's place while the backend sizes the next session.
    private var loadingSection: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(AppTheme.textSecondary)

            Text("Sizing up your next session")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .surfaceCard(cornerRadius: nudgeCardCornerRadius)
    }

    private func settledSection(_ note: String?) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            stateCapsule(note ?? "Your targets are working. No changes.")

            Button("Done") {
                dismiss()
            }
            .buttonStyle(GhostButtonStyle())
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
            .buttonStyle(GhostButtonStyle())
        }
    }

    /// Saved-style capsule (the coach draft's "Saved"): success check + the
    /// state's existing copy on `mutedFill` under a hairline.
    private func stateCapsule(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "checkmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.success)

            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(AppTheme.mutedFill)
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        }
    }

    // MARK: - Nudge

    private func nudgeSection(_ nudge: WorkoutNudge) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            nudgeCard(nudge)

            Button("APPLY TO ROUTINE") {
                applyNudge(nudge)
            }
            .buttonStyle(PrimaryButtonStyle())

            Button("Not now") {
                dismiss()
            }
            .buttonStyle(GhostButtonStyle())
        }
    }

    /// NEXT SESSION card: one row per changed exercise, then the nudge's own
    /// one-line note. The fallback line only appears when the payload carries
    /// no note — it states the mechanism (targets come from the last completed
    /// set), never a claim about the result.
    private func nudgeCard(_ nudge: WorkoutNudge) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NEXT SESSION")
                .microLabel(AppTheme.accent)

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

            Text(nudge.overallNote ?? "Sized from today's completed sets")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .topTrailing) {
            nudgeCardGlow
        }
        .surfaceCard(cornerRadius: nudgeCardCornerRadius)
    }

    /// The board's faint accent glow in the card's top-right corner: the
    /// `.heroGlow()` token drawn behind an empty 120pt box pinned top-trailing
    /// and nudged into the corner; the card's clip trims the overflow. The
    /// radial itself lives in Theme.swift.
    private var nudgeCardGlow: some View {
        Color.clear
            .frame(width: 120, height: 120)
            .heroGlow()
            .offset(x: 28, y: -28)
            .allowsHitTesting(false)
    }

    private func nudgeRow(_ item: WorkoutNudgeItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(item.name)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 2) {
                ForEach(changeLines(for: item), id: \.self) { line in
                    Text(line)
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .padding(.vertical, 12)
    }

    /// Display only. The "to" side of every line is the payload's echo-verbatim
    /// field (`suggestedWeightText` / `repText` / `setCount`); the "from" side is
    /// the routine's own current value — the very number the request sent as
    /// `lastWeightText` / `sets` — read back, never recomputed.
    private func changeLines(for item: WorkoutNudgeItem) -> [String] {
        let routine = store.routine(withID: prompt.routineID)
        var lines: [String] = []

        if let weight = item.suggestedWeightText {
            var line = weight
            if let last = routine?.progression?[item.name]?.lastWeight, !last.isEmpty {
                line = "\(last) → \(weight)"
            }
            if let reps = item.repText {
                line += " × \(reps)"
            }
            lines.append(line)
        } else if let reps = item.repText {
            lines.append("\(reps) reps")
        }

        if let sets = item.setCount {
            if let current = routine?.preferredSetCount(for: item.name), current != sets {
                lines.append("\(current) → \(sets) sets")
            } else {
                lines.append("\(sets) sets")
            }
        }

        return lines
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
            .buttonStyle(GhostButtonStyle())
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
