import SwiftUI

struct PlaybackRequest: Identifiable {
    let id = UUID()
    let episodeId: String?
    let isTrailer: Bool
    var forceRestart: Bool = false
}

struct ContentDetailView: View {
    let contentId: String
    var seed: ContentItem?

    @EnvironmentObject private var appState: AppState
    @ObservedObject private var parental = ParentalControls.shared
    @State private var detail: ContentDetail?
    @State private var crew: [CrewCredit] = []
    @State private var related: [ContentItem] = []
    @State private var errorMessage: String?
    @State private var playbackRequest: PlaybackRequest?
    @State private var inWatchlist = false
    @State private var watchlistBusy = false
    @State private var selectedRelated: ContentItem?
    @State private var selectedPerson: PersonRoute?
    @State private var isResolvingAccess = false
    @State private var pendingPlayback: PlaybackRequest?
    @State private var showPPVPaywall = false
    @State private var resumePositionSeconds = 0
    @State private var showPlayPIN = false
    @State private var pendingPINPlayback: PlaybackRequest?
    @State private var downloadBlockedMessage: String?

    private var displayTitle: String {
        detail?.title ?? seed?.title ?? ""
    }

    private var playButtonTitle: String {
        if appState.isPayPerViewAccount { return "Unlock & Play" }
        return "Play"
    }

    private var heroImageURLs: [URL] {
        if let urls = detail?.backdropCandidates, !urls.isEmpty { return urls }
        if let urls = seed?.backdropCandidates, !urls.isEmpty { return urls }
        if let urls = detail?.posterCandidates, !urls.isEmpty { return urls }
        return seed?.posterCandidates ?? []
    }

    private var isMaturityBlocked: Bool {
        guard parental.isEnabled else { return false }
        let contentAge = detail?.numericMinAge ?? seed?.minAge
        guard let contentAge, contentAge > 0 else { return false }
        return !parental.allows(contentMinAge: contentAge, profileAge: appState.activeProfile?.age)
    }

    private var synopsisText: String? {
        let raw = detail?.description ?? seed?.description
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var body: some View {
        if isMaturityBlocked {
            maturityBlockedView
        } else {
            mainContent
        }
    }

    private var maturityBlockedView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.accent.opacity(0.7))
            Text("Content Restricted")
                .font(.title2.bold())
                .foregroundStyle(Theme.foreground)
            Text("This title is rated \(detail?.ageRating ?? "above your limit") and is blocked by parental controls (limit: \(parental.maturityLabel)).")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    @ViewBuilder
    private var mainContent: some View {
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
                    downloadSpec: filmDownloadSpec,
                    playLabel: playButtonTitle,
                    showStartFromBeginning: resumePositionSeconds > 5,
                    onPlay: { startPlayback(trailer: false, episodeId: firstEpisodeId, forceRestart: false) },
                    onStartFromBeginning: { startPlayback(trailer: false, episodeId: firstEpisodeId, forceRestart: true) },
                    onTrailer: { startPlayback(trailer: true, episodeId: nil, forceRestart: false) },
                    onWatchlist: { Task { await toggleWatchlist() } },
                    onDownloadBlocked: {
                        downloadBlockedMessage = "Downloads are blocked by parental controls on this device."
                    }
                )

