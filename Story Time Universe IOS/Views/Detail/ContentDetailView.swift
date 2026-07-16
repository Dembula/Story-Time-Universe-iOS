import SwiftUI

struct ContentDetailView: View {
    let contentId: String
    var seed: ContentItem?

    @State private var detail: ContentDetail?
    @State private var crew: [CrewCredit] = []
    @State private var related: [ContentItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showPlayer = false
    @State private var playTrailer = false
    @State private var playerEpisodeId: String?
    @State private var inWatchlist = false
    @State private var watchlistBusy = false
    @State private var selectedRelated: ContentItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero

                VStack(alignment: .leading, spacing: 28) {
                    if let description = detail?.description ?? seed?.description, !description.isEmpty {
                        Text(shortDescription(description))
                            .font(.body)
                            .foregroundStyle(Theme.muted)
                            .lineSpacing(3)
                    }

                    if detail?.hasTrailer == true {
                        trailersSection
                    }

                    if let seasons = detail?.seasons, !seasons.isEmpty {
                        episodesSection(seasons)
                    }

                    if !related.isEmpty {
                        moreLikeThisSection
                    }

                    if !crew.isEmpty {
                        castAndCrewSection
                    }

                    if let bts = detail?.btsVideos, !bts.isEmpty {
                        btsSection(bts)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red.opacity(0.9))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .navigationDestination(item: $selectedRelated) { item in
            ContentDetailView(contentId: item.id, seed: item)
        }
        .fullScreenCover(isPresented: $showPlayer) {
            PlayerContainerView(
                contentId: contentId,
                title: detail?.title ?? seed?.title ?? "Now Playing",
                episodeId: playerEpisodeId,
                isTrailer: playTrailer
            )
            .onDisappear {
                OrientationLock.unlockPortrait()
                playTrailer = false
                playerEpisodeId = nil
            }
        }
    }

    // MARK: - Hero (Apple TV style)

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(
                urls: detail?.backdropCandidates
                    ?? seed?.backdropCandidates
                    ?? detail?.posterCandidates
                    ?? seed?.posterCandidates
                    ?? []
            )
            .frame(maxWidth: .infinity)
            .frame(height: 420)

            LinearGradient(
                colors: [.clear, .black.opacity(0.35), .black.opacity(0.95)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 12) {
                Text(detail?.title ?? seed?.title ?? "")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .minimumScaleFactor(0.75)

                metaLine

                if let rating = detail?.ratingStats, (rating.count ?? 0) > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "star.fill")
                            .foregroundStyle(Theme.accent)
                        Text(String(format: "%.1f", rating.average ?? 0))
                            .fontWeight(.semibold)
                        Text("(\(rating.count ?? 0))")
                            .foregroundStyle(Theme.muted)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.white)
                }

