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
    func loadFirst(of urls: [URL]) async -> UIImage? {
        let candidates = Array(urls.prefix(4))
        guard !candidates.isEmpty else { return nil }

        for url in candidates {
            if let cached = await ImageCache.shared.image(for: url) {
                return cached
            }
        }

        for url in candidates {
            if isTemporarilyFailed(url) { continue }
            if let image = await fetchAndStore(url) {
                return image
            }
        }
        return nil
    }

    /// Warm cache without caring about the result (home/profiles rows).
    func prefetch(urls: [URL]) async {
        _ = await loadFirst(of: urls)
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
