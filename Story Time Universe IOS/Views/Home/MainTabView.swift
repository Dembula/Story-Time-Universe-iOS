import SwiftUI

enum MainTab: Hashable {
    case home, search, downloads, myList, account
}

struct MainTabView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView(selection: $appState.selectedMainTab) {
            HomeView()
                .tag(MainTab.home)

            SearchView()
                .tag(MainTab.search)

            DownloadsView()
                .tag(MainTab.downloads)

            MyListView()
                .tag(MainTab.myList)

            AccountView()
                .tag(MainTab.account)
        }
        .toolbar(.hidden, for: .tabBar)
        .tint(Theme.accent)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if appState.tabBarVisible {
                UniverseTabBar(selection: $appState.selectedMainTab)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .bottom).combined(with: .opacity)
                        )
                    )
            }
        }
        .animation(.easeInOut(duration: 0.28), value: appState.tabBarVisible)
        .onChange(of: appState.selectedMainTab) { _, _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                appState.tabBarVisible = true
            }
        }
    }
}
