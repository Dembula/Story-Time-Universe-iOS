import Foundation

enum MediaURL {
    /// Ordered image candidates — callers should try until one loads.
    static func candidates(
        posterUrl: String?,
        backdropUrl: String? = nil,
        videoUrl: String? = nil,
        preferBackdrop: Bool = false
    ) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []

        func append(_ url: URL?) {
            guard let url else { return }
            let key = url.absoluteString
            guard !seen.contains(key) else { return }
            seen.insert(key)
            result.append(url)
        }

        let primary = preferBackdrop ? backdropUrl : posterUrl
        let secondary = preferBackdrop ? posterUrl : backdropUrl
        let backdropKey = normalizedKey(backdropUrl)

        if preferBackdrop {
            // Hero / Continue Watching — wide art first.
            append(displayableHTTPURL(from: primary))
            append(previewProxyURL(from: primary))
            append(siteRelativeURL(from: primary))
            append(streamThumbnailURL(from: videoUrl, time: "5s", height: 720, width: nil))
            append(displayableHTTPURL(from: secondary))
            append(previewProxyURL(from: secondary))
            append(siteRelativeURL(from: secondary))
        } else {
            // Poster cards — never use backdrop URLs.
            // Order matters: real poster sources first. Do NOT fall back to Stream video
            // frames when a poster exists — those landscape stills look like backdrops
            // (The Second: 14MB S3 poster was timing out, then Stream won).
            append(posterOnly(displayableHTTPURL(from: primary), excludingBackdrop: backdropKey))
            append(posterOnly(previewProxyURL(from: primary), excludingBackdrop: backdropKey))
            append(posterOnly(siteRelativeURL(from: primary), excludingBackdrop: backdropKey))

            let hasPosterArt = !(posterUrl?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            if !hasPosterArt {
                append(streamThumbnailURL(from: videoUrl, time: "2s", height: 480, width: 320))
            }
        }

        if result.count > 4 {
            return Array(result.prefix(4))
        }
        return result
    }

    static func resolve(
        posterUrl: String?,
        backdropUrl: String? = nil,
        videoUrl: String? = nil,
        preferBackdrop: Bool = false
    ) -> URL? {
        candidates(
            posterUrl: posterUrl,
            backdropUrl: backdropUrl,
            videoUrl: videoUrl,
            preferBackdrop: preferBackdrop
        ).first
    }

    static func displayableHTTPURL(from raw: String?) -> URL? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        guard raw.lowercased().hasPrefix("https://") || raw.lowercased().hasPrefix("http://") else { return nil }
        if isNonImageMediaURL(raw) { return nil }
        return URL(string: raw)
    }

    static func httpURL(from raw: String?) -> URL? {
        displayableHTTPURL(from: raw) ?? siteRelativeURL(from: raw)
    }

    static func siteRelativeURL(from raw: String?) -> URL? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if raw.hasPrefix("/") {
            return URL(string: raw, relativeTo: AppConfig.apiBaseURL)?.absoluteURL
        }
        return nil
    }

    static func previewProxyURL(from raw: String?) -> URL? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let looksPrivate = raw.hasPrefix("s3://")
            || raw.contains(".amazonaws.com/")
            || raw.contains("r2.cloudflarestorage.com")
            || raw.contains("storage.googleapis.com")
            || (!raw.lowercased().hasPrefix("http://") && !raw.lowercased().hasPrefix("https://") && !raw.hasPrefix("/"))
        // Also proxy plain s3-style keys that aren't full URLs.
        let shouldProxy = looksPrivate || raw.hasPrefix("s3://")
        guard shouldProxy else { return nil }
        var components = URLComponents(string: AppConfig.apiBaseURL.absoluteString + "/api/files/preview")
        components?.queryItems = [
            URLQueryItem(name: "ref", value: raw),
            URLQueryItem(name: "context", value: "marketplace"),
        ]
        return components?.url
    }

    static func streamThumbnailURL(
        from videoUrl: String?,
        time: String = "3s",
        height: Int = 480,
        width: Int? = nil
    ) -> URL? {
        guard let uid = extractStreamUID(from: videoUrl) else { return nil }
        var components = URLComponents(string: "https://videodelivery.net/\(uid)/thumbnails/thumbnail.jpg")
        var items = [
            URLQueryItem(name: "time", value: time),
            URLQueryItem(name: "height", value: String(height)),
        ]
        if let width {
            items.append(URLQueryItem(name: "width", value: String(width)))
            items.append(URLQueryItem(name: "fit", value: "crop"))
        }
        components?.queryItems = items
        return components?.url
    }

    static func extractStreamUID(from videoUrl: String?) -> String? {
        guard let videoUrl = videoUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !videoUrl.isEmpty else { return nil }

        if videoUrl.range(of: #"^[a-fA-F0-9]{32}$"#, options: .regularExpression) != nil {
            return videoUrl
        }

        guard let url = URL(string: videoUrl), let host = url.host?.lowercased() else {
            if videoUrl.contains("videodelivery.net") || videoUrl.contains("cloudflarestream.com") {
                return extractStreamUID(from: "https://\(videoUrl)")
            }
            return nil
        }
        guard host.contains("videodelivery.net") || host.contains("cloudflarestream.com") else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        guard let first = parts.first, !first.isEmpty else { return nil }
        if first.contains(".") { return nil }
        return first
    }

    /// Drop backdrop URLs from poster candidate lists.
    private static func posterOnly(_ url: URL?, excludingBackdrop backdropKey: String?) -> URL? {
        guard let url else { return nil }
        if let backdropKey, !backdropKey.isEmpty, normalizedKey(url.absoluteString) == backdropKey {
            return nil
        }
        return url
    }

    private static func normalizedKey(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return raw.lowercased()
    }

    private static func isNonImageMediaURL(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        return lower.contains("manifest/video")
            || lower.hasSuffix(".m3u8")
            || lower.hasSuffix(".mpd")
            || lower.hasSuffix(".mp4")
            || lower.contains("/iframe")
            || lower.contains("/downloads/")
    }
}
