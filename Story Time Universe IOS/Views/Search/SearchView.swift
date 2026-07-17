import SwiftUI

struct SearchView: View {
    @State private var query = ""
    @State private var results: [SearchResult] = []
    @State private var isSearching = false
    @State private var selected: ContentItem?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Theme.muted)
                    TextField("Search titles, genres…", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { Task { await runSearch() } }
                    if !query.isEmpty {
                        Button {
                            query = ""
                            results = []
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Theme.muted)
                        }
                    }
                }
                .padding(14)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding()

                if isSearching {
                    ProgressView().tint(Theme.accent)
                    Spacer()
                } else if results.isEmpty {
                    ContentUnavailableView(
                        query.count < 2 ? "Search Story Time" : "No results",
                        systemImage: "magnifyingglass",
                        description: Text(query.count < 2 ? "Type at least 2 characters." : "Try another title or genre.")
                    )
                    .foregroundStyle(Theme.muted)
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 12)], spacing: 12) {
                            ForEach(results) { result in
                                Button {
                                    selected = result.asContentItem
                                } label: {
                                    PosterCard(item: result.asContentItem)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding()
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Search")
            .navigationDestination(item: $selected) { item in
                ContentDetailView(contentId: item.id, seed: item)
            }
            .onChange(of: query) { _, newValue in
                Task { await debouncedSearch(newValue) }
            }
        }
    }

    private func debouncedSearch(_ value: String) async {
        try? await Task.sleep(nanoseconds: 350_000_000)
        guard value == query else { return }
        await runSearch()
    }

    private func runSearch() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else {
            results = []
            return
        }
        isSearching = true
        errorMessage = nil
        defer { isSearching = false }
        do {
            results = try await ViewerAPI.shared.search(query: q)
            ImagePrefetcher.prefetchPosters(results.map(\.asContentItem))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
