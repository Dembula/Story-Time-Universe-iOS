import Foundation

nonisolated enum DownloadState: String, Codable, Hashable {
    case queued
    case downloading
    case completed
    case failed
    case paused
}

/// Metadata for an offline download. The media itself lives in the app's private
/// container (an iOS-managed `.movpkg` for HLS, or a sandboxed file for progressive
/// video) — never in the Files app and never exportable.
///
/// Each record is owned by one viewer account (`ownerAccountId`). Only that account
/// may list or play the download; signed-out / other accounts see nothing.
nonisolated struct DownloadRecord: Codable, Identifiable, Hashable {
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
    /// Stable account id (user id, else email) that owns this download.
    var ownerAccountId: String?

    var id: String { key }

    enum CodingKeys: String, CodingKey {
        case key, contentId, episodeId, title, subtitle, posterUrl, type
        case relativePath, isHLS, state, progress, totalBytes, createdAt
        case durationSeconds, seasonNumber, episodeNumber, ownerAccountId
    }

    init(
        key: String,
        contentId: String,
        episodeId: String?,
        title: String,
        subtitle: String?,
        posterUrl: String?,
        type: String?,
        relativePath: String?,
        isHLS: Bool,
        state: DownloadState,
        progress: Double,
        totalBytes: Int64,
        createdAt: Date,
        durationSeconds: Int?,
        seasonNumber: Int?,
        episodeNumber: Int?,
        ownerAccountId: String?
    ) {
        self.key = key
        self.contentId = contentId
        self.episodeId = episodeId
        self.title = title
        self.subtitle = subtitle
        self.posterUrl = posterUrl
        self.type = type
        self.relativePath = relativePath
        self.isHLS = isHLS
        self.state = state
        self.progress = progress
        self.totalBytes = totalBytes
        self.createdAt = createdAt
        self.durationSeconds = durationSeconds
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.ownerAccountId = ownerAccountId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        contentId = try c.decode(String.self, forKey: .contentId)
        episodeId = try c.decodeIfPresent(String.self, forKey: .episodeId)
        title = try c.decode(String.self, forKey: .title)
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle)
        posterUrl = try c.decodeIfPresent(String.self, forKey: .posterUrl)
        type = try c.decodeIfPresent(String.self, forKey: .type)
        relativePath = try c.decodeIfPresent(String.self, forKey: .relativePath)
        isHLS = try c.decodeIfPresent(Bool.self, forKey: .isHLS) ?? true
        state = try c.decodeIfPresent(DownloadState.self, forKey: .state) ?? .failed
        progress = try c.decodeIfPresent(Double.self, forKey: .progress) ?? 0
        totalBytes = try c.decodeIfPresent(Int64.self, forKey: .totalBytes) ?? 0
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        durationSeconds = try c.decodeIfPresent(Int.self, forKey: .durationSeconds)
        seasonNumber = try c.decodeIfPresent(Int.self, forKey: .seasonNumber)
        episodeNumber = try c.decodeIfPresent(Int.self, forKey: .episodeNumber)
        ownerAccountId = try c.decodeIfPresent(String.self, forKey: .ownerAccountId)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(key, forKey: .key)
        try c.encode(contentId, forKey: .contentId)
        try c.encodeIfPresent(episodeId, forKey: .episodeId)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(subtitle, forKey: .subtitle)
        try c.encodeIfPresent(posterUrl, forKey: .posterUrl)
        try c.encodeIfPresent(type, forKey: .type)
        try c.encodeIfPresent(relativePath, forKey: .relativePath)
        try c.encode(isHLS, forKey: .isHLS)
        try c.encode(state, forKey: .state)
        try c.encode(progress, forKey: .progress)
        try c.encode(totalBytes, forKey: .totalBytes)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(durationSeconds, forKey: .durationSeconds)
        try c.encodeIfPresent(seasonNumber, forKey: .seasonNumber)
        try c.encodeIfPresent(episodeNumber, forKey: .episodeNumber)
        try c.encodeIfPresent(ownerAccountId, forKey: .ownerAccountId)
    }

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
nonisolated struct EpisodePlaybackInfo: Identifiable, Hashable {
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
nonisolated struct DownloadSpec: Hashable {
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