                DetailBodySections(
                    synopsis: synopsisText,
                    hasTrailer: detail?.hasTrailer == true,
                    trailerImageURLs: detail?.backdropCandidates ?? detail?.posterCandidates ?? [],
                    seasons: detail?.seasons ?? [],
                    isSeriesLike: (detail?.isSeriesLike == true) || (seed?.isSeriesLike == true),
                    seriesTitle: displayTitle,
                    seriesContentId: contentId,
                    seriesFallbackImageURLs: detail?.posterCandidates ?? detail?.backdropCandidates ?? seed?.posterCandidates ?? [],
                    contentType: detail?.type ?? seed?.type,
                    category: detail?.category ?? seed?.category,
                    year: detail?.year ?? seed?.year,
                    ageRating: detail?.ageRating,
                    language: detail?.language,
                    country: detail?.country,
                    runtimeLabel: detail?.runtimeLabel,
                    creatorName: detail?.creator?.name,
                    related: related,
                    crew: crew,
                    btsVideos: detail?.btsVideos ?? [],
                    errorMessage: errorMessage,
                    onPlayTrailer: { startPlayback(trailer: true, episodeId: nil, forceRestart: false) },
                    onPlayEpisode: { startPlayback(trailer: false, episodeId: $0, forceRestart: false) },
                    onSelectRelated: { selectedRelated = $0 },
                    onSelectPerson: { selectedPerson = $0 }
                )
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
            .trackScrollForTabBar()
        }
        .tabScrollCoordinateSpace()
        .ignoresSafeArea(edges: .top)
        .background(Theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await load() }
        .navigationDestination(item: $selectedRelated) { item in
            ContentDetailView(contentId: item.id, seed: item)
        }
        .navigationDestination(item: $selectedPerson) { route in
            PersonDetailView(route: route)
        }
        .fullScreenCover(item: $playbackRequest) { request in
            PlayerContainerView(
                contentId: contentId,
                title: displayTitle,
                episodeId: request.episodeId,
                isTrailer: request.isTrailer,
                episodes: request.isTrailer ? [] : episodePlaybackInfos,
                forceRestart: request.forceRestart
            )
            .environmentObject(appState)
        }
        .sheet(isPresented: $showPPVPaywall) {
            SubscriptionPaywallView(
                context: .ppv(contentId: contentId, title: displayTitle)
            ) {
                Task { await handlePPVPurchaseFinished() }
            }
            .environmentObject(appState)
        }
        .sheet(isPresented: $showPlayPIN) {
            ParentalPINSheet(
                title: "Parental PIN",
                message: "Enter your parental PIN to play this title.",
                onCancel: {
                    showPlayPIN = false
                    pendingPINPlayback = nil
                },
                onSuccess: {
                    showPlayPIN = false
                    if let pending = pendingPINPlayback {
                        pendingPINPlayback = nil
                        Task { await resolvePlayback(pending) }
                    }
                }
            )
        }
        .alert("Downloads blocked", isPresented: Binding(
            get: { downloadBlockedMessage != nil },
            set: { if !$0 { downloadBlockedMessage = nil } }
        )) {
            Button("OK", role: .cancel) { downloadBlockedMessage = nil }
        } message: {
            Text(downloadBlockedMessage ?? "")
        }
        .overlay {
            if isResolvingAccess {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    ProgressView("Checking access…")
                        .padding(20)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                        .tint(Theme.accent)
                }
            }
        }
    }

    private var episodePlaybackInfos: [EpisodePlaybackInfo] {
        guard let seasons = detail?.seasons else { return [] }
        var list: [EpisodePlaybackInfo] = []
        for season in seasons {
            let sNum = season.seasonNumber ?? 1
            for episode in season.episodes ?? [] {
                let eNum = episode.episodeNumber ?? (list.count + 1)
                list.append(
                    EpisodePlaybackInfo(
                        episodeId: episode.id,
                        title: episode.title ?? "Episode \(eNum)",
                        episodeLabel: "S\(sNum) E\(eNum)",
                        thumbnailUrl: episode.thumbnailUrl,
                        durationSeconds: episode.duration
                    )
                )
            }
        }
        return list
    }

    private var filmDownloadSpec: DownloadSpec? {
        // Series episodes are downloaded individually; only offer a single download for films.
        guard (detail?.seasons?.isEmpty ?? true) else { return nil }
        return DownloadSpec(
            contentId: contentId,
            episodeId: nil,
            title: displayTitle,
            subtitle: nil,
            posterUrl: detail?.posterUrl ?? seed?.posterUrl,
            type: detail?.type ?? seed?.type,
            durationSeconds: detail?.duration
        )
    }

    private var metaText: String {
        var parts: [String] = []
        if let year = detail?.year ?? seed?.year {
            parts.append(String(year))
        }
        if let age = detail?.ageRating, !age.isEmpty {
            parts.append(age)
        }
        if let runtime = detail?.runtimeLabel {
            parts.append(runtime)
        }
        if let type = detail?.type ?? seed?.type {
            parts.append(type.replacingOccurrences(of: "_", with: " ").capitalized)
        }
        return parts.joined(separator: " · ")
    }

    private var firstEpisodeId: String? {
        detail?.seasons?.first?.episodes?.first?.id
    }

    private func startPlayback(trailer: Bool, episodeId: String?, forceRestart: Bool) {
        let resolvedEpisode = episodeId.flatMap { $0.isEmpty ? nil : $0 } ?? (trailer ? nil : firstEpisodeId)
        let request = PlaybackRequest(episodeId: resolvedEpisode, isTrailer: trailer, forceRestart: forceRestart)
        if !trailer, ParentalPINGate.needsPinForPlayer {
            pendingPINPlayback = request
            showPlayPIN = true
            return
        }
        Task { await resolvePlayback(request) }
    }

    private func resolvePlayback(_ request: PlaybackRequest) async {
        if request.isTrailer {
            playbackRequest = request
            return
        }
        if DownloadManager.shared.offlineAsset(contentId: contentId, episodeId: request.episodeId) != nil {
            playbackRequest = request
            return
        }

        isResolvingAccess = true
        defer { isResolvingAccess = false }
        errorMessage = nil

        if appState.subscription == nil {
            await appState.refreshSubscriptionFromServer()
        }

        let access = await ViewerAPI.shared.resolveTitleAccess(
            contentId: contentId,
            isPayPerViewAccount: appState.isPayPerViewAccount,
            isTrailer: false
        )

        switch access {
        case .playable:
            playbackRequest = request
        case .requiresInAppPurchase:
            pendingPlayback = request
            showPPVPaywall = true
        case .blocked(let message):
            errorMessage = message
        }
    }

    private func handlePPVPurchaseFinished() async {
        guard let pending = pendingPlayback else { return }
        pendingPlayback = nil
        showPPVPaywall = false
        isResolvingAccess = true
        defer { isResolvingAccess = false }
        try? await Task.sleep(nanoseconds: 800_000_000)

        let access = await ViewerAPI.shared.resolveTitleAccess(
            contentId: contentId,
            isPayPerViewAccount: true,
            isTrailer: false
        )
        switch access {
        case .playable:
            playbackRequest = pending
            errorMessage = nil
        case .requiresInAppPurchase:
            errorMessage = "If the title isn’t unlocked yet, wait a moment and press Play again."
        case .blocked(let message):
            errorMessage = message
        }
    }

    private func load() async {
        do {
            let loaded = try await ViewerAPI.shared.fetchContentDetail(id: contentId)
            detail = loaded

            Task { await PlaybackWarmCache.shared.warm(contentId: contentId) }
            if let firstEp = loaded.seasons?.first?.episodes?.first?.id {
                Task { await PlaybackWarmCache.shared.warm(contentId: contentId, episodeId: firstEp) }
            }

            async let crewReq = ViewerAPI.shared.fetchCrew(contentId: contentId)
            async let relatedReq = ViewerAPI.shared.fetchRelated(
                excluding: contentId,
                category: loaded.category,
                type: loaded.type,
                limit: 12
            )
            async let listReq = ViewerAPI.shared.fetchWatchlist()
            async let progressReq = ViewerAPI.shared.fetchWatchProgress(contentId: contentId)

            crew = (try? await crewReq) ?? []
            related = parental.filter(
                (try? await relatedReq) ?? [],
                profileAge: appState.activeProfile?.age
            )
            ImagePrefetcher.prefetch([loaded.backdropCandidates])
            ImagePrefetcher.prefetchPosters(related)
            // Warm episode thumbnails so the series strip is instant (e.g. Colour Me Blu).
            let episodeThumbs = (loaded.seasons ?? []).flatMap { season in
                (season.episodes ?? []).map {
                    MediaURL.candidates(
                        posterUrl: $0.thumbnailUrl,
                        backdropUrl: nil,
                        videoUrl: $0.videoUrl,
                        preferBackdrop: true
                    )
                }
            }
            ImagePrefetcher.prefetch(episodeThumbs, preferPortrait: false)
            let list = try? await listReq
            inWatchlist = list?.contains(where: { $0.id == contentId }) ?? false
            resumePositionSeconds = (try? await progressReq)?.position ?? 0
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
    let downloadSpec: DownloadSpec?
    let playLabel: String
    let showStartFromBeginning: Bool
    let onPlay: () -> Void
    let onStartFromBeginning: () -> Void
    let onTrailer: () -> Void
    let onWatchlist: () -> Void
    let onDownloadBlocked: () -> Void

    private let heroHeight: CGFloat = min(UIScreen.main.bounds.height * 0.62, 560)

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            GeometryReader { geo in
                RemoteImage(urls: imageURLs)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }

            LinearGradient(
                colors: [.black.opacity(0.55), .clear, .clear],
                startPoint: .top,
                endPoint: .center
            )

            LinearGradient(
                colors: [.clear, .black.opacity(0.35), .black.opacity(0.96)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.system(size: 34, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .minimumScaleFactor(0.75)

                if !meta.isEmpty {
                    metaBadges
                }

                ratingRow
                actionRow
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .frame(height: heroHeight)
        .clipped()
    }

    private var metaBadges: some View {
        let parts = meta
            .components(separatedBy: " · ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(parts, id: \.self) { part in
                    Text(part)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
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
                Label(playLabel, systemImage: "play.fill")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 14)
                    .background(Color.white)
                    .clipShape(Capsule())
            }

            if hasTrailer {
                circularAction(systemImage: "film", label: "Play trailer", action: onTrailer)
            }

            Button(action: onWatchlist) {
                Image(systemName: inWatchlist ? "checkmark" : "plus")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Color.black.opacity(0.45))
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            .disabled(watchlistBusy)
            .accessibilityLabel(inWatchlist ? "In My List" : "Add to My List")

            if let downloadSpec {
                circularDownload(spec: downloadSpec)
            }

            if showStartFromBeginning {
                circularAction(
                    systemImage: "arrow.counterclockwise",
                    label: "Start from beginning",
                    action: onStartFromBeginning
                )
            }

            Spacer(minLength: 0)
        }
    }

    private func circularAction(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Color.black.opacity(0.45))
                .background(.ultraThinMaterial)
                .clipShape(Circle())
        }
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private func circularDownload(spec: DownloadSpec) -> some View {
        DownloadButton(spec: spec, style: .icon, onBlocked: onDownloadBlocked)
            .frame(width: 48, height: 48)
            .background(Color.black.opacity(0.45))
            .background(.ultraThinMaterial)
            .clipShape(Circle())
    }
}

