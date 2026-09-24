import SwiftUI

// The action hub: create and start workouts. Owns the routine library and every
// create-flow entry; the logger is pushed from here. Routines render in stored
// order — group sections first (creation order), the ungrouped after — nothing
// is reshuffled. The one promotion is the gradient START on each group's next
// member (and on the overall next when it sits outside every group): the same
// rotation rule Home's "Up next" reads, via `WorkoutTabInsights`.
struct WorkoutTabView: View {
    @EnvironmentObject private var store: WorkoutStore
    @EnvironmentObject private var coachRouter: CoachRouter
    @State private var routines: [Routine] = []
    @State private var routineGroups: [RoutineGroup] = []
    @State private var selectedRoutine: Routine?
    @State private var routineToEdit: Routine?
    @State private var navigateToLogger = false
    @State private var navigateToEdit = false
    @State private var navigateToCreate = false
    @State private var routinePendingDelete: Routine?
    /// Live in-progress workout (persisted by the logger) offered for resume.
    @State private var activeWorkout: ActiveWorkoutState?
    @State private var showDiscardActiveAlert = false
    /// Routine whose START tap awaits the replace-in-progress confirmation
    /// (another routine's workout holds the slot with content).
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
                    }
                    .padding(.horizontal, AppTheme.screenPadding)
                    .padding(.top, 20)
                    .padding(.bottom, 32)
                }
                .safeAreaInset(edge: .bottom) {
                    pinnedGenerate
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
            .onChange(of: coachRouter.pendingWorkoutStart, initial: true) { _, request in
                consumePendingStart(request)
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
    // "WORKOUTS" in accent over the library count. The hairline "+" is the
    // create-routine entry (the manual editor); generating is the pinned
    // pill at the bottom of the screen.

    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("WORKOUTS")
                    .microLabel(AppTheme.primary)

                Text(WorkoutTabInsights.countLine(routineCount: routines.count, groupCount: routineGroups.count))
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer()

            Button {
                routineToEdit = nil
                navigateToEdit = true
            } label: {
                Image(systemName: "plus")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .frame(width: 40, height: 40)
                    .overlay {
                        Circle()
                            .stroke(AppTheme.cardBorder, lineWidth: 1)
                    }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New routine")
        }
    }

    // MARK: - Empty state
    // The header already says NO ROUTINES YET; the pinned GENERATE WORKOUT
    // pill is the generate path, so the card offers the manual one.

    private var emptyHero: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Build your first routine")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)

            Button("Create Manually") {
                routineToEdit = nil
                navigateToEdit = true
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding(AppTheme.cardPadding)
        .glassCard()
    }

    // MARK: - Pinned generate
    // The screen's primary gradient pill → the create flow's AI path. Only
    // the next-up cards' small START pills share the gradient.

    private var pinnedGenerate: some View {
        Button("GENERATE WORKOUT") {
            navigateToCreate = true
        }
        .buttonStyle(PrimaryButtonStyle())
        .padding(.horizontal, AppTheme.screenPadding)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(AppTheme.backgroundTop)
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
    // Grouped routines render first as sections (name + hairline, with an
    // accent chip naming the group's next member), ordered by group creation
    // order; ungrouped routines follow under a quiet UNGROUPED label in the
    // same stored-array order as before. A user who never creates a group
    // sees the plain list — zero groups means zero sections and no label.

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
        // One pass over the history per render: who is next, and when each
        // routine was last done (the logger's id-or-name rule).
        let sessions = store.sessions
        let rotation = WorkoutTabInsights.rotation(routines: routines, groups: routineGroups, sessions: sessions)
        let lastDone = HomeInsights.lastDoneDates(routines: routines, sessions: sessions)
        let now = Date()
        let calendar = HomeInsights.weekCalendar(.current)

        return VStack(alignment: .leading, spacing: 20) {
            ForEach(groupedSections) { section in
                VStack(alignment: .leading, spacing: 12) {
                    groupHeader(section.group, next: rotation.nextByGroup[section.group.id])

                    ForEach(section.routines) { routine in
                        routineCard(
                            routine,
                            isNext: rotation.isNext(routine.id),
                            lastDoneLabel: WorkoutTabInsights.lastDoneLabel(lastDone[routine.id], now: now, calendar: calendar)
                        )
                    }
                }
            }

            if !ungroupedRoutines.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    if !routineGroups.isEmpty {
                        Text("UNGROUPED")
                            .microLabel()
                    }

                    ForEach(ungroupedRoutines) { routine in
                        routineCard(
                            routine,
                            isNext: rotation.isNext(routine.id),
                            lastDoneLabel: WorkoutTabInsights.lastDoneLabel(lastDone[routine.id], now: now, calendar: calendar)
                        )
                    }
                }
            }
        }
    }

    private func groupHeader(_ group: RoutineGroup, next: Routine?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(group.name.uppercased())
                    .microLabel(AppTheme.textSecondary)
                    .lineLimit(1)
                    .layoutPriority(1)

                Spacer(minLength: 0)

                if let next {
                    Text(WorkoutTabInsights.nextChipText(for: next.name))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.accentChipFill)
                        .clipShape(Capsule())
                }

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

    private func routineCard(_ routine: Routine, isNext: Bool, lastDoneLabel: String) -> some View {
        let preview = WorkoutTabInsights.exercisePreview(routine.exercises)
        let count = routine.exercises.count

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Text(routine.name)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                startButton(for: routine, isNext: isNext)
            }

            if !preview.isEmpty {
                Text(preview)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            HStack(spacing: 8) {
                chip("\(count) exercise\(count == 1 ? "" : "s")")
                chip(lastDoneLabel)

                Spacer(minLength: 0)

                groupMenu(for: routine)
                cardMenu(for: routine)
            }
        }
        .padding(AppTheme.rowPadding)
        .glassCard()
    }

    /// The gradient START marks the next-up card (the group's next member, or
    /// the overall next among the ungrouped); every other card gets a ghost
    /// capsule. Both run the same replace-in-progress guard.
    @ViewBuilder
    private func startButton(for routine: Routine, isNext: Bool) -> some View {
        if isNext {
            Button {
                requestStartWorkout(routine)
            } label: {
                Text("START")
                    .tracking(1)
            }
            .buttonStyle(PrimaryButtonStyle(isCompact: true))
        } else {
            Button {
                requestStartWorkout(routine)
            } label: {
                Text("START")
                    .tracking(1)
            }
            .buttonStyle(GhostButtonStyle(isCompact: true))
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(AppTheme.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppTheme.mutedFill)
            .clipShape(Capsule())
    }

    /// Edit and delete, folded behind "…" so the card's chrome stays at two
    /// quiet icons: the folder for grouping, this one for the routine itself.
    private func cardMenu(for routine: Routine) -> some View {
        Menu {
            Button("Edit") {
                routineToEdit = routine
                navigateToEdit = true
            }

            Button("Delete", role: .destructive) {
                routinePendingDelete = routine
            }
        } label: {
            iconChrome("ellipsis")
        }
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
            iconChrome("folder")
        }
    }

    private func iconChrome(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.caption.weight(.bold))
            .foregroundStyle(AppTheme.textSecondary)
            .frame(width: 30, height: 30)
            .background(AppTheme.surfaceElevated)
            .clipShape(Circle())
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

    /// A `CoachRouter.requestWorkoutStart` request from another tab lands
    /// here, so the routine goes through the SAME guard as the card's START
    /// button — replace-in-progress prompt included. Deferred one runloop so
    /// the NavigationLink activation never races the tab switch (or the
    /// stale-tab rebuild) that brought us here. A routine deleted meanwhile
    /// simply lands the user on the Workout tab.
    private func consumePendingStart(_ request: WorkoutStartRequest?) {
        guard request != nil else { return }
        DispatchQueue.main.async {
            guard let pending = coachRouter.pendingWorkoutStart else { return }
            coachRouter.pendingWorkoutStart = nil
            loadRoutines()
            guard let routine = store.routine(withID: pending.routineID) else { return }
            requestStartWorkout(routine)
        }
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
