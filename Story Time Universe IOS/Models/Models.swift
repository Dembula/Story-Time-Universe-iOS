import Foundation

nonisolated struct SessionUser: Codable, Equatable {
    let id: String?
    let name: String?
    let email: String?
    let image: String?
    let role: String?
}

nonisolated struct AuthSession: Codable, Equatable {
    let user: SessionUser?
    let expires: String?
}

nonisolated struct ViewerProfile: Codable, Identifiable, Equatable, Hashable {
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

nonisolated struct ProfilesResponse: Codable {
    let profiles: [ViewerProfile]
}

nonisolated struct ActiveProfileResponse: Codable {
    let profile: ViewerProfile?
    let ok: Bool?
    let error: String?
    let requiresPin: Bool?
    let paymentRequired: Bool?
}

nonisolated struct ContentItem: Codable, Identifiable, Hashable {
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
    let createdAt: String?
    let publishedAt: String?
    let isNew: Bool?

    var displayType: String {
        (type ?? "TITLE").replacingOccurrences(of: "_", with: " ").capitalized
    }

    /// True when the title is freshly uploaded / marked new for browse badges.
    var showsNewBadge: Bool {
        if isNew == true { return true }
        if let tags {
            let lower = tags.lowercased()
            if lower.contains("new") || lower.contains("#new") || lower.contains("just added") {
                return true
            }
        }
        if let date = Self.parseFlexibleDate(createdAt) ?? Self.parseFlexibleDate(publishedAt) {
            return date.timeIntervalSinceNow > -30 * 24 * 60 * 60
        }
        return false
    }

    var posterCandidates: [URL] {
        MediaURL.candidates(
            posterUrl: posterUrl,
            backdropUrl: backdropUrl,
            videoUrl: videoUrl,
            preferBackdrop: false,
            allowStreamThumbnail: false
        )
    }

    var backdropCandidates: [URL] {
        let list = MediaURL.candidates(
            posterUrl: posterUrl,
            backdropUrl: backdropUrl,
            videoUrl: videoUrl,
            preferBackdrop: true,
            allowStreamThumbnail: false
        )
        return list.isEmpty ? posterCandidates : list
    }

    /// Home hero — still artwork only (never Cloudflare Stream video frames).
    var heroBackdropCandidates: [URL] { backdropCandidates }

    var posterURL: URL? { posterCandidates.first }
    var backdropURL: URL? { backdropCandidates.first }

    static func makeURL(_ raw: String?) -> URL? {
        MediaURL.httpURL(from: raw) ?? MediaURL.previewProxyURL(from: raw)
    }

    enum CodingKeys: String, CodingKey {
        case id, title, description, type, category, year
        case posterUrl, backdropUrl, trailerUrl, videoUrl
        case duration, featured, tags, minAge
        case createdAt, publishedAt, isNew
        case created_at, published_at, is_new, newlyAdded
    }

    init(
        id: String,
        title: String,
        description: String? = nil,
        type: String? = nil,
        category: String? = nil,
        year: Int? = nil,
        posterUrl: String? = nil,
        backdropUrl: String? = nil,
        trailerUrl: String? = nil,
        videoUrl: String? = nil,
        duration: Int? = nil,
        featured: Bool? = nil,
        tags: String? = nil,
        minAge: Int? = nil,
        createdAt: String? = nil,
        publishedAt: String? = nil,
        isNew: Bool? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.type = type
        self.category = category
        self.year = year
        self.posterUrl = posterUrl
        self.backdropUrl = backdropUrl
        self.trailerUrl = trailerUrl
        self.videoUrl = videoUrl
        self.duration = duration
        self.featured = featured
        self.tags = tags
        self.minAge = minAge
        self.createdAt = createdAt
        self.publishedAt = publishedAt
        self.isNew = isNew
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        type = try c.decodeIfPresent(String.self, forKey: .type)
        category = try c.decodeIfPresent(String.self, forKey: .category)
        year = Self.decodeFlexibleInt(c, forKey: .year)
        posterUrl = try c.decodeIfPresent(String.self, forKey: .posterUrl)
        backdropUrl = try c.decodeIfPresent(String.self, forKey: .backdropUrl)
        trailerUrl = try c.decodeIfPresent(String.self, forKey: .trailerUrl)
        videoUrl = try c.decodeIfPresent(String.self, forKey: .videoUrl)
        duration = Self.decodeFlexibleInt(c, forKey: .duration)
        featured = try c.decodeIfPresent(Bool.self, forKey: .featured)
        tags = Self.decodeFlexibleString(c, forKey: .tags)
        minAge = Self.decodeFlexibleInt(c, forKey: .minAge)
        createdAt = (try? c.decodeIfPresent(String.self, forKey: .createdAt))
            ?? (try? c.decodeIfPresent(String.self, forKey: .created_at))
        publishedAt = (try? c.decodeIfPresent(String.self, forKey: .publishedAt))
            ?? (try? c.decodeIfPresent(String.self, forKey: .published_at))
        isNew = (try? c.decodeIfPresent(Bool.self, forKey: .isNew))
            ?? (try? c.decodeIfPresent(Bool.self, forKey: .is_new))
            ?? (try? c.decodeIfPresent(Bool.self, forKey: .newlyAdded))
    }

    private static func decodeFlexibleInt(_ c: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Int? {
        if let v = try? c.decodeIfPresent(Int.self, forKey: key) { return v }
        if let v = try? c.decodeIfPresent(Double.self, forKey: key) { return Int(v) }
        if let s = try? c.decodeIfPresent(String.self, forKey: key), let v = Int(s) { return v }
        return nil
    }

    private static func decodeFlexibleString(_ c: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> String? {
        if let v = try? c.decodeIfPresent(String.self, forKey: key) { return v }
        if let arr = try? c.decodeIfPresent([String].self, forKey: key) {
            return arr.joined(separator: ", ")
        }
        return nil
    }

    private static func parseFlexibleDate(_ raw: String?) -> Date? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: raw) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: raw) { return d }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        return df.date(from: String(raw.prefix(10)))
    }
}

