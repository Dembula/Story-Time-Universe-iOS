import SwiftUI

struct DownloadsView: View {
    @ObservedObject private var downloads = DownloadManager.shared
    @State private var playback: DownloadPlayback?

    private var completed: [DownloadRecord] { downloads.completedRecords }
    private var active: [DownloadRecord] { downloads.activeRecords }

    var body: some View {
        NavigationStack {
            Group {
                if completed.isEmpty && active.isEmpty {
                    emptyState
                } else {
                    List {
                        if !active.isEmpty {
                            Section("Downloading") {
                                ForEach(active) { record in
                                    DownloadRow(record: record, isActive: true) {}
                                }
                            }
                        }
                        if !completed.isEmpty {
                            Section("Available Offline") {
                                ForEach(completed) { record in
                                    DownloadRow(record: record, isActive: false) {
                                        play(record)
                                    }
                                    .swipeActions {
                                        Button(role: .destructive) {
                                            downloads.deleteDownload(key: record.key)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Downloads")
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .fullScreenCover(item: $playback) { item in
            PlayerContainerView(
                contentId: item.contentId,
                title: item.title,
                episodeId: item.episodeId,
                isTrailer: false,
                episodes: item.episodes
            )
            .onDisappear { OrientationLock.unlockPortrait() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 54))
                .foregroundStyle(Theme.accent)
            Text("No Downloads Yet")
                .font(.title3.bold())
                .foregroundStyle(Theme.foreground)
            Text("Download films and episodes to watch offline. Downloads stay inside the app and can only be played here.")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func play(_ record: DownloadRecord) {
        let episodes = queue(forSeries: record.contentId)
        playback = DownloadPlayback(
            contentId: record.contentId,
            episodeId: record.episodeId,
            title: record.title,
            episodes: record.episodeId == nil ? [] : episodes
        )
    }

    /// Only offline (downloaded) episodes form the in-player queue.
    private func queue(forSeries contentId: String) -> [EpisodePlaybackInfo] {
        downloads.completedRecords
            .filter { $0.contentId == contentId && $0.episodeId != nil }
            .sorted { lhs, rhs in
                let ls = lhs.seasonNumber ?? 0, rs = rhs.seasonNumber ?? 0
                if ls != rs { return ls < rs }
                return (lhs.episodeNumber ?? 0) < (rhs.episodeNumber ?? 0)
            }
            .map { record in
                EpisodePlaybackInfo(
                    episodeId: record.episodeId ?? record.key,
                    title: record.subtitle ?? record.title,
                    episodeLabel: "S\(record.seasonNumber ?? 1) E\(record.episodeNumber ?? 0)",
                    thumbnailUrl: record.posterUrl,
                    durationSeconds: record.durationSeconds
                )
            }
    }
}

private struct DownloadPlayback: Identifiable {
    let id = UUID()
    let contentId: String
    let episodeId: String?
    let title: String
    let episodes: [EpisodePlaybackInfo]
}

private struct DownloadRow: View {
    let record: DownloadRecord
    let isActive: Bool
    let onTap: () -> Void

    @ObservedObject private var downloads = DownloadManager.shared

    private var posterURLs: [URL] {
        MediaURL.candidates(posterUrl: record.posterUrl, backdropUrl: nil, videoUrl: nil, preferBackdrop: record.episodeId != nil)
    }

    var body: some View {
        Button(action: { if !isActive { onTap() } }) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.08))
                    RemoteImage(urls: posterURLs)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    if !isActive {
                        Image(systemName: "play.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
                .frame(width: 112, height: 64)

                VStack(alignment: .leading, spacing: 4) {
                    Text(record.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(1)
                    if let subtitle = record.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                    if isActive {
                        statusLine
                    } else {
                        Label("Watch offline", systemImage: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(Theme.accent)
                    }
                }

                Spacer(minLength: 0)

                if isActive {
                    Button {
                        downloads.cancelDownload(key: record.key)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Theme.muted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private var statusLine: some View {
        switch record.state {
        case .failed:
            Button("Tap to retry") { downloads.startDownload(retrySpec) }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.orange)
                .buttonStyle(.plain)
        default:
            HStack(spacing: 6) {
                ProgressView(value: record.progress)
                    .tint(Theme.accent)
                    .frame(width: 90)
                Text("\(Int(record.progress * 100))%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    private var retrySpec: DownloadSpec {
        DownloadSpec(
            contentId: record.contentId,
            episodeId: record.episodeId,
            title: record.title,
            subtitle: record.subtitle,
            posterUrl: record.posterUrl,
            type: record.type,
            durationSeconds: record.durationSeconds,
            seasonNumber: record.seasonNumber,
            episodeNumber: record.episodeNumber
        )
    }
}
