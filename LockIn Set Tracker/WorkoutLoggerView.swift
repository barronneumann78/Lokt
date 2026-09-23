import SwiftUI
import Combine

struct WorkoutLoggerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var coachRouter: CoachRouter
    @AppStorage("workoutCoachModeEnabled") private var isCoachModeEnabled = true
    @EnvironmentObject private var exerciseStore: ExerciseStore
    @EnvironmentObject private var workoutStore: WorkoutStore
    @State private var activeRoutine: Routine
    @State private var logs: [String: [WorkoutSet]] = [:]
    @State private var completed = false
    @State private var expandedExercises: Set<String> = []
    @State private var preferredSetCounts: [String: Int] = [:]
    @State private var draggedExercise: String?
    @State private var workoutStartDate = Date()
    @State private var currentTime = Date()
    @State private var hasStartedWorkoutTimer = false
    @State private var restTimerEndDate: Date?
    @State private var lastRestDuration: TimeInterval = 90
    @State private var activeRestExercise: String?
    @State private var swapTarget: ExerciseSwapTarget?
    @State private var showSupplementaryBlockGenerator = false
    /// The bottom-of-list "Add Exercise" picker sheet.
    @State private var showAddExercisePicker = false
    /// Exercises added mid-workout, in add order. Session-scoped: they never
    /// touch the saved routine unless the user keeps them at finish.
    @State private var sessionAddedExercises: [String] = []
    /// The one keep-in-routine question has been answered (either way).
    @State private var keepAddedPromptResolved = false
    @State private var workoutBuilderFeedbackMessage: String?
    @State private var showUncheckedFinishDialog = false
    /// M4: the just-saved session awaiting its post-workout check-in.
    @State private var checkInPrompt: SessionCheckInPrompt?
    /// In-memory mirror of the persisted `activeWorkoutV1` slot.
    @State private var activeWorkoutState: ActiveWorkoutState?
    @State private var activePersistWorkItem: DispatchWorkItem?
    /// Finish paused on an implausible clock — the one inserted step.
    @State private var durationFixPrompt: DurationFixPrompt?
    @State private var pendingFinishDurationSeconds: Int?
    /// The duration actually written to the saved session (may be the fixed one).
    @State private var savedDurationSeconds: Int?
    /// The one focus coordinate for every set cell. Plain state (not
    /// `@FocusState`): the cells are UIKit text fields, which report and
    /// receive first-responder moves through this value.
    @State private var focusedField: LoggerField?
    /// Sessions matching this routine, decoded ONCE per appearance (and after
    /// a finish) instead of per body evaluation — previous-set lookups, stat
    /// chips, and history all read this cache.
    @State private var routineSessions: [WorkoutSession] = []

    private let workoutTicker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(routine: Routine) {
        _activeRoutine = State(initialValue: routine)
    }

    var body: some View {
        ZStack {
            AppBackground()

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        headerSection

                        if isRestTimerActive {
                            restCard
                        }

                        ForEach(activeRoutine.exercises, id: \.self) { exercise in
                            exerciseCard(for: exercise)
                                .onDrop(
                                    of: [.plainText],
                                    delegate: ExerciseReorderDropDelegate(
                                        targetExercise: exercise,
                                        exercises: $activeRoutine.exercises,
                                        draggedExercise: $draggedExercise,
                                        didReorder: saveActiveRoutine
                                    )
                                )
                        }

                        addExerciseRow

                        finishSection
                        .padding(20)
                        .glassCard()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)
                }
                .onChange(of: focusedField) {
                    scrollToFocusedRow(proxy)
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            configureInitialSetCounts()
            restoreActiveWorkoutIfAvailable()
            startWorkoutTimerIfNeeded()
            refreshRoutineSessionsCache()
        }
        .onReceive(workoutTicker) { tick in
            handleTimerTick(tick)
        }
        .onChange(of: logs) {
            scheduleActiveWorkoutPersist()
        }
        .onChange(of: preferredSetCounts) {
            scheduleActiveWorkoutPersist()
        }
        .sheet(item: $swapTarget) { target in
            ExerciseSwapSheet(
                target: target,
                exercises: exerciseStore.exercises.filter {
                    exercise in
                    exercise.name.caseInsensitiveCompare(target.exerciseName) == .orderedSame ||
                    !activeRoutine.exercises.contains(where: { $0.caseInsensitiveCompare(exercise.name) == .orderedSame })
                }
            ) { suggestion in
                applySmartSwap(suggestion, replacing: target.exerciseName)
            }
        }
        .sheet(isPresented: $showSupplementaryBlockGenerator) {
            NavigationView {
                SupplementaryWorkoutGeneratorView(
                    onSave: { },
                    addToCurrentWorkout: appendSupplementaryBlock,
                    currentWorkoutTitle: activeRoutine.name
                )
            }
        }
        .sheet(isPresented: $showAddExercisePicker) {
            WorkoutAddExercisePicker(currentExerciseNames: activeRoutine.exercises) { exercise in
                addExerciseToCurrentWorkout(exercise)
            }
        }
        .sheet(item: $durationFixPrompt, onDismiss: handleDurationFixDismiss) { prompt in
            WorkoutDurationFixSheet(prompt: prompt) { seconds in
                pendingFinishDurationSeconds = seconds
                durationFixPrompt = nil
            }
        }
        .sheet(item: $checkInPrompt) { prompt in
            SessionCheckInSheet(prompt: prompt)
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(AppTheme.primary)
                        .frame(width: 7, height: 7)

                    Text("RECORDING")
                        .microLabel(AppTheme.primary)

                    Text("· \(workoutDurationText)")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.primary)
                }

                Text(activeRoutine.name)
                    .font(.system(size: 30, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(AppTheme.textPrimary)
            }

            if let nextTarget = nextLoggingTarget {
                Text("NEXT · \(nextTarget.exercise.uppercased()) · SET \(nextTarget.setIndex + 1)")
                    .microLabel(AppTheme.textSecondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }

            HStack(spacing: 10) {
                Button(isCoachModeEnabled ? "Coach On" : "Coach Off") {
                    isCoachModeEnabled.toggle()
                }
                .buttonStyle(SecondaryButtonStyle())

                Button("Ask Coach") {
                    coachRouter.openActiveWorkout(routine: activeRoutine, nextExercise: nextLoggingTarget?.exercise)
                }
                .buttonStyle(SecondaryButtonStyle())

                Button("Add Block") {
                    showSupplementaryBlockGenerator = true
                }
                .buttonStyle(SecondaryButtonStyle())

                if let workoutBuilderFeedbackMessage {
                    Text(workoutBuilderFeedbackMessage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.success)
                        .lineLimit(2)
                }
            }
            .padding(.top, 2)

            if isCoachModeEnabled, let coachContext = currentCoachContext {
                coachModeCard(for: coachContext)
            }
        }
    }

    private var restCard: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("REST")
                    .microLabel()

                Text(restCountdownText)
                    .font(.system(size: 44, weight: .bold))
                    .monospacedDigit()
                    .tracking(-1)
                    .foregroundStyle(AppTheme.primary)

                if let activeRestExercise {
                    Text("after \(activeRestExercise)")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 8) {
                    restAdjustChip("−15") { adjustRestTimer(by: -15) }
                    restAdjustChip("+15") { adjustRestTimer(by: 15) }
                }

                HStack(spacing: 8) {
                    Button("Reset") {
                        resetRestTimer()
                    }
                    .buttonStyle(TertiaryButtonStyle())

                    Button("Skip") {
                        skipRestTimer()
                    }
                    .buttonStyle(TertiaryButtonStyle())
                }
            }
        }
        .padding(AppTheme.cardPadding)
        .glassCard()
    }

    private func restAdjustChip(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(AppTheme.textPrimary)
                .frame(width: 52, height: 40)
                .background(AppTheme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppTheme.cardBorder, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private func adjustRestTimer(by seconds: TimeInterval) {
        guard let endDate = restTimerEndDate else { return }
        let adjusted = endDate.addingTimeInterval(seconds)
        restTimerEndDate = max(adjusted, Date().addingTimeInterval(1))
    }

    // MARK: - Exercise card

    /// Builds one isolated card: every input is a value derived for this
    /// exercise, so `.equatable()` lets unchanged cards skip their bodies
    /// entirely — a keystroke re-diffs one card, a timer tick re-diffs none.
    private func exerciseCard(for exercise: String) -> some View {
        LoggerExerciseCard(
            exercise: exercise,
            sets: logs[exercise] ?? [],
            setCount: setCount(for: exercise),
            isActiveExercise: isPrimaryExercise(exercise),
            activeSetIndex: activeSetIndex(for: exercise),
            focus: cardFocus(for: exercise),
            lastSessionSets: routineSessions.last?.logs[exercise],
            lastSummary: lastSessionSummary(for: exercise),
            targetChip: targetChipText(for: exercise),
            oneRM: estimatedOneRM(for: exercise),
            nudgeNote: appliedNudgeState(for: exercise)?.nudgeNote,
            isHistoryExpanded: expandedExercises.contains(exercise),
            history: historyEntries(for: exercise),
            isLastExercise: activeRoutine.exercises.last == exercise,
            draggedExercise: $draggedExercise,
            addAction: ExerciseDetailPrimaryAddAction(title: "Add to This Workout") { detailExercise in
                addExerciseToCurrentWorkout(detailExercise)
            },
            onSmartSwap: {
                swapTarget = ExerciseSwapTarget(
                    exerciseName: exercise,
                    sourceNote: "Swap this exercise without losing the workout’s overall purpose."
                )
            },
            onToggleHistory: { toggleHistory(exercise) },
            onAddSet: { addSet(to: exercise) },
            onRemoveSet: { removeSet(from: exercise) },
            onWeightChange: { set, newValue in
                logs[exercise, default: []] = update(
                    logs[exercise],
                    exercise: exercise,
                    at: set,
                    weight: newValue,
                    targetCount: setCount(for: exercise)
                )
            },
            onRepsChange: { set, newValue in
                logs[exercise, default: []] = update(
                    logs[exercise],
                    exercise: exercise,
                    at: set,
                    reps: newValue,
                    targetCount: setCount(for: exercise)
                )
            },
            onToggleCompletion: { toggleSetCompletion(for: exercise, at: $0) },
            onUseLast: { applyLastSet(to: exercise, at: $0) },
            onFocusChange: fieldFocusChanged(_:isFocused:),
            onAdvance: advanceFocus(from:)
        )
        .equatable()
    }

    private func activeSetIndex(for exercise: String) -> Int? {
        guard let nextTarget = nextLoggingTarget, nextTarget.exercise == exercise else { return nil }
        return nextTarget.setIndex
    }

    /// Focus scoped to one card — nil unless the focused cell lives there,
    /// so a focus change invalidates only the cards it leaves and enters.
    private func cardFocus(for exercise: String) -> LoggerField? {
        guard let focusedField, focusedField.exercise == exercise else { return nil }
        return focusedField
    }

    /// TARGET chip text: an applied check-in nudge wins, otherwise the
    /// fatigue model's estimate as before.
    private func targetChipText(for exercise: String) -> String? {
        if let nudgeTarget = nudgeTargetText(for: exercise) {
            return nudgeTarget
        }
        if let suggestion = fatigueAdjustedSuggestedWeight(for: exercise) {
            return "\(formatWeight(suggestion.suggestedWeight)) lb"
        }
        return nil
    }

    /// Recent completed set-lists, newest first — only computed while the
    /// card's history is expanded.
    private func historyEntries(for exercise: String) -> [[WorkoutSet]] {
        guard expandedExercises.contains(exercise) else { return [] }
        return Array(
            routineSessions.reversed()
                .compactMap { session -> [WorkoutSet]? in
                    guard let sets = session.logs[exercise]?.filter(\.isCompleted), !sets.isEmpty else { return nil }
                    return sets
                }
                .prefix(5)
        )
    }

    private func fieldFocusChanged(_ field: LoggerField, isFocused: Bool) {
        if isFocused {
            if focusedField != field {
                focusedField = field
            }
        } else if focusedField == field {
            focusedField = nil
        }
    }

    /// Next: weight → reps → next set's weight → next exercise's first set,
    /// skipping nothing. False = nothing left (the field dismisses itself).
    private func advanceFocus(from field: LoggerField) -> Bool {
        if let next = nextField(after: field) {
            focusedField = next
            return true
        }
        focusedField = nil
        return false
    }

    private func applyLastSet(to exercise: String, at set: Int) {
        guard let previous = getLastSet(for: exercise, at: set) else { return }
        applyPreviousSet(previous, to: exercise, at: set)
    }

    /// Keeps the focused row visible above the keyboard — the UIKit cells
    /// don't get SwiftUI's own focused-TextField auto-scroll. Each row is
    /// tagged with its weight-field id; anchor nil scrolls minimally, so an
    /// already-visible row doesn't move. Deferred a beat to land after the
    /// keyboard's safe-area change.
    private func scrollToFocusedRow(_ proxy: ScrollViewProxy) {
        guard let focusedField else { return }
        let rowID = LoggerField.weight(focusedField.exercise, focusedField.setIndex)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard let current = self.focusedField,
                  LoggerField.weight(current.exercise, current.setIndex) == rowID else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(rowID, anchor: nil)
            }
        }
    }

    private func toggleSetCompletion(for exercise: String, at index: Int) {
        var sets = resize(sets: logs[exercise], to: setCount(for: exercise))
        guard sets.indices.contains(index) else { return }

        if sets[index].isCompleted {
            sets[index].completed = false
            logs[exercise] = sets
            return
        }

        // A set can only be checked once it has parseable numbers.
        guard AnalyticsMath.isMeaningfulSet(sets[index]) else {
            focusedField = .weight(exercise, index)
            return
        }

        sets[index].completed = true
        logs[exercise] = sets
        startRestTimer(for: exercise)
    }

    /// Progression state carrying an applied-nudge target for this exercise.
    private func appliedNudgeState(for exercise: String) -> ExerciseProgressionState? {
        guard let state = activeRoutine.progression?[exercise],
              state.suggestedWeightText != nil || state.suggestedRepText != nil || state.nudgeNote != nil else {
            return nil
        }
        return state
    }

    /// Applied-nudge target rendered for the TARGET chip / coach WEIGHT pill.
    private func nudgeTargetText(for exercise: String) -> String? {
        guard let state = appliedNudgeState(for: exercise) else { return nil }

        let weight = nonEmptyTrimmed(state.suggestedWeightText)
        let reps = nonEmptyTrimmed(state.suggestedRepText)

        switch (weight, reps) {
        case let (weight?, reps?): return "\(weight) × \(reps)"
        case let (weight?, nil): return weight
        case let (nil, reps?): return "\(reps) reps"
        default: return nil
        }
    }

    private func nonEmptyTrimmed(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func lastSessionSummary(for exercise: String) -> String? {
        guard let sets = routineSessions.last?.logs[exercise],
              let best = sets.first(where: { $0.isCompleted && isLoggedSet($0) }) else {
            return nil
        }
        return "\(best.weight) × \(best.reps)"
    }

    private func estimatedOneRM(for exercise: String) -> Int? {
        guard let sets = routineSessions.last?.logs[exercise] else { return nil }

        let estimates: [Double] = sets.compactMap { set in
            guard set.isCompleted,
                  let weight = parseWeight(set.weight),
                  let reps = Double(set.reps.trimmingCharacters(in: .whitespacesAndNewlines)),
                  weight > 0, reps > 0, reps < 15 else {
                return nil
            }
            return weight * (1 + reps / 30)
        }

        guard let best = estimates.max() else { return nil }
        return Int(best.rounded())
    }

    /// The direct mid-workout add: one obvious row at the bottom of the
    /// exercise list, right where the user is when they want one more.
    /// Neutral chrome — the finish button keeps this screen's accent.
    private var addExerciseRow: some View {
        Button {
            showAddExercisePicker = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))

                Text("Add Exercise")
                    .font(.body.weight(.semibold))

                Spacer()
            }
            .foregroundStyle(AppTheme.textPrimary)
            .padding(20)
            .glassCard()
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var finishSection: some View {
        if completed {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(AppTheme.success)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Workout Saved")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(AppTheme.textPrimary)

                        Text("Nice work. This session is now in your history.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }

                HStack(spacing: 12) {
                    completionStat(
                        title: "Duration",
                        value: savedDurationSeconds.map { formatDuration(TimeInterval($0)) } ?? workoutDurationText
                    )
                    completionStat(title: "Sets", value: "\(loggedSetCount)")
                    completionStat(title: "Exercises", value: "\(completedExerciseCount)")
                }

                // The one keep-in-routine question — asked here in the wrap-up,
                // never mid-workout. Keep = explicit tap, so review-before-save
                // holds for session-added exercises too.
                if !sessionAddedExercises.isEmpty && !keepAddedPromptResolved {
                    HStack(spacing: 10) {
                        Text(keepAddedPromptText)
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(AppTheme.textPrimary)

                        Spacer()

                        Button("Keep") {
                            resolveKeepAddedPrompt(keep: true)
                        }
                        .buttonStyle(SecondaryButtonStyle())

                        Button("No") {
                            resolveKeepAddedPrompt(keep: false)
                        }
                        .buttonStyle(TertiaryButtonStyle())
                    }
                }

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle(fill: AppTheme.surfaceElevated))
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Wrap Up")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.textPrimary)

                HStack(spacing: 12) {
                    completionStat(title: "Logged Sets", value: "\(loggedSetCount)")
                    completionStat(title: "Exercises", value: "\(completedExerciseCount)/\(activeRoutine.exercises.count)")
                }

                Button("Finish Workout") {
                    if uncheckedFilledSetCount > 0 {
                        showUncheckedFinishDialog = true
                    } else {
                        finishWorkout(checkingAllFilledSets: false)
                    }
                }
                .buttonStyle(PrimaryButtonStyle(fill: AppTheme.success))
                .confirmationDialog(
                    uncheckedFinishTitle,
                    isPresented: $showUncheckedFinishDialog,
                    titleVisibility: .visible
                ) {
                    Button("Check All & Finish") {
                        finishWorkout(checkingAllFilledSets: true)
                    }

                    Button("Finish Without Them") {
                        finishWorkout(checkingAllFilledSets: false)
                    }

                    Button("Cancel", role: .cancel) { }
                }
            }
        }
    }

    private var uncheckedFinishTitle: String {
        let count = uncheckedFilledSetCount
        return count == 1
            ? "1 set isn't checked off — finish anyway?"
            : "\(count) sets aren't checked off — finish anyway?"
    }

    /// Marks the finish. Unchecked sets keep their numbers but carry
    /// `completed == false`, so nothing downstream ever counts them.
    /// A plausible clock saves straight away; an implausible one (forgotten
    /// workout, phone slept overnight) inserts the ONE duration-fix step first.
    private func finishWorkout(checkingAllFilledSets: Bool) {
        if checkingAllFilledSets {
            for exercise in activeRoutine.exercises {
                var sets = resize(sets: logs[exercise], to: setCount(for: exercise))
                for index in sets.indices where !sets[index].isCompleted && AnalyticsMath.isMeaningfulSet(sets[index]) {
                    sets[index].completed = true
                }
                logs[exercise] = sets
            }
        }

        let now = Date()
        guard hasStartedWorkoutTimer else {
            completeFinish(durationSeconds: nil)
            return
        }

        let reference = activeWorkoutState ?? ActiveWorkoutState(
            routineID: activeRoutine.id,
            routineName: activeRoutine.name,
            startedAt: workoutStartDate,
            lastInteractionAt: workoutStartDate,
            activeSeconds: nil,
            logs: logs,
            preferredSetCounts: preferredSetCounts
        )

        if reference.needsDurationFix(now: now) {
            durationFixPrompt = DurationFixPrompt(
                defaultSeconds: reference.smartDurationSeconds(now: now),
                elapsedSeconds: max(0, Int(now.timeIntervalSince(workoutStartDate)))
            )
        } else {
            completeFinish(durationSeconds: max(0, Int(now.timeIntervalSince(workoutStartDate))))
        }
    }

    /// A confirmed duration fix resumes the finish once the sheet is gone;
    /// a swiped-away sheet cancels nothing — the workout keeps recording.
    private func handleDurationFixDismiss() {
        guard let seconds = pendingFinishDurationSeconds else { return }
        pendingFinishDurationSeconds = nil
        completeFinish(durationSeconds: seconds)
    }

    /// The actual save. Clears the persisted in-progress slot, then hands off
    /// to the M4 check-in exactly as before.
    private func completeFinish(durationSeconds: Int?) {
        let session = WorkoutSession(
            date: Date(),
            routineID: activeRoutine.id,
            routineName: activeRoutine.name,
            logs: logs,
            durationSeconds: durationSeconds,
            // The on-screen order at finish — the only record of where each
            // exercise sat (logs is a dictionary). Feeds the Advanced analytics.
            exerciseOrder: activeRoutine.exercises
        )
        saveWorkoutSession(session)
        savedDurationSeconds = durationSeconds
        refreshRoutineSessionsCache()

        activePersistWorkItem?.cancel()
        activePersistWorkItem = nil
        ActiveWorkoutStore.clear()
        activeWorkoutState = nil

        currentTime = Date()
        skipRestTimer()
        completed = true

        // M4: one ultra-light check-in right after the save — every finish
        // path (direct, unchecked-sets dialog, duration fix) lands here.
        checkInPrompt = SessionCheckInPrompt(
            sessionID: session.id,
            routineID: activeRoutine.id,
            routineName: activeRoutine.name,
            exercises: activeRoutine.exercises
        )
    }

    private var keepAddedPromptText: String {
        let count = sessionAddedExercises.count
        return count == 1
            ? "Keep 1 added exercise in the routine?"
            : "Keep \(count) added exercises in the routine?"
    }

    /// Keep = upsert the SAME routine id with the session-added exercises
    /// appended (their in-session set counts included). No = session-only;
    /// either answer retires the prompt for good.
    private func resolveKeepAddedPrompt(keep: Bool) {
        keepAddedPromptResolved = true
        guard keep else { return }

        let base = workoutStore.routine(withID: activeRoutine.id)
            ?? SessionAdditionLogic.routineStrippingSessionAdded(
                activeRoutine,
                sessionAdded: sessionAddedExercises
            )
        workoutStore.upsertRoutine(
            SessionAdditionLogic.routineKeepingSessionAdded(
                base,
                sessionAdded: sessionAddedExercises,
                preferredSetCounts: preferredSetCounts
            )
        )

        // Kept exercises are routine exercises now — clear the session list so
        // a later routine write (post-finish reorder or set-count tweak) never
        // strips them back out.
        sessionAddedExercises = []
    }

    private func configureInitialSetCounts() {
        for exercise in activeRoutine.exercises {
            let count = activeRoutine.preferredSetCount(for: exercise)
            preferredSetCounts[exercise] = count
            logs[exercise] = resize(sets: logs[exercise], to: count)
        }
    }

    private var nextLoggingTarget: (exercise: String, setIndex: Int)? {
        for exercise in activeRoutine.exercises {
            if let setIndex = firstIncompleteSetIndex(for: exercise) {
                return (exercise, setIndex)
            }
        }

        guard let firstExercise = activeRoutine.exercises.first else { return nil }
        return (firstExercise, max(setCount(for: firstExercise) - 1, 0))
    }

    private func firstIncompleteSetIndex(for exercise: String) -> Int? {
        let sets = resize(sets: logs[exercise], to: setCount(for: exercise))
        return sets.firstIndex(where: { !$0.isCompleted })
    }

    private func isPrimaryExercise(_ exercise: String) -> Bool {
        nextLoggingTarget?.exercise == exercise
    }

    private func startWorkoutTimerIfNeeded() {
        guard !hasStartedWorkoutTimer else { return }
        workoutStartDate = Date()
        currentTime = workoutStartDate
        hasStartedWorkoutTimer = true
    }

    // MARK: - In-progress persistence (activeWorkoutV1)

    /// Reopening the logger for the routine with a live persisted workout
    /// picks it up where it left off: entered numbers, checkmarks, set counts,
    /// and the ORIGINAL start time (quit-and-relaunch lands here too).
    private func restoreActiveWorkoutIfAvailable() {
        guard !hasStartedWorkoutTimer,
              let saved = ActiveWorkoutStore.load(),
              saved.routineID == activeRoutine.id else {
            return
        }

        for (exercise, count) in saved.preferredSetCounts {
            preferredSetCounts[exercise] = max(1, count)
        }

        // Session-added exercises live only in this snapshot — put them back
        // at the end of the session's order (skipping any the routine has
        // since absorbed) so quit-and-resume keeps them loggable.
        let restoredAdded = (saved.sessionAddedExercises ?? []).filter { name in
            !activeRoutine.exercises.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
        }
        activeRoutine.exercises.append(contentsOf: restoredAdded)
        for name in restoredAdded {
            activeRoutine.preferredSetCounts[name] =
                saved.preferredSetCounts[name] ?? SessionAdditionLogic.defaultSetCount
        }
        sessionAddedExercises = restoredAdded

        logs = saved.logs
        for exercise in activeRoutine.exercises {
            logs[exercise] = resize(sets: logs[exercise], to: setCount(for: exercise))
        }

        workoutStartDate = saved.startedAt
        currentTime = Date()
        hasStartedWorkoutTimer = true
        activeWorkoutState = saved
    }

    /// Cheap debounce: meaningful mutations (set edits, checks, add/remove)
    /// coalesce into one write shortly after the last change.
    private func scheduleActiveWorkoutPersist() {
        guard !completed else { return }
        activePersistWorkItem?.cancel()
        let item = DispatchWorkItem { persistActiveWorkoutNow() }
        activePersistWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: item)
    }

    private func persistActiveWorkoutNow() {
        guard !completed, ActiveWorkoutStore.hasMeaningfulContent(logs) else { return }

        let base = activeWorkoutState ?? ActiveWorkoutState(
            routineID: activeRoutine.id,
            routineName: activeRoutine.name,
            startedAt: workoutStartDate,
            lastInteractionAt: workoutStartDate,
            activeSeconds: 0,
            logs: [:],
            preferredSetCounts: [:]
        )
        var updated = base.updatingActivity(now: Date())
        updated.routineName = activeRoutine.name
        updated.logs = logs
        updated.preferredSetCounts = preferredSetCounts
        updated.sessionAddedExercises = sessionAddedExercises.isEmpty ? nil : sessionAddedExercises
        ActiveWorkoutStore.save(updated)
        activeWorkoutState = updated
    }

    private func handleTimerTick(_ tick: Date) {
        currentTime = tick

        if let restTimerEndDate, tick >= restTimerEndDate {
            skipRestTimer()
        }
    }

    private func setCount(for exercise: String) -> Int {
        max(1, preferredSetCounts[exercise] ?? activeRoutine.preferredSetCount(for: exercise))
    }

    private func addSet(to exercise: String) {
        let newCount = setCount(for: exercise) + 1
        applyPreferredSetCount(newCount, for: exercise)
    }

    private func removeSet(from exercise: String) {
        let newCount = max(1, setCount(for: exercise) - 1)
        applyPreferredSetCount(newCount, for: exercise)
    }

    private func applyPreferredSetCount(_ count: Int, for exercise: String) {
        preferredSetCounts[exercise] = count
        activeRoutine.preferredSetCounts[exercise] = count
        logs[exercise] = resize(sets: logs[exercise], to: count)
        saveActiveRoutine()
    }

    private func resize(sets: [WorkoutSet]?, to count: Int) -> [WorkoutSet] {
        // In-session sets carry an explicit flag — only the checkmark completes them.
        LoggerSetMath.resize(sets: sets, to: count)
    }

    private func saveActiveRoutine() {
        guard workoutStore.routine(withID: activeRoutine.id) != nil else {
            return
        }

        // Session-added exercises stay out of the SAVED routine until the
        // user's explicit Keep at finish — mid-workout writes (reorder, set
        // counts, swaps) persist the routine's own exercises only.
        workoutStore.upsertRoutine(
            SessionAdditionLogic.routineStrippingSessionAdded(
                activeRoutine,
                sessionAdded: sessionAddedExercises
            )
        )
    }

    private var workoutDurationText: String {
        formatDuration(currentTime.timeIntervalSince(workoutStartDate))
    }

    private var isRestTimerActive: Bool {
        restTimerEndDate != nil
    }

    private var restCountdownText: String {
        guard let restTimerEndDate else { return "0:00" }
        let remaining = max(0, Int(ceil(restTimerEndDate.timeIntervalSince(currentTime))))
        return formatDuration(TimeInterval(remaining))
    }

    private func completionStat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .microLabel()

            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(AppTheme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(AppTheme.mutedFill)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func coachModeCard(for context: WorkoutCoachContext) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("COACH")
                        .microLabel()

                    Text(context.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                }

                Spacer()

                if let afterExercise = context.afterExercise {
                    Text("Then \(afterExercise)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.textTertiary)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 10) {
                coachPill(title: "NEXT", value: context.nextLabel)
                coachPill(title: "REST", value: context.restLabel)

                if let suggestedWeight = context.suggestedWeight {
                    coachPill(title: "WEIGHT", value: suggestedWeight)
                }
            }

            if let cue = context.cue {
                Text(cue)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .surfaceCard(cornerRadius: AppTheme.rowCornerRadius)
    }

    private func coachPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .microLabel()

            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(AppTheme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppTheme.mutedFill)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var loggedSetCount: Int {
        activeRoutine.exercises.reduce(into: 0) { total, exercise in
            total += resize(sets: logs[exercise], to: setCount(for: exercise)).filter(\.isCompleted).count
        }
    }

    /// Sets with usable numbers the user never checked off — surfaced once at Finish.
    private var uncheckedFilledSetCount: Int {
        activeRoutine.exercises.reduce(into: 0) { total, exercise in
            total += resize(sets: logs[exercise], to: setCount(for: exercise))
                .filter { !$0.isCompleted && AnalyticsMath.isMeaningfulSet($0) }
                .count
        }
    }

    private var currentCoachContext: WorkoutCoachContext? {
        guard let nextTarget = nextLoggingTarget else { return nil }

        let currentExercise = nextTarget.exercise
        let exerciseDetail = exerciseStore.exercises.exercise(named: currentExercise)
        let suggestedWeightText = nudgeTargetText(for: currentExercise)
            ?? fatigueAdjustedSuggestedWeight(for: currentExercise).map {
                formatWeight($0.suggestedWeight)
            }
        let recommendedRest = restDuration(for: currentExercise)
        let afterExercise = nextExercise(after: currentExercise)

        return WorkoutCoachContext(
            title: currentExercise,
            nextLabel: "Set \(nextTarget.setIndex + 1)",
            restLabel: formatDuration(TimeInterval(recommendedRest)),
            suggestedWeight: suggestedWeightText,
            cue: exerciseDetail?.cues.first,
            afterExercise: afterExercise
        )
    }

    private var completedExerciseCount: Int {
        activeRoutine.exercises.filter { exercise in
            resize(sets: logs[exercise], to: setCount(for: exercise)).contains(where: \.isCompleted)
        }.count
    }

    private func startRestTimer(for exercise: String) {
        let duration = TimeInterval(restDuration(for: exercise))
        lastRestDuration = duration
        restTimerEndDate = Date().addingTimeInterval(duration)
        activeRestExercise = exercise
    }

    private func skipRestTimer() {
        restTimerEndDate = nil
        activeRestExercise = nil
    }

    private func resetRestTimer() {
        restTimerEndDate = Date().addingTimeInterval(lastRestDuration)
    }

    private func nextField(after field: LoggerField) -> LoggerField? {
        LoggerFocusModel.nextField(
            after: field,
            exercises: activeRoutine.exercises,
            setCount: setCount(for:)
        )
    }

    private func nextExercise(after exercise: String) -> String? {
        guard let currentIndex = activeRoutine.exercises.firstIndex(of: exercise) else { return nil }
        let nextIndex = currentIndex + 1
        guard activeRoutine.exercises.indices.contains(nextIndex) else { return nil }
        return activeRoutine.exercises[nextIndex]
    }

    private func applyPreviousSet(_ previousSet: WorkoutSet, to exercise: String, at set: Int) {
        var updatedSets = resize(sets: logs[exercise], to: setCount(for: exercise))
        guard updatedSets.indices.contains(set) else { return }

        // Copy the numbers only — the user still checks the set off themselves.
        updatedSets[set] = WorkoutSet(weight: previousSet.weight, reps: previousSet.reps, completed: false)
        logs[exercise] = updatedSets
    }

    private func restDuration(for exercise: String) -> Int {
        activeRoutine.importContext?.exercisePlans
            .first(where: { $0.exerciseName.caseInsensitiveCompare(exercise) == .orderedSame })?
            .restSeconds ?? 90
    }

    private func fatigueAdjustedSuggestedWeight(for exercise: String) -> FatigueAdjustedWeightSuggestion? {
        guard let baseWeight = recentWorkingWeight(for: exercise),
              let orderIndex = activeRoutine.exercises.firstIndex(of: exercise) else {
            return nil
        }

        return WorkoutFatigueModel.suggestion(baseWeight: baseWeight, orderIndex: orderIndex)
    }

    private func recentWorkingWeight(for exercise: String) -> Double? {
        guard let latestWeights = routineSessions.last?.logs[exercise] else { return nil }

        return latestWeights
            .filter(\.isCompleted)
            .compactMap { parseWeight($0.weight) }
            .first
    }

    private func parseWeight(_ weight: String) -> Double? {
        LoggerSetMath.parseWeight(weight)
    }

    private func formatWeight(_ weight: Double) -> String {
        if weight.rounded() == weight {
            return "\(Int(weight))"
        }

        return String(format: "%.1f", weight)
    }

    private func toggleHistory(_ exercise: String) {
        if expandedExercises.contains(exercise) {
            expandedExercises.remove(exercise)
        } else {
            expandedExercises.insert(exercise)
        }
    }

    private func update(
        _ sets: [WorkoutSet]?,
        exercise: String,
        at index: Int,
        weight: String? = nil,
        reps: String? = nil,
        targetCount: Int
    ) -> [WorkoutSet] {
        var updatedSets = resize(sets: sets, to: targetCount)
        if index < updatedSets.count {
            if let w = weight { updatedSets[index].weight = w }
            if let r = reps { updatedSets[index].reps = r }

            // Filling numbers never completes a set — only the checkmark does.
            // But clearing the numbers out of a checked set un-checks it.
            if !AnalyticsMath.isMeaningfulSet(updatedSets[index]) {
                updatedSets[index].completed = false
            }
        }
        return updatedSets
    }

    private func isLoggedSet(_ set: WorkoutSet) -> Bool {
        !set.weight.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !set.reps.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func formatDuration(_ timeInterval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(timeInterval))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%d:%02d", minutes, seconds)
    }

    private func saveWorkoutSession(_ session: WorkoutSession) {
        workoutStore.addSession(session)
    }

    private func getLastSet(for exercise: String, at index: Int) -> WorkoutSet? {
        guard let set = routineSessions.last?.logs[exercise]?[safe: index], set.isCompleted else { return nil }
        return set
    }

    /// One decode of the session history per appearance/finish — everything
    /// per-keystroke reads the cache. Sessions only change under this screen
    /// at finish (refreshed there) or while it's off-screen (onAppear).
    private func refreshRoutineSessionsCache() {
        routineSessions = workoutStore.sessions.filter(matchesRoutine)
    }

    private func matchesRoutine(_ session: WorkoutSession) -> Bool {
        if session.routineID == activeRoutine.id {
            return true
        }

        return activeRoutine.allKnownNames.contains(session.routineName)
    }

    /// SESSION-SCOPED add (picker rows and the detail page's "Add to This
    /// Workout" both land here): appended to this session's order, seeded with
    /// 3 empty sets, immediately loggable. The saved routine is untouched —
    /// the finish wrap-up asks ONCE whether to keep the additions.
    private func addExerciseToCurrentWorkout(_ exercise: Exercise) -> AddExerciseResult {
        guard let outcome = SessionAdditionLogic.addingExercise(
            named: exercise.name,
            toOrder: activeRoutine.exercises,
            sessionAdded: sessionAddedExercises,
            preferredSetCounts: preferredSetCounts,
            logs: logs
        ) else {
            return AddExerciseResult(message: "\(exercise.name) is already in this workout.", didMutate: false)
        }

        activeRoutine.exercises = outcome.order
        sessionAddedExercises = outcome.sessionAdded
        preferredSetCounts = outcome.preferredSetCounts
        // Mirrored into the in-memory routine copy so re-appearing (detail
        // push/pop) reseeds the same count — stripped before any persist.
        activeRoutine.preferredSetCounts[exercise.name] = outcome.preferredSetCounts[exercise.name]
        logs = outcome.logs

        return AddExerciseResult(message: "Added \(exercise.name) to this workout.", didMutate: true)
    }

    private func appendSupplementaryBlock(_ draft: AIGeneratedRoutineDraft) -> AddExerciseResult {
        var addedCount = 0

        for exercise in draft.exercises {
            let name = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }

            if activeRoutine.exercises.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                continue
            }

            activeRoutine.exercises.append(name)
            activeRoutine.preferredSetCounts[name] = max(1, exercise.sets)
            preferredSetCounts[name] = max(1, exercise.sets)
            logs[name] = resize(sets: logs[name], to: max(1, exercise.sets))
            addedCount += 1
        }

        guard addedCount > 0 else {
            return AddExerciseResult(message: "Those exercises are already in this workout.", didMutate: false)
        }

        saveActiveRoutine()
        workoutBuilderFeedbackMessage = addedCount == 1
            ? "Added 1 exercise."
            : "Added \(addedCount) exercises."

        return AddExerciseResult(
            message: addedCount == 1
                ? "Added 1 exercise to this workout."
                : "Added \(addedCount) exercises to this workout.",
            didMutate: true
        )
    }

    private func applySmartSwap(_ suggestion: ExerciseSwapSuggestion, replacing currentExerciseName: String) {
        guard let exerciseIndex = activeRoutine.exercises.firstIndex(where: {
            $0.caseInsensitiveCompare(currentExerciseName) == .orderedSame
        }) else {
            return
        }

        let newExerciseName = suggestion.exerciseName
        activeRoutine.exercises[exerciseIndex] = newExerciseName

        if let currentLogs = logs.removeValue(forKey: currentExerciseName) {
            logs[newExerciseName] = currentLogs
        }

        if let setCount = preferredSetCounts.removeValue(forKey: currentExerciseName) {
            preferredSetCounts[newExerciseName] = setCount
            activeRoutine.preferredSetCounts.removeValue(forKey: currentExerciseName)
            activeRoutine.preferredSetCounts[newExerciseName] = setCount
        }

        if expandedExercises.remove(currentExerciseName) != nil {
            expandedExercises.insert(newExerciseName)
        }

        if activeRestExercise?.caseInsensitiveCompare(currentExerciseName) == .orderedSame {
            activeRestExercise = newExerciseName
        }

        // Swapping a session-added exercise keeps the ADDITION session-scoped
        // under its new name (and keeps the finish prompt's count honest).
        if let addedIndex = sessionAddedExercises.firstIndex(where: {
            $0.caseInsensitiveCompare(currentExerciseName) == .orderedSame
        }) {
            sessionAddedExercises[addedIndex] = newExerciseName
        }

        if var context = activeRoutine.importContext,
           let planIndex = context.exercisePlans.firstIndex(where: { $0.exerciseName.caseInsensitiveCompare(currentExerciseName) == .orderedSame }) {
            context.exercisePlans[planIndex].matchedExerciseName = newExerciseName
            context.exercisePlans[planIndex].exerciseName = newExerciseName
            activeRoutine.importContext = context
        }

        saveActiveRoutine()
    }
}

