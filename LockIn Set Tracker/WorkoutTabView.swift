import SwiftUI

// The action hub: create and start workouts. Owns the routine library and every
// create-flow entry; the logger is pushed from here. All saved routines render
// as one uniform list in stored order — nothing is promoted or reshuffled.
struct WorkoutTabView: View {
    @EnvironmentObject private var store: WorkoutStore
    @EnvironmentObject private var exerciseStore: ExerciseStore
    @State private var routines: [Routine] = []
    @State private var routineGroups: [RoutineGroup] = []
    @State private var selectedRoutine: Routine?
    @State private var routineToEdit: Routine?
    @State private var navigateToLogger = false
    @State private var navigateToEdit = false
    @State private var navigateToCreate = false
    @State private var navigateToPresetGenerator = false
    @State private var routinePendingDelete: Routine?
    /// Live in-progress workout (persisted by the logger) offered for resume.
    @State private var activeWorkout: ActiveWorkoutState?
    @State private var showDiscardActiveAlert = false
    /// Routine whose Start Workout tap awaits the replace-in-progress
    /// confirmation (another routine's workout holds the slot with content).
    @State private var routinePendingStart: Routine?
    /// Group management state — a new group is created inline from a
    /// routine's folder menu; rename/delete live on a group section's menu.
    @State private var showNewGroupPrompt = false
    @State private var newGroupText = ""
    @State private var newGroupTargetRoutineID: UUID?
    @State private var groupPendingRename: RoutineGroup?
    @State private var renameGroupText = ""
    @State private var groupPendingDelete: RoutineGroup?

    var body: some View {
        NavigationView {
            ZStack {
                AppBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        headerSection

                        if let activeWorkout {
                            resumeCard(activeWorkout)
                        }

                        if routines.isEmpty {
                            emptyHero
                        } else {
                            routineSection
                        }

                        createSection

                        NavigationLink(destination: CreateWorkoutOptionsView(entryMode: .aiTools, onSave: {
                            loadRoutines()
                        }), isActive: $navigateToCreate) {
                            EmptyView()
                        }

                        NavigationLink(destination: CreateRoutineView(routineToEdit: routineToEdit, onSave: {
                            loadRoutines()
                        }), isActive: $navigateToEdit) {
                            EmptyView()
                        }

                        NavigationLink(destination: WorkoutLoggerView(routine: selectedRoutine ?? Routine(name: "", exercises: [])), isActive: $navigateToLogger) {
                            EmptyView()
                        }

                        NavigationLink(destination: PresetWorkoutGeneratorView(onSave: {
                            loadRoutines()
                        }), isActive: $navigateToPresetGenerator) {
                            EmptyView()
                        }
                    }
                    .padding(.horizontal, AppTheme.screenPadding)
                    .padding(.top, 20)
                    .padding(.bottom, 32)
                }
                .alert(replacePromptTitle, isPresented: replacePromptBinding) {
                    Button(activeWorkout.map { "Resume \($0.routineName)" } ?? "Resume") {
                        routinePendingStart = nil
                        if let activeWorkout {
                            resumeActiveWorkout(activeWorkout)
                        }
                    }

                    Button("Start New", role: .destructive) {
                        if let routinePendingStart {
                            ActiveWorkoutStore.clear()
                            activeWorkout = nil
                            selectedRoutine = routinePendingStart
                            navigateToLogger = true
                        }
                        routinePendingStart = nil
                    }

                    Button("Cancel", role: .cancel) {
                        routinePendingStart = nil
                    }
                } message: {
                    Text(replacePromptMessage)
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                loadRoutines()
                refreshActiveWorkout()
            }
            .alert("Delete routine?", isPresented: deleteAlertBinding) {
                Button("Cancel", role: .cancel) {
                    routinePendingDelete = nil
                }

                Button("Delete", role: .destructive) {
                    if let routinePendingDelete {
                        deleteRoutine(id: routinePendingDelete.id)
                    }
                    routinePendingDelete = nil
                }
            } message: {
                Text("This removes the routine, but your saved workout history stays intact.")
            }
            .alert("New Group", isPresented: $showNewGroupPrompt) {
                TextField("Group name", text: $newGroupText)

                Button("Cancel", role: .cancel) {
                    newGroupTargetRoutineID = nil
                    newGroupText = ""
                }

                Button("Create") {
                    createGroupAndAssignIfNeeded()
                }
            }
            .alert("Rename Group", isPresented: renameGroupAlertBinding) {
                TextField("Group name", text: $renameGroupText)

                Button("Cancel", role: .cancel) {
                    groupPendingRename = nil
                }

                Button("Save") {
                    renameGroupIfNeeded()
                }
            }
            .alert("Delete group?", isPresented: deleteGroupAlertBinding) {
                Button("Cancel", role: .cancel) {
                    groupPendingDelete = nil
                }

                Button("Delete", role: .destructive) {
                    if let groupPendingDelete {
                        deleteGroup(groupPendingDelete)
                    }
                    groupPendingDelete = nil
                }
            } message: {
                Text("Routines inside stay — only the grouping is removed.")
            }
        }
        .tint(AppTheme.textPrimary)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(routines.isEmpty ? "NO ROUTINES YET" : "\(routines.count) ROUTINE\(routines.count == 1 ? "" : "S") READY")
                .microLabel()