nonisolated struct ContinueWatchingItem: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let description: String?
    let type: String?
    let category: String?
    let posterUrl: String?
    let backdropUrl: String?
    let videoUrl: String?
    let duration: Int?
    let positionSeconds: Int?
    let durationSeconds: Int?
    let progressPercent: Int?

    var posterCandidates: [URL] {
        MediaURL.candidates(
            posterUrl: posterUrl,
            backdropUrl: backdropUrl,
            videoUrl: videoUrl,
            preferBackdrop: false,
            allowStreamThumbnail: false
        )
    }

    var backdropCandidates: [URL] {
        // Continue Watching may lack stills — allow a single static stream thumb as last resort.
        let list = MediaURL.candidates(
            posterUrl: posterUrl,
            backdropUrl: backdropUrl,
            videoUrl: videoUrl,
            preferBackdrop: true,
            allowStreamThumbnail: true
        )
        return list.isEmpty ? posterCandidates : list
    }

    var posterURL: URL? { posterCandidates.first }

    var backdropURL: URL? { backdropCandidates.first ?? posterURL }

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
            videoUrl: videoUrl,
            duration: durationSeconds ?? duration,
            featured: nil,
            tags: nil,
            minAge: nil
        )
    }
}

nonisolated struct CreatorInfo: Codable, Hashable {
    let id: String?
    let name: String?
    let image: String?
}

nonisolated struct RatingStats: Codable, Hashable {
    let average: Double?
    let count: Int?
}

