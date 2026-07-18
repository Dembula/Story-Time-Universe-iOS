import SwiftUI

enum MainTab: Hashable {
    case home, search, downloads, myList, account
}

struct MainTabView: View {
    @EnvironmentObject private var appState: AppState
    @State private var tab: MainTab = .home

    var body: some View {
        TabView(selection: $tab) {
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
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .tint(Theme.accent)
    }
}
