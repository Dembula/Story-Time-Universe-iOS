import AVFoundation
import Foundation

/// Warms playback metadata / media assets so Play starts faster.
actor PlaybackWarmCache {
    static let shared = PlaybackWarmCache()

    private var primed = Set<String>()
    private var inFlight = Set<String>()

    func warm(contentId: String, episodeId: String? = nil) {
        let key = "\(contentId)|\(episodeId ?? "")"
        guard !primed.contains(key), !inFlight.contains(key) else { return }
        inFlight.insert(key)

        Task {
            defer {
                Task { await self.markDone(key: key) }
            }
            // Prefer offline assets; nothing to warm.
            if await MainActor.run(body: {
                DownloadManager.shared.offlineAsset(contentId: contentId, episodeId: episodeId) != nil
            }) {
                return
            }
            guard let bundle = try? await ViewerAPI.shared.fetchPlaybackBundle(
                contentId: contentId,
                episodeId: episodeId,
                trailer: false
            ), let url = bundle.streamURL else { return }

            let cookies = HTTPCookieStorage.shared.cookies(for: url) ?? []
            let options: [String: Any] = cookies.isEmpty ? [:] : [AVURLAssetHTTPCookiesKey: cookies]
            let asset = AVURLAsset(url: url, options: options)
            _ = try? await asset.load(.isPlayable, .duration)
        }
    }

    private func markDone(key: String) {
        inFlight.remove(key)
        primed.insert(key)
    }

    func warmMany(contentIds: [String]) {
        for id in contentIds.prefix(8) {
            warm(contentId: id)
        }
    }
}
