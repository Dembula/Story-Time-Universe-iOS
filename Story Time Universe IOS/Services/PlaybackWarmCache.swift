import AVFoundation
import Foundation

/// Preloads stream metadata and the first few seconds of video so Play feels instant.
actor PlaybackWarmCache {
    static let shared = PlaybackWarmCache()

    private var primedItems: [String: AVPlayerItem] = [:]
    private var bufferPlayers: [String: AVPlayer] = [:]
    private var inFlight = Set<String>()

    /// Begin buffering the first ~10s of a title in the background.
    func warm(contentId: String, episodeId: String? = nil) {
        let key = Self.key(contentId: contentId, episodeId: episodeId)
        guard !inFlight.contains(key), primedItems[key] == nil else { return }
        inFlight.insert(key)

        Task {
            defer {
                Task { await self.clearInFlight(key) }
            }

            let offline = await MainActor.run {
                DownloadManager.shared.offlineAsset(contentId: contentId, episodeId: episodeId) != nil
            }
            if offline { return }

            guard let bundle = try? await ViewerAPI.shared.fetchPlaybackBundle(
                contentId: contentId,
                episodeId: episodeId,
                trailer: false
            ), let url = bundle.streamURL else { return }

            let asset = Self.makeAsset(url: url)
            do {
                let playable = try await asset.load(.isPlayable)
                guard playable else { return }
            } catch {
                return
            }

            let item = AVPlayerItem(asset: asset)
            item.preferredForwardBufferDuration = 12
            let player = AVPlayer(playerItem: item)
            player.isMuted = true
            player.volume = 0
            player.automaticallyWaitsToMinimizeStalling = true
            bufferPlayers[key] = player
            player.play()

            // Let the first segments arrive, then park at zero with buffer retained.
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            player.pause()
            await player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)

            // Keep the player alive (holding the item) so the buffer is not discarded.
            primedItems[key] = item
        }
    }

    func warmMany(contentIds: [String]) {
        for id in contentIds.prefix(6) {
            warm(contentId: id)
        }
    }

    /// Claim a primed item for immediate playback (detaches the silent bufferer).
    func consumePrimedItem(contentId: String, episodeId: String?) -> AVPlayerItem? {
        let key = Self.key(contentId: contentId, episodeId: episodeId)
        if let player = bufferPlayers.removeValue(forKey: key) {
            player.pause()
            // Detach without killing the item so its buffer survives.
            player.replaceCurrentItem(with: nil)
        }
        return primedItems.removeValue(forKey: key)
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
        } else if let all = HTTPCookieStorage.shared.cookies {
            let host = url.host ?? AppConfig.apiBaseURL.host ?? ""
            let matched = all.filter { cookie in
                host.hasSuffix(cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")))
                    || cookie.domain == host
            }
            if !matched.isEmpty {
                let cookieHeader = HTTPCookie.requestHeaderFields(with: matched)
                for (key, value) in cookieHeader {
                    headers[key] = value
                }
            }
        }
        return AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
    }
}
