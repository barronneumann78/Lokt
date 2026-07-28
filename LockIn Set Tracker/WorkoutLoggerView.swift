import SwiftUI
import Combine

struct WorkoutLoggerView: View {
    private enum WorkoutInputField: Hashable {
        case weight(String, Int)
        case reps(String, Int)
    }

    private struct QuickLogCommand {
        var weight: String?
        var reps: String?
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var coachRouter: CoachRouter
    @AppStorage("workoutCoachModeEnabled") private var isCoachModeEnabled = true
    @StateObject private var exerciseStore = ExerciseStore()
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
    @State private var quickLogInputs: [String: String] = [:]
    @State private var swapTarget: ExerciseSwapTarget?
    @State private var showSupplementaryBlockGenerator = false
    @State private var workoutBuilderFeedbackMessage: String?
    @State private var showUncheckedFinishDialog = false
    @FocusState private var focusedField: WorkoutInputField?

    private let workoutTicker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(routine: Routine) {
        _activeRoutine = State(initialValue: routine)
    }

    var body: some View {
        ZStack {
            AppBackground()

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

                    finishSection
                    .padding(20)
                    .glassCard()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            configureInitialSetCounts()
            startWorkoutTimerIfNeeded()
        }
        .onReceive(workoutTicker) { tick in
            handleTimerTick(tick)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if currentFocusedPreviousSet != nil {
                    Button("Use Last") {
                        applyFocusedPreviousSet()
                    }
                }

                Spacer()

                Button(keyboardPrimaryActionTitle) {
                    handleKeyboardPrimaryAction()
                }

                Button("Done") {
                    focusedField = nil
                }
            }
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

    private func exerciseCard(for exercise: String) -> some View {
        let isActiveExercise = isPrimaryExercise(exercise)

        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        if isActiveExercise {
                            Text("ACTIVE")
                                .microLabel(AppTheme.primary)
                        }

                        ExerciseTextNavigationLink(
                            exerciseName: exercise,
                            exercises: exerciseStore.exercises,
                            primaryAddAction: ExerciseDetailPrimaryAddAction(title: "Add to This Workout") { detailExercise in
                                addExerciseToCurrentWorkout(detailExercise)
                            }
                        ) {
                            Text(exercise)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(AppTheme.textPrimary)
                        }
                    }

                    Spacer()

                    ExerciseDragHandle(exerciseName: exercise, draggedExercise: $draggedExercise)
                }

                HStack(spacing: 8) {
                    Button("Smart Swap") {
                        swapTarget = ExerciseSwapTarget(
                            exerciseName: exercise,
                            sourceNote: "Swap this exercise without losing the workout’s overall purpose."
                        )
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    Button(expandedExercises.contains(exercise) ? "Hide History" : "History") {
                        toggleHistory(exercise)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }

            setTable(for: exercise)

            HStack(spacing: 10) {
                Button {
                    addSet(to: exercise)
                } label: {
                    Label("Add Set", systemImage: "plus")
                }
                .buttonStyle(SecondaryButtonStyle())

                Button {
                    removeSet(from: exercise)
                } label: {
                    Label("Delete Set", systemImage: "minus")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(setCount(for: exercise) <= 1)
                .opacity(setCount(for: exercise) <= 1 ? 0.55 : 1)

                Spacer()
            }

            statChips(for: exercise)

            if expandedExercises.contains(exercise) {
                historySection(for: exercise)
            }
        }
        .padding(20)
        .glassCard()
    }

    private func setTable(for exercise: String) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("SET")
                    .microLabel()
                    .frame(width: 30, alignment: .leading)

                Text("WEIGHT")
                    .microLabel()
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("REPS")
                    .microLabel()
                    .frame(maxWidth: .infinity, alignment: .leading)

                Color.clear
                    .frame(width: 44, height: 1)
            }
            .padding(.bottom, 8)

            hairline

