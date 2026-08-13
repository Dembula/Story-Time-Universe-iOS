import SwiftUI

struct MyListView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var parental = ParentalControls.shared
    @State private var items: [ContentItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selected: ContentItem?

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]
    private var profileAge: Int? { appState.activeProfile?.age }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView().tint(Theme.accent)
                } else if items.isEmpty {
                    ContentUnavailableView(
                        "Your list is empty",
                        systemImage: "bookmark",
                        description: Text("Add titles from any detail page.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(items) { item in
                                Button { selected = item } label: {
                                    PosterCard(item: item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                        .trackScrollForTabBar()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("My List")
            .refreshable { await load() }
            .task { await load() }
            .navigationDestination(item: $selected) { item in
                ContentDetailView(contentId: item.id, seed: item)
            }
            .overlay(alignment: .bottom) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding()
                }
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let raw = try await ViewerAPI.shared.fetchWatchlist()
            items = parental.filter(raw, profileAge: profileAge)
            errorMessage = nil
            ImagePrefetcher.prefetchPosters(items)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
