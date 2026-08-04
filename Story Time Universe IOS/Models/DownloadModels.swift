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
    /// Path of the downloaded asset relative to the app home directory
    /// (or an absolute sandbox path if that's what AVFoundation returned).
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

    /// Resolves a playable local file/directory on disk.
    var localURL: URL? {
        guard let relativePath, !relativePath.isEmpty else { return nil }
        let fm = FileManager.default
        let candidates = Self.candidateURLs(forStoredPath: relativePath)
        return candidates.first { fm.fileExists(atPath: $0.path) }
    }

    var isPlayableOffline: Bool {
        state == .completed && localURL != nil
    }

    static func candidateURLs(forStoredPath path: String) -> [URL] {
        var urls: [URL] = []
        if path.hasPrefix("/") {
            urls.append(URL(fileURLWithPath: path))
        }
        let home = NSHomeDirectory()
        urls.append(URL(fileURLWithPath: home).appendingPathComponent(path))
        // Sometimes paths are stored without the leading Library/ path segment.
        if !path.hasPrefix("Library"), !path.hasPrefix("Documents"), !path.hasPrefix("tmp") {
            urls.append(URL(fileURLWithPath: home).appendingPathComponent("Library").appendingPathComponent(path))
        }
        return urls
    }

    /// Persist paths relative to home when possible so sandbox container moves keep working.
    static func storagePath(for fileURL: URL) -> String {
        let home = NSHomeDirectory()
        let path = fileURL.standardizedFileURL.path
        if path.hasPrefix(home) {
            return String(path.dropFirst(home.count).drop(while: { $0 == "/" }))
        }
        return path
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