nonisolated struct Episode: Codable, Identifiable, Hashable {
    let id: String
    let title: String?
    let description: String?
    let episodeNumber: Int?
    let duration: Int?
    let thumbnailUrl: String?
    let videoUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, title, description, episodeNumber, duration, thumbnailUrl, videoUrl
        case episode_number, thumbnail, thumbUrl, posterUrl, video_url
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .id) {
            id = s
        } else if let i = try? c.decode(Int.self, forKey: .id) {
            id = String(i)
        } else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "Episode id missing")
        }
        title = try c.decodeIfPresent(String.self, forKey: .title)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        episodeNumber = Self.flexInt(c, .episodeNumber) ?? Self.flexInt(c, .episode_number)
        duration = Self.flexInt(c, .duration)
        thumbnailUrl = (try? c.decodeIfPresent(String.self, forKey: .thumbnailUrl))
            ?? (try? c.decodeIfPresent(String.self, forKey: .thumbnail))
            ?? (try? c.decodeIfPresent(String.self, forKey: .thumbUrl))
            ?? (try? c.decodeIfPresent(String.self, forKey: .posterUrl))
        videoUrl = (try? c.decodeIfPresent(String.self, forKey: .videoUrl))
            ?? (try? c.decodeIfPresent(String.self, forKey: .video_url))
    }

    private static func flexInt(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Int? {
        if let v = try? c.decodeIfPresent(Int.self, forKey: key) { return v }
        if let v = try? c.decodeIfPresent(Double.self, forKey: key) { return Int(v) }
        if let s = try? c.decodeIfPresent(String.self, forKey: key), let v = Int(s) { return v }
        return nil
    }
}

nonisolated struct Season: Codable, Hashable {
    let id: String?
    let seasonNumber: Int?
    let title: String?
    let episodes: [Episode]?

    var stableId: String { id ?? "season-\(seasonNumber ?? 0)" }

    enum CodingKeys: String, CodingKey {
        case id, title, episodes
        case seasonNumber, season_number, number
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decodeIfPresent(String.self, forKey: .id) {
            id = s
        } else if let i = try? c.decodeIfPresent(Int.self, forKey: .id) {
            id = String(i)
        } else {
            id = nil
        }
        title = try c.decodeIfPresent(String.self, forKey: .title)
        seasonNumber = Self.flexInt(c, .seasonNumber)
            ?? Self.flexInt(c, .season_number)
            ?? Self.flexInt(c, .number)
        episodes = Self.decodeEpisodesLossy(from: c)
    }

    private static func flexInt(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Int? {
        if let v = try? c.decodeIfPresent(Int.self, forKey: key) { return v }
        if let v = try? c.decodeIfPresent(Double.self, forKey: key) { return Int(v) }
        if let s = try? c.decodeIfPresent(String.self, forKey: key), let v = Int(s) { return v }
        return nil
    }

    private static func decodeEpisodesLossy(from c: KeyedDecodingContainer<CodingKeys>) -> [Episode]? {
        guard c.contains(.episodes) else { return nil }
        guard var unkeyed = try? c.nestedUnkeyedContainer(forKey: .episodes) else {
            return try? c.decodeIfPresent([Episode].self, forKey: .episodes)
        }
        var out: [Episode] = []
        while !unkeyed.isAtEnd {
            if let episode = try? unkeyed.decode(Episode.self) {
                out.append(episode)
            } else {
                // Skip malformed episode objects without aborting the season.
                _ = try? unkeyed.decode(LossyJSONValue.self)
            }
        }
        return out
    }
}

/// Minimal JSON value used only to advance past bad episode entries.
nonisolated private enum LossyJSONValue: Decodable {
    case null
    case bool
    case number
    case string
    case array
    case object

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer() {
            if container.decodeNil() { self = .null; return }
            if (try? container.decode(Bool.self)) != nil { self = .bool; return }
            if (try? container.decode(Double.self)) != nil { self = .number; return }
            if (try? container.decode(String.self)) != nil { self = .string; return }
        }
        if var unkeyed = try? decoder.unkeyedContainer() {
            while !unkeyed.isAtEnd { _ = try? unkeyed.decode(LossyJSONValue.self) }
            self = .array
            return
        }
        if let keyed = try? decoder.container(keyedBy: DynamicKey.self) {
            for key in keyed.allKeys { _ = try? keyed.decode(LossyJSONValue.self, forKey: key) }
            self = .object
            return
        }
        self = .null
    }

    private struct DynamicKey: CodingKey {
        var stringValue: String
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int?
        init?(intValue: Int) { self.stringValue = "\(intValue)"; self.intValue = intValue }
    }
}

