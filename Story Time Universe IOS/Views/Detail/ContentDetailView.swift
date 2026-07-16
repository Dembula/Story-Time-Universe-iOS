import SwiftUI

struct ContentDetailView: View {
    let contentId: String
    var seed: ContentItem?

    @State private var detail: ContentDetail?
    @State private var crew: [CrewCredit] = []
    @State private var related: [ContentItem] = []
    @State private var errorMessage: String?
    @State private var showPlayer = false
    @State private var playTrailer = false
    @State private var playerEpisodeId: String?
    @State private var inWatchlist = false
    @State private var watchlistBusy = false
    @State private var selectedRelated: ContentItem?

    private var displayTitle: String {
        detail?.title ?? seed?.title ?? ""
    }

    private var heroImageURLs: [URL] {
        if let urls = detail?.backdropCandidates, !urls.isEmpty { return urls }
        if let urls = seed?.backdropCandidates, !urls.isEmpty { return urls }
        if let urls = detail?.posterCandidates, !urls.isEmpty { return urls }
        return seed?.posterCandidates ?? []
    }

    private var synopsisText: String? {
        let raw = detail?.description ?? seed?.description
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return Self.shorten(raw)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DetailHeroView(
                    title: displayTitle,
                    meta: metaText,
                    rating: detail?.ratingStats,
                    imageURLs: heroImageURLs,
                    hasTrailer: detail?.hasTrailer == true,
                    inWatchlist: inWatchlist,
                    watchlistBusy: watchlistBusy,
                    onPlay: { startPlayback(trailer: false, episodeId: firstEpisodeId) },
                    onTrailer: { startPlayback(trailer: true, episodeId: nil) },
                    onWatchlist: { Task { await toggleWatchlist() } }
                )

                DetailBodySections(
                    synopsis: synopsisText,
                    hasTrailer: detail?.hasTrailer == true,
                    trailerImageURLs: detail?.backdropCandidates ?? detail?.posterCandidates ?? [],
                    seasons: detail?.seasons ?? [],
                    related: related,
                    crew: crew,
                    btsVideos: detail?.btsVideos ?? [],
                    errorMessage: errorMessage,
                    onPlayTrailer: { startPlayback(trailer: true, episodeId: nil) },
                    onPlayEpisode: { startPlayback(trailer: false, episodeId: $0) },
                    onSelectRelated: { selectedRelated = $0 }
                )
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
            playerCover
        }
    }

    @ViewBuilder
    private var playerCover: some View {
        PlayerContainerView(
            contentId: contentId,
            title: displayTitle,
            episodeId: playerEpisodeId,
            isTrailer: playTrailer
        )
        .onDisappear {
            OrientationLock.unlockPortrait()
            playTrailer = false
            playerEpisodeId = nil
        }
    }

    private var metaText: String {
        var parts: [String] = []
        if let type = detail?.type ?? seed?.type {
            parts.append(type.replacingOccurrences(of: "_", with: " ").capitalized)
        }
        if let category = detail?.category ?? seed?.category, !category.isEmpty {
            parts.append(category)
        }
        if let year = detail?.year ?? seed?.year {
            parts.append(String(year))
        }
        if let runtime = detail?.runtimeLabel {
            parts.append(runtime)
        }
        if let age = detail?.ageRating, !age.isEmpty {
            parts.append(age)
        }
        if let creator = detail?.creator?.name, !creator.isEmpty {
            parts.append("By \(creator)")
        }
        return parts.joined(separator: " · ")
    }

    private var firstEpisodeId: String? {
        detail?.seasons?.first?.episodes?.first?.id
    }

    private func startPlayback(trailer: Bool, episodeId: String?) {
        playTrailer = trailer
        playerEpisodeId = episodeId
        showPlayer = true
    }

    private static func shorten(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 280 { return trimmed }
        return String(trimmed.prefix(277)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    private func load() async {
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

// MARK: - Hero

private struct DetailHeroView: View {
    let title: String
    let meta: String
    let rating: RatingStats?
    let imageURLs: [URL]
    let hasTrailer: Bool
    let inWatchlist: Bool
    let watchlistBusy: Bool
    let onPlay: () -> Void
    let onTrailer: () -> Void
    let onWatchlist: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(urls: imageURLs)
                .frame(maxWidth: .infinity)
                .frame(height: 420)

            LinearGradient(
                colors: [.clear, .black.opacity(0.35), .black.opacity(0.95)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .minimumScaleFactor(0.75)

                if !meta.isEmpty {
                    Text(meta)
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                }

                ratingRow

                actionRow
            }
            .padding(20)
        }
    }

    @ViewBuilder
    private var ratingRow: some View {
        if let rating, (rating.count ?? 0) > 0 {
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
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button(action: onPlay) {
                Label("Play", systemImage: "play.fill")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white)
                    .clipShape(Capsule())
            }

            if hasTrailer {
                Button(action: onTrailer) {
                    Image(systemName: "film")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(Color.white.opacity(0.16))
                        .clipShape(Circle())
                }
                .accessibilityLabel("Play trailer")
            }

            Button(action: onWatchlist) {
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
}

// MARK: - Body sections

private struct DetailBodySections: View {
    let synopsis: String?
    let hasTrailer: Bool
    let trailerImageURLs: [URL]
    let seasons: [Season]
    let related: [ContentItem]
    let crew: [CrewCredit]
    let btsVideos: [BtsVideo]
    let errorMessage: String?
    let onPlayTrailer: () -> Void
    let onPlayEpisode: (String) -> Void
    let onSelectRelated: (ContentItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            if let synopsis {
                Text(synopsis)
                    .font(.body)
                    .foregroundStyle(Theme.muted)
                    .lineSpacing(3)
            }

            if hasTrailer {
                DetailTrailersSection(imageURLs: trailerImageURLs, onPlay: onPlayTrailer)
            }

            if !seasons.isEmpty {
                DetailEpisodesSection(seasons: seasons, onPlayEpisode: onPlayEpisode)
            }

            if !related.isEmpty {
                DetailRelatedSection(items: related, onSelect: onSelectRelated)
            }

            if !crew.isEmpty {
                DetailCastSection(crew: crew)
            }

            if !btsVideos.isEmpty {
                DetailBtsSection(videos: btsVideos)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red.opacity(0.9))
            }
        }
    }
}

private struct DetailTrailersSection: View {
    let imageURLs: [URL]
    let onPlay: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trailers")
                .font(.title3.bold())
                .foregroundStyle(Theme.foreground)

            Button(action: onPlay) {
                ZStack(alignment: .bottomLeading) {
                    RemoteImage(urls: imageURLs)
                        .frame(width: 280, height: 158)

                    LinearGradient(
                        colors: [.clear, .black.opacity(0.75)],
                        startPoint: .center,
                        endPoint: .bottom
                    )

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
}

private struct DetailEpisodesSection: View {
    let seasons: [Season]
    let onPlayEpisode: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Episodes")
                .font(.title3.bold())
                .foregroundStyle(Theme.foreground)

            ForEach(seasons, id: \.stableId) { season in
                DetailSeasonBlock(season: season, onPlayEpisode: onPlayEpisode)
            }
        }
    }
}

private struct DetailSeasonBlock: View {
    let season: Season
    let onPlayEpisode: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Season \(season.seasonNumber ?? 1)")
                .font(.headline)
                .foregroundStyle(Theme.accentGold)

            ForEach(season.episodes ?? []) { episode in
                DetailEpisodeRow(episode: episode) {
                    onPlayEpisode(episode.id)
                }
            }
        }
    }
}

private struct DetailEpisodeRow: View {
    let episode: Episode
    let onPlay: () -> Void

    private var thumbURL: URL? {
        guard let thumb = episode.thumbnailUrl else { return nil }
        return MediaURL.resolve(posterUrl: thumb, videoUrl: episode.videoUrl)
    }

    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 120, height: 68)
                    if let thumbURL {
                        RemoteImage(url: thumbURL)
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

private struct DetailRelatedSection: View {
    let items: [ContentItem]
    let onSelect: (ContentItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("More Like This")
                .font(.title3.bold())
                .foregroundStyle(Theme.foreground)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(items) { item in
                        Button {
                            onSelect(item)
                        } label: {
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
}

private struct DetailCastSection: View {
    let crew: [CrewCredit]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Cast & Crew")
                    .font(.title3.bold())
                    .foregroundStyle(Theme.foreground)
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
                        DetailCastCard(member: member)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

private struct DetailCastCard: View {
    let member: CrewCredit

    var body: some View {
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

private struct DetailBtsSection: View {
    let videos: [BtsVideo]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Behind the Scenes")
                .font(.title3.bold())
                .foregroundStyle(Theme.foreground)

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
}
