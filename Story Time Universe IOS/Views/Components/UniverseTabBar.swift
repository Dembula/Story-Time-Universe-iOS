import SwiftUI

/// Bottom tab bar that slides/fades with `AppState.tabBarVisible`.
struct UniverseTabBar: View {
    @Binding var selection: MainTab

    private let items: [(MainTab, String, String)] = [
        (.home, "Home", "house.fill"),
        (.search, "Search", "magnifyingglass"),
        (.downloads, "Downloads", "arrow.down.circle.fill"),
        (.myList, "My List", "bookmark.fill"),
        (.account, "Account", "person.crop.circle"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.0) { tab, title, icon in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: icon)
                            .font(.system(size: 20, weight: .semibold))
                        Text(title)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(selection == tab ? Theme.accent : Theme.navInactive)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
            }
        }
        .padding(.horizontal, 4)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Theme.border)
                        .frame(height: 0.5)
                }
                .ignoresSafeArea(edges: .bottom)
        )
    }
}