// MARK: - Body sections

private struct DetailBodySections: View {
    let synopsis: String?
    let hasTrailer: Bool
    let trailerImageURLs: [URL]
    let seasons: [Season]
    let isSeriesLike: Bool
    let seriesTitle: String
    let seriesContentId: String
    let seriesFallbackImageURLs: [URL]
    let contentType: String?
    let category: String?
    let year: Int?
    let ageRating: String?
    let language: String?
    let country: String?
    let runtimeLabel: String?
    let creatorName: String?
    let related: [ContentItem]
    let crew: [CrewCredit]
    let btsVideos: [BtsVideo]
    let errorMessage: String?
    let onPlayTrailer: () -> Void
    let onPlayEpisode: (String) -> Void
    let onSelectRelated: (ContentItem) -> Void
    let onSelectPerson: (PersonRoute) -> Void

    @State private var relatedGlow = false
    @State private var relatedGlowTask: Task<Void, Never>?

    private var hasEpisodeCards: Bool {
        seasons.contains { !($0.episodes ?? []).isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            if hasTrailer {
                DetailTrailersSection(imageURLs: trailerImageURLs, onPlay: onPlayTrailer)
            }

            if hasEpisodeCards {
                DetailEpisodesSection(
                    seasons: seasons,
                    seriesTitle: seriesTitle,
                    seriesContentId: seriesContentId,
                    seriesFallbackImageURLs: seriesFallbackImageURLs,
                    contentType: contentType,
                    onPlayEpisode: onPlayEpisode
                )
            } else if isSeriesLike {
                // Series with missing season payloads still get a trailer-style Episode 1 preview.
                DetailSeriesEpisodePreview(
                    title: seriesTitle,
                    imageURLs: seriesFallbackImageURLs.isEmpty ? trailerImageURLs : seriesFallbackImageURLs,
                    onPlay: { onPlayEpisode("") }
                )
            }

            if let synopsis {
                DetailAboutSection(
                    title: seriesTitle,
                    synopsis: synopsis,
                    contentType: contentType
                )
            }

            if !crew.isEmpty {
                DetailCastSection(crew: crew, onSelect: onSelectPerson)
            }

            DetailReleaseSection(
                category: category,
                year: year,
                ageRating: ageRating,
                language: language,
                country: country,
                runtimeLabel: runtimeLabel,
                creatorName: creatorName,
                contentType: contentType
            )

            if !related.isEmpty {
                DetailRelatedSection(
                    items: related,
                    glowActive: relatedGlow,
                    onSelect: onSelectRelated,
                    onScrollActivity: { active in
                        relatedGlowTask?.cancel()
                        if active {
                            withAnimation(.easeOut(duration: 0.18)) { relatedGlow = true }
                        } else {
                            relatedGlowTask = Task {
                                try? await Task.sleep(nanoseconds: 280_000_000)
                                guard !Task.isCancelled else { return }
                                await MainActor.run {
                                    withAnimation(.easeOut(duration: 0.55)) { relatedGlow = false }
                                }
                            }
                        }
                    }
                )
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

private struct DetailSynopsisView: View {
    let text: String
    @State private var expanded = false

    private let previewLimit = 220

    private var needsExpansion: Bool {
        text.count > previewLimit
    }

    private var displayedText: String {
        guard needsExpansion, !expanded else { return text }
        let end = text.index(text.startIndex, offsetBy: previewLimit, limitedBy: text.endIndex) ?? text.endIndex
        var snippet = String(text[..<end])
        if let lastSpace = snippet.lastIndex(of: " ") {
            snippet = String(snippet[..<lastSpace])
        }
        return snippet.trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(displayedText)
                .font(.body)
                .foregroundStyle(Theme.muted)
                .lineSpacing(3)
                .animation(.easeInOut(duration: 0.2), value: expanded)

            if needsExpansion {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        expanded.toggle()
                    }
                } label: {
                    Text(expanded ? "See less" : "See more")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
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

/// Trailer-shaped Episode 1 preview when the API hasn't returned season rows yet.
private struct DetailSeriesEpisodePreview: View {
    let title: String
    let imageURLs: [URL]
    let onPlay: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Episodes")
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

                    Text("Episode 1")
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
            .accessibilityLabel("Play Episode 1")

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
                .frame(width: 280, alignment: .leading)
        }
    }
}

private struct DetailAboutSection: View {
    let title: String
    let synopsis: String
    let contentType: String?
    @State private var expanded = false

    private let previewLimit = 220

    private var needsExpansion: Bool { synopsis.count > previewLimit }

    private var displayedText: String {
        guard needsExpansion, !expanded else { return synopsis }
        let end = synopsis.index(synopsis.startIndex, offsetBy: previewLimit, limitedBy: synopsis.endIndex) ?? synopsis.endIndex
        var snippet = String(synopsis[..<end])
        if let lastSpace = snippet.lastIndex(of: " ") {
            snippet = String(snippet[..<lastSpace])
        }
        return snippet.trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("About")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(Theme.foreground)

            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.system(.title2, design: .serif).weight(.bold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                if let contentType, !contentType.isEmpty {
                    Text(contentType.replacingOccurrences(of: "_", with: " ").uppercased())
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.4)
                        .foregroundStyle(Theme.accentGold)
                }

                Text(displayedText)
                    .font(.system(.body, design: .default))
                    .foregroundStyle(Color.white.opacity(0.82))
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)

                if needsExpansion {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                    } label: {
                        Text(expanded ? "Show less" : "Show more")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [Color.white.opacity(0.09), Color.white.opacity(0.04)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

private struct DetailReleaseSection: View {
    let category: String?
    let year: Int?
    let ageRating: String?
    let language: String?
    let country: String?
    let runtimeLabel: String?
    let creatorName: String?
    let contentType: String?

    private var rows: [(String, String)] {
        var list: [(String, String)] = []
        if let contentType, !contentType.isEmpty {
            list.append(("Type", contentType.replacingOccurrences(of: "_", with: " ").capitalized))
        }
        if let category, !category.isEmpty {
            list.append(("Genre", category))
        }
        if let year {
            list.append(("Released", String(year)))
        }
        if let ageRating, !ageRating.isEmpty {
            list.append(("Rating", ageRating))
        }
        if let runtimeLabel, !runtimeLabel.isEmpty {
            list.append(("Runtime", runtimeLabel))
        }
        if let language, !language.isEmpty {
            list.append(("Language", language))
        }
        if let country, !country.isEmpty {
            list.append(("Country", country))
        }
        if let creatorName, !creatorName.isEmpty {
            list.append(("Creator", creatorName))
        }
        return list
    }

    var body: some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("Release Info")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.foreground)

                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                        HStack(alignment: .firstTextBaseline) {
                            Text(row.0)
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .foregroundStyle(Theme.muted)
                                .frame(width: 88, alignment: .leading)
                            Text(row.1)
                                .font(.system(.body, design: .serif))
                                .foregroundStyle(.white.opacity(0.9))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 12)
                        if idx < rows.count - 1 {
                            Divider().overlay(Color.white.opacity(0.08))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }
}

private struct DetailEpisodesSection: View {
    let seasons: [Season]
    let seriesTitle: String
    let seriesContentId: String
    let seriesFallbackImageURLs: [URL]
    let contentType: String?
    let onPlayEpisode: (String) -> Void

    @State private var selectedSeasonIndex = 0

    private var selectedSeason: Season? {
        guard seasons.indices.contains(selectedSeasonIndex) else { return seasons.first }
        return seasons[selectedSeasonIndex]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Menu {
                    ForEach(Array(seasons.enumerated()), id: \.element.stableId) { idx, season in
                        Button("Season \(season.seasonNumber ?? idx + 1)") {
                            selectedSeasonIndex = idx
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text("Season \(selectedSeason?.seasonNumber ?? 1)")
                            .font(.title3.bold())
                            .foregroundStyle(Theme.foreground)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.muted)
                    }
                }

                Spacer()

                let episodeCount = selectedSeason?.episodes?.count ?? 0
                Text(episodeCount == 1 ? "1 Episode" : "\(episodeCount) Episodes")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.muted)
            }

            if let season = selectedSeason {
                let episodes = season.episodes ?? []
                if episodes.isEmpty {
                    Text("Episodes for this season aren't available yet.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                        .padding(.vertical, 8)
                } else {
                    // Trailer-style horizontal previews (same shape as Official Trailer cards).
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(Array(episodes.enumerated()), id: \.element.id) { idx, episode in
                                let epNum = episode.episodeNumber ?? (idx + 1)
                                EpisodePosterCard(
                                    episode: episode,
                                    episodeNumber: epNum,
                                    seasonNumber: season.seasonNumber ?? 1,
                                    fallbackImageURLs: seriesFallbackImageURLs,
                                    downloadSpec: DownloadSpec(
                                        contentId: seriesContentId,
                                        episodeId: episode.id,
                                        title: seriesTitle,
                                        subtitle: "S\(season.seasonNumber ?? 1) E\(epNum) · \(episode.title ?? "Episode \(epNum)")",
                                        posterUrl: episode.thumbnailUrl ?? seriesFallbackImageURLs.first.map(\.absoluteString),
                                        type: contentType,
                                        durationSeconds: episode.duration,
                                        seasonNumber: season.seasonNumber,
                                        episodeNumber: epNum
                                    ),
                                    onPlay: { onPlayEpisode(episode.id) }
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct EpisodePosterCard: View {
    let episode: Episode
    let episodeNumber: Int
    let seasonNumber: Int
    let fallbackImageURLs: [URL]
    let downloadSpec: DownloadSpec
    let onPlay: () -> Void

    private var thumbURLs: [URL] {
        let episodeThumbs = MediaURL.candidates(
            posterUrl: episode.thumbnailUrl,
            backdropUrl: nil,
            videoUrl: episode.videoUrl,
            preferBackdrop: true
        )
        return episodeThumbs.isEmpty ? fallbackImageURLs : episodeThumbs
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onPlay) {
                ZStack(alignment: .bottomLeading) {
                    RemoteImage(urls: thumbURLs)
                        .frame(width: 280, height: 158)
                        .background(Color.white.opacity(0.06))

                    LinearGradient(
                        colors: [.clear, .black.opacity(0.75)],
                        startPoint: .center,
                        endPoint: .bottom
                    )

                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.45), radius: 6, y: 1)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Text(episode.title?.isEmpty == false ? (episode.title ?? "Episode \(episodeNumber)") : "Episode \(episodeNumber)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(12)
                }
                .frame(width: 280, height: 158)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play Episode \(episodeNumber)")

            HStack(spacing: 10) {
                Text("EPISODE \(episodeNumber)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.accent)
                if let duration = episode.duration, duration > 0 {
                    Text("\(duration)m")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
                DownloadButton(spec: downloadSpec, style: .icon)
            }
            .frame(width: 280)

            if let description = episode.description, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(2)
                    .frame(width: 280, alignment: .leading)
            }
        }
    }
}

private struct DetailRelatedSection: View {
    let items: [ContentItem]
    var glowActive: Bool = false
    let onSelect: (ContentItem) -> Void
    var onScrollActivity: ((Bool) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("More Like This")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(Theme.foreground)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(items) { item in
                        Button {
                            onSelect(item)
                        } label: {
                            PosterCard(item: item, glowActive: glowActive)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 10)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { _ in onScrollActivity?(true) }
                    .onEnded { _ in onScrollActivity?(false) }
            )
        }
    }
}

private struct DetailCastSection: View {
    let crew: [CrewCredit]
    var onSelect: (PersonRoute) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Cast & Crew")
                    .font(.system(.title3, design: .rounded).weight(.bold))
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
                        Button {
                            onSelect(PersonRoute(from: member))
                        } label: {
                            DetailCastCard(member: member)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Shows profile and credits")
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
