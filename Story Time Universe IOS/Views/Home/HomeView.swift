import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @State private var featured: [ContentItem] = []
    @State private var continueWatching: [ContinueWatchingItem] = []
    @State private var trending: [ContentItem] = []
    @State private var catalogRows: [HomeCatalogRow] = []
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

                        ForEach(catalogRows.filter(\.shouldDisplay)) { row in
                            ContentRowView(
                                title: row.title,
                                items: row.items,
                                showEmptyPlaceholder: row.reserveEmptySlot && row.items.isEmpty
                            ) { selectedContent = $0 }
                        }
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
        if !force && (!featured.isEmpty || !trending.isEmpty || !catalogRows.isEmpty) {
            isLoading = false
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        async let featuredReq = ViewerAPI.shared.fetchContent(featured: true, limit: 8)
        async let trendingReq = ViewerAPI.shared.fetchContent(limit: 24)
        async let continueReq = ViewerAPI.shared.fetchContinueWatching()

        let typeResults = await fetchAllTypeRows()

        let f = (try? await featuredReq) ?? []
        let t = (try? await trendingReq) ?? []
        let cw = (try? await continueReq) ?? []

        featured = f.isEmpty ? Array(t.prefix(5)) : f
        trending = t
        continueWatching = cw
        catalogRows = mergeDiscoveredTypes(knownRows: typeResults, sample: t + f)

        ImagePrefetcher.prefetchHome(
            featured: featured,
            continueWatching: continueWatching,
            trending: trending,
            catalogRows: catalogRows
        )

        if featured.isEmpty && trending.isEmpty && catalogRows.allSatisfy(\.items.isEmpty) {
            errorMessage = "Could not load the catalogue. Pull to refresh."
        }
    }

    private func fetchAllTypeRows() async -> [HomeCatalogRow] {
        await withTaskGroup(of: (Int, HomeCatalogRow).self) { group in
            for (index, def) in CatalogueTypes.allHomeRows.enumerated() {
                group.addTask {
                    let items = await ViewerAPI.shared.fetchCatalogRow(definition: def, limit: 16)
                    let row = HomeCatalogRow(
                        id: def.id,
                        typeValue: def.typeValues.first ?? def.id,
                        title: def.title,
                        items: items,
                        reserveEmptySlot: def.reserveEmptySlot
                    )
                    return (index, row)
                }
            }

            var indexed: [(Int, HomeCatalogRow)] = []
            for await pair in group {
                indexed.append(pair)
            }
            return indexed.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    /// If the API returns a type we don't list yet, add a row automatically.
    private func mergeDiscoveredTypes(knownRows: [HomeCatalogRow], sample: [ContentItem]) -> [HomeCatalogRow] {
        var rows = knownRows
        let known = CatalogueTypes.allTrackedTypeValues
        var extras: [String: [ContentItem]] = [:]

        for item in sample {
            guard let raw = item.type?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { continue }
            let key = raw.uppercased()
            guard !known.contains(key) else { continue }
            extras[key, default: []].append(item)
        }

        for (typeValue, items) in extras.sorted(by: { $0.key < $1.key }) {
            rows.append(
                HomeCatalogRow(
                    id: typeValue,
                    typeValue: typeValue,
                    title: CatalogueTypes.pluralTitle(for: typeValue),
                    items: Array(items.prefix(16)),
                    reserveEmptySlot: false
                )
            )
        }
        return rows
    }
}