nonisolated struct BtsVideo: Codable, Identifiable, Hashable {
    let id: String
    let title: String?
    let videoUrl: String?
    let thumbnail: String?

    var thumbnailCandidates: [URL] {
        MediaURL.candidates(posterUrl: thumbnail, backdropUrl: nil, videoUrl: videoUrl, preferBackdrop: false)
    }
}

nonisolated struct CrewCredit: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let role: String?
    let bio: String?
    let creditPersonId: String?

    var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let chars = parts.compactMap(\.first)
        return chars.isEmpty ? String(name.prefix(1)).uppercased() : String(chars).uppercased()
    }
}

nonisolated struct ContentDetail: Codable, Identifiable, Hashable {
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
    let language: String?
    let country: String?
    let ageRating: String?
    let creator: CreatorInfo?
    let ratingStats: RatingStats?
    let seasons: [Season]?
    let btsVideos: [BtsVideo]?

    var posterCandidates: [URL] {
        MediaURL.candidates(
            posterUrl: posterUrl,
            backdropUrl: backdropUrl,
            videoUrl: videoUrl,
            preferBackdrop: false,
            allowStreamThumbnail: false
        )
    }

    var backdropCandidates: [URL] {
        let list = MediaURL.candidates(
            posterUrl: posterUrl,
            backdropUrl: backdropUrl,
            videoUrl: videoUrl,
            preferBackdrop: true,
            allowStreamThumbnail: false
        )
        return list.isEmpty ? posterCandidates : list
    }

    var posterURL: URL? { posterCandidates.first }
    var backdropURL: URL? { backdropCandidates.first }

    var hasTrailer: Bool {
        guard let trailerUrl, !trailerUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return true
    }

    var runtimeLabel: String? {
        guard let duration, duration > 0 else { return nil }
        let hours = duration / 60
        let mins = duration % 60
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(mins) min"
    }

    /// Derive a numeric minimum age from the ageRating string (e.g. "PG-13" → 13, "18+" → 18, "R" → 17).
    var numericMinAge: Int? {
        Self.parseMinAge(from: ageRating)
    }

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
            minAge: numericMinAge
        )
    }

    static func parseMinAge(from rating: String?) -> Int? {
        guard let raw = rating?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
              !raw.isEmpty else { return nil }

        let digits = raw.filter(\.isNumber)
        if let num = Int(digits), num > 0, num <= 21 { return num }

        switch raw {
        case "G", "U", "ALL", "EVERYONE", "TV-Y", "TV-Y7", "TV-G":
            return 0
        case "PG", "TV-PG":
            return 7
        case "PG-13", "TV-14", "12A", "12":
            return 13
        case "R", "M", "MA15+", "15", "TV-MA":
            return 17
        case "NC-17", "X", "18", "18+", "ADULTS", "AO":
            return 18
        default:
            return nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, title, description, type, category, year
        case posterUrl, backdropUrl, trailerUrl, videoUrl
        case duration, tags, language, country, ageRating
        case creator, ratingStats, seasons, btsVideos
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        type = try c.decodeIfPresent(String.self, forKey: .type)
        category = try c.decodeIfPresent(String.self, forKey: .category)
        if let y = try? c.decodeIfPresent(Int.self, forKey: .year) {
            year = y
        } else if let y = try? c.decodeIfPresent(Double.self, forKey: .year) {
            year = Int(y)
        } else {
            year = nil
        }
        posterUrl = try c.decodeIfPresent(String.self, forKey: .posterUrl)
        backdropUrl = try c.decodeIfPresent(String.self, forKey: .backdropUrl)
        trailerUrl = try c.decodeIfPresent(String.self, forKey: .trailerUrl)
        videoUrl = try c.decodeIfPresent(String.self, forKey: .videoUrl)
        if let d = try? c.decodeIfPresent(Int.self, forKey: .duration) {
            duration = d
        } else if let d = try? c.decodeIfPresent(Double.self, forKey: .duration) {
            duration = Int(d)
        } else {
            duration = nil
        }
        if let t = try? c.decodeIfPresent(String.self, forKey: .tags) {
            tags = t
        } else if let arr = try? c.decodeIfPresent([String].self, forKey: .tags) {
            tags = arr.joined(separator: ", ")
        } else {
            tags = nil
        }
        language = try c.decodeIfPresent(String.self, forKey: .language)
        country = try c.decodeIfPresent(String.self, forKey: .country)
        ageRating = try c.decodeIfPresent(String.self, forKey: .ageRating)
        creator = try c.decodeIfPresent(CreatorInfo.self, forKey: .creator)
        ratingStats = try c.decodeIfPresent(RatingStats.self, forKey: .ratingStats)
        // Soft-decode seasons so one bad episode doesn't wipe the whole series list.
        if let decoded = try? c.decodeIfPresent([Season].self, forKey: .seasons) {
            seasons = decoded
        } else {
            seasons = nil
        }
        btsVideos = try c.decodeIfPresent([BtsVideo].self, forKey: .btsVideos)
    }
}

