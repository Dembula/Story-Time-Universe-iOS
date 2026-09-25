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

    @FocusState private var searchFocused: Bool

    private var profileAge: Int? { appState.activeProfile?.age }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchHeader
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
            .navigationBarHidden(true)
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

    private var searchHeader: some View {
        HStack(alignment: .center) {
            Text("Search")
                .font(.largeTitle.bold())
                .foregroundStyle(Theme.foreground)

            Spacer(minLength: 12)

            Button {
                showAISearch = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.subheadline.weight(.semibold))
                    Text("AI")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.accent.opacity(0.14))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("AI Search")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.semibold))
                .foregroundStyle(searchFocused || !query.isEmpty ? Theme.accent : Theme.muted)
            TextField("Search titles, genres…", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($searchFocused)
                .onSubmit { Task { await runSearch() } }
            if !query.isEmpty {
                Button {
                    query = ""
                    results = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.muted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(Color.white.opacity(0.06))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: [
                            Theme.accent.opacity(searchFocused || !query.isEmpty ? 0.9 : 0.4),
                            Theme.accentGold.opacity(searchFocused || !query.isEmpty ? 0.75 : 0.28),
                            Theme.accent.opacity(searchFocused || !query.isEmpty ? 0.65 : 0.22),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    lineWidth: 1.35
                )
                .shadow(color: Theme.accent.opacity(searchFocused ? 0.35 : 0.14), radius: searchFocused ? 8 : 4)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .padding(.top, 4)
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
            .tabScrollCoordinateSpace()
        }
    }

    private func recommendedRow(_ item: ContentItem) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Theme.accent.opacity(0.28),
                                Theme.accent.opacity(0.08),
                                Color.clear,
                            ],
                            startPoint: .bottomLeading,
                            endPoint: .topTrailing
                        )
                    )
                    .frame(width: 72, height: 104)
                    .blur(radius: 1)

                RemoteImage(urls: item.posterCandidates, preferPortrait: true)
                    .frame(width: 64, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Theme.accent.opacity(0.22), lineWidth: 1)
                    )
            }
            .frame(width: 72, height: 104)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(item.displayType)
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                if item.isSeriesLike {
                    Text("Episode 1")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
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
                            ZStack {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(
                                        RadialGradient(
                                            colors: [
                                                Theme.accent.opacity(0.32),
                                                Theme.accent.opacity(0.1),
                                                Color.clear,
                                            ],
                                            center: .center,
                                            startRadius: 8,
                                            endRadius: 90
                                        )
                                    )
                                    .frame(width: 130, height: 190)
                                    .blur(radius: 2)

                                PosterCard(item: result.asContentItem)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 28)
                .trackScrollForTabBar()
            }
            .tabScrollCoordinateSpace()
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
