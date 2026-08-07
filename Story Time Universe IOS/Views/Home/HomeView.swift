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
    @State private var isResolvingAccess = false
    @State private var pendingPlayItem: ContentItem?
    @State private var accessError: String?
    @State private var ppvFinishInFlight = false
    @State private var showPPVPaywall = false
    @State private var ppvTitle: String?

    private var profileAge: Int? { appState.activeProfile?.age }

    private func requestPlay(_ item: ContentItem) {
        Task { await resolveAndPlay(item) }
    }

    private func resolveAndPlay(_ item: ContentItem) async {
        if DownloadManager.shared.offlineAsset(contentId: item.id, episodeId: nil) != nil {
            playingContent = item
            return
        }
        isResolvingAccess = true
        accessError = nil
        defer { isResolvingAccess = false }

        if appState.subscription == nil {
            await appState.refreshSubscriptionFromServer()
        }

        let access = await ViewerAPI.shared.resolveTitleAccess(
            contentId: item.id,
            isPayPerViewAccount: appState.isPayPerViewAccount,
            isTrailer: false
        )
        switch access {
        case .playable:
            playingContent = item
        case .requiresInAppPurchase:
            pendingPlayItem = item
            ppvTitle = item.title
            showPPVPaywall = true
        case .blocked(let message):
            accessError = message
        }
    }

    private func handlePPVPurchaseFinished() async {
        guard !ppvFinishInFlight else { return }
        guard let item = pendingPlayItem else { return }
        ppvFinishInFlight = true
        defer { ppvFinishInFlight = false }

        pendingPlayItem = nil
        showPPVPaywall = false
        isResolvingAccess = true
        defer { isResolvingAccess = false }
        try? await Task.sleep(nanoseconds: 800_000_000)
        let access = await ViewerAPI.shared.resolveTitleAccess(
            contentId: item.id,
            isPayPerViewAccount: true,
            isTrailer: false
        )
        switch access {
        case .playable:
            playingContent = item
            accessError = nil
        case .requiresInAppPurchase:
            accessError = "Purchase completed with Apple — if the title isn’t unlocked yet, wait a moment and press Play again."
        case .blocked(let message):
            accessError = message
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Full-bleed hero (goes under status bar)
                        Group {
                            if isLoading {
                                Color.black
                                    .frame(height: min(UIScreen.main.bounds.height * 0.58, 500))
                                    .overlay { ProgressView().tint(Theme.accent) }
                            } else if !featured.isEmpty {
                                HeroCarousel(
                                    items: featured,
                                    index: $heroIndex,
                                    fullBleed: true,
                                    onPlay: { requestPlay($0) },
                                    onOpen: { selectedContent = $0 }
                                )
                            } else {
                                Color.black.frame(height: 220)
                            }
                        }

                        VStack(alignment: .leading, spacing: 28) {
                            if !isLoading {
                                if !continueWatching.isEmpty {
                                    ContinueWatchingRow(items: continueWatching) { item in
                                        requestPlay(item.asContentItem)
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

                // Home + profile sit BELOW the Dynamic Island / status bar safe area
                homeChrome
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationBarHidden(true)
            .refreshable { await load(force: true) }
            .navigationDestination(item: $selectedContent) { item in
                ContentDetailView(contentId: item.id, seed: item)
            }
            .fullScreenCover(item: $playingContent) { item in
                PlayerContainerView(contentId: item.id, title: item.title)
                    .environmentObject(appState)
            }
            .sheet(isPresented: $showPPVPaywall) {
                if let item = pendingPlayItem {
                    SubscriptionPaywallView(
                        context: .ppv(contentId: item.id, title: ppvTitle)
                    ) {
                        Task { await handlePPVPurchaseFinished() }
                    }
                    .environmentObject(appState)
                }
            }
            .overlay {
                if isResolvingAccess {
                    ZStack {
                        Color.black.opacity(0.3).ignoresSafeArea()
                        ProgressView("Checking access…")
                            .padding(18)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                            .tint(Theme.accent)
                    }
                }
            }
            .alert("Unable to play", isPresented: Binding(
                get: { accessError != nil },
                set: { if !$0 { accessError = nil } }
            )) {
                Button("OK", role: .cancel) { accessError = nil }
            } message: {
                Text(accessError ?? "")
            }
            .task { await load(force: false) }
        }
    }

    private var homeChrome: some View {
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
        .padding(.top, 6)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [.black.opacity(0.55), .black.opacity(0.2), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
        )
        // Overlay is laid out inside the safe area unless we ignore it — keep default safe area.
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