                HStack(spacing: 12) {
                    Button {
                        playTrailer = false
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

                    if detail?.hasTrailer == true {
                        Button {
                            playTrailer = true
                            playerEpisodeId = nil
                            showPlayer = true
                        } label: {
                            Image(systemName: "film")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 48, height: 48)
                                .background(Color.white.opacity(0.16))
                                .clipShape(Circle())
                        }
                        .accessibilityLabel("Play trailer")
                    }

                    Button {
                        Task { await toggleWatchlist() }
                    } label: {
                        Image(systemName: inWatchlist ? "checkmark" : "plus")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .background(Color.white.opacity(0.16))
                            .clipShape(Circle())
                    }
                    .disabled(watchlistBusy)
                    .accessibilityLabel(inWatchlist ? "In My List" : "Add to My List")
                }
            }
            .padding(20)
        }
    }

    private var metaLine: some View {
        let parts: [String] = [
            (detail?.type ?? seed?.type)?.replacingOccurrences(of: "_", with: " ").capitalized,
            detail?.category ?? seed?.category,
            detail?.year.map(String.init) ?? seed?.year.map(String.init),
            detail?.runtimeLabel,
            detail?.ageRating,
            detail?.creator?.name.map { "By \($0)" },
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }

        return Text(parts.joined(separator: " · "))
            .font(.subheadline)
            .foregroundStyle(Theme.muted)
            .lineLimit(2)
    }

    // MARK: - Trailers

    private var trailersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Trailers")

            Button {
                playTrailer = true
                playerEpisodeId = nil
                showPlayer = true
            } label: {
                ZStack(alignment: .bottomLeading) {
                    RemoteImage(urls: detail?.backdropCandidates ?? detail?.posterCandidates ?? [])
                        .frame(width: 280, height: 158)

                    LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)

                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Text("Official Trailer")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(12)
                }
                .frame(width: 280, height: 158)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Episodes

    @ViewBuilder
    private func episodesSection(_ seasons: [Season]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Episodes")

            ForEach(seasons, id: \.stableId) { season in
                Text("Season \(season.seasonNumber ?? 1)")
                    .font(.headline)
                    .foregroundStyle(Theme.accentGold)

                ForEach(season.episodes ?? []) { episode in
                    Button {
                        playTrailer = false
                        playerEpisodeId = episode.id
                        showPlayer = true
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.white.opacity(0.08))
                                    .frame(width: 120, height: 68)
                                if let thumb = episode.thumbnailUrl,
                                   let url = MediaURL.resolve(posterUrl: thumb, videoUrl: episode.videoUrl) {
                                    RemoteImage(url: url)
                                        .frame(width: 120, height: 68)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                } else {
                                    Image(systemName: "play.fill")
                                        .foregroundStyle(.white.opacity(0.8))
                                }
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(episode.episodeNumber ?? 0). \(episode.title ?? "Episode")")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.foreground)
                                    .lineLimit(2)
                                if let description = episode.description {
                                    Text(description)
                                        .font(.caption)
                                        .foregroundStyle(Theme.muted)
                                        .lineLimit(2)
                                }
                                if let duration = episode.duration, duration > 0 {
                                    Text("\(duration) min")
                                        .font(.caption2)
                                        .foregroundStyle(Theme.muted)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - More Like This

    private var moreLikeThisSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("More Like This")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(related) { item in
                        Button { selectedRelated = item } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                PosterCard(item: item)
                                Text(item.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .frame(width: 118, alignment: .leading)
                                Text((item.type ?? "").replacingOccurrences(of: "_", with: " "))
                                    .font(.caption2)
                                    .foregroundStyle(Theme.muted)
                                    .lineLimit(1)
                                    .frame(width: 118, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Cast & Crew

    private var castAndCrewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionHeader("Cast & Crew")
                Spacer()
                Text("\(crew.count) credited")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.08))
                    .foregroundStyle(Theme.muted)
                    .clipShape(Capsule())
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(crew) { member in
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Theme.accent.opacity(0.7), Theme.profileColor(for: member.id)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 72, height: 72)
                                Text(member.initials)
                                    .font(.headline.bold())
                                    .foregroundStyle(.white)
                            }
                            Text(member.name)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .frame(width: 88)
                            Text(member.role ?? "Crew")
                                .font(.caption2)
                                .foregroundStyle(Theme.muted)
                                .lineLimit(1)
                                .frame(width: 88)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - BTS

    private func btsSection(_ videos: [BtsVideo]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Behind the Scenes")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(videos) { video in
                        VStack(alignment: .leading, spacing: 6) {
                            RemoteImage(urls: video.thumbnailCandidates)
                                .frame(width: 200, height: 112)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            Text(video.title ?? "Behind the Scenes")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .frame(width: 200, alignment: .leading)
                        }
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title3.bold())
            .foregroundStyle(Theme.foreground)
    }

    private var firstEpisodeId: String? {
        detail?.seasons?.first?.episodes?.first?.id
    }

    private func shortDescription(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 280 { return trimmed }
        return String(trimmed.prefix(277)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await ViewerAPI.shared.fetchContentDetail(id: contentId)
            detail = loaded

            async let crewReq = ViewerAPI.shared.fetchCrew(contentId: contentId)
            async let relatedReq = ViewerAPI.shared.fetchRelated(
                excluding: contentId,
                category: loaded.category,
                type: loaded.type,
                limit: 12
            )
            async let listReq = ViewerAPI.shared.fetchWatchlist()

            crew = (try? await crewReq) ?? []
            related = (try? await relatedReq) ?? []
            let list = try? await listReq
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
