import SwiftUI
import UIKit

@main
struct LockInSetTrackerApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    // Single source of truth for routines + sessions (build plan M1).
    @StateObject private var store = WorkoutStore()
    // The exercise library decodes ~2 MB of JSON, so it's built once here and
    // shared app-wide; views consume it via @EnvironmentObject.
    @StateObject private var exerciseStore = ExerciseStore()
    // Accent scheme owner. The token cache self-seeds from the stored scheme
    // on first read (so `AppChrome.apply()` below already captures the right
    // accent); the store handles changes at runtime.
    @StateObject private var themeStore = ThemeStore()

    init() {
        AppChrome.apply()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding {
                    MainTabView()
                } else {
                    OnboardingView {
                        hasCompletedOnboarding = true
                    }
                }
            }
            .environmentObject(store)
            .environmentObject(exerciseStore)
            .environmentObject(themeStore)
            // The AI memory digest names muscle-group focus by resolving logged
            // exercise names against the shared library. Installed here once so
            // digest rebuilds anywhere in the app resolve consistently.
            .onAppear {
                UserMemoryStore.exerciseResolver = { name in
                    exerciseStore.exercises.resolvedExercise(named: name)
                }
            }
            // The app is fully dark-themed; declare it so system-managed
            // chrome (search-field placeholders, keyboard, alerts) uses
            // legible dark-mode colors instead of light-mode grays.
            .preferredColorScheme(.dark)
        }
    }
}
