import Foundation

enum AppRootTab: Hashable {
    case home
    case workout
    case coach
}

struct CoachWorkoutSnapshot: Hashable {
    /// Identity of the routine being logged, so the backend can resolve
    /// "edit this workout" during a session to the actual saved routine.
    var routineID: UUID
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
}

enum CoachLaunchContext: Hashable {
    case planning
    case activeWorkout(CoachWorkoutSnapshot)
}

struct CoachLaunchRequest: Identifiable {
    let id = UUID()
    let context: CoachLaunchContext
}

final class CoachRouter: ObservableObject {
    @Published var selectedTab: AppRootTab = .home
    @Published var launchRequest = CoachLaunchRequest(context: .planning)

    func openPlanning() {
        launchRequest = CoachLaunchRequest(context: .planning)
        selectedTab = .coach
    }

    func openActiveWorkout(routine: Routine, nextExercise: String?, checkInNote: String? = nil) {
        launchRequest = CoachLaunchRequest(
            context: .activeWorkout(CoachWorkoutSnapshot(
                routine: routine,
                nextExercise: nextExercise,
                checkInNote: checkInNote
            ))
        )
        selectedTab = .coach
    }
}
