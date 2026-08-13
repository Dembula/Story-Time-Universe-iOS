import SwiftUI

enum MainTab: Hashable {
    case home, search, downloads, myList, account
}

struct MainTabView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView(selection: $appState.selectedMainTab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(MainTab.home)

            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(MainTab.search)

            DownloadsView()
                .tabItem { Label("Downloads", systemImage: "arrow.down.circle.fill") }
                .tag(MainTab.downloads)

            MyListView()
                .tabItem { Label("My List", systemImage: "bookmark.fill") }
                .tag(MainTab.myList)

            AccountView()
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
                .tag(MainTab.account)
        }
        .toolbar(appState.tabBarVisible ? .visible : .hidden, for: .tabBar)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .tint(Theme.accent)
        .animation(.easeInOut(duration: 0.28), value: appState.tabBarVisible)
        .onChange(of: appState.selectedMainTab) { _, _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                appState.tabBarVisible = true
            }
        }
    }
}
