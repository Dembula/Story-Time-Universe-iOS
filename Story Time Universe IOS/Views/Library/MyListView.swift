import SwiftUI

struct MyListView: View {
    @State private var items: [ContentItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selected: ContentItem?

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

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
            items = try await ViewerAPI.shared.fetchWatchlist()
            errorMessage = nil
            ImagePrefetcher.prefetchPosters(items)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
