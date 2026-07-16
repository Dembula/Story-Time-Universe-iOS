import Foundation

actor ViewerAPI {
    static let shared = ViewerAPI()
    private let api = APIClient.shared

    // MARK: Profiles

    func fetchProfiles() async throws -> [ViewerProfile] {
        let (data, response) = try await api.request(path: "api/viewer/profiles")
        guard response.statusCode == 200 else { throw api.parseAPIError(data: data, status: response.statusCode) }
        return try api.decode(ProfilesResponse.self, from: data).profiles
    }

    func activateProfile(id: String, pin: String? = nil) async throws -> ViewerProfile {
        var body: [String: Any] = ["profileId": id]
        if let pin, !pin.isEmpty { body["pin"] = pin }
        let (data, response) = try await api.request(
            path: "api/viewer/profiles/active",
            method: "POST",
            jsonBody: body
        )
        if response.statusCode == 402 {
            throw api.parseAPIError(data: data, status: response.statusCode)
        }
        if response.statusCode == 401 || response.statusCode == 403 {
            let err = try? api.decode(APIErrorBody.self, from: data)
            if err?.requiresPin == true {
                throw APIError.server(err?.error ?? "PIN required")
            }
            throw api.parseAPIError(data: data, status: response.statusCode)
        }
        guard (200...299).contains(response.statusCode) else {
            throw api.parseAPIError(data: data, status: response.statusCode)
        }
        let decoded = try api.decode(ActiveProfileResponse.self, from: data)
        guard let profile = decoded.profile else {
            throw APIError.server(decoded.error ?? "Failed to select profile")
        }
        api.setViewerProfileCookie(profile.id)
        return profile
    }

    func createProfile(name: String, birthYear: Int, birthMonth: Int, birthDay: Int, pin: String?) async throws -> ViewerProfile {
        var body: [String: Any] = [
            "name": name,
            "birthYear": birthYear,
            "birthMonth": birthMonth,
            "birthDay": birthDay,
        ]
        if let pin, pin.count == 4 {
            body["pinEnabled"] = true
            body["pin"] = pin
        }
        let (data, response) = try await api.request(
            path: "api/viewer/profiles",
            method: "POST",
            jsonBody: body
        )
        guard (200...299).contains(response.statusCode) else {
            throw api.parseAPIError(data: data, status: response.statusCode)
        }
        struct Wrap: Codable { let profile: ViewerProfile }
        return try api.decode(Wrap.self, from: data).profile
    }

    // MARK: Catalogue

    func fetchContent(type: String? = nil, featured: Bool = false, category: String? = nil, limit: Int = 20) async throws -> [ContentItem] {
        var query: [URLQueryItem] = [URLQueryItem(name: "limit", value: String(limit))]
        if let type { query.append(URLQueryItem(name: "type", value: type)) }
        if featured { query.append(URLQueryItem(name: "featured", value: "true")) }
        if let category { query.append(URLQueryItem(name: "category", value: category)) }
        let (data, response) = try await api.request(path: "api/content", query: query)
        guard response.statusCode == 200 else { throw api.parseAPIError(data: data, status: response.statusCode) }
        return Self.decodeContentList(data)
    }

    /// Decode catalogue items one-by-one so a single bad row cannot blank the whole UI.
    nonisolated private static func decodeContentList(_ data: Data) -> [ContentItem] {
        let decoder = JSONDecoder()
        if let all = try? decoder.decode([ContentItem].self, from: data) {
            return all
        }
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return array.compactMap { row in
            guard let rowData = try? JSONSerialization.data(withJSONObject: row) else { return nil }
            return try? decoder.decode(ContentItem.self, from: rowData)
        }
    }

    func fetchContinueWatching() async throws -> [ContinueWatchingItem] {
        let (data, response) = try await api.request(path: "api/watch/continue-watching")
        guard response.statusCode == 200 else { return [] }
        return (try? api.decode([ContinueWatchingItem].self, from: data)) ?? []
    }

    func fetchContentDetail(id: String) async throws -> ContentDetail {
        let (data, response) = try await api.request(path: "api/content/\(id)")
        guard response.statusCode == 200 else { throw api.parseAPIError(data: data, status: response.statusCode) }
        return try api.decode(ContentDetail.self, from: data)
    }

    func fetchPlaybackBundle(contentId: String, episodeId: String? = nil, trailer: Bool = false) async throws -> PlaybackBundle {
        var query: [URLQueryItem] = []
        if let episodeId { query.append(URLQueryItem(name: "episodeId", value: episodeId)) }
        if trailer { query.append(URLQueryItem(name: "trailer", value: "1")) }
        let (data, response) = try await api.request(
            path: "api/content/\(contentId)/playback-bundle",
            query: query
        )
        guard response.statusCode == 200 else { throw api.parseAPIError(data: data, status: response.statusCode) }
        return try api.decode(PlaybackBundle.self, from: data)
    }

    func fetchWatchProgress(contentId: String) async throws -> (position: Int, duration: Int?) {
        let (data, response) = try await api.request(
            path: "api/watch/progress",
            query: [URLQueryItem(name: "contentId", value: contentId)]
        )
        guard response.statusCode == 200 else { return (0, nil) }
        struct Progress: Codable {
            let positionSeconds: Int?
            let durationSeconds: Int?
        }
        let progress = try api.decode(Progress.self, from: data)
        return (progress.positionSeconds ?? 0, progress.durationSeconds)
    }

    func saveWatchProgress(contentId: String, positionSeconds: Double, durationSeconds: Double?) async {
        var body: [String: Any] = [
            "contentId": contentId,
            "positionSeconds": positionSeconds,
        ]
        if let durationSeconds { body["durationSeconds"] = durationSeconds }
        _ = try? await api.request(path: "api/watch/progress", method: "PUT", jsonBody: body)
    }

    func recordWatchSession(contentId: String, durationSeconds: Double) async {
        _ = try? await api.request(
            path: "api/watch",
            method: "POST",
            jsonBody: [
                "contentId": contentId,
                "durationSeconds": durationSeconds,
            ]
        )
    }

    func search(query: String) async throws -> [SearchResult] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return [] }
        let (data, response) = try await api.request(
            path: "api/browse/search",
            query: [
                URLQueryItem(name: "q", value: q),
                URLQueryItem(name: "limit", value: "24"),
            ]
        )
        guard response.statusCode == 200 else { return [] }
        return try api.decode(SearchResponse.self, from: data).results
    }

    func fetchWatchlist() async throws -> [ContentItem] {
        let (data, response) = try await api.request(path: "api/watchlist")
        guard response.statusCode == 200 else { throw api.parseAPIError(data: data, status: response.statusCode) }
        // Response is array of { content: ContentItem }
        struct Row: Codable { let content: ContentItem? }
        let rows = (try? api.decode([Row].self, from: data)) ?? []
        return rows.compactMap(\.content)
    }

    func updateWatchlist(contentId: String, add: Bool) async throws {
        let (data, response) = try await api.request(
            path: "api/watchlist",
            method: "POST",
            jsonBody: [
                "contentId": contentId,
                "action": add ? "add" : "remove",
            ]
        )
        guard (200...299).contains(response.statusCode) else {
            throw api.parseAPIError(data: data, status: response.statusCode)
        }
    }

    func fetchSubscription() async throws -> ViewerSubscription? {
        let (data, response) = try await api.request(path: "api/viewer/subscription")
        guard response.statusCode == 200 else { return nil }
        return try api.decode(SubscriptionResponse.self, from: data).subscription
    }
}
