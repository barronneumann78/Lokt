import SwiftUI

struct MainTabView: View {
    @StateObject private var coachRouter = CoachRouter()
    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        TabView(selection: $coachRouter.selectedTab) {
            // Timed tab-root reset: re-entering Home/Workout after >5 min away
            // bumps that tab's epoch (see TabResetPolicy in CoachRouter.swift),
            // rebuilding the tab at its root. Coach is exempt (chat survives),
            // and Workout never resets while a workout is in progress.
            HomeView()
                .id(coachRouter.resetEpoch(for: .home))
            .tabItem {
                Label("Home", systemImage: "house.fill")
            }
            .tag(AppRootTab.home)

            WorkoutTabView()
                .id(coachRouter.resetEpoch(for: .workout))
            .tabItem {
                Label("Workout", systemImage: "dumbbell.fill")
            }
            .tag(AppRootTab.workout)

            CoachView(initialContext: coachRouter.launchRequest.context)
                .id(coachRouter.launchRequest.id)
            .tabItem {
                Label("Coach", systemImage: "message.fill")
            }
            .tag(AppRootTab.coach)
        }
        .tint(AppTheme.primary)
        .environmentObject(coachRouter)
        // Accent-scheme commit boundary: bumping `rootEpoch` rebuilds every
        // tab with the new accent (and fresh UIKit bars). `coachRouter` lives
        // above this id, so the selected tab survives the rebuild; the tabs'
        // navigation stacks reset to their roots.
        .id(theme.rootEpoch)
    }
}
