import Foundation

enum MediaURL {
    /// Resolve a catalogue image URL the way the web app does:
    /// prefer https artwork, then Cloudflare Stream thumbnail from `videoUrl`.
    static func resolve(
        posterUrl: String?,
        backdropUrl: String? = nil,
        videoUrl: String? = nil,
        preferBackdrop: Bool = false
    ) -> URL? {
        let primary = preferBackdrop ? backdropUrl : posterUrl
        let secondary = preferBackdrop ? posterUrl : backdropUrl

        if let url = httpURL(from: primary) { return url }
        if let url = httpURL(from: secondary) { return url }
        if let url = previewProxyURL(from: primary) { return url }
        if let url = previewProxyURL(from: secondary) { return url }
        if let url = streamThumbnailURL(from: videoUrl, time: preferBackdrop ? "5s" : "3s", height: preferBackdrop ? 720 : 480) {
            return url
        }
        return nil
    }

    static func httpURL(from raw: String?) -> URL? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if raw.lowercased().hasPrefix("https://") || raw.lowercased().hasPrefix("http://") {
            if isStreamPlaybackURL(raw) { return nil }
            return URL(string: raw)
        }
        if raw.hasPrefix("/") {
            return URL(string: raw, relativeTo: AppConfig.apiBaseURL)?.absoluteURL
        }
        return nil
    }

    /// Authenticated storage preview for `s3://` refs (cookies via shared storage).
    static func previewProxyURL(from raw: String?) -> URL? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        guard raw.hasPrefix("s3://") || raw.contains(".amazonaws.com/") else { return nil }
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
        guard let url = URL(string: videoUrl), let host = url.host?.lowercased() else { return nil }
        guard host.contains("videodelivery.net") || host.contains("cloudflarestream.com") else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        guard let first = parts.first, !first.isEmpty, first.split(separator: ".").count < 3 else { return nil }
        return first
    }

    private static func isStreamPlaybackURL(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        return lower.contains("manifest/video") || lower.hasSuffix(".m3u8") || lower.hasSuffix(".mpd")
    }
}
