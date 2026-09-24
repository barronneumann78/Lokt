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
    /// Cards the lifter re-opened after every set was checked (the header
    /// chevron). Session-only like `expandedExercises`; any un-check drops
    /// the exercise so `LoggerCollapseModel`'s derived rule reopens the card.
    @State private var manuallyExpandedExercises: Set<String> = []
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
                    VStack(alignment: .leading, spacing: 16) {
                        headerSection

                        if completed {
                            savedCard
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

                            // Under the active card: what comes next. Under
                            // the last card: the mid-workout add.
                            if !completed, isPrimaryExercise(exercise) || activeRoutine.exercises.last == exercise {
                                underCardRow(for: exercise)
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.screenPadding)
                    .padding(.vertical, 20)
                }
                // Drag-to-dismiss beside the cells' own Done key (their UIKit
                // accessory toolbar). No tap-to-dismiss on this screen: the
                // pinned COMPLETE SET and the row buttons keep the keyboard up
                // for the focus hand-off, and every cell is already a native
                // whole-cell tap target.
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom) {
                    pinnedActions
                }
                .onChange(of: focusedField) {
                    scrollToFocusedRow(proxy)
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                coachMenu
            }
        }
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

    // MARK: - Header (recording row · routine name · coach cue)

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 7) {
                Circle()
                    .fill(AppTheme.danger)
                    .frame(width: 7, height: 7)
                    .recordingGlow()

                Text("RECORDING")
                    .microLabel(AppTheme.textSecondary)

                Text("· \(workoutDurationText)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.textPrimary)

                Spacer(minLength: 8)

                if isRestTimerActive {
                    restChip
                }
            }

            Text(activeRoutine.name)
                .font(.system(size: 24, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(2)

            if let workoutBuilderFeedbackMessage {
                Text(workoutBuilderFeedbackMessage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.success)
                    .lineLimit(1)
            }

            // One coach line for the active exercise — off via Cues Off.
            if isCoachModeEnabled, let cue = currentCoachCue {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("COACH")
                        .microLabel()

                    Text(cue)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(2)
                }
            }
        }
    }

    /// The rest timer as an accent chip — shown only while a rest runs.
    /// Tapping it opens the timer controls (+15 / −15 / Reset / Skip), the
    /// same adjustments the old rest card carried.
    private var restChip: some View {
        Menu {
            Button("+15 s") { adjustRestTimer(by: 15) }
            Button("−15 s") { adjustRestTimer(by: -15) }
            Button("Reset") { resetRestTimer() }
            Button("Skip") { skipRestTimer() }
        } label: {
            Text("REST \(restCountdownText)")
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .tracking(0.6)
                .foregroundStyle(AppTheme.backgroundTop)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(AppTheme.primary)
                .clipShape(Capsule())
                .contentShape(Capsule())
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
    }

    /// Coach entry points, out of the header and into the nav bar: Ask
    /// Coach, Add Block, and the cue line's on/off.
    private var coachMenu: some View {
        Menu {
            Button("Ask Coach") {
                coachRouter.openActiveWorkout(routine: activeRoutine, nextExercise: nextLoggingTarget?.exercise)
            }

            Button("Add Block") {
                showSupplementaryBlockGenerator = true
            }

            Button(isCoachModeEnabled ? "Cues Off" : "Cues On") {
                isCoachModeEnabled.toggle()
            }
        } label: {
            Text("Coach")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
        }
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
            activeSetIndex: activeSetIndex(for: exercise),
            focus: cardFocus(for: exercise),
            lastSessionSets: routineSessions.last?.logs[exercise],
            targetChip: targetChipText(for: exercise),
            recommendedSets: recommendedSets(for: exercise),
            nudgeNote: appliedNudgeState(for: exercise)?.nudgeNote,
            isHistoryExpanded: expandedExercises.contains(exercise),
            history: historyEntries(for: exercise),
            isLastExercise: activeRoutine.exercises.last == exercise,
            isManuallyExpanded: manuallyExpandedExercises.contains(exercise),
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
            onToggleCollapse: { toggleManualExpansion(exercise) },
            onAddSet: { addSet(to: exercise) },
            onRemoveSet: { removeSet(from: exercise) },
            onSetCountChange: { applyPreferredSetCount(max(1, $0), for: exercise) },
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

    /// The plan's set count for the "Recommended sets: N" chip — only while
    /// it differs from what's on screen (the chip restores it in one tap).
    private func recommendedSets(for exercise: String) -> Int? {
        guard let planned = importedPlan(for: exercise)?.targetSets, planned >= 1,
              planned != setCount(for: exercise) else {
            return nil
        }
        return planned
    }

    private func importedPlan(for exercise: String) -> RoutineImportedExercisePlan? {
        activeRoutine.importContext?.exercisePlans
            .first(where: { $0.exerciseName.caseInsensitiveCompare(exercise) == .orderedSame })
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
            // Un-checking reopens the card: clear the manual flag so the
            // derived rule (all checked && !manual) is what folds it next.
            manuallyExpandedExercises.remove(exercise)
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

    // MARK: - Under the card

    /// Beneath the active card: a quiet "Then <next> · sets × reps" line.
    /// Beneath the last card: the mid-workout Add Exercise pill (session-
    /// scoped — the finish wrap-up asks once whether to keep additions).
    private func underCardRow(for exercise: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            if isPrimaryExercise(exercise), let thenLine = thenLine(after: exercise) {
                Text(thenLine)
                    .font(.footnote.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if activeRoutine.exercises.last == exercise {
                Button {
                    showAddExercisePicker = true
                } label: {
                    Label("Add Exercise", systemImage: "plus")
                }
                .buttonStyle(TertiaryButtonStyle())
            }
        }
        .padding(.horizontal, 4)
    }

    private func thenLine(after exercise: String) -> String? {
        guard let next = nextExercise(after: exercise) else { return nil }
        let sets = setCount(for: next)
        if let reps = plannedRepsText(for: next) {
            return "Then \(next) · \(sets) × \(reps)"
        }
        return "Then \(next) · \(sets) sets"
    }

    /// Rep target for an exercise: an applied nudge's rep text, else the
    /// imported plan's target reps.
    private func plannedRepsText(for exercise: String) -> String? {
        nonEmptyTrimmed(appliedNudgeState(for: exercise)?.suggestedRepText)
            ?? nonEmptyTrimmed(importedPlan(for: exercise)?.targetReps)
    }

    // MARK: - Saved state

    /// "Workout Saved" — under the header once the session is in history;
    /// the pinned Done dismisses.
    private var savedCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(AppTheme.success)

                Text("Workout Saved")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppTheme.textPrimary)
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
        }
        .padding(AppTheme.cardPadding)
        .glassCard()
    }

    // MARK: - Pinned actions — THE gradient pill of the screen

    /// COMPLETE SET checks the active set through the row checkmark's own
    /// path (numbers required, rest timer starts) and, with the keyboard up,
    /// walks focus on exactly as Next would. Once every set is checked the
    /// pill reads WRAP UP. Beneath it, Wrap Up as a ghost pill — hidden while
    /// typing so the stack above the keyboard stays short. After the save,
    /// the slot holds Done.
    private var pinnedActions: some View {
        VStack(spacing: 8) {
            if completed {
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle(fill: AppTheme.surfaceElevated))
            } else {
                Button(completionTarget == nil ? "WRAP UP" : "COMPLETE SET") {
                    if completionTarget == nil {
                        requestFinish()
                    } else {
                        completeActiveSet()
                    }
                }
                .buttonStyle(PrimaryButtonStyle())

                if completionTarget != nil && focusedField == nil {
                    Button("Wrap Up") {
                        requestFinish()
                    }
                    .buttonStyle(GhostButtonStyle())
                }
            }
        }
        .padding(.horizontal, AppTheme.screenPadding)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(AppTheme.backgroundTop)
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

    /// The finish flow, unchanged: unchecked-but-filled sets get the one
    /// dialog first; otherwise the save proceeds (duration fix included).
    private func requestFinish() {
        if uncheckedFilledSetCount > 0 {
            showUncheckedFinishDialog = true
        } else {
            finishWorkout(checkingAllFilledSets: false)
        }
    }

    /// The set COMPLETE SET acts on — the first incomplete set in order. A
    /// set the logs haven't padded yet is incomplete; entries past the set
    /// count are ignored, matching `resize`.
    private var completionTarget: (exercise: String, setIndex: Int)? {
        LoggerFocusModel.completionTarget(
            exercises: activeRoutine.exercises,
            setCount: setCount(for:),
            isCompleted: { exercise, index in logs[exercise]?[safe: index]?.isCompleted ?? false }
        )
    }

    private func completeActiveSet() {
        guard let target = completionTarget else { return }
        let keyboardWasUp = focusedField != nil

        // Same path as the row's checkmark: numbers required (an empty set
        // focuses its weight cell instead), rest timer starts on success.
        toggleSetCompletion(for: target.exercise, at: target.setIndex)
        guard logs[target.exercise]?[safe: target.setIndex]?.isCompleted == true else { return }

        // Keyboard up: walk on as Next would; past the last set focus stays
        // put (Done dismisses). Keyboard down stays down — the active row
        // moves on its own.
        if keyboardWasUp,
           let next = LoggerFocusModel.fieldAfterCompleting(
               exercise: target.exercise,
               setIndex: target.setIndex,
               exercises: activeRoutine.exercises,
               setCount: setCount(for:)
           ) {
            focusedField = next
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

    /// The table's highlighted set: the first incomplete one (the same target
    /// the COMPLETE SET pill acts on); once everything is checked, the first
    /// exercise's last set keeps the coach cue pointing somewhere.
    private var nextLoggingTarget: (exercise: String, setIndex: Int)? {
        if let target = completionTarget {
            return target
        }

        guard let firstExercise = activeRoutine.exercises.first else { return nil }
        return (firstExercise, max(setCount(for: firstExercise) - 1, 0))
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

    /// The library's first cue for the active exercise — the coach line.
    /// (Its NEXT / REST / WEIGHT pills are now the table's active row, the
    /// REST chip and the TARGET chip.)
    private var currentCoachCue: String? {
        guard let nextTarget = nextLoggingTarget else { return nil }
        return exerciseStore.exercises.exercise(named: nextTarget.exercise)?.cues.first
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

    /// Header chevron on a fully checked card: re-open or fold its set table.
    private func toggleManualExpansion(_ exercise: String) {
        if manuallyExpandedExercises.contains(exercise) {
            manuallyExpandedExercises.remove(exercise)
        } else {
            manuallyExpandedExercises.insert(exercise)
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

        if manuallyExpandedExercises.remove(currentExerciseName) != nil {
            manuallyExpandedExercises.insert(newExerciseName)
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