nonisolated struct PlaybackSource: Codable, Hashable {
    let src: String?
    let type: String?
}

nonisolated struct SubtitleTrack: Codable, Identifiable, Hashable {
    let id: String
    let language: String?
    let label: String?
    let vttUrl: String?
    let isDefault: Bool?

    enum CodingKeys: String, CodingKey {
        case id, language, label, vttUrl, isDefault
        case url, src, fileUrl, subtitleUrl, defaultTrack
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .id) {
            id = s
        } else if let i = try? c.decode(Int.self, forKey: .id) {
            id = String(i)
        } else {
            id = UUID().uuidString
        }
        language = try c.decodeIfPresent(String.self, forKey: .language)
        label = try c.decodeIfPresent(String.self, forKey: .label)
        vttUrl = (try? c.decodeIfPresent(String.self, forKey: .vttUrl))
            ?? (try? c.decodeIfPresent(String.self, forKey: .url))
            ?? (try? c.decodeIfPresent(String.self, forKey: .src))
            ?? (try? c.decodeIfPresent(String.self, forKey: .fileUrl))
            ?? (try? c.decodeIfPresent(String.self, forKey: .subtitleUrl))
        isDefault = (try? c.decodeIfPresent(Bool.self, forKey: .isDefault))
            ?? (try? c.decodeIfPresent(Bool.self, forKey: .defaultTrack))
    }
}

