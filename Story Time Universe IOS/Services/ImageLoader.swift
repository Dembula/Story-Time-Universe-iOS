import Foundation
import UIKit

/// Shared network loader for posters/backdrops — used by RemoteImage and prefetch.
actor ImageLoader {
    static let shared = ImageLoader()

    private let session: URLSession
    private var failedUntil: [String: Date] = [:]

    private init() {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 18
        config.waitsForConnectivity = false
        config.urlCache = URLCache(
            memoryCapacity: 48 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024,
            diskPath: "storytime-url-cache"
        )
        config.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: config)
    }

    /// Try candidates in order; memory/disk hits win immediately. Caps work for speed.
    /// When `preferPortrait` is true, skip clearly landscape frames if a later candidate may be better
    /// (stops video stills / backdrops filling tall poster cards).
    func loadFirst(of urls: [URL], preferPortrait: Bool = false) async -> UIImage? {
        let candidates = Array(urls.prefix(4))
        guard !candidates.isEmpty else { return nil }

        var landscapeFallback: UIImage?

        for (index, url) in candidates.enumerated() {
            if isTemporarilyFailed(url) { continue }

            let image: UIImage?
            if let cached = await ImageCache.shared.image(for: url) {
                image = cached
            } else {
                image = await fetchAndStore(url)
            }
            guard let image else { continue }

            if preferPortrait, isVisiblyLandscape(image) {
                let hasLater = index < candidates.count - 1
                if hasLater {
                    if landscapeFallback == nil { landscapeFallback = image }
                    continue
                }
            }
            return image
        }
        return landscapeFallback
    }

    /// Warm cache without caring about the result (home/profiles rows).
    func prefetch(urls: [URL], preferPortrait: Bool = false) async {
        _ = await loadFirst(of: urls, preferPortrait: preferPortrait)
    }

    private func isVisiblyLandscape(_ image: UIImage) -> Bool {
        let size = image.size
        guard size.height > 1 else { return false }
        return size.width / size.height > 1.25
    }

    private func fetchAndStore(_ url: URL) async -> UIImage? {
        if let cached = await ImageCache.shared.image(for: url) {
            return cached
        }

        var request = URLRequest(url: url)
        request.setValue("StoryTimeUniverseiOS/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10
        request.cachePolicy = .returnCacheDataElseLoad

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                markFailed(url)
                return nil
            }
            guard data.count > 256, let image = UIImage(data: data) else {
                markFailed(url)
                return nil
            }
            ImageCache.shared.store(image, data: data, for: url)
            clearFailed(url)
            return image
        } catch {
            markFailed(url)
            return nil
        }
    }

    private func isTemporarilyFailed(_ url: URL) -> Bool {
        guard let until = failedUntil[url.absoluteString] else { return false }
        if until > Date() { return true }
        failedUntil[url.absoluteString] = nil
        return false
    }

    private func markFailed(_ url: URL) {
        failedUntil[url.absoluteString] = Date().addingTimeInterval(90)
    }

    private func clearFailed(_ url: URL) {
        failedUntil[url.absoluteString] = nil
    }
}