private struct WorkoutCoachContext {
    var title: String
    var nextLabel: String
    var restLabel: String
    var suggestedWeight: String?
    var cue: String?
    var afterExercise: String?
}

/// Finish paused on an implausible clock — carries the smart default the
/// wheel starts at (never zero) and the raw elapsed for context.
struct DurationFixPrompt: Identifiable {
    let id = UUID()
    let defaultSeconds: Int
    let elapsedSeconds: Int
}

/// The ONE inserted step when the workout clock ran implausibly long: a wheel
/// already positioned at what the workout probably took — the user scrolls
/// from there, then the save proceeds as normal.
struct WorkoutDurationFixSheet: View {
    let prompt: DurationFixPrompt
    let onConfirm: (Int) -> Void

    @State private var selectedSeconds: Int

    init(prompt: DurationFixPrompt, onConfirm: @escaping (Int) -> Void) {
        self.prompt = prompt
        self.onConfirm = onConfirm
        _selectedSeconds = State(initialValue: prompt.defaultSeconds)
    }

    private var options: [Int] {
        let step = ActiveWorkoutState.durationStep
        let maxSeconds = max(8 * 3600, prompt.defaultSeconds)
        return Array(stride(from: step, through: maxSeconds, by: step))
    }

    var body: some View {
        ZStack {
            AppBackground()

            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("TIMER RAN \(formatElapsed(prompt.elapsedSeconds))")
                        .microLabel()
                        .monospacedDigit()

                    Text("How long was it really?")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(AppTheme.textPrimary)
                }

                Picker("Duration", selection: $selectedSeconds) {
                    ForEach(options, id: \.self) { seconds in
                        Text(durationLabel(seconds))
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(AppTheme.textPrimary)
                            .tag(seconds)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
                .frame(height: 168)

                Button("Save Workout") {
                    onConfirm(selectedSeconds)
                }
                .buttonStyle(PrimaryButtonStyle(fill: AppTheme.success))
            }
            .padding(20)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func durationLabel(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return String(format: "%d h %02d min", hours, minutes)
        }
        return "\(minutes) min"
    }

    private func formatElapsed(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
