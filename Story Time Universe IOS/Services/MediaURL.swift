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

        // 1) Direct https artwork (best quality / fastest when present)
        append(displayableHTTPURL(from: primary))
        append(displayableHTTPURL(from: secondary))

        // 2) One Cloudflare Stream still from the video (skip duplicate times / artwork-as-stream)
        append(streamThumbnailURL(
            from: videoUrl,
            time: preferBackdrop ? "5s" : "2s",
            height: preferBackdrop ? 720 : 480
        ))

        // 3) Authenticated storage preview for private objects only
        append(previewProxyURL(from: primary))
        if result.count < 3 {
            append(previewProxyURL(from: secondary))
        }

        // 4) Relative site paths (/public/posters/...)
        append(siteRelativeURL(from: primary))
        if result.count < 4 {
            append(siteRelativeURL(from: secondary))
        }

        // Cap so loaders don't cascade through many slow failures.
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
        guard looksPrivate else { return nil }
        var components = URLComponents(string: AppConfig.apiBaseURL.absoluteString + "/api/files/preview")
        components?.queryItems = [
            URLQueryItem(name: "ref", value: raw),
            URLQueryItem(name: "context", value: "marketplace"),
        ]
        return components?.url
    }

    static func streamThumbnailURL(from videoUrl: String?, time: String = "3s", height: Int = 480) -> URL? {
        guard let uid = extractStreamUID(from: videoUrl) else { return nil }
        var components = URLComponents(string: "https://videodelivery.net/\(uid)/thumbnails/thumbnail.jpg")
        components?.queryItems = [
            URLQueryItem(name: "time", value: time),
            URLQueryItem(name: "height", value: String(height)),
        ]
        return components?.url
    }

    static func extractStreamUID(from videoUrl: String?) -> String? {
        guard let videoUrl = videoUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !videoUrl.isEmpty else { return nil }

        // Direct UID (32 hex-ish cloudflare ids are typically 32 chars)
        if videoUrl.range(of: #"^[a-fA-F0-9]{32}$"#, options: .regularExpression) != nil {
            return videoUrl
        }

        guard let url = URL(string: videoUrl), let host = url.host?.lowercased() else {
            // Sometimes stored without scheme
            if videoUrl.contains("videodelivery.net") || videoUrl.contains("cloudflarestream.com") {
                return extractStreamUID(from: "https://\(videoUrl)")
            }
            return nil
        }
        guard host.contains("videodelivery.net") || host.contains("cloudflarestream.com") else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        guard let first = parts.first, !first.isEmpty else { return nil }
        // Skip file-like segments
        if first.contains(".") { return nil }
        return first
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
