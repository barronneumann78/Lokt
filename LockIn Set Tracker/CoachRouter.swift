import Foundation

enum AppRootTab: Hashable {
    case home
    case workout
    case coach
}

/// Timed tab-root reset — pure decision logic, logic-checked in
/// `harness/logic-checks/tab-reset`.
///
/// Switching INTO a tab the user left more than `staleAfterSeconds` ago tears
/// that tab's content down to its root (MainTabView applies the per-tab reset
/// epoch as the content's `.id`). A quick flip away and back (left recently)
/// preserves the tab exactly as today — the accidental-switch case, e.g. deep
/// in Analytics. Timestamps, not timers: time spent backgrounded counts as
/// "off the tab" by itself, with no running clocks.
///
/// Exempt:
/// - Coach: a reset would destroy the chat conversation. Never reset.
/// - Workout while a workout is in progress (`activeWorkoutV1` key present):
///   never throw away a live session's logger.
enum TabResetPolicy {
    /// "Off the tab for a bit" — how long a tab must be left before re-entry
    /// resets it to its root.
    static let staleAfterSeconds: TimeInterval = 5 * 60

    /// UserDefaults key owned by the logger's persistent active-workout state.
    /// Checked by presence only — never decoded here.
    static let activeWorkoutKey = "activeWorkoutV1"

    static func shouldReset(
        entering tab: AppRootTab,
        leftAt: Date?,
        now: Date,
        hasActiveWorkout: Bool
    ) -> Bool {
        if tab == .coach { return false }
        if tab == .workout && hasActiveWorkout { return false }
        guard let leftAt else { return false }
        return now.timeIntervalSince(leftAt) > staleAfterSeconds
    }
}

struct CoachRoutineSnapshot: Hashable {
    /// Present for a saved routine. A manual routine that is still being
    /// composed has no identity yet, but Coach can still discuss its exercise
    /// list without treating it as a saved routine.
    var routineID: UUID?
    var routineName: String
    var exercises: [String]
    var nextExercise: String?
    /// M4 safety branch: one-line post-workout check-in summary (pain flag or
    /// repeated too-hard) so the coach's first reply addresses it directly.
    var checkInNote: String?

    init(routine: Routine, nextExercise: String? = nil, checkInNote: String? = nil) {
        self.routineID = routine.id
        self.routineName = routine.name
        self.exercises = routine.exercises
        self.nextExercise = nextExercise
        self.checkInNote = checkInNote
    }

    init(routineID: UUID?, routineName: String, exercises: [String]) {
        self.routineID = routineID
        self.routineName = routineName
        self.exercises = exercises
        self.nextExercise = nil
        self.checkInNote = nil
    }
}

enum CoachLaunchContext: Hashable {
    case planning
    case activeWorkout(CoachRoutineSnapshot)
}

struct CoachLaunchRequest: Identifiable {
    let id = UUID()
    let context: CoachLaunchContext
}

final class CoachRouter: ObservableObject {
    @Published var selectedTab: AppRootTab = .home {
        didSet { tabSelectionDidChange(from: oldValue) }
    }
    @Published var launchRequest = CoachLaunchRequest(context: .planning)

    /// Per-tab reset epochs. MainTabView applies each as its tab content's
    /// `.id`; bumping one rebuilds that tab from its root (navigation, scroll,
    /// and in-progress form state on that tab are discarded — intended for
    /// stale re-entry). Lives here, above ThemeStore's `rootEpoch` id on the
    /// TabView, so a theme rebuild neither clears these epochs nor fights them.
    @Published private(set) var tabResetEpochs: [AppRootTab: Int] = [:]

    /// When the user last LEFT each tab. Wall-clock stamps — backgrounded time
    /// accrues on its own, no timers.
    private var tabLeftAt: [AppRootTab: Date] = [:]

    /// Seams for the tab-reset logic check; production uses these defaults.
    var now: () -> Date = Date.init
    var defaults: UserDefaults = .standard

    func resetEpoch(for tab: AppRootTab) -> Int {
        tabResetEpochs[tab] ?? 0
    }

    private func tabSelectionDidChange(from oldTab: AppRootTab) {
        let newTab = selectedTab
        guard oldTab != newTab else { return }
        let moment = now()
        tabLeftAt[oldTab] = moment
        if TabResetPolicy.shouldReset(
            entering: newTab,
            leftAt: tabLeftAt[newTab],
            now: moment,
            hasActiveWorkout: defaults.object(forKey: TabResetPolicy.activeWorkoutKey) != nil
        ) {
            tabResetEpochs[newTab, default: 0] += 1
        }
    }

    func openPlanning() {
        launchRequest = CoachLaunchRequest(context: .planning)
        selectedTab = .coach
    }

    func openActiveWorkout(routine: Routine, nextExercise: String?, checkInNote: String? = nil) {
        launchRequest = CoachLaunchRequest(
            context: .activeWorkout(CoachRoutineSnapshot(
                routine: routine,
                nextExercise: nextExercise,
                checkInNote: checkInNote
            ))
        )
        selectedTab = .coach
    }

}
