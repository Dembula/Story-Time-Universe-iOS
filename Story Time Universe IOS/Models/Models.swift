import Foundation

struct SessionUser: Codable, Equatable {
    let id: String?
    let name: String?
    let email: String?
    let image: String?
    let role: String?
}

struct AuthSession: Codable, Equatable {
    let user: SessionUser?
    let expires: String?
}

struct ViewerProfile: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let age: Int
    let dateOfBirth: String?
    let updatedAt: String?
    let pinEnabled: Bool?

    var isKids: Bool { age <= 12 }

    var ageLabel: String {
        if age <= 12 { return "Kids" }
        if age <= 15 { return "Teen" }
        return "Adult"
    }
}

struct ProfilesResponse: Codable {
    let profiles: [ViewerProfile]
}

struct ActiveProfileResponse: Codable {
    let profile: ViewerProfile?
    let ok: Bool?
    let error: String?
    let requiresPin: Bool?
    let paymentRequired: Bool?
}

struct ContentItem: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let description: String?
    let type: String?
    let category: String?
    let year: Int?
    let posterUrl: String?
    let backdropUrl: String?
    let trailerUrl: String?
    let videoUrl: String?
    let duration: Int?
    let featured: Bool?
    let tags: String?
    let minAge: Int?

    var displayType: String {
        (type ?? "TITLE").replacingOccurrences(of: "_", with: " ").capitalized
    }

    var posterURL: URL? { Self.makeURL(posterUrl) }
    var backdropURL: URL? { Self.makeURL(backdropUrl) ?? posterURL }

    static func makeURL(_ raw: String?) -> URL? {
        guard let raw, !raw.isEmpty else { return nil }
        if raw.hasPrefix("http") { return URL(string: raw) }
        if raw.hasPrefix("/") {
            return URL(string: raw, relativeTo: AppConfig.apiBaseURL)?.absoluteURL
        }
        return URL(string: raw)
    }
}

struct ContinueWatchingItem: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let description: String?
    let type: String?
    let category: String?
    let posterUrl: String?
    let backdropUrl: String?
    let duration: Int?
    let positionSeconds: Int?
    let durationSeconds: Int?
    let progressPercent: Int?

    var posterURL: URL? { ContentItem.makeURL(posterUrl) }
    var backdropURL: URL? { ContentItem.makeURL(backdropUrl) ?? posterURL }

    var progress: Double {
        if let percent = progressPercent { return min(1, max(0, Double(percent) / 100)) }
        let pos = Double(positionSeconds ?? 0)
        let dur = Double(durationSeconds ?? duration ?? 0)
        guard dur > 0 else { return 0 }
        return min(1, max(0, pos / dur))
    }

    var asContentItem: ContentItem {
        ContentItem(
            id: id,
            title: title,
            description: description,
            type: type,
            category: category,
            year: nil,
            posterUrl: posterUrl,
            backdropUrl: backdropUrl,
            trailerUrl: nil,
            videoUrl: nil,
            duration: durationSeconds ?? duration,
            featured: nil,
            tags: nil,
            minAge: nil
        )
    }
}

struct CreatorInfo: Codable, Hashable {
    let id: String?
    let name: String?
    let image: String?
}

struct RatingStats: Codable, Hashable {
    let average: Double?
    let count: Int?
}

struct Episode: Codable, Identifiable, Hashable {
    let id: String
    let title: String?
    let description: String?
    let episodeNumber: Int?
    let duration: Int?
    let thumbnailUrl: String?
    let videoUrl: String?
}

struct Season: Codable, Hashable {
    let id: String?
    let seasonNumber: Int?
    let title: String?
    let episodes: [Episode]?

    var stableId: String { id ?? "season-\(seasonNumber ?? 0)" }
}

struct ContentDetail: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let description: String?
    let type: String?
    let category: String?
    let year: Int?
    let posterUrl: String?
    let backdropUrl: String?
    let trailerUrl: String?
    let videoUrl: String?
    let duration: Int?
    let tags: String?
    let creator: CreatorInfo?
    let ratingStats: RatingStats?
    let seasons: [Season]?

    var posterURL: URL? { ContentItem.makeURL(posterUrl) }
    var backdropURL: URL? { ContentItem.makeURL(backdropUrl) ?? posterURL }

    var asContentItem: ContentItem {
        ContentItem(
            id: id,
            title: title,
            description: description,
            type: type,
            category: category,
            year: year,
            posterUrl: posterUrl,
            backdropUrl: backdropUrl,
            trailerUrl: trailerUrl,
            videoUrl: videoUrl,
            duration: duration,
            featured: nil,
            tags: tags,
            minAge: nil
        )
    }
}

struct PlaybackSource: Codable, Hashable {
    let src: String?
    let type: String?
}

struct SubtitleTrack: Codable, Identifiable, Hashable {
    let id: String
    let language: String?
    let label: String?
    let vttUrl: String?
    let isDefault: Bool?
}

struct PlaybackBundle: Codable, Hashable {
    let id: String?
    let title: String?
    let playback: PlaybackSource?
    let posterUrl: String?
    let duration: Int?
    let subtitles: [SubtitleTrack]?

    var streamURL: URL? {
        guard let src = playback?.src, !src.isEmpty else { return nil }
        if src.hasPrefix("http") { return URL(string: src) }
        return URL(string: src, relativeTo: AppConfig.apiBaseURL)?.absoluteURL
    }
}

struct WatchlistItem: Codable, Hashable {
    let id: String?
    let contentId: String?
    let content: ContentItem?
}

struct SearchResponse: Codable {
    let results: [SearchResult]
}

struct SearchResult: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let type: String?
    let category: String?
    let year: Int?
    let posterUrl: String?
    let creatorName: String?

    var posterURL: URL? { ContentItem.makeURL(posterUrl) }

    var asContentItem: ContentItem {
        ContentItem(
            id: id,
            title: title,
            description: nil,
            type: type,
            category: category,
            year: year,
            posterUrl: posterUrl,
            backdropUrl: nil,
            trailerUrl: nil,
            videoUrl: nil,
            duration: nil,
            featured: nil,
            tags: nil,
            minAge: nil
        )
    }
}

struct ViewerSubscription: Codable, Hashable {
    let id: String?
    let plan: String?
    let status: String?
    let viewerModel: String?
    let profileLimit: Int?
    let deviceCount: Int?
    let currentPeriodEnd: String?
    let cancelAtPeriodEnd: Bool?
}

struct SubscriptionResponse: Codable {
    let subscription: ViewerSubscription?
}

struct APIErrorBody: Codable {
    let error: String?
    let requiresPin: Bool?
    let paymentRequired: Bool?
}
