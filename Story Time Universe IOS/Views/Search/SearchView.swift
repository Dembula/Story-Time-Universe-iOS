import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var parental = ParentalControls.shared

    @State private var query = ""
    @State private var results: [SearchResult] = []
    @State private var recommended: [ContentItem] = []
    @State private var isSearching = false
    @State private var isLoadingRecommended = false
    @State private var selected: ContentItem?
    @State private var errorMessage: String?
    @State private var showAISearch = false

    private var profileAge: Int? { appState.activeProfile?.age }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar

                if isSearching {
                    ProgressView().tint(Theme.accent).padding(.top, 40)
                    Spacer()
                } else if query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 {
                    resultsList
                } else {
                    recommendedList
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAISearch = true
                    } label: {
                        Image(systemName: "sparkles")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    .accessibilityLabel("AI Search")
                }
            }
            .navigationDestination(item: $selected) { item in
                ContentDetailView(contentId: item.id, seed: item)
            }
            .sheet(isPresented: $showAISearch) {
                AISearchView {
                    showAISearch = false
                }
                .environmentObject(appState)
            }
            .onChange(of: query) { _, newValue in
                Task { await debouncedSearch(newValue) }
            }
            .task { await loadRecommended() }
        }
    }

    private var searchBar: some View {
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
    }

    @ViewBuilder
    private var recommendedList: some View {
        if isLoadingRecommended && recommended.isEmpty {
            ProgressView().tint(Theme.accent)
            Spacer()
        } else if recommended.isEmpty {
            ContentUnavailableView(
                "Search Story Time",
                systemImage: "magnifyingglass",
                description: Text("Type at least 2 characters, or browse recommended titles below.")
            )
            .foregroundStyle(Theme.muted)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Recommended series & films")
                        .font(.title3.bold())
                        .foregroundStyle(Theme.foreground)
                        .padding(.horizontal, 16)

                    LazyVStack(spacing: 0) {
                        ForEach(recommended) { item in
                            Button {
                                selected = item
                            } label: {
                                recommendedRow(item)
                            }
                            .buttonStyle(.plain)
                            Divider().background(Theme.border)
                        }
                    }
                }
                .padding(.bottom, 28)
                .trackScrollForTabBar()
            }
        }
    }

    private func recommendedRow(_ item: ContentItem) -> some View {
        HStack(spacing: 14) {
            RemoteImage(urls: item.posterCandidates, preferPortrait: true)
                .frame(width: 64, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(
                    [item.displayType, item.category]
                        .compactMap { $0 }
                        .filter { !$0.isEmpty }
                        .joined(separator: " · ")
                )
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "play.circle.fill")
                .font(.title2)
                .foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var resultsList: some View {
        if results.isEmpty {
            ContentUnavailableView(
                "No results",
                systemImage: "magnifyingglass",
                description: Text("Try another title or genre.")
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
                .padding(.bottom, 28)
                .trackScrollForTabBar()
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
            let raw = try await ViewerAPI.shared.search(query: q)
            results = parental.filter(raw.map(\.asContentItem), profileAge: profileAge)
                .compactMap { item in raw.first(where: { $0.id == item.id }) }
            ImagePrefetcher.prefetchPosters(results.map(\.asContentItem))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadRecommended() async {
        isLoadingRecommended = true
        defer { isLoadingRecommended = false }
        async let featured = ViewerAPI.shared.fetchContent(featured: true, limit: 12)
        async let trending = ViewerAPI.shared.fetchContent(limit: 24)
        let f = (try? await featured) ?? []
        let t = (try? await trending) ?? []
        var seen = Set<String>()
        let merged = (f + t).filter { seen.insert($0.id).inserted }
        recommended = parental.filter(merged, profileAge: profileAge)
        ImagePrefetcher.prefetchPosters(recommended)
    }
}