            ForEach(0..<setCount(for: exercise), id: \.self) { set in
                setRow(exercise: exercise, set: set)

                if set < setCount(for: exercise) - 1 {
                    hairline
                }
            }
        }
    }

    private func setRow(exercise: String, set: Int) -> some View {
        let isActive = isPrimarySet(exercise: exercise, setIndex: set)
        let isDone = isCompletedSet(exercise: exercise, setIndex: set)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text("\(set + 1)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(isActive ? AppTheme.backgroundTop : AppTheme.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(isActive ? AppTheme.primary : AppTheme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .frame(width: 30, alignment: .leading)

                setField(
                    text: Binding(
                        get: { logs[exercise]?[safe: set]?.weight ?? "" },
                        set: { newValue in
                            logs[exercise, default: []] = update(
                                logs[exercise],
                                exercise: exercise,
                                at: set,
                                weight: newValue,
                                targetCount: setCount(for: exercise)
                            )
                        }
                    ),
                    keyboard: .decimalPad,
                    isActive: isActive
                )
                .focused($focusedField, equals: .weight(exercise, set))

                setField(
                    text: Binding(
                        get: { logs[exercise]?[safe: set]?.reps ?? "" },
                        set: { newValue in
                            logs[exercise, default: []] = update(
                                logs[exercise],
                                exercise: exercise,
                                at: set,
                                reps: newValue,
                                targetCount: setCount(for: exercise)
                            )
                        }
                    ),
                    keyboard: .numberPad,
                    isActive: isActive
                )
                .focused($focusedField, equals: .reps(exercise, set))

                setCheckButton(exercise: exercise, set: set, isActive: isActive, isDone: isDone)
                    .frame(width: 44)
            }

            if let previous = getLastSet(for: exercise, at: set), !isDone {
                Button {
                    applyPreviousSet(previous, to: exercise, at: set)
                } label: {
                    Text("Use last · \(previous.weight) × \(previous.reps)")
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .padding(.leading, 42)
            }

            if isActive {
                HStack(spacing: 10) {
                    TextField(
                        "Quick log: 135 x 8 · drop to 120",
                        text: quickLogBinding(for: exercise, set: set)
                    )
                    .font(.footnote)
                    .textFieldStyle(TrackerTextFieldStyle())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit {
                        applyQuickLogInput(for: exercise, at: set)
                    }

                    Button("Apply") {
                        applyQuickLogInput(for: exercise, at: set)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(quickLogInputs[quickLogKey(for: exercise, set: set), default: ""]
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty)
                    .opacity(quickLogInputs[quickLogKey(for: exercise, set: set), default: ""]
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty ? 0.6 : 1)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, isActive ? 8 : 0)
        .background(isActive ? AppTheme.surfaceElevated : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func setField(text: Binding<String>, keyboard: UIKeyboardType, isActive: Bool) -> some View {
        TextField("0", text: text)
            .keyboardType(keyboard)
            .font(.system(size: 20, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(isActive ? AppTheme.primary : AppTheme.textPrimary)
            .tint(AppTheme.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(isActive ? AppTheme.backgroundTop.opacity(0.45) : AppTheme.mutedFill)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// The checkmark is the single source of truth for set completion.
    /// Completed = volt check, incomplete = hollow circle (volt on the active row).
    private func setCheckButton(exercise: String, set: Int, isActive: Bool, isDone: Bool) -> some View {
        Button {
            toggleSetCompletion(for: exercise, at: set)
        } label: {
            ZStack {
                if isDone {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppTheme.primary)
                        .frame(width: 26, height: 26)

                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppTheme.backgroundTop)
                } else {
                    Circle()
                        .stroke(isActive ? AppTheme.primary : AppTheme.textTertiary, lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    private func statChips(for exercise: String) -> some View {
        HStack(spacing: 10) {
            statChip(label: "LAST", value: lastSessionSummary(for: exercise) ?? "—")

            if let suggestion = fatigueAdjustedSuggestedWeight(for: exercise) {
                statChip(label: "TARGET", value: "\(formatWeight(suggestion.suggestedWeight)) lb")
            }

            if let oneRM = estimatedOneRM(for: exercise) {
                statChip(label: "1RM", value: "\(oneRM) lb")
            }

            statChip(label: "VOL", value: sessionVolumeText(for: exercise))
        }
    }

    private func statChip(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .microLabel()
                .lineLimit(1)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(AppTheme.mutedFill)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var hairline: some View {
        Rectangle()
            .fill(AppTheme.cardBorder)
            .frame(height: 1)
    }

    private func lastSessionSummary(for exercise: String) -> String? {
        let sessions = loadWorkoutSessions().filter(matchesRoutine)
        guard let sets = sessions.last?.logs[exercise],
              let best = sets.first(where: { $0.isCompleted && isLoggedSet($0) }) else {
            return nil
        }
        return "\(best.weight) × \(best.reps)"
    }

    private func estimatedOneRM(for exercise: String) -> Int? {
        let sessions = loadWorkoutSessions().filter(matchesRoutine)
        guard let sets = sessions.last?.logs[exercise] else { return nil }

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

    private func sessionVolumeText(for exercise: String) -> String {
        let sets = resize(sets: logs[exercise], to: setCount(for: exercise))
        let volume = sets.reduce(0.0) { total, set in
            guard set.isCompleted,
                  let weight = parseWeight(set.weight),
                  let reps = Double(set.reps.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                return total
            }
            return total + weight * reps
        }
        guard volume > 0 else { return "—" }
        return Int(volume).formatted(.number.grouping(.automatic))
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
                    completionStat(title: "Duration", value: workoutDurationText)
                    completionStat(title: "Sets", value: "\(loggedSetCount)")
                    completionStat(title: "Exercises", value: "\(completedExerciseCount)")
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

    /// Saves the session. Unchecked sets keep their numbers but carry
    /// `completed == false`, so nothing downstream ever counts them.
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

        let session = WorkoutSession(date: Date(), routineID: activeRoutine.id, routineName: activeRoutine.name, logs: logs)
        saveWorkoutSession(session)
        currentTime = Date()
        skipRestTimer()
        completed = true
    }

    @ViewBuilder
    private func historySection(for exercise: String) -> some View {
        let allSessions = loadWorkoutSessions().reversed().filter(matchesRoutine)
        let history = Array(
            allSessions
                .compactMap { session -> [WorkoutSet]? in
                    guard let sets = session.logs[exercise]?.filter(\.isCompleted), !sets.isEmpty else { return nil }
                    return sets
                }
                .prefix(5)
        )

        if history.isEmpty {
            Text("No history yet for this exercise.")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("RECENT HISTORY")
                    .microLabel()

                ForEach(Array(history.enumerated()), id: \.offset) { item in
                    let sets = item.element

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Workout \(item.offset + 1)")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(AppTheme.textSecondary)

                        Text(historySummary(for: sets))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.mutedFill)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(.top, 6)
        }
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

    private func isCompletedSet(exercise: String, setIndex: Int) -> Bool {
        guard let set = resize(sets: logs[exercise], to: setCount(for: exercise))[safe: setIndex] else {
            return false
        }

        return set.isCompleted
    }

    private func isPrimaryExercise(_ exercise: String) -> Bool {
        nextLoggingTarget?.exercise == exercise
    }

    private func isPrimarySet(exercise: String, setIndex: Int) -> Bool {
        guard let nextTarget = nextLoggingTarget else { return false }
        return nextTarget.exercise == exercise && nextTarget.setIndex == setIndex
    }

    private func startWorkoutTimerIfNeeded() {
        guard !hasStartedWorkoutTimer else { return }
        workoutStartDate = Date()
        currentTime = workoutStartDate
        hasStartedWorkoutTimer = true
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
        var updatedSets = sets ?? []

        if updatedSets.count < count {
            // In-session sets carry an explicit flag — only the checkmark completes them.
            updatedSets.append(contentsOf: Array(
                repeating: WorkoutSet(weight: "", reps: "", completed: false),
                count: count - updatedSets.count
            ))
        } else if updatedSets.count > count {
            updatedSets = Array(updatedSets.prefix(count))
        }

        return updatedSets
    }

    private func saveActiveRoutine() {
        guard let data = UserDefaults.standard.data(forKey: "routines"),
              var routines = try? JSONDecoder().decode([Routine].self, from: data),
              let index = routines.firstIndex(where: { $0.id == activeRoutine.id }) else {
            return
        }

        routines[index] = activeRoutine

        if let encoded = try? JSONEncoder().encode(routines) {
            UserDefaults.standard.set(encoded, forKey: "routines")
        }
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
        let suggestedWeightText = fatigueAdjustedSuggestedWeight(for: currentExercise).map {
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

    private var currentFocusedPreviousSet: WorkoutSet? {
        guard let focusedField else { return nil }

        switch focusedField {
        case let .weight(exercise, set), let .reps(exercise, set):
            return getLastSet(for: exercise, at: set)
        }
    }

    private var keyboardPrimaryActionTitle: String {
        guard let focusedField else { return "Done" }

        switch focusedField {
        case .weight:
            return "Next"
        case .reps(let exercise, let set):
            return nextField(after: .reps(exercise, set)) == nil ? "Done" : "Next"
        }
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

    private func handleKeyboardPrimaryAction() {
        guard let activeField = focusedField else { return }

        if let nextField = nextField(after: activeField) {
            focusedField = nextField
        } else {
            focusedField = nil
        }
    }

    private func nextField(after field: WorkoutInputField) -> WorkoutInputField? {
        switch field {
        case let .weight(exercise, set):
            return .reps(exercise, set)

        case let .reps(exercise, set):
            guard let exerciseIndex = activeRoutine.exercises.firstIndex(of: exercise) else {
                return nil
            }

            if set + 1 < setCount(for: exercise) {
                return .weight(exercise, set + 1)
            }

            let nextExerciseIndex = exerciseIndex + 1
            guard activeRoutine.exercises.indices.contains(nextExerciseIndex) else {
                return nil
            }

            return .weight(activeRoutine.exercises[nextExerciseIndex], 0)
        }
    }

    private func nextExercise(after exercise: String) -> String? {
        guard let currentIndex = activeRoutine.exercises.firstIndex(of: exercise) else { return nil }
        let nextIndex = currentIndex + 1
        guard activeRoutine.exercises.indices.contains(nextIndex) else { return nil }
        return activeRoutine.exercises[nextIndex]
    }

    private func applyFocusedPreviousSet() {
        guard let focusedField, let previousSet = currentFocusedPreviousSet else { return }

        switch focusedField {
        case let .weight(exercise, set), let .reps(exercise, set):
            applyPreviousSet(previousSet, to: exercise, at: set)
        }
    }

    private func quickLogBinding(for exercise: String, set: Int) -> Binding<String> {
        let key = quickLogKey(for: exercise, set: set)

        return Binding(
            get: { quickLogInputs[key, default: ""] },
            set: { quickLogInputs[key] = $0 }
        )
    }

    private func quickLogKey(for exercise: String, set: Int) -> String {
        "\(exercise.lowercased())::\(set)"
    }

    private func applyQuickLogInput(for exercise: String, at set: Int) {
        let key = quickLogKey(for: exercise, set: set)
        let input = quickLogInputs[key, default: ""]

        guard let command = parseQuickLogCommand(input, exercise: exercise, setIndex: set) else {
            return
        }

        let currentSet = resize(sets: logs[exercise], to: setCount(for: exercise))[safe: set] ?? WorkoutSet(weight: "", reps: "")
        let resolvedWeight = command.weight ?? currentSet.weight
        let resolvedReps = command.reps ?? currentSet.reps

        logs[exercise, default: []] = update(
            logs[exercise],
            exercise: exercise,
            at: set,
            weight: resolvedWeight,
            reps: resolvedReps,
            targetCount: setCount(for: exercise)
        )

        quickLogInputs[key] = ""
    }

    private func parseQuickLogCommand(_ input: String, exercise: String, setIndex: Int) -> QuickLogCommand? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let normalized = trimmed
            .lowercased()
            .replacingOccurrences(of: "×", with: "x")
            .replacingOccurrences(of: ",", with: "")

        if let match = firstMatch(
            in: normalized,
            pattern: #"^\s*(\d+(?:\.\d+)?)\s*(?:x|for)\s*(\d+)\s*(?:reps?)?\s*$"#
        ) {
            return QuickLogCommand(weight: match[0], reps: match[1])
        }

        if normalized.contains("same weight") {
            guard let referenceWeight = quickLogReferenceSet(for: exercise, before: setIndex)?.weight,
                  !referenceWeight.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }

            let reps = firstMatch(in: normalized, pattern: #"(\d+)\s*(?:reps?)"#)?.first
                ?? firstMatch(in: normalized, pattern: #"same weight\s*(\d+)"#)?.first

            return QuickLogCommand(weight: referenceWeight, reps: reps)
        }

        if let match = firstMatch(
            in: normalized,
            pattern: #"(?:drop|down)\s*(?:to)?\s*(\d+(?:\.\d+)?)"#
        ) {
            return QuickLogCommand(weight: match[0], reps: nil)
        }

        return nil
    }

    private func quickLogReferenceSet(for exercise: String, before setIndex: Int) -> WorkoutSet? {
        let currentSets = resize(sets: logs[exercise], to: setCount(for: exercise))

        if setIndex > 0 {
            for previousIndex in stride(from: setIndex - 1, through: 0, by: -1) {
                let candidate = currentSets[previousIndex]
                if isLoggedSet(candidate) {
                    return candidate
                }
            }
        }

        if let previousWorkoutSet = getLastSet(for: exercise, at: setIndex), isLoggedSet(previousWorkoutSet) {
            return previousWorkoutSet
        }

        let sessions = loadWorkoutSessions().filter(matchesRoutine)
        if let latestLoggedSet = sessions.last?.logs[exercise]?
            .reversed()
            .first(where: { $0.isCompleted && isLoggedSet($0) }) {
            return latestLoggedSet
        }

        return nil
    }

    private func firstMatch(in text: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1 else {
            return nil
        }

        return (1..<match.numberOfRanges).compactMap { index in
            let captureRange = match.range(at: index)
            guard captureRange.location != NSNotFound,
                  let range = Range(captureRange, in: text) else {
                return nil
            }

            return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
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
        let sessions = loadWorkoutSessions().filter(matchesRoutine)
        guard let latestWeights = sessions.last?.logs[exercise] else { return nil }

        return latestWeights
            .filter(\.isCompleted)
            .compactMap { parseWeight($0.weight) }
            .first
    }

    private func parseWeight(_ weight: String) -> Double? {
        let cleaned = weight
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")

        return Double(cleaned)
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

    private func historySummary(for sets: [WorkoutSet]) -> String {
        sets.enumerated()
            .map { "Set \($0.offset + 1): \($0.element.weight) x \($0.element.reps)" }
            .joined(separator: "  •  ")
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
        var saved = loadWorkoutSessions()
        saved.append(session)
        if let encoded = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(encoded, forKey: "workoutSessions")
        }
    }

    private func loadWorkoutSessions() -> [WorkoutSession] {
        if let data = UserDefaults.standard.data(forKey: "workoutSessions"),
           let decoded = try? JSONDecoder().decode([WorkoutSession].self, from: data) {
            return decoded
        }
        return []
    }

    private func getLastSet(for exercise: String, at index: Int) -> WorkoutSet? {
        let sessions = loadWorkoutSessions().filter(matchesRoutine)
        guard let set = sessions.last?.logs[exercise]?[safe: index], set.isCompleted else { return nil }
        return set
    }

    private func matchesRoutine(_ session: WorkoutSession) -> Bool {
        if session.routineID == activeRoutine.id {
            return true
        }

        return activeRoutine.allKnownNames.contains(session.routineName)
    }

    private func addExerciseToCurrentWorkout(_ exercise: Exercise) -> AddExerciseResult {
        guard !activeRoutine.exercises.contains(exercise.name) else {
            return AddExerciseResult(message: "\(exercise.name) is already in this workout.", didMutate: false)
        }

        activeRoutine.exercises.append(exercise.name)
        activeRoutine.preferredSetCounts[exercise.name] = 3
        preferredSetCounts[exercise.name] = 3
        logs[exercise.name] = resize(sets: logs[exercise.name], to: 3)
        saveActiveRoutine()

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

        let migratedQuickLogInputs = quickLogInputs
            .filter { $0.key.hasPrefix("\(currentExerciseName.lowercased())::") }

        for (key, value) in migratedQuickLogInputs {
            quickLogInputs.removeValue(forKey: key)
            if let separator = key.range(of: "::") {
                let suffix = key[separator.lowerBound...]
                quickLogInputs["\(newExerciseName.lowercased())\(suffix)"] = value
            }
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

extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