            Text("Workout")
                .font(.system(size: 34, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(AppTheme.textPrimary)
        }
    }

    // MARK: - Empty state

    private var emptyHero: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("START")
                .microLabel()

            Text("Build your first routine")
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)

            Button("Ask Lokt for a Workout") {
                navigateToCreate = true
            }
            .buttonStyle(PrimaryButtonStyle())

            Button("Create Manually") {
                routineToEdit = nil
                navigateToEdit = true
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding(AppTheme.cardPadding)
        .glassCard()
    }

    // MARK: - Resume in-progress workout
    // A started workout survives leaving the logger (and the app). One compact
    // row offers the way back in; the only volt on this screen when fresh,
    // neutral once it's gone stale ("yesterday"). Discard is explicit — never
    // automatic.

    private func resumeCard(_ state: ActiveWorkoutState) -> some View {
        let now = Date()
        let isStale = state.isStale(now: now)

        return Button {
            resumeActiveWorkout(state)
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(isStale ? AppTheme.textTertiary : AppTheme.primary)
                    .frame(width: 7, height: 7)

                VStack(alignment: .leading, spacing: 3) {
                    Text(resumeStatusText(state, now: now))
                        .microLabel(isStale ? AppTheme.textSecondary : AppTheme.primary)
                        .monospacedDigit()
                        .lineLimit(1)

                    Text(state.routineName)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    showDiscardActiveAlert = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(width: 34, height: 34)
                        .background(AppTheme.surfaceElevated)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.textTertiary)
            }
            .padding(AppTheme.rowPadding)
            .glassCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .alert("Discard workout in progress?", isPresented: $showDiscardActiveAlert) {
            Button("Cancel", role: .cancel) { }

            Button("Discard", role: .destructive) {
                ActiveWorkoutStore.clear()
                activeWorkout = nil
            }
        } message: {
            Text("Its logged sets won't be saved to history.")
        }
    }

    private func resumeStatusText(_ state: ActiveWorkoutState, now: Date) -> String {
        if state.isStale(now: now) {
            return "RESUME · \(state.startedAt.formatted(.relative(presentation: .named)).uppercased())"
        }
        return "RESUME · \(elapsedLabel(since: state.startedAt, now: now))"
    }

    private func elapsedLabel(since start: Date, now: Date) -> String {
        let totalMinutes = max(0, Int(now.timeIntervalSince(start)) / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "\(hours) H \(String(format: "%02d", minutes)) MIN"
        }
        return "\(minutes) MIN"
    }

    // MARK: - Saved routines
    // Grouped routines render first as minimal sections (label + hairline),
    // ordered by group creation order; ungrouped routines follow in the same
    // stored-array order as before. A user who never creates a group sees
    // this exact same flat list — zero groups means zero sections.

    private struct RoutineGroupSection: Identifiable {
        let group: RoutineGroup
        let routines: [Routine]
        var id: UUID { group.id }
    }

    private var groupedSections: [RoutineGroupSection] {
        routineGroups
            .sorted { $0.order < $1.order }
            .map { group in
                RoutineGroupSection(group: group, routines: routines.filter { $0.groupID == group.id })
            }
    }

    private var ungroupedRoutines: [Routine] {
        let groupIDs = Set(routineGroups.map(\.id))
        return routines.filter { routine in
            guard let groupID = routine.groupID else { return true }
            // A group that no longer exists (defensive) reads as ungrouped.
            return !groupIDs.contains(groupID)
        }
    }

    private var routineSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(groupedSections) { section in
                groupSection(section)
            }

            if !ungroupedRoutines.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(ungroupedRoutines) { routine in
                        routineCard(routine)
                    }
                }
            }
        }
    }

    private func groupSection(_ section: RoutineGroupSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            groupHeader(section.group)

            ForEach(section.routines) { routine in
                routineCard(routine)
            }
        }
    }

    private func groupHeader(_ group: RoutineGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(group.name.uppercased())
                    .microLabel()

                Spacer()

                Menu {
                    Button("Rename") {
                        renameGroupText = group.name
                        groupPendingRename = group
                    }

                    Button("Delete Group", role: .destructive) {
                        groupPendingDelete = group
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.textTertiary)
                        .frame(width: 22, height: 22)
                }
            }

            hairline
        }
    }

    private func routineCard(_ routine: Routine) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(routine.name)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text("\(routine.exercises.count) exercises")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.textSecondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    groupMenu(for: routine)

                    Button {
                        routineToEdit = routine
                        navigateToEdit = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.textSecondary)
                            .frame(width: 34, height: 34)
                            .background(AppTheme.surfaceElevated)
                            .clipShape(Circle())
                    }

                    Button {
                        routinePendingDelete = routine
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.danger.opacity(0.85))
                            .frame(width: 34, height: 34)
                            .background(AppTheme.surfaceElevated)
                            .clipShape(Circle())
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(routine.exercises.prefix(5), id: \.self) { exercise in
                        ExerciseTextNavigationLink(exerciseName: exercise, exercises: exerciseStore.exercises) {
                            Text(exercise)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(AppTheme.textSecondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(AppTheme.mutedFill)
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            Button("Start Workout") {
                requestStartWorkout(routine)
            }
            .buttonStyle(PrimaryButtonStyle(fill: AppTheme.surfaceElevated))
        }
        .padding(AppTheme.rowPadding)
        .glassCard()
    }

    private func groupMenu(for routine: Routine) -> some View {
        Menu {
            if routine.groupID != nil {
                Button("Remove from Group") {
                    setRoutineGroup(nil, for: routine)
                }

                Divider()
            }

            ForEach(routineGroups.sorted(by: { $0.order < $1.order })) { group in
                Button {
                    setRoutineGroup(group.id, for: routine)
                } label: {
                    if routine.groupID == group.id {
                        Label(group.name, systemImage: "checkmark")
                    } else {
                        Text(group.name)
                    }
                }
            }

            if !routineGroups.isEmpty {
                Divider()
            }

            Button("New Group…") {
                newGroupTargetRoutineID = routine.id
                newGroupText = ""
                showNewGroupPrompt = true
            }
        } label: {
            Image(systemName: "folder")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 34, height: 34)
                .background(AppTheme.surfaceElevated)
                .clipShape(Circle())
        }
    }

    // MARK: - Create flows

    private var createSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("CREATE")
                .microLabel()
                .padding(.bottom, 12)

            Button {
                navigateToCreate = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text("Ask Lokt for a Workout")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.textTertiary)
                }
                .padding(.vertical, 16)
            }
            .buttonStyle(.plain)

            createRow(title: "Create Manually", icon: "square.and.pencil") {
                routineToEdit = nil
                navigateToEdit = true
            }

            createRow(title: "Start with a Preset Plan", icon: "list.bullet.rectangle", isLast: true) {
                navigateToPresetGenerator = true
            }
        }
        .padding(.horizontal, AppTheme.cardPadding)
        .padding(.vertical, AppTheme.rowPadding)
        .glassCard()
    }

    private func createRow(title: String, icon: String, isLast: Bool = false, action: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            hairline

            Button(action: action) {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(width: 22)

                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(AppTheme.textTertiary)
                }
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var hairline: some View {
        Rectangle()
            .fill(AppTheme.cardBorder)
            .frame(height: 1)
    }

    // MARK: - Data

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { routinePendingDelete != nil },
            set: { isPresented in
                if !isPresented {
                    routinePendingDelete = nil
                }
            }
        )
    }

    private var renameGroupAlertBinding: Binding<Bool> {
        Binding(
            get: { groupPendingRename != nil },
            set: { isPresented in
                if !isPresented {
                    groupPendingRename = nil
                }
            }
        )
    }

    private var deleteGroupAlertBinding: Binding<Bool> {
        Binding(
            get: { groupPendingDelete != nil },
            set: { isPresented in
                if !isPresented {
                    groupPendingDelete = nil
                }
            }
        )
    }

    func loadRoutines() {
        routines = store.routines
        routineGroups = store.routineGroups
    }

    func deleteRoutine(id: UUID) {
        store.deleteRoutine(id: id)
        routines = store.routines
        // An active workout pointing at the deleted routine has nothing to
        // resume into — drop it gracefully.
        refreshActiveWorkout()
    }

    // MARK: - Routine groups

    private func setRoutineGroup(_ groupID: UUID?, for routine: Routine) {
        store.setRoutineGroup(groupID, forRoutineID: routine.id)
        routines = store.routines
    }

    private func createGroupAndAssignIfNeeded() {
        let trimmed = newGroupText.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetID = newGroupTargetRoutineID
        newGroupTargetRoutineID = nil
        newGroupText = ""
        guard !trimmed.isEmpty else { return }

        let group = store.addRoutineGroup(name: trimmed)
        routineGroups = store.routineGroups

        if let targetID {
            store.setRoutineGroup(group.id, forRoutineID: targetID)
            routines = store.routines
        }
    }

    private func renameGroupIfNeeded() {
        guard let group = groupPendingRename else { return }
        groupPendingRename = nil
        let trimmed = renameGroupText.trimmingCharacters(in: .whitespacesAndNewlines)
        renameGroupText = ""
        guard !trimmed.isEmpty else { return }

        store.renameRoutineGroup(id: group.id, name: trimmed)
        routineGroups = store.routineGroups
    }

    private func deleteGroup(_ group: RoutineGroup) {
        store.deleteRoutineGroup(id: group.id)
        routineGroups = store.routineGroups
        routines = store.routines
    }

    /// Load the persisted in-progress workout, discarding it gracefully when
    /// its routine no longer exists.
    private func refreshActiveWorkout() {
        guard let state = ActiveWorkoutStore.load() else {
            activeWorkout = nil
            return
        }

        guard ActiveWorkoutStore.resumableRoutine(for: state, in: routines) != nil else {
            ActiveWorkoutStore.clear()
            activeWorkout = nil
            return
        }

        activeWorkout = state
    }

    private func resumeActiveWorkout(_ state: ActiveWorkoutState) {
        guard let routine = ActiveWorkoutStore.resumableRoutine(for: state, in: routines) else {
            ActiveWorkoutStore.clear()
            activeWorkout = nil
            return
        }

        selectedRoutine = routine
        navigateToLogger = true
    }

    // MARK: - Start Workout guard
    // Starting a routine while a DIFFERENT routine's workout holds the slot
    // with logged content asks first: resume it, or explicitly discard and
    // start fresh. Same routine, empty slot, or contentless slot start
    // straight away — exactly the old behavior.

    private func requestStartWorkout(_ routine: Routine) {
        refreshActiveWorkout()   // freshest slot; also drops deleted-routine slots
        if ActiveWorkoutStore.needsReplacePrompt(slot: activeWorkout, startingRoutineID: routine.id) {
            routinePendingStart = routine
            return
        }
        selectedRoutine = routine
        navigateToLogger = true
    }

    private var replacePromptBinding: Binding<Bool> {
        Binding(
            get: { routinePendingStart != nil },
            set: { isPresented in
                if !isPresented {
                    routinePendingStart = nil
                }
            }
        )
    }

    private var replacePromptTitle: String {
        guard let activeWorkout else { return "Workout in progress" }
        return "\(activeWorkout.routineName) is in progress"
    }

    private var replacePromptMessage: String {
        guard let activeWorkout else { return "" }
        let now = Date()
        let sets = ActiveWorkoutStore.meaningfulSetCount(activeWorkout.logs)
        let context = activeWorkout.isStale(now: now)
            ? "Started \(activeWorkout.startedAt.formatted(.relative(presentation: .named)))"
            : "\(elapsedLabel(since: activeWorkout.startedAt, now: now).lowercased()) in"
        let target = routinePendingStart?.name ?? "a new workout"
        return "\(context), \(sets) set\(sets == 1 ? "" : "s") logged. Starting \(target) discards those sets."
    }
}
