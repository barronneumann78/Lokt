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

                    ForEach(activeRoutine.exercises, id: \.self) { exercise in
                        let isPrimaryExercise = isPrimaryExercise(exercise)

                        VStack(alignment: .leading, spacing: 14) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 6) {
                                    if isPrimaryExercise {
                                        Text("Up Next")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(AppTheme.primary)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(AppTheme.primary.opacity(0.16))
                                            .clipShape(Capsule())
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

                                    Text("\(setCount(for: exercise)) working sets")
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.textSecondary)

                                    if let suggestion = fatigueAdjustedSuggestedWeight(for: exercise) {
                                        Text("Suggested: \(formatWeight(suggestion.suggestedWeight))")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(AppTheme.secondary)

                                        Text(fatigueExplanation(for: suggestion))
                                            .font(.caption2)
                                            .foregroundStyle(AppTheme.textSecondary)
                                    }
                                }

                                Spacer()

                                HStack(spacing: 8) {
                                    ExerciseDragHandle(exerciseName: exercise, draggedExercise: $draggedExercise)

                                    Button("Smart Swap") {
                                        swapTarget = ExerciseSwapTarget(
                                            exerciseName: exercise,
                                            sourceNote: "Swap this exercise without losing the workout’s overall purpose."
                                        )
                                    }
                                    .buttonStyle(SecondaryButtonStyle())

                                    Button(expandedExercises.contains(exercise) ? "Hide" : "History") {
                                        toggleHistory(exercise)
                                    }
                                    .buttonStyle(SecondaryButtonStyle())
                                }
                            }

                            HStack(spacing: 10) {
                                Button {
                                    removeSet(from: exercise)
                                } label: {
                                    Label("Delete Set", systemImage: "minus")
                                }
                                .buttonStyle(SecondaryButtonStyle())
                                .disabled(setCount(for: exercise) <= 1)
                                .opacity(setCount(for: exercise) <= 1 ? 0.55 : 1)

                                Button {
                                    addSet(to: exercise)
                                } label: {
                                    Label("Add Set", systemImage: "plus")
                                }
                                .buttonStyle(SecondaryButtonStyle())
                            }

                            ForEach(0..<setCount(for: exercise), id: \.self) { set in
                                let isPrimarySet = isPrimarySet(exercise: exercise, setIndex: set)
                                let isCompletedSet = isCompletedSet(exercise: exercise, setIndex: set)

                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        HStack(spacing: 8) {
                                            Text("Set \(set + 1)")
                                                .font(.headline)
                                                .foregroundStyle(AppTheme.textPrimary)

                                            if isPrimarySet {
                                                Text("Next Set")
                                                    .font(.caption2.weight(.bold))
                                                    .foregroundStyle(AppTheme.primary)
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 4)
                                                    .background(AppTheme.primary.opacity(0.16))
                                                    .clipShape(Capsule())
                                            }

                                            if isCompletedSet {
                                                Label("Logged", systemImage: "checkmark.circle.fill")
                                                    .font(.caption2.weight(.bold))
                                                    .foregroundStyle(AppTheme.success)
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 4)
                                                    .background(AppTheme.success.opacity(0.14))
                                                    .clipShape(Capsule())
                                            }
                                        }

                                        Spacer()

                                    if let previous = getLastSet(for: exercise, at: set) {
                                        Button {
                                            applyPreviousSet(previous, to: exercise, at: set)
                                        } label: {
                                                Text("Use Last: \(previous.weight) x \(previous.reps)")
                                                    .font(.caption.weight(.semibold))
                                                    .foregroundStyle(isCompletedSet ? AppTheme.textSecondary : AppTheme.secondary)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }

                                    if isPrimarySet {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("Quick Log")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(AppTheme.textSecondary)

                                            HStack(spacing: 10) {
                                                TextField(
                                                    "135 x 8  •  same weight 7 reps  •  drop to 120",
                                                    text: quickLogBinding(for: exercise, set: set)
                                                )
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

                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("Weight")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(AppTheme.textSecondary)

                                            TextField("0", text: Binding(
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
                                            ))
                                            .keyboardType(.decimalPad)
                                            .textFieldStyle(TrackerTextFieldStyle())
                                            .focused($focusedField, equals: .weight(exercise, set))
                                        }

                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("Reps")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(AppTheme.textSecondary)

                                            TextField("0", text: Binding(
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
                                            ))
                                            .keyboardType(.numberPad)
                                            .textFieldStyle(TrackerTextFieldStyle())
                                            .focused($focusedField, equals: .reps(exercise, set))
                                        }
                                    }
                                }
                                .padding(16)
                                .background(setCardBackground(isPrimarySet: isPrimarySet, isCompletedSet: isCompletedSet))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .stroke(setCardBorder(isPrimarySet: isPrimarySet, isCompletedSet: isCompletedSet), lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            }

                            if expandedExercises.contains(exercise) {
                                historySection(for: exercise)
                            }
                        }
                        .padding(20)
                        .glassCard()
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .stroke(isPrimaryExercise ? AppTheme.primary.opacity(0.22) : Color.clear, lineWidth: 1)
                        )
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
        .navigationTitle(activeRoutine.name)
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
        VStack(alignment: .leading, spacing: 10) {
            Text(activeRoutine.name)
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)

            Text("Stay focused, record the lift, and adjust your set count when needed.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)

            if let nextTarget = nextLoggingTarget {
                HStack(spacing: 10) {
                    Image(systemName: "scope")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.primary)

                    Text("Next up: \(nextTarget.exercise) • Set \(nextTarget.setIndex + 1)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            HStack(spacing: 12) {
                timerPill(title: "Workout", value: workoutDurationText, tint: AppTheme.primary)

                if isRestTimerActive {
                    timerPill(title: "Rest", value: restCountdownText, tint: AppTheme.secondary)
                }
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

            if isCoachModeEnabled, let coachContext = currentCoachContext {
                coachModeCard(for: coachContext)
            }

            if isRestTimerActive {
                HStack(spacing: 10) {
                    if let activeRestExercise {
                        Text("Resting after \(activeRestExercise)")
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                    }

                    Spacer()

                    Button("Reset") {
                        resetRestTimer()
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    Button("Skip") {
                        skipRestTimer()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                .padding(.top, 4)
            }
        }
        .padding(20)
        .glassCard()
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

                Text("Your next workout will use this session for history and weight suggestions.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)

                Button("Back to Home") {
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle(fill: AppTheme.surfaceElevated))
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Wrap Up")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text("Save the workout once you finish your last working set.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)

                HStack(spacing: 12) {
                    completionStat(title: "Logged Sets", value: "\(loggedSetCount)")
                    completionStat(title: "Exercises", value: "\(completedExerciseCount)/\(activeRoutine.exercises.count)")
                }

                Button("Finish Workout") {
                    let session = WorkoutSession(date: Date(), routineID: activeRoutine.id, routineName: activeRoutine.name, logs: logs)
                    saveWorkoutSession(session)
                    currentTime = Date()
                    skipRestTimer()
                    completed = true
                }
                .buttonStyle(PrimaryButtonStyle(fill: AppTheme.success))
            }
        }
    }

    @ViewBuilder
    private func historySection(for exercise: String) -> some View {
        let allSessions = loadWorkoutSessions().reversed().filter(matchesRoutine)
        let history = Array(allSessions.compactMap { $0.logs[exercise] }.prefix(5))

        if history.isEmpty {
            Text("No history yet for this exercise.")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("Recent History")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.textPrimary)

                ForEach(Array(history.enumerated()), id: \.offset) { item in
                    let sets = item.element

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Workout \(item.offset + 1)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.textSecondary)

                        Text(historySummary(for: sets))
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
        return sets.firstIndex(where: { !isLoggedSet($0) })
    }

    private func isCompletedSet(exercise: String, setIndex: Int) -> Bool {
        guard let set = resize(sets: logs[exercise], to: setCount(for: exercise))[safe: setIndex] else {
            return false
        }

        return isLoggedSet(set)
    }

    private func setCardBackground(isPrimarySet: Bool, isCompletedSet: Bool) -> some ShapeStyle {
        if isCompletedSet {
            return AppTheme.success.opacity(isPrimarySet ? 0.2 : 0.14)
        }

        return isPrimarySet ? AppTheme.surfaceElevated : AppTheme.surface
    }

    private func setCardBorder(isPrimarySet: Bool, isCompletedSet: Bool) -> Color {
        if isCompletedSet {
            return AppTheme.success.opacity(isPrimarySet ? 0.55 : 0.38)
        }

        return isPrimarySet ? AppTheme.primary.opacity(0.45) : AppTheme.cardBorder.opacity(0.55)
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
            updatedSets.append(contentsOf: Array(repeating: WorkoutSet(weight: "", reps: ""), count: count - updatedSets.count))
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

    private func timerPill(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(AppTheme.textSecondary)

            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(tint.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func completionStat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(AppTheme.textSecondary)

            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func coachModeCard(for context: WorkoutCoachContext) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Coach Mode")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.primary)

                    Text(context.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                }

                Spacer()

                if let afterExercise = context.afterExercise {
                    Text("Then \(afterExercise)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 10) {
                coachPill(title: "Next", value: context.nextLabel, tint: AppTheme.primary)
                coachPill(title: "Rest", value: context.restLabel, tint: AppTheme.secondary)

                if let suggestedWeight = context.suggestedWeight {
                    coachPill(title: "Weight", value: suggestedWeight, tint: AppTheme.success)
                }
            }

            if let cue = context.cue {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "text.quote")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .padding(.top, 2)

                    Text(cue)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .surfaceCard(cornerRadius: 18, border: AppTheme.primary.opacity(0.18))
    }

    private func coachPill(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(AppTheme.textSecondary)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(tint.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var loggedSetCount: Int {
        activeRoutine.exercises.reduce(into: 0) { total, exercise in
            total += resize(sets: logs[exercise], to: setCount(for: exercise)).filter(isLoggedSet).count
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
            resize(sets: logs[exercise], to: setCount(for: exercise)).contains(where: isLoggedSet)
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

        if let updatedSet = logs[exercise]?[safe: set], isLoggedSet(updatedSet) {
            focusNextTarget(afterLogging: exercise, set: set)
        }
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
        if let latestLoggedSet = sessions.last?.logs[exercise]?.reversed().first(where: isLoggedSet) {
            return latestLoggedSet
        }

        return nil
    }

    private func focusNextTarget(afterLogging exercise: String, set: Int) {
        if let nextTarget = nextLoggingTarget {
            focusedField = .weight(nextTarget.exercise, nextTarget.setIndex)
            return
        }

        if set + 1 < setCount(for: exercise) {
            focusedField = .weight(exercise, set + 1)
        } else {
            focusedField = nil
        }
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

        let priorValue = updatedSets[set]
        updatedSets[set] = previousSet
        logs[exercise] = updatedSets

        if !isLoggedSet(priorValue) && isLoggedSet(previousSet) {
            startRestTimer(for: exercise)
        }
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

    private func fatigueExplanation(for suggestion: FatigueAdjustedWeightSuggestion) -> String {
        if suggestion.fatiguePercent <= 0 {
            return "Base \(formatWeight(suggestion.baseWeight)) from your last workout."
        }

        return "Base \(formatWeight(suggestion.baseWeight)) • Slot \(suggestion.orderIndex + 1) • -\(formatPercent(suggestion.fatiguePercent)) fatigue"
    }

    private func recentWorkingWeight(for exercise: String) -> Double? {
        let sessions = loadWorkoutSessions().filter(matchesRoutine)
        guard let latestWeights = sessions.last?.logs[exercise] else { return nil }

        return latestWeights
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

    private func formatPercent(_ value: Double) -> String {
        if value.rounded() == value {
            return "\(Int(value))%"
        }

        return String(format: "%.1f%%", value)
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
            let previousSet = updatedSets[index]
            if let w = weight { updatedSets[index].weight = w }
            if let r = reps { updatedSets[index].reps = r }

            let currentSet = updatedSets[index]
            if !isLoggedSet(previousSet) && isLoggedSet(currentSet) {
                startRestTimer(for: exercise)
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
        return sessions.last?.logs[exercise]?[safe: index]
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
