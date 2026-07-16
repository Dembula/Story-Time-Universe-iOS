import SwiftUI

struct ContentDetailView: View {
    let contentId: String
    var seed: ContentItem?

    @State private var detail: ContentDetail?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showPlayer = false
    @State private var playerEpisodeId: String?
    @State private var inWatchlist = false
    @State private var watchlistBusy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    RemoteImage(
                        urls: detail?.backdropCandidates
                            ?? seed?.backdropCandidates
                            ?? detail?.posterCandidates
                            ?? seed?.posterCandidates
                            ?? []
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 360)

                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(detail?.title ?? seed?.title ?? "")
                            .font(.largeTitle.bold())
                            .foregroundStyle(.white)
                        metaLine
                        HStack(spacing: 12) {
                            Button {
                                playerEpisodeId = firstEpisodeId
                                showPlayer = true
                            } label: {
                                Label("Play", systemImage: "play.fill")
                                    .font(.headline)
                                    .foregroundStyle(.black)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.white)
                                    .clipShape(Capsule())
                            }

                            Button {
                                Task { await toggleWatchlist() }
                            } label: {
                                Image(systemName: inWatchlist ? "checkmark" : "plus")
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 48, height: 48)
                                    .background(Color.white.opacity(0.15))
                                    .clipShape(Circle())
                            }
                            .disabled(watchlistBusy)
                        }
                    }
                    .padding(20)
                }

                if let description = detail?.description ?? seed?.description {
                    Text(description)
                        .font(.body)
                        .foregroundStyle(Theme.muted)
                        .padding(20)
                }

                if let seasons = detail?.seasons, !seasons.isEmpty {
                    episodesSection(seasons)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .padding()
                }
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .fullScreenCover(isPresented: $showPlayer) {
            PlayerContainerView(
                contentId: contentId,
                title: detail?.title ?? seed?.title ?? "Now Playing",
                episodeId: playerEpisodeId
            )
            .onDisappear {
                OrientationLock.unlockPortrait()
            }
        }
    }

    private var metaLine: some View {
        let parts = [
            detail?.type ?? seed?.type,
            detail?.category ?? seed?.category,
            detail?.year.map(String.init),
            detail?.creator?.name,
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }

        return Text(parts.joined(separator: " • "))
            .font(.subheadline)
            .foregroundStyle(Theme.muted)
    }

    private var firstEpisodeId: String? {
        detail?.seasons?.first?.episodes?.first?.id
    }

    @ViewBuilder
    private func episodesSection(_ seasons: [Season]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Episodes")
                .font(.title3.bold())
                .padding(.horizontal, 20)

            ForEach(seasons, id: \.stableId) { season in
                Text("Season \(season.seasonNumber ?? 1)")
                    .font(.headline)
                    .foregroundStyle(Theme.accentGold)
                    .padding(.horizontal, 20)

                ForEach(season.episodes ?? []) { episode in
                    Button {
                        playerEpisodeId = episode.id
                        showPlayer = true
                    } label: {
                        HStack(spacing: 12) {
                            Text("\(episode.episodeNumber ?? 0)")
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(Theme.muted)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(episode.title ?? "Episode \(episode.episodeNumber ?? 0)")
                                    .foregroundStyle(Theme.foreground)
                                if let description = episode.description {
                                    Text(description)
                                        .font(.caption)
                                        .foregroundStyle(Theme.muted)
                                        .lineLimit(2)
                                }
                            }
                            Spacer()
                            Image(systemName: "play.circle.fill")
                                .foregroundStyle(Theme.accent)
                                .font(.title2)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.bottom, 24)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            detail = try await ViewerAPI.shared.fetchContentDetail(id: contentId)
            let list = try? await ViewerAPI.shared.fetchWatchlist()
            inWatchlist = list?.contains(where: { $0.id == contentId }) ?? false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleWatchlist() async {
        watchlistBusy = true
        defer { watchlistBusy = false }
        do {
            try await ViewerAPI.shared.updateWatchlist(contentId: contentId, add: !inWatchlist)
            inWatchlist.toggle()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
