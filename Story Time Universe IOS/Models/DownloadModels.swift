import Foundation

enum DownloadState: String, Codable, Hashable {
    case queued
    case downloading
    case completed
    case failed
    case paused
}

/// Metadata for an offline download. The media itself lives in the app's private
/// container (an iOS-managed `.movpkg` for HLS, or a sandboxed file for progressive
/// video) — never in the Files app and never exportable.
struct DownloadRecord: Codable, Identifiable, Hashable {
    let key: String
    let contentId: String
    let episodeId: String?
    var title: String
    var subtitle: String?
    var posterUrl: String?
    var type: String?
    /// Path of the downloaded asset relative to the app home directory.
    /// Stored relative because the sandbox absolute path changes between launches.
    var relativePath: String?
    var isHLS: Bool
    var state: DownloadState
    var progress: Double
    var totalBytes: Int64
    var createdAt: Date
    var durationSeconds: Int?
    var seasonNumber: Int?
    var episodeNumber: Int?

    var id: String { key }

    var localURL: URL? {
        guard let relativePath, !relativePath.isEmpty else { return nil }
        return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(relativePath)
    }

    var isPlayableOffline: Bool {
        state == .completed && localURL != nil
    }
}

/// A single item in an in-player "up next" queue (series episodes).
struct EpisodePlaybackInfo: Identifiable, Hashable {
    let id: String
    let episodeId: String
    let title: String
    let episodeLabel: String
    let thumbnailUrl: String?
    let durationSeconds: Int?

    init(episodeId: String, title: String, episodeLabel: String, thumbnailUrl: String?, durationSeconds: Int?) {
        self.id = episodeId
        self.episodeId = episodeId
        self.title = title
        self.episodeLabel = episodeLabel
        self.thumbnailUrl = thumbnailUrl
        self.durationSeconds = durationSeconds
    }
}

/// Everything needed to begin a download without re-fetching content metadata.
struct DownloadSpec: Hashable {
    let contentId: String
    let episodeId: String?
    let title: String
    let subtitle: String?
    let posterUrl: String?
    let type: String?
    let durationSeconds: Int?
    let seasonNumber: Int?
    let episodeNumber: Int?

    init(
        contentId: String,
        episodeId: String? = nil,
        title: String,
        subtitle: String? = nil,
        posterUrl: String? = nil,
        type: String? = nil,
        durationSeconds: Int? = nil,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil
    ) {
        self.contentId = contentId
        self.episodeId = episodeId
        self.title = title
        self.subtitle = subtitle
        self.posterUrl = posterUrl
        self.type = type
        self.durationSeconds = durationSeconds
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
    }

    var key: String { DownloadManager.makeKey(contentId: contentId, episodeId: episodeId) }
}
