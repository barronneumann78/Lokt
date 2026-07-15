import Foundation

enum AppRootTab: Hashable {
    case home
    case coach
}

struct CoachWorkoutSnapshot: Hashable {
    var routineName: String
    var exercises: [String]
    var nextExercise: String?

    init(routine: Routine, nextExercise: String? = nil) {
        self.routineName = routine.name
        self.exercises = routine.exercises
        self.nextExercise = nextExercise
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

    func openActiveWorkout(routine: Routine, nextExercise: String?) {
        launchRequest = CoachLaunchRequest(
            context: .activeWorkout(CoachWorkoutSnapshot(routine: routine, nextExercise: nextExercise))
        )
        selectedTab = .coach
    }
}
