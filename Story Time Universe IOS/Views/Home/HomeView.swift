import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var parental = ParentalControls.shared
    @State private var featured: [ContentItem] = []
    @State private var continueWatching: [ContinueWatchingItem] = []
    @State private var trending: [ContentItem] = []
    @State private var catalogRows: [HomeCatalogRow] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedContent: ContentItem?
    @State private var playingContent: ContentItem?
    @State private var heroIndex = 0
    @State private var isLoadInFlight = false
    @State private var queuedForceReload = false

    private var profileAge: Int? { appState.activeProfile?.age }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Full-bleed hero to the top edge (Apple TV style)
                    ZStack(alignment: .top) {
                        if isLoading {
                            Color.black
                                .frame(height: min(UIScreen.main.bounds.height * 0.55, 480))
                                .overlay { ProgressView().tint(Theme.accent) }
                        } else if !featured.isEmpty {
                            HeroCarousel(
                                items: featured,
                                index: $heroIndex,
                                fullBleed: true,
                                onPlay: { playingContent = $0 },
                                onOpen: { selectedContent = $0 }
                            )
                        } else {
                            Color.black.frame(height: 220)
                        }

                        // Floating HOME + profile over hero
                        HStack {
                            Text("Home")
                                .font(.largeTitle.bold())
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.55), radius: 8, y: 2)
                            Spacer()
                            Button {
                                appState.switchProfile()
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(Theme.profileColor(for: appState.activeProfile?.id ?? "x"))
                                        .frame(width: 36, height: 36)
                                        .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1))
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

                    VStack(alignment: .leading, spacing: 28) {
                        if !isLoading {
                            if !continueWatching.isEmpty {
                                ContinueWatchingRow(items: continueWatching) { item in
                                    playingContent = item.asContentItem
                                }
                            }

                            ContentRowView(title: "Trending Now", items: trending) { selectedContent = $0 }

                            ForEach(catalogRows.filter(\.shouldDisplay)) { row in
                                ContentRowView(
                                    title: row.title,
                                    items: row.items
                                ) { selectedContent = $0 }
                            }
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red.opacity(0.9))
                                .padding(.horizontal, 20)
                        }
                    }
                    .padding(.top, 22)
                    .padding(.bottom, 40)
                }
            }
            .ignoresSafeArea(edges: .top)
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

    private func applyFilters(_ items: [ContentItem]) -> [ContentItem] {
        parental.filter(items, profileAge: profileAge)
    }

    private func load(force: Bool) async {
        if isLoadInFlight {
            if force { queuedForceReload = true }
            return
        }

        if !force && (!featured.isEmpty || !trending.isEmpty || !catalogRows.isEmpty) {
            isLoading = false
            return
        }

        isLoadInFlight = true
        isLoading = true
        if force {
            errorMessage = nil
        }
        defer {
            isLoading = false
            isLoadInFlight = false
            if queuedForceReload {
                queuedForceReload = false
                Task { await load(force: true) }
            }
        }

        async let featuredReq = ViewerAPI.shared.fetchContent(featured: true, limit: 8)
        async let trendingReq = ViewerAPI.shared.fetchContent(limit: 24)
        async let continueReq = ViewerAPI.shared.fetchContinueWatching()

        let typeResults = await fetchAllTypeRows()

        let f = applyFilters((try? await featuredReq) ?? [])
        let t = applyFilters((try? await trendingReq) ?? [])
        let cw = (try? await continueReq) ?? []
        let rows = typeResults.map { row in
            HomeCatalogRow(
                id: row.id,
                typeValue: row.typeValue,
                title: row.title,
                items: applyFilters(row.items),
                reserveEmptySlot: row.reserveEmptySlot
            )
        }
        let discoveredRows = mergeDiscoveredTypes(knownRows: rows, sample: t + f)
        let hasFreshData = !f.isEmpty || !t.isEmpty || discoveredRows.contains(where: { !$0.items.isEmpty })

        if hasFreshData || (featured.isEmpty && trending.isEmpty && catalogRows.isEmpty) {
            featured = f.isEmpty ? Array(t.prefix(5)) : f
            trending = t
            continueWatching = cw
            catalogRows = discoveredRows
        } else if !cw.isEmpty {
            continueWatching = cw
        }

        ImagePrefetcher.prefetchHome(
            featured: featured,
            continueWatching: continueWatching,
            trending: trending,
            catalogRows: catalogRows
        )

        // Warm first few playable titles for seamless play.
        let warmIds = (featured + trending).prefix(6).map(\.id)
        await PlaybackWarmCache.shared.warmMany(contentIds: Array(warmIds))

        if featured.isEmpty && trending.isEmpty && catalogRows.allSatisfy(\.items.isEmpty) {
            errorMessage = "Could not load the catalogue. Pull to refresh."
        } else {
            errorMessage = nil
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
