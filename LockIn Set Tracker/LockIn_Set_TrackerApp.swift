import SwiftUI
import UIKit

@main
struct LockInSetTrackerApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    // Single source of truth for routines + sessions (build plan M1).
    @StateObject private var store = WorkoutStore()
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
            .environmentObject(themeStore)
            // The app is fully dark-themed; declare it so system-managed
            // chrome (search-field placeholders, keyboard, alerts) uses
            // legible dark-mode colors instead of light-mode grays.
            .preferredColorScheme(.dark)
        }
    }
}
