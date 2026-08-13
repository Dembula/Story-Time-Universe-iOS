import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var parental = ParentalControls.shared
    @State private var browseFilter: HomeBrowseFilter = .all
    @State private var showCategoryPicker = false
    @State private var catalogueRequest: CatalogueListRequest?
    @State private var featured: [ContentItem] = []
    @State private var continueWatching: [ContinueWatchingItem] = []
    @State private var trending: [ContentItem] = []
    @State private var catalogRows: [HomeCatalogRow] = []
    @State private var discoveredGenres: [String] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedContent: ContentItem?
    @State private var playingContent: ContentItem?
    @State private var forceRestartPlay = false
    @State private var heroIndex = 0
    @State private var isLoadInFlight = false
    @State private var queuedForceReload = false
    @State private var isResolvingAccess = false
    @State private var pendingPlayItem: ContentItem?
    @State private var accessError: String?
    @State private var ppvFinishInFlight = false
    @State private var showPPVPaywall = false
    @State private var ppvTitle: String?
    @State private var showSwitchPIN = false
    @State private var showPlayPIN = false
    @State private var pendingPlayAfterPIN: ContentItem?

    private var profileAge: Int? { appState.activeProfile?.age }

    private func requestPlay(_ item: ContentItem) {
        if ParentalPINGate.needsPinForPlayer {
            pendingPlayAfterPIN = item
            showPlayPIN = true
            return
        }
        Task { await resolveAndPlay(item) }
    }

    private func requestSwitchProfile() {
        if ParentalPINGate.needsPinToSwitchProfile {
            showSwitchPIN = true
            return
        }
        appState.switchProfile()
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
                                    ContinueWatchingRow(
                                        items: continueWatching,
                                        onSelect: { requestPlay($0.asContentItem) },
                                        onSeeAll: {
                                            catalogueRequest = CatalogueListRequest(
                                                id: "continue",
                                                title: "Continue Watching",
                                                continueWatching: continueWatching
                                            )
                                        }
                                    )
                                }

                                ContentRowView(
                                    title: "Trending Now",
                                    items: trending,
                                    onSelect: { selectedContent = $0 },
                                    onSeeAll: {
                                        catalogueRequest = CatalogueListRequest(
                                            id: "trending-\(browseFilter.chromeTitle)",
                                            title: "Trending Now",
                                            typeValues: activeTypeValues,
                                            seedItems: trending
                                        )
                                    }
                                )

                                ForEach(catalogRows.filter(\.shouldDisplay)) { row in
                                    ContentRowView(
                                        title: row.title,
                                        items: row.items,
                                        onSelect: { selectedContent = $0 },
                                        onSeeAll: {
                                            catalogueRequest = CatalogueListRequest(
                                                id: row.id,
                                                title: row.title,
                                                typeValues: row.resolvedTypeValues,
                                                categoryFilter: row.categoryFilter,
                                                seedItems: row.items
                                            )
                                        }
                                    )
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
                    .trackScrollForTabBar()
                }
                .ignoresSafeArea(edges: .top)
                .tabScrollCoordinateSpace()

                homeChrome

                if showCategoryPicker {
                    HomeCategoryPickerOverlay(
                        filter: browseFilter,
                        populatedTypeIds: populatedBrowseTypeIds,
                        populatedGenres: discoveredGenres,
                        onSelect: { applyBrowseFilter($0) },
                        onClose: { showCategoryPicker = false }
                    )
                    .transition(.opacity)
                    .zIndex(20)
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationBarHidden(true)
            .refreshable { await load(force: true) }
            .navigationDestination(item: $selectedContent) { item in
                ContentDetailView(contentId: item.id, seed: item)
            }
            .navigationDestination(item: $catalogueRequest) { request in
                CatalogueListView(request: request)
            }
            .fullScreenCover(item: $playingContent) { item in
                PlayerContainerView(
                    contentId: item.id,
                    title: item.title,
                    forceRestart: forceRestartPlay
                )
                .environmentObject(appState)
                .onDisappear { forceRestartPlay = false }
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
            .sheet(isPresented: $showSwitchPIN) {
                ParentalPINSheet(
                    title: "Parental PIN",
                    message: "Enter your parental PIN to switch profiles.",
                    onCancel: { showSwitchPIN = false },
                    onSuccess: {
                        showSwitchPIN = false
                        appState.switchProfile()
                    }
                )
            }
            .sheet(isPresented: $showPlayPIN) {
                ParentalPINSheet(
                    title: "Parental PIN",
                    message: "Enter your parental PIN to play this title.",
                    onCancel: {
                        showPlayPIN = false
                        pendingPlayAfterPIN = nil
                    },
                    onSuccess: {
                        showPlayPIN = false
                        if let item = pendingPlayAfterPIN {
                            pendingPlayAfterPIN = nil
                            Task { await resolveAndPlay(item) }
                        }
                    }
                )
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
            .onChange(of: browseFilter) { _, _ in
                Task { await load(force: true) }
            }
        }
    }

    private var activeTypeValues: [String] {
        if case .contentType(_, _, let values) = browseFilter {
            return values
        }
        return []
    }

    /// Media-type chips that already have at least one title (same idea as Home rows).
    private var populatedBrowseTypeIds: Set<String> {
        var ids = Set<String>()
        let sample = featured + trending + catalogRows.filter(\.shouldDisplay).flatMap(\.items)
        let presentTypes = Set(sample.compactMap { $0.type?.uppercased() }.filter { !$0.isEmpty })

        for option in CatalogueTypes.browseTypeOptions where option.id != "ALL" {
            let values = Set(option.typeValues.map { $0.uppercased() })
            let rowHit = catalogRows.contains { row in
                row.shouldDisplay && row.resolvedTypeValues.contains { values.contains($0.uppercased()) }
            }
            let sampleHit = !presentTypes.isDisjoint(with: values)
            if rowHit || sampleHit {
                ids.insert(option.id)
            }
        }
        return ids
    }

    private var homeChrome: some View {
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showCategoryPicker = true
                }
            } label: {
                HStack(spacing: 6) {
                    Text(browseFilter.chromeTitle)
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                    Image(systemName: "chevron.down")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .shadow(color: .black.opacity(0.55), radius: 8, y: 2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Browse categories")

            Spacer()
            Button {
                requestSwitchProfile()
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
    }

    private func applyBrowseFilter(_ filter: HomeBrowseFilter) {
        showCategoryPicker = false
        if case .genre(let name) = filter {
            catalogueRequest = CatalogueListRequest(
                id: "genre-\(name.lowercased())",
                title: name,
                genre: name
            )
            return
        }
        browseFilter = filter
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

        let typeFilter: String? = {
            if case .contentType(_, _, let values) = browseFilter, values.count == 1 {
                return values[0]
            }
            return nil
        }()

        async let featuredReq = ViewerAPI.shared.fetchContent(type: typeFilter, featured: true, limit: 8)
        async let trendingReq = ViewerAPI.shared.fetchContent(type: typeFilter, limit: 24)
        async let continueReq = ViewerAPI.shared.fetchContinueWatching()

        let typeResults = await fetchAllTypeRows()

        var f = applyFilters((try? await featuredReq) ?? [])
        var t = applyFilters((try? await trendingReq) ?? [])
        var cw = (try? await continueReq) ?? []

        if case .contentType(_, _, let values) = browseFilter, !values.isEmpty {
            let allowed = Set(values.map { $0.uppercased() })
            f = f.filter { allowed.contains(($0.type ?? "").uppercased()) }
            t = t.filter { allowed.contains(($0.type ?? "").uppercased()) }
            cw = cw.filter { allowed.contains(($0.type ?? "").uppercased()) }
            // Multi-type filters (e.g. Comedy) may need a wider pull.
            if f.isEmpty || t.isEmpty {
                let broad = applyFilters((try? await ViewerAPI.shared.fetchContent(limit: 40)) ?? [])
                let typed = broad.filter { allowed.contains(($0.type ?? "").uppercased()) }
                if f.isEmpty { f = Array(typed.prefix(8)) }
                if t.isEmpty { t = Array(typed.prefix(24)) }
            }
        }

        var rows = typeResults.map { row in
            HomeCatalogRow(
                id: row.id,
                typeValue: row.typeValue,
                title: row.title,
                items: applyFilters(row.items),
                reserveEmptySlot: row.reserveEmptySlot,
                typeValues: row.typeValues.isEmpty ? [row.typeValue] : row.typeValues,
                categoryFilter: row.categoryFilter
            )
        }

        if case .contentType(_, _, let values) = browseFilter, !values.isEmpty {
            let allowed = Set(values.map { $0.uppercased() })
            rows = rows.filter { row in
                row.resolvedTypeValues.contains { allowed.contains($0.uppercased()) }
            }
        } else {
            rows = mergeDiscoveredTypes(knownRows: rows, sample: t + f)
        }

        refreshDiscoveredGenres(from: t + f + rows.flatMap(\.items))

        let hasFreshData = !f.isEmpty || !t.isEmpty || rows.contains(where: { !$0.items.isEmpty })

        if hasFreshData || (featured.isEmpty && trending.isEmpty && catalogRows.isEmpty) {
            featured = f.isEmpty ? Array(t.prefix(5)) : f
            trending = t
            continueWatching = cw
            catalogRows = rows
        } else if !cw.isEmpty {
            continueWatching = cw
        }

        ImagePrefetcher.prefetchHome(
            featured: featured,
            continueWatching: continueWatching,
            trending: trending,
            catalogRows: catalogRows
        )

        let warmIds = (featured + trending).prefix(6).map(\.id)
        await PlaybackWarmCache.shared.warmMany(contentIds: Array(warmIds))

        if featured.isEmpty && trending.isEmpty && catalogRows.allSatisfy(\.items.isEmpty) {
            errorMessage = "Could not load the catalogue. Pull to refresh."
        } else {
            errorMessage = nil
        }
    }

    private func refreshDiscoveredGenres(from items: [ContentItem]) {
        // Only keep genres that actually appear on loaded titles (no empty seed placeholders).
        var counts: [String: Int] = [:]
        var displayByKey: [String: String] = [:]
        for item in items {
            if let category = item.category?.trimmingCharacters(in: .whitespacesAndNewlines),
               !category.isEmpty {
                let key = category.lowercased()
                counts[key, default: 0] += 1
                displayByKey[key] = category
            }
            if let tags = item.tags?.split(separator: ",").map({
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }) {
                for tag in tags where !tag.isEmpty {
                    let key = tag.lowercased()
                    counts[key, default: 0] += 1
                    if displayByKey[key] == nil { displayByKey[key] = tag }
                }
            }
        }
        discoveredGenres = counts.keys
            .filter { (counts[$0] ?? 0) > 0 }
            .compactMap { displayByKey[$0] }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func fetchAllTypeRows() async -> [HomeCatalogRow] {
        let defs: [CatalogueTypes.RowDefinition] = {
            if case .contentType(_, _, let values) = browseFilter, !values.isEmpty {
                let allowed = Set(values.map { $0.uppercased() })
                return CatalogueTypes.allHomeRows.filter {
                    $0.typeValues.contains { allowed.contains($0.uppercased()) }
                }
            }
            return CatalogueTypes.allHomeRows
        }()

        return await withTaskGroup(of: (Int, HomeCatalogRow).self) { group in
            for (index, def) in defs.enumerated() {
                group.addTask {
                    let items = await ViewerAPI.shared.fetchCatalogRow(definition: def, limit: 16)
                    let row = HomeCatalogRow(
                        id: def.id,
                        typeValue: def.typeValues.first ?? def.id,
                        title: def.title,
                        items: items,
                        reserveEmptySlot: def.reserveEmptySlot,
                        typeValues: def.typeValues,
                        categoryFilter: def.categoryFilter
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
                    reserveEmptySlot: false,
                    typeValues: [typeValue]
                )
            )
        }
        return rows
    }
}