nonisolated struct PlaybackBundle: Codable, Hashable {
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

nonisolated struct WatchlistItem: Codable, Hashable {
    let id: String?
    let contentId: String?
    let content: ContentItem?
}

nonisolated struct SearchResponse: Codable {
    let results: [SearchResult]
}

nonisolated struct SearchResult: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let type: String?
    let category: String?
    let year: Int?
    let posterUrl: String?
    let creatorName: String?

    var posterCandidates: [URL] {
        MediaURL.candidates(posterUrl: posterUrl, backdropUrl: nil, videoUrl: nil, preferBackdrop: false)
    }

    var posterURL: URL? { posterCandidates.first }

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

extension ContentItem {
    var asSearchResult: SearchResult {
        SearchResult(
            id: id,
            title: title,
            type: type,
            category: category,
            year: year,
            posterUrl: posterUrl,
            creatorName: nil
        )
    }
}

nonisolated struct AISearchPayload: Codable {
    let results: [SearchResult]?
    let items: [SearchResult]?
    let reasoning: String?
    let explanation: String?
    let suggestions: [String]?

    var resolvedResults: [SearchResult] { results ?? items ?? [] }
    var resolvedReasoning: String? { reasoning ?? explanation }
}

nonisolated struct AISearchResult: Hashable {
    let results: [SearchResult]
    let reasoning: String?
    let suggestions: [String]
    let usedFallback: Bool
    /// Horizontal rows for the Netflix-style AI UI (Top Results, genre lanes, etc.).
    let sections: [AISearchSection]
    /// True when the user asked for something we can't honestly fulfill from the catalogue.
    let unmetIntent: Bool

    init(
        results: [SearchResult],
        reasoning: String?,
        suggestions: [String],
        usedFallback: Bool,
        sections: [AISearchSection] = [],
        unmetIntent: Bool = false
    ) {
        self.results = results
        self.reasoning = reasoning
        self.suggestions = suggestions
        self.usedFallback = usedFallback
        self.sections = sections.isEmpty && !results.isEmpty
            ? [AISearchSection(title: "Top Results", results: Array(results.prefix(12)))]
            : sections
        self.unmetIntent = unmetIntent
    }
}

nonisolated struct AISearchSection: Hashable, Identifiable {
    var id: String { title }
    let title: String
    let results: [SearchResult]
}

nonisolated struct ViewerSubscription: Codable, Hashable {
    let id: String?
    let plan: String?
    let status: String?
    let viewerModel: String?
    let profileLimit: Int?
    let deviceCount: Int?
    let currentPeriodEnd: String?
    let cancelAtPeriodEnd: Bool?
}

nonisolated struct SubscriptionResponse: Codable {
    let subscription: ViewerSubscription?
}

nonisolated struct APIErrorBody: Codable {
    let error: String?
    let requiresPin: Bool?
    let paymentRequired: Bool?
}

// MARK: - Person / credits (matches web PersonPreview)

nonisolated struct PersonPreview: Codable, Identifiable, Hashable {
    var id: String { personId }
    let personId: String
    let displayName: String
    let imageUrl: String?
    let roles: [String]?
    let bio: String?
    let blurb: String?
    let productionCount: Int?
    let followerCount: Int?
    let followingCount: Int?
    let verified: Bool?
    let profileHref: String?
    let latestProject: PersonLatestProject?
    let topGenres: [String]?
    let isCreator: Bool?
    let creatorUserId: String?
    let credits: [PersonCredit]?

    var imageCandidates: [URL] {
        MediaURL.candidates(posterUrl: imageUrl, backdropUrl: nil, videoUrl: nil, preferBackdrop: false)
    }

    var initials: String {
        let parts = displayName.split(separator: " ").prefix(2)
        let chars = parts.compactMap(\.first)
        return chars.isEmpty ? String(displayName.prefix(1)).uppercased() : String(chars).uppercased()
    }
}

nonisolated struct PersonLatestProject: Codable, Hashable {
    let id: String
    let title: String
    let type: String?
    let posterUrl: String?
}

nonisolated struct PersonCredit: Codable, Identifiable, Hashable {
    var id: String { "\(contentId)-\(role)" }
    let contentId: String
    let title: String
    let type: String?
    let role: String
    let posterUrl: String?
    let year: Int?

    var posterCandidates: [URL] {
        MediaURL.candidates(posterUrl: posterUrl, backdropUrl: nil, videoUrl: nil, preferBackdrop: false)
    }

    var asContentItem: ContentItem {
        ContentItem(
            id: contentId,
            title: title,
            description: nil,
            type: type,
            category: nil,
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

/// Navigation payload when tapping a cast/crew credit.
nonisolated struct PersonRoute: Hashable, Identifiable {
    var id: String { personId ?? crewMemberId ?? fallbackName }
    var personId: String?
    var crewMemberId: String?
    var fallbackName: String
    var fallbackRole: String?
    var fallbackBio: String?

    init(from member: CrewCredit) {
        personId = member.creditPersonId
        crewMemberId = member.id
        fallbackName = member.name
        fallbackRole = member.role
        fallbackBio = member.bio
    }
}
