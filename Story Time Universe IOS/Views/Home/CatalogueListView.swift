import SwiftUI

/// Apple TV–style vertical catalogue list for See All / genre browse.
struct CatalogueListView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var parental = ParentalControls.shared
    let request: CatalogueListRequest

    @State private var items: [ContentItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selected: ContentItem?
    @State private var playing: ContentItem?
    @State private var forceRestart = false

    private var profileAge: Int? { appState.activeProfile?.age }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if isLoading && items.isEmpty {
                    ProgressView()
                        .tint(Theme.accent)
                        .padding(.top, 80)
                } else if items.isEmpty {
                    ContentUnavailableView(
                        "Nothing here yet",
                        systemImage: "film.stack",
                        description: Text(errorMessage ?? "Check back when new titles arrive.")
                    )
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 60)
                } else {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        Button {
                            selected = item
                        } label: {
                            catalogueRow(index: index + 1, item: item)
                        }
                        .buttonStyle(.plain)

                        if index < items.count - 1 {
                            Divider().background(Theme.border)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
            .trackScrollForTabBar()
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(request.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationDestination(item: $selected) { item in
            ContentDetailView(contentId: item.id, seed: item)
        }
        .fullScreenCover(item: $playing) { item in
            PlayerContainerView(
                contentId: item.id,
                title: item.title,
                forceRestart: forceRestart
            )
            .environmentObject(appState)
            .onDisappear { forceRestart = false }
        }
        .task { await load() }
    }

    private func catalogueRow(index: Int, item: ContentItem) -> some View {
        HStack(spacing: 14) {
            RemoteImage(urls: item.posterCandidates, preferPortrait: true)
                .frame(width: 72, height: 108)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text("\(index)")
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.muted)
                .frame(width: 28, alignment: .trailing)

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
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        if !request.continueWatching.isEmpty {
            items = parental.filter(
                request.continueWatching.map(\.asContentItem),
                profileAge: profileAge
            )
            return
        }

        var combined: [ContentItem] = request.seedItems
        if !request.typeValues.isEmpty || request.categoryFilter != nil || request.genre != nil {
            if let genre = request.genre {
                let sample = (try? await ViewerAPI.shared.fetchContent(limit: 80)) ?? []
                combined = sample.filter { $0.matchesGenre(genre) }
            } else {
                let def = CatalogueTypes.RowDefinition(
                    id: request.id,
                    typeValues: request.typeValues,
                    categoryFilter: request.categoryFilter,
                    title: request.title,
                    reserveEmptySlot: false
                )
                let fetched = await ViewerAPI.shared.fetchCatalogRow(definition: def, limit: 60)
                combined = fetched.isEmpty ? request.seedItems : fetched
            }
        }

        var seen = Set<String>()
        items = parental.filter(combined, profileAge: profileAge).filter { seen.insert($0.id).inserted }
        if items.isEmpty, let errorMessage {
            self.errorMessage = errorMessage
        }
    }
}
