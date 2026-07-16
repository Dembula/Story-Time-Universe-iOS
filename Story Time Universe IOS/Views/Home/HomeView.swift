import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @State private var featured: [ContentItem] = []
    @State private var continueWatching: [ContinueWatchingItem] = []
    @State private var trending: [ContentItem] = []
    @State private var movies: [ContentItem] = []
    @State private var series: [ContentItem] = []
    @State private var shows: [ContentItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedContent: ContentItem?
    @State private var playingContent: ContentItem?
    @State private var heroIndex = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header

                    if isLoading {
                        ProgressView()
                            .tint(Theme.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 80)
                    } else {
                        if !featured.isEmpty {
                            HeroCarousel(
                                items: featured,
                                index: $heroIndex,
                                onPlay: { playingContent = $0 },
                                onOpen: { selectedContent = $0 }
                            )
                        }

                        if !continueWatching.isEmpty {
                            ContinueWatchingRow(items: continueWatching) { item in
                                playingContent = item.asContentItem
                            }
                        }

                        ContentRowView(title: "Trending Now", items: trending) { selectedContent = $0 }
                        ContentRowView(title: "Movies", items: movies) { selectedContent = $0 }
                        ContentRowView(title: "Series", items: series) { selectedContent = $0 }
                        ContentRowView(title: "Shows", items: shows) { selectedContent = $0 }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red.opacity(0.9))
                            .padding(.horizontal)
                    }
                }
                .padding(.bottom, 32)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationBarHidden(true)
            .refreshable { await load(force: true) }
            .navigationDestination(item: $selectedContent) { item in
                ContentDetailView(contentId: item.id, seed: item)
            }
            .fullScreenCover(item: $playingContent) { item in
                PlayerContainerView(contentId: item.id, title: item.title)
                    .onDisappear {
                        OrientationLock.unlockPortrait()
                    }
            }
            .task { await load(force: false) }
        }
    }

    private var header: some View {
        HStack {
            Text("Home")
                .font(.largeTitle.bold())
                .foregroundStyle(Theme.foreground)
            Spacer()
            Button {
                appState.switchProfile()
            } label: {
                ZStack {
                    Circle()
                        .fill(Theme.profileColor(for: appState.activeProfile?.id ?? "x"))
                        .frame(width: 36, height: 36)
                    Text(String((appState.activeProfile?.name ?? "?").prefix(1)).uppercased())
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                }
            }
            .accessibilityLabel("Switch profile")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private func load(force: Bool) async {
        if !force && (!featured.isEmpty || !trending.isEmpty) {
            isLoading = false
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let featuredReq = ViewerAPI.shared.fetchContent(featured: true, limit: 8)
            async let trendingReq = ViewerAPI.shared.fetchContent(limit: 16)
            async let moviesReq = ViewerAPI.shared.fetchContent(type: "MOVIE", limit: 16)
            async let seriesReq = ViewerAPI.shared.fetchContent(type: "SERIES", limit: 16)
            async let showsReq = ViewerAPI.shared.fetchContent(type: "SHOW", limit: 16)
            async let continueReq = ViewerAPI.shared.fetchContinueWatching()

            let (f, t, m, s, sh, cw) = try await (featuredReq, trendingReq, moviesReq, seriesReq, showsReq, continueReq)
            featured = f.isEmpty ? Array(t.prefix(5)) : f
            trending = t
            movies = m
            series = s
            shows = sh
            continueWatching = cw
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
