import Foundation
import ImageIO
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
        // Catalogue posters can be very large (The Second poster is ~14MB on S3).
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        config.waitsForConnectivity = true
        config.urlCache = URLCache(
            memoryCapacity: 64 * 1024 * 1024,
            diskCapacity: 512 * 1024 * 1024,
            diskPath: "storytime-url-cache"
        )
        config.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: config)
    }

    /// Try candidates in order; memory/disk hits win immediately.
    /// When `preferPortrait` is true, skip clearly landscape frames if a later candidate may be better.
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
        // Per-request timeout — large S3 catalogue art needs headroom.
        request.timeoutInterval = isLikelyLargeAsset(url) ? 90 : 45
        request.cachePolicy = .returnCacheDataElseLoad

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                markFailed(url, seconds: 45)
                return nil
            }
            guard data.count > 256 else {
                markFailed(url, seconds: 45)
                return nil
            }

            // Downsample huge uploads (14MB+ masters) so cards load fast and fit memory.
            guard let image = Self.downsampledImage(from: data, maxPixelSize: 1200) else {
                markFailed(url, seconds: 30)
                return nil
            }

            let cacheData = image.jpegData(compressionQuality: 0.82) ?? data
            ImageCache.shared.store(image, data: cacheData, for: url)
            clearFailed(url)
            return image
        } catch {
            let ns = error as NSError
            // Timeouts / transient network must NOT blacklist the real poster for long —
            // that was causing Stream video frames to win permanently for The Second.
            if ns.domain == NSURLErrorDomain,
               [NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost, NSURLErrorNotConnectedToInternet]
                .contains(ns.code) {
                markFailed(url, seconds: 5)
            } else {
                markFailed(url, seconds: 45)
            }
            return nil
        }
    }

    private func isLikelyLargeAsset(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host.contains("amazonaws.com")
            || host.contains("r2.cloudflarestorage.com")
            || host.contains("storage.googleapis.com")
            || url.path.lowercased().contains("/uploads/")
    }

    private func isTemporarilyFailed(_ url: URL) -> Bool {
        guard let until = failedUntil[url.absoluteString] else { return false }
        if until > Date() { return true }
        failedUntil[url.absoluteString] = nil
        return false
    }

    private func markFailed(_ url: URL, seconds: TimeInterval) {
        failedUntil[url.absoluteString] = Date().addingTimeInterval(seconds)
    }

    private func clearFailed(_ url: URL) {
        failedUntil[url.absoluteString] = nil
    }

    /// Decode with ImageIO thumbnailing — critical for multi‑MB catalogue masters.
    nonisolated private static func downsampledImage(from data: Data, maxPixelSize: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return UIImage(data: data)
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) {
            return UIImage(cgImage: cgImage)
        }
        return UIImage(data: data)
    }
}
