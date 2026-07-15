import SwiftUI

struct MainTabView: View {
    @StateObject private var coachRouter = CoachRouter()

    var body: some View {
        TabView(selection: $coachRouter.selectedTab) {
            HomeView()
            .tabItem {
                Label("Home", systemImage: "house.fill")
            }
            .tag(AppRootTab.home)

            CoachView(initialContext: coachRouter.launchRequest.context)
                .id(coachRouter.launchRequest.id)
            .tabItem {
                Label("Coach", systemImage: "message.fill")
            }
            .tag(AppRootTab.coach)
        }
        .tint(AppTheme.primary)
        .environmentObject(coachRouter)
    }
}
