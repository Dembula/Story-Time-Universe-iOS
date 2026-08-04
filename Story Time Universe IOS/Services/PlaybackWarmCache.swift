import AVFoundation
import Foundation

/// Safe pre-fetch for smoother Play.
///
/// IMPORTANT: Never transfers live `AVPlayer` / `AVPlayerItem` instances into the UI player.
/// Reusing items across players is a common crash source. We only:
///  1. Fetch the playback-bundle (session cookies + stream URL)
///  2. Load asset playability metadata
///  3. Optionally nudge HLS with a lightweight `AVAsset` load
actor PlaybackWarmCache {
    static let shared = PlaybackWarmCache()

    private struct Entry {
        let streamURL: URL
        let fetchedAt: Date
    }

    private var entries: [String: Entry] = [:]
    private var inFlight = Set<String>()
    private let maxEntries = 12

    func warm(contentId: String, episodeId: String? = nil) {
        let key = Self.key(contentId: contentId, episodeId: episodeId)
        guard !inFlight.contains(key) else { return }
        if let existing = entries[key], Date().timeIntervalSince(existing.fetchedAt) < 120 {
            return
        }
        inFlight.insert(key)

        Task {
            defer { Task { await self.clearInFlight(key) } }

            let offline = await MainActor.run {
                DownloadManager.shared.offlineAsset(contentId: contentId, episodeId: episodeId) != nil
            }
            if offline { return }

            do {
                let bundle = try await ViewerAPI.shared.fetchPlaybackBundle(
                    contentId: contentId,
                    episodeId: episodeId,
                    trailer: false
                )
                guard let url = bundle.streamURL else { return }

                // Metadata only — no silent AVPlayer (those caused crashes under load).
                let asset = Self.makeAsset(url: url)
                _ = try? await asset.load(.isPlayable, .duration)

                await store(key: key, url: url)
            } catch {
                // Soft fail — Play will fetch again.
            }
        }
    }

    func warmMany(contentIds: [String]) {
        for id in contentIds.prefix(4) {
            warm(contentId: id)
        }
    }

    /// Peek cached stream URL if recently warmed (nil is fine — player fetches live).
    func cachedStreamURL(contentId: String, episodeId: String?) -> URL? {
        let key = Self.key(contentId: contentId, episodeId: episodeId)
        guard let entry = entries[key], Date().timeIntervalSince(entry.fetchedAt) < 180 else {
            return nil
        }
        return entry.streamURL
    }

    private func store(key: String, url: URL) {
        entries[key] = Entry(streamURL: url, fetchedAt: Date())
        if entries.count > maxEntries {
            let sorted = entries.sorted { $0.value.fetchedAt < $1.value.fetchedAt }
            for (oldKey, _) in sorted.prefix(entries.count - maxEntries) {
                entries.removeValue(forKey: oldKey)
            }
        }
    }

    private func clearInFlight(_ key: String) {
        inFlight.remove(key)
    }

    private static func key(contentId: String, episodeId: String?) -> String {
        "\(contentId)|\(episodeId ?? "")"
    }

    private static func makeAsset(url: URL) -> AVURLAsset {
        var headers: [String: String] = [
            "User-Agent": DeviceIdentity.userAgent,
            "Accept": "*/*",
        ]
        if let cookies = HTTPCookieStorage.shared.cookies(for: url), !cookies.isEmpty {
            let cookieHeader = HTTPCookie.requestHeaderFields(with: cookies)
            for (key, value) in cookieHeader {
                headers[key] = value
            }
        }
        return AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
    }
}
