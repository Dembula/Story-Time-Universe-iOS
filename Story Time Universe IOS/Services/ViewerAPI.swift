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

    /// Fetch one Home row that may span multiple `type` values (and optional category).
    func fetchCatalogRow(definition: CatalogueTypes.RowDefinition, limit: Int = 16) async -> [ContentItem] {
        if definition.typeValues.count == 1, definition.categoryFilter == nil {
            return (try? await fetchContent(type: definition.typeValues[0], limit: limit)) ?? []
        }

        var combined: [ContentItem] = []
        var seen = Set<String>()

        for typeValue in definition.typeValues {
            let batch = (try? await fetchContent(
                type: typeValue,
                category: definition.categoryFilter,
                limit: limit
            )) ?? []
            for item in batch where seen.insert(item.id).inserted {
                combined.append(item)
            }
            if combined.count >= limit { break }
        }

        // Category-only fallback if type+category returned nothing (API may AND filters tightly).
        if combined.isEmpty, let category = definition.categoryFilter {
            let byCategory = (try? await fetchContent(category: category, limit: limit)) ?? []
            for item in byCategory {
                let type = item.type?.uppercased() ?? ""
                if definition.typeValues.isEmpty || definition.typeValues.contains(type) {
                    if seen.insert(item.id).inserted {
                        combined.append(item)
                    }
                }
            }
        }

        return Array(combined.prefix(limit))
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

    func fetchCrew(contentId: String) async throws -> [CrewCredit] {
        let (data, response) = try await api.request(
            path: "api/crew",
            query: [URLQueryItem(name: "contentId", value: contentId)]
        )
        guard response.statusCode == 200 else { return [] }
        return (try? api.decode([CrewCredit].self, from: data)) ?? []
    }

    /// Web person card — `GET /api/people/{personId}/preview`
    func fetchPersonPreview(personId: String) async throws -> PersonPreview {
        let (data, response) = try await api.request(path: "api/people/\(personId)/preview")
        guard response.statusCode == 200 else { throw api.parseAPIError(data: data, status: response.statusCode) }
        return try api.decode(PersonPreview.self, from: data)
    }

    /// Resolve via crew member id — `GET /api/people/preview?crewMemberId=`
    func fetchPersonPreview(crewMemberId: String) async throws -> PersonPreview {
        let (data, response) = try await api.request(
            path: "api/people/preview",
            query: [URLQueryItem(name: "crewMemberId", value: crewMemberId)]
        )
        guard response.statusCode == 200 else { throw api.parseAPIError(data: data, status: response.statusCode) }
        return try api.decode(PersonPreview.self, from: data)
    }

    func fetchPerson(route: PersonRoute) async throws -> PersonPreview {
        if let personId = route.personId, !personId.isEmpty {
            do {
                return try await fetchPersonPreview(personId: personId)
            } catch {
                if let crewMemberId = route.crewMemberId, !crewMemberId.isEmpty {
                    return try await fetchPersonPreview(crewMemberId: crewMemberId)
                }
                throw error
            }
        }
        if let crewMemberId = route.crewMemberId, !crewMemberId.isEmpty {
            return try await fetchPersonPreview(crewMemberId: crewMemberId)
        }
        throw APIError.server("No person profile is linked to this credit.")
    }

    func fetchRelated(excluding id: String, category: String?, type: String?, limit: Int = 12) async throws -> [ContentItem] {
        var items: [ContentItem] = []
        if let category, !category.isEmpty {
            items = try await fetchContent(category: category, limit: limit + 4)
        }
        if items.count < 4, let type {
            let byType = try await fetchContent(type: type, limit: limit + 4)
            items.append(contentsOf: byType)
        }
        if items.isEmpty {
            items = try await fetchContent(limit: limit + 4)
        }
        var seen = Set<String>()
        return items.filter { item in
            guard item.id != id else { return false }
            return seen.insert(item.id).inserted
        }
        .prefix(limit)
        .map { $0 }
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

    /// Pay Per View unlock. Production creates a PENDING access row; when the title is not
    /// already owned, iOS routes the user to StoreKit instead of any web `checkoutUrl`.
    func requestPpvAccess(contentId: String) async throws -> PpvCheckoutResponse {
        let (data, response) = try await api.request(
            path: "api/viewer/ppv",
            method: "POST",
            jsonBody: ["contentId": contentId]
        )
        if !(200...299).contains(response.statusCode) {
            throw api.parseAPIError(data: data, status: response.statusCode)
        }
        return try api.decode(PpvCheckoutResponse.self, from: data)
    }

    /// Gate Play for PPV accounts before opening the player.
    /// iOS never surfaces web/PayFast checkout URLs (App Store 3.1.1) — only StoreKit unlock.
    func resolveTitleAccess(contentId: String, isPayPerViewAccount: Bool, isTrailer: Bool) async -> TitleAccessResult {
        if isTrailer { return .playable }
        guard isPayPerViewAccount else { return .playable }

        do {
            let result = try await requestPpvAccess(contentId: contentId)
            if result.alreadyOwned == true {
                return .playable
            }
            // Any server request for payment becomes an in-app purchase path on iOS.
            if result.requiresPayment == true
                || result.checkoutURL != nil
                || result.success == false
            {
                return .requiresInAppPurchase(contentId: contentId)
            }
            return .playable
        } catch let error as APIError {
            if case .paymentRequired = error {
                return .requiresInAppPurchase(contentId: contentId)
            }
            return .blocked(error.localizedDescription)
        } catch {
            return .blocked(error.localizedDescription)
        }
    }

    // MARK: - Apple In-App Purchase activation

    /// Attach a verified App Store subscription transaction to the signed-in viewer.
    /// Production endpoint contract (implement on web):
    /// `POST /api/viewer/apple/activate` with signed transaction fields → activates plan.
    func activateAppleSubscription(
        productId: String,
        transactionId: String,
        originalTransactionId: String,
        signedTransactionInfo: String,
        environment: String,
        planCode: String
    ) async throws {
        let body: [String: Any] = [
            "productId": productId,
            "transactionId": transactionId,
            "originalTransactionId": originalTransactionId,
            "signedTransactionInfo": signedTransactionInfo,
            "jwsRepresentation": signedTransactionInfo,
            "environment": environment,
            "plan": planCode,
            "planCode": planCode,
            "platform": "ios",
            "source": "ios_app",
        ]
        try await postAppleActivate(candidates: [
            "api/viewer/apple/activate",
            "api/viewer/apple/subscription",
            "api/viewer/iap/subscription",
            "api/billing/apple/activate",
            "api/payments/apple/activate",
        ], body: body)
    }

    /// Attach a verified App Store PPV consumable to a content id.
    func activateApplePPV(
        contentId: String,
        productId: String,
        transactionId: String,
        originalTransactionId: String,
        signedTransactionInfo: String,
        environment: String
    ) async throws {
        let body: [String: Any] = [
            "contentId": contentId,
            "productId": productId,
            "transactionId": transactionId,
            "originalTransactionId": originalTransactionId,
            "signedTransactionInfo": signedTransactionInfo,
            "jwsRepresentation": signedTransactionInfo,
            "environment": environment,
            "platform": "ios",
            "source": "ios_app",
            "kind": "ppv",
        ]
        try await postAppleActivate(candidates: [
            "api/viewer/apple/ppv",
            "api/viewer/apple/activate",
            "api/viewer/iap/ppv",
            "api/billing/apple/ppv",
            "api/payments/apple/ppv",
        ], body: body)
    }

    /// Tries known endpoints; succeeds on first 2xx. Treats 404 as “try next”.
    private func postAppleActivate(candidates: [String], body: [String: Any]) async throws {
        var lastError: Error = APIError.server("Apple purchase could not be linked to your account.")
        var sawNotFound = true
        for path in candidates {
            do {
                let (data, response) = try await api.request(path: path, method: "POST", jsonBody: body)
                if (200...299).contains(response.statusCode) {
                    return
                }
                if response.statusCode == 404 || response.statusCode == 405 {
                    continue
                }
                sawNotFound = false
                lastError = api.parseAPIError(data: data, status: response.statusCode)
            } catch {
                lastError = error
                sawNotFound = false
            }
        }
        if sawNotFound {
            // Backend not deployed yet — still surface a clear operator message.
            // StoreKit transaction remains unfinished only when activate throws before finish;
            // callers that need strict gate should fail. We fail closed with guidance.
            throw APIError.server(
                "Purchase succeeded with Apple, but account activation is not ready yet. Contact support@story-time.online with your Apple receipt."
            )
        }
        throw lastError
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
        // Extra analytics so admin/creator dashboards can attribute iOS app views.
        _ = try? await api.request(
            path: "api/analytics/events",
            method: "POST",
            jsonBody: [
                "name": "watch_session_ios",
                "path": "/ios/player/\(contentId)",
                "properties": [
                    "contentId": contentId,
                    "durationSeconds": durationSeconds,
                    "platform": DeviceIdentity.platform,
                    "device": DeviceIdentity.deviceSummary,
                    "client": "StoryTimeUniverseiOS",
                ],
                "clientTs": ISO8601DateFormatter().string(from: Date()),
            ]
        )
    }

    /// Admin activity log entry (device + UA) — production `POST /api/session/telemetry`.
    func reportSessionTelemetry() async {
        _ = try? await api.request(path: "api/session/telemetry", method: "POST", jsonBody: [:])
        _ = try? await api.request(
            path: "api/analytics/events",
            method: "POST",
            jsonBody: [
                "name": "app_open_ios",
                "path": "/ios",
                "properties": [
                    "platform": DeviceIdentity.platform,
                    "device": DeviceIdentity.deviceSummary,
                    "client": "StoryTimeUniverseiOS",
                ],
                "clientTs": ISO8601DateFormatter().string(from: Date()),
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

    /// Production AI search with path fallbacks; enhanced catalogue matching if routes 404.
    func aiSearch(query: String, limit: Int = 24) async throws -> AISearchResult {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else {
            return AISearchResult(results: [], reasoning: nil, suggestions: [], usedFallback: false)
        }

        let paths = [
            "api/viewer/ai/search",
            "api/browse/ai/search",
            "api/ai/viewer/search",
        ]
        let bodies: [[String: Any]] = [
            ["query": q, "limit": limit],
            ["q": q, "limit": limit],
            ["prompt": q, "limit": limit],
        ]

        for path in paths {
            for body in bodies {
                do {
                    let (data, response) = try await api.request(path: path, method: "POST", jsonBody: body)
                    if response.statusCode == 404 { break } // try next path
                    guard (200...299).contains(response.statusCode) else { continue }
                    if let payload = try? api.decode(AISearchPayload.self, from: data) {
                        let results = payload.resolvedResults
                        if !results.isEmpty || payload.resolvedReasoning != nil || !(payload.suggestions ?? []).isEmpty {
                            // Weak / off-genre remote payloads fall through to local honesty.
                            let intent = Self.detectSearchIntent(q)
                            if !Self.fulfillsIntent(results, intent: intent, prompt: q) {
                                break
                            }
                            var suggestions = payload.suggestions ?? []
                            if suggestions.isEmpty {
                                suggestions = Self.contextualSuggestions(for: q, results: results)
                            }
                            let trimmed = Array(results.prefix(limit))
                            return AISearchResult(
                                results: trimmed,
                                reasoning: payload.resolvedReasoning
                                    ?? Self.buildAIReport(
                                        prompt: q,
                                        results: trimmed,
                                        searchLenses: Self.expandPromptTerms(q),
                                        usedRemoteAI: true
                                    ),
                                suggestions: suggestions,
                                usedFallback: false,
                                sections: Self.buildResultSections(trimmed, intent: intent)
                            )
                        }
                    }
                    if let search = try? api.decode(SearchResponse.self, from: data), !search.results.isEmpty {
                        let intent = Self.detectSearchIntent(q)
                        if !Self.fulfillsIntent(search.results, intent: intent, prompt: q) {
                            continue
                        }
                        return AISearchResult(
                            results: Array(search.results.prefix(limit)),
                            reasoning: Self.buildAIReport(
                                prompt: q,
                                results: search.results,
                                searchLenses: Self.expandPromptTerms(q),
                                usedRemoteAI: true
                            ),
                            suggestions: Self.contextualSuggestions(for: q, results: search.results),
                            usedFallback: false,
                            sections: Self.buildResultSections(Array(search.results.prefix(limit)), intent: intent)
                        )
                    }
                } catch {
                    continue
                }
            }
        }

        // Also try GET variants some backends expose.
        for path in paths {
            do {
                let (data, response) = try await api.request(
                    path: path,
                    query: [
                        URLQueryItem(name: "q", value: q),
                        URLQueryItem(name: "query", value: q),
                        URLQueryItem(name: "limit", value: String(limit)),
                    ]
                )
                if response.statusCode == 404 { continue }
                guard (200...299).contains(response.statusCode) else { continue }
                if let payload = try? api.decode(AISearchPayload.self, from: data),
                   !payload.resolvedResults.isEmpty {
                    let intent = Self.detectSearchIntent(q)
                    if !Self.fulfillsIntent(payload.resolvedResults, intent: intent, prompt: q) {
                        continue
                    }
                    return AISearchResult(
                        results: Array(payload.resolvedResults.prefix(limit)),
                        reasoning: payload.resolvedReasoning ?? Self.buildAIReport(
                            prompt: q,
                            results: payload.resolvedResults,
                            searchLenses: Self.expandPromptTerms(q),
                            usedRemoteAI: true
                        ),
                        suggestions: payload.suggestions ?? Self.contextualSuggestions(for: q, results: payload.resolvedResults),
                        usedFallback: false,
                        sections: Self.buildResultSections(Array(payload.resolvedResults.prefix(limit)), intent: intent)
                    )
                }
            } catch {
                continue
            }
        }

        return try await enhancedAIFallback(query: q, limit: limit)
    }

    /// Multi-term browse search + catalogue vibe scoring so prompts still return useful picks.
    /// When the user asks for a genre/mood we don't carry, we say so instead of padding random titles.
    private func enhancedAIFallback(query: String, limit: Int) async throws -> AISearchResult {
        let intent = Self.detectSearchIntent(query)
        let expansions = Self.expandPromptTerms(query)
        var combined: [SearchResult] = []
        var seen = Set<String>()

        for term in expansions {
            let batch = (try? await search(query: term)) ?? []
            for item in batch where seen.insert(item.id).inserted {
                combined.append(item)
            }
            if combined.count >= limit * 2 { break }
        }

        let catalogue = (try? await fetchContent(limit: 80)) ?? []
        let catalogueResults = catalogue.map(\.asSearchResult)
        for item in catalogueResults where seen.insert(item.id).inserted {
            combined.append(item)
        }

        let scored = combined.map { item -> (SearchResult, Int) in
            let score = Self.vibeScore(item, prompt: query) + Self.tokenScore(item, query: query)
            return (item, score)
        }
        .sorted { $0.1 > $1.1 }

        let threshold = intent.isSpecific ? 3 : 1
        let strong = scored.filter { $0.1 >= threshold }.map(\.0)
        let availableGenres = CatalogueTypes.populatedGenres(from: catalogue)
        let fulfilled = Self.fulfillsIntent(strong, intent: intent, prompt: query)

        // Honest path: specific ask with no real genre/mood matches.
        if intent.isSpecific, !fulfilled {
            let adjacent = Self.adjacentAvailableResults(
                intent: intent,
                catalogue: catalogueResults,
                availableGenres: availableGenres,
                limit: min(8, limit)
            )
            let report = Self.buildHonestMissReport(
                prompt: query,
                intent: intent,
                availableGenres: availableGenres,
                adjacent: adjacent
            )
            let suggestions = Self.honestSuggestions(
                intent: intent,
                availableGenres: availableGenres,
                adjacent: adjacent
            )
            let sections: [AISearchSection]
            if adjacent.isEmpty {
                sections = []
            } else {
                sections = [
                    AISearchSection(title: "Closest on Story Time", results: adjacent),
                ]
            }
            return AISearchResult(
                results: adjacent,
                reasoning: report,
                suggestions: suggestions,
                usedFallback: true,
                sections: sections,
                unmetIntent: true
            )
        }

        let genreMatched: [SearchResult]
        if let primary = intent.primaryGenre {
            genreMatched = strong.filter { Self.matchesGenre($0, genre: primary) }
        } else {
            genreMatched = strong
        }
        let final = Array((genreMatched.isEmpty ? (strong.isEmpty ? scored.map(\.0) : strong) : genreMatched).prefix(limit))
        let sections = Self.buildResultSections(final, intent: intent)
        let suggestions = Self.contextualSuggestions(for: query, results: final)
        let report = Self.buildAIReport(
            prompt: query,
            results: final,
            searchLenses: expansions,
            usedRemoteAI: false,
            intent: intent,
            unmetIntent: false
        )

        return AISearchResult(
            results: final,
            reasoning: report,
            suggestions: suggestions,
            usedFallback: true,
            sections: sections,
            unmetIntent: false
        )
    }

    /// True when results honestly answer the ask — genre queries need real genre hits, not adjacent filler.
    nonisolated private static func fulfillsIntent(
        _ results: [SearchResult],
        intent: SearchIntent,
        prompt: String
    ) -> Bool {
        guard intent.isSpecific else {
            return !results.isEmpty
        }
        let strong = results.filter {
            vibeScore($0, prompt: prompt) + tokenScore($0, query: prompt) >= 3
        }
        guard !strong.isEmpty else { return false }

        if let primary = intent.primaryGenre {
            return strong.contains { matchesGenre($0, genre: primary) }
        }
        // Mood-only asks: vibe/token threshold is enough.
        return true
    }

    nonisolated private static func matchesGenre(_ result: SearchResult, genre: String) -> Bool {
        let target = genre.lowercased()
        let parts = [result.category, result.type]
            .compactMap { $0?.lowercased() }
            .map {
                $0.replacingOccurrences(of: "_", with: " ")
                    .replacingOccurrences(of: "-", with: " ")
                    .replacingOccurrences(of: "#", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        for hay in parts where !hay.isEmpty {
            if hay == target
                || hay.hasPrefix(target + " ")
                || hay.hasSuffix(" " + target)
                || hay.contains(" " + target + " ")
                || hay.contains(target) {
                return true
            }
        }
        return result.title.lowercased().contains(target)
    }

    /// Narrative “what I think” report so the UI feels like AI, not keyword search.
    nonisolated static func buildAIReport(
        prompt: String,
        results: [SearchResult],
        searchLenses: [String],
        usedRemoteAI: Bool,
        intent: SearchIntent? = nil,
        unmetIntent: Bool = false
    ) -> String {
        let resolvedIntent = intent ?? detectSearchIntent(prompt)
        if unmetIntent {
            return buildHonestMissReport(
                prompt: prompt,
                intent: resolvedIntent,
                availableGenres: [],
                adjacent: results
            )
        }

        let moods = interpretMood(prompt)
        var parts: [String] = []

        if moods.isEmpty {
            parts.append("Got it — looking across Story Time for titles that fit \"\(prompt)\".")
        } else if let first = moods.first {
            let lead = first.prefix(1).uppercased() + first.dropFirst()
            parts.append("\(lead).")
            if moods.count > 1 {
                parts.append("Also picking up: \(moods.dropFirst().joined(separator: "; ")).")
            }
        }

        if results.isEmpty {
            parts.append("I couldn't find a strong match in the catalogue yet. Try another mood or genre word and I'll rethink it.")
        } else {
            let topTitles = results.prefix(3).map(\.title).joined(separator: ", ")
            parts.append("Here are the picks that fit best right now — starting with \(topTitles).")
        }

        return parts.joined(separator: "\n\n")
    }

    nonisolated static func buildHonestMissReport(
        prompt: String,
        intent: SearchIntent,
        availableGenres: [String],
        adjacent: [SearchResult]
    ) -> String {
        let asked = intent.displayLabel
        var parts: [String] = []

        if let asked {
            parts.append("I looked for \(asked) on Story Time, but we don't have that lane populated yet.")
        } else {
            parts.append("I understood \"\(prompt)\", but nothing in the catalogue matches that vibe closely enough to recommend honestly.")
        }

        if !availableGenres.isEmpty {
            let sample = availableGenres.prefix(4).joined(separator: ", ")
            parts.append("What we do have right now includes \(sample)\(availableGenres.count > 4 ? ", and more" : "").")
        }

        if !adjacent.isEmpty {
            parts.append("If you want, here are the closest titles we can offer instead — not a perfect match, but nearby in tone.")
        } else {
            parts.append("Ask for one of the genres we carry, or describe a different mood, and I'll try again.")
        }

        return parts.joined(separator: "\n\n")
    }

    nonisolated struct SearchIntent: Hashable {
        var genres: [String]
        var moods: [String]
        var isSpecific: Bool { !genres.isEmpty || !moods.isEmpty }

        var displayLabel: String? {
            if let g = genres.first { return g.lowercased() }
            if let m = moods.first { return m.lowercased() }
            return nil
        }

        var primaryGenre: String? { genres.first }
    }

    nonisolated static func detectSearchIntent(_ prompt: String) -> SearchIntent {
        let q = prompt.lowercased()
        var genres: [String] = []
        var moods: [String] = []

        let genreMap: [(needles: [String], label: String)] = [
            (["horror", "scary", "creepy", "spooky", "terror", "haunt"], "Horror"),
            (["thriller", "suspense", "edge of my seat"], "Thriller"),
            (["comedy", "funny", "laugh", "humor", "humour", "hilarious"], "Comedy"),
            (["documentary", "doc ", "true story", "nonfiction", "non-fiction"], "Documentary"),
            (["romance", "romantic", "love story", "date night"], "Romance"),
            (["action", "explosive", "fight"], "Action"),
            (["drama"], "Drama"),
            (["sci-fi", "scifi", "science fiction", "sci fi"], "Sci-Fi"),
            (["family", "kids", "children"], "Family"),
            (["animation", "animated", "cartoon"], "Animation"),
            (["sports", "football", "soccer", "rugby"], "Sports"),
            (["music", "concert", "musical"], "Music"),
            (["crime", "heist", "detective"], "Crime"),
            (["mystery"], "Mystery"),
            (["fantasy"], "Fantasy"),
            (["western"], "Western"),
            (["war "], "War"),
            (["reality"], "Reality"),
            (["podcast"], "Podcast"),
            (["stand-up", "standup", "stand up"], "Stand-Up"),
        ]

        for entry in genreMap where entry.needles.contains(where: { q.contains($0) }) {
            if !genres.contains(entry.label) { genres.append(entry.label) }
        }

        if q.contains("cozy") || q.contains("comfort") || q.contains("rainy") || q.contains("chill") {
            moods.append("something cozy / comforting")
        }
        if q.contains("feel-good") || q.contains("feel good") || q.contains("wholesome") {
            moods.append("feel-good energy")
        }
        if q.contains("late night") || q.contains("intense") || q.contains("gritty") {
            moods.append("late-night intensity")
        }
        if q.contains("quick") || q.contains("short") || q.contains("under an hour") {
            moods.append("a quicker watch")
        }

        return SearchIntent(genres: genres, moods: moods)
    }

    nonisolated private static func adjacentAvailableResults(
        intent: SearchIntent,
        catalogue: [SearchResult],
        availableGenres: [String],
        limit: Int
    ) -> [SearchResult] {
        let neighbors: [String: [String]] = [
            "Horror": ["Thriller", "Mystery", "Crime", "Drama"],
            "Thriller": ["Crime", "Mystery", "Drama", "Action"],
            "Comedy": ["Family", "Romance", "Animation"],
            "Romance": ["Drama", "Comedy"],
            "Action": ["Adventure", "Thriller", "Sports"],
            "Documentary": ["Educational", "Sports", "News"],
            "Sci-Fi": ["Fantasy", "Action", "Thriller"],
            "Family": ["Animation", "Comedy"],
        ]

        var preferred = intent.genres.flatMap { neighbors[$0] ?? [] }
        preferred.append(contentsOf: availableGenres.prefix(6))

        var scored: [(SearchResult, Int)] = []
        for item in catalogue {
            let hay = [item.category, item.type, item.title]
                .compactMap { $0?.lowercased() }
                .joined(separator: " ")
            var score = 0
            for genre in preferred {
                if hay.contains(genre.lowercased()) { score += 5 }
            }
            // Soft mood adjacency only — never dump random catalogue filler.
            if intent.moods.contains(where: { $0.contains("cozy") }) || intent.moods.contains(where: { $0.contains("feel-good") }) {
                if hay.contains("comedy") || hay.contains("family") || hay.contains("drama") { score += 2 }
            }
            if score > 0 { scored.append((item, score)) }
        }

        return Array(
            scored
                .sorted { $0.1 > $1.1 }
                .map(\.0)
                .prefix(limit)
        )
    }

    nonisolated private static func honestSuggestions(
        intent: SearchIntent,
        availableGenres: [String],
        adjacent: [SearchResult]
    ) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        func add(_ s: String) {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard t.count >= 2, seen.insert(t.lowercased()).inserted else { return }
            out.append(t)
        }

        for genre in availableGenres.prefix(4) {
            add("Show me \(genre.lowercased())")
        }
        if !adjacent.isEmpty {
            add("Show me those closest picks")
        }
        add("Something feel-good")
        add("Family night picks")
        if intent.primaryGenre != nil {
            add("Notify me when that genre arrives")
        }
        return Array(out.prefix(6))
    }

    nonisolated private static func buildResultSections(
        _ results: [SearchResult],
        intent: SearchIntent
    ) -> [AISearchSection] {
        guard !results.isEmpty else { return [] }
        var sections: [AISearchSection] = [
            AISearchSection(title: "Top Results", results: Array(results.prefix(8))),
        ]

        var byLane: [String: [SearchResult]] = [:]
        for item in results {
            let lane: String
            if let raw = item.category?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
                var value = raw
                while value.hasPrefix("#") { value.removeFirst() }
                let cleaned = value
                    .replacingOccurrences(of: "_", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                lane = cleaned.isEmpty
                    ? (item.type?.replacingOccurrences(of: "_", with: " ").capitalized ?? "More picks")
                    : cleaned.capitalized
            } else if let type = item.type {
                lane = type.replacingOccurrences(of: "_", with: " ").capitalized
            } else {
                lane = "More picks"
            }
            byLane[lane, default: []].append(item)
        }

        let preferredOrder = intent.genres + intent.moods.map { _ in "More picks" }
        let orderedKeys = byLane.keys.sorted { a, b in
            let ai = preferredOrder.firstIndex(of: a) ?? 100
            let bi = preferredOrder.firstIndex(of: b) ?? 100
            if ai != bi { return ai < bi }
            return a < b
        }

        for key in orderedKeys {
            guard let items = byLane[key], items.count >= 2 else { continue }
            if key == "Top Results" { continue }
            let trimmed = Array(items.prefix(8))
            // Avoid duplicating the exact same Top Results strip.
            if trimmed.map(\.id) == sections.first?.results.prefix(trimmed.count).map(\.id) { continue }
            sections.append(AISearchSection(title: key, results: trimmed))
            if sections.count >= 4 { break }
        }

        return sections
    }

    nonisolated private static func interpretMood(_ prompt: String) -> [String] {
        let q = prompt.lowercased()
        var moods: [String] = []
        func add(_ line: String) { if !moods.contains(line) { moods.append(line) } }

        if q.contains("cozy") || q.contains("rain") || q.contains("chill") || q.contains("comfort") {
            add("comfort / low-stress viewing")
        }
        if q.contains("feel-good") || q.contains("feel good") || q.contains("wholesome") || q.contains("heartwarming") {
            add("uplifting, feel-good energy")
        }
        if q.contains("late") || q.contains("dark") || q.contains("gritty") || q.contains("intense") {
            add("late-night / intense tone")
        }
        if q.contains("funny") || q.contains("comedy") || q.contains("laugh") || q.contains("humor") || q.contains("humour") {
            add("comedy first")
        }
        if q.contains("scary") || q.contains("horror") || q.contains("creepy") {
            add("horror / suspense")
        }
        if q.contains("family") || q.contains("kids") || q.contains("everyone") {
            add("something the whole family can watch")
        }
        if q.contains("quick") || q.contains("short") || q.contains("brief") {
            add("shorter / easy to finish")
        }
        if q.contains("doc") || q.contains("true story") || q.contains("real") {
            add("documentary / true stories")
        }
        if q.contains("romance") || q.contains("date") || q.contains("love") {
            add("romance / date-night mood")
        }
        if q.contains("action") || q.contains("adventure") {
            add("action & adventure")
        }
        if q.contains("thriller") || q.contains("mystery") || q.contains("crime") {
            add("thriller / mystery")
        }
        return moods
    }

    nonisolated private static func expandPromptTerms(_ query: String) -> [String] {
        let q = query.lowercased()
        var terms: [String] = [query]

        let rules: [(needles: [String], add: [String])] = [
            (["feel-good", "feel good", "cozy", "comfort", "warm", "wholesome", "heartwarming"],
             ["comedy", "family", "feel-good", "romance"]),
            (["late night", "latenight", "dark", "gritty", "intense"],
             ["thriller", "crime", "drama", "horror"]),
            (["family", "kids", "children", "everyone"],
             ["family", "animation", "comedy"]),
            (["quick", "short", "brief", "one sitting"],
             ["short", "comedy", "documentary"]),
            (["funny", "comedy", "laugh", "humor", "humour", "skit"],
             ["comedy", "stand-up", "skit"]),
            (["scary", "horror", "creepy", "spooky"],
             ["horror", "thriller"]),
            (["doc", "documentary", "true story", "real"],
             ["documentary"]),
            (["action", "adventure", "fight"],
             ["action", "adventure"]),
            (["romance", "love", "date night"],
             ["romance", "drama"]),
            (["sports", "football", "soccer", "rugby"],
             ["sports"]),
            (["music", "concert", "song"],
             ["music"]),
            (["rainy", "rain", "chill", "relax"],
             ["drama", "comedy", "feel-good"]),
        ]

        for rule in rules where rule.needles.contains(where: { q.contains($0) }) {
            terms.append(contentsOf: rule.add)
        }

        let tokens = q
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= 3 }
        terms.append(contentsOf: tokens)

        var seen = Set<String>()
        return terms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
            .prefix(8)
            .map { $0 }
    }

    private static func rankSearchResults(_ results: [SearchResult], query: String) -> [SearchResult] {
        results.sorted { tokenScore($0, query: query) > tokenScore($1, query: query) }
    }

    nonisolated private static func tokenScore(_ result: SearchResult, query: String) -> Int {
        let tokens = query.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= 2 }
        guard !tokens.isEmpty else { return 0 }
        let hay = [
            result.title,
            result.category,
            result.type,
            result.creatorName,
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")
        return tokens.reduce(0) { partial, token in
            partial
                + (hay.contains(token) ? 3 : 0)
                + (result.title.lowercased().hasPrefix(token) ? 2 : 0)
        }
    }

    nonisolated private static func vibeScore(_ result: SearchResult, prompt: String) -> Int {
        let p = prompt.lowercased()
        let hay = [
            result.title,
            result.category,
            result.type,
            result.creatorName,
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")

        var score = 0
        let pairs: [(String, [String])] = [
            ("comedy", ["comedy", "stand", "skit", "funny"]),
            ("thriller", ["thriller", "crime", "mystery", "suspense"]),
            ("horror", ["horror", "scary", "haunt", "terror", "creep"]),
            ("scary", ["horror", "thriller", "suspense"]),
            ("creepy", ["horror", "thriller"]),
            ("spooky", ["horror", "thriller"]),
            ("documentary", ["documentary", "doc"]),
            ("family", ["family", "animation", "kids"]),
            ("romance", ["romance", "love"]),
            ("sports", ["sport"]),
            ("drama", ["drama"]),
            ("action", ["action", "adventure"]),
            ("music", ["music"]),
            ("feel", ["comedy", "family", "romance"]),
            ("cozy", ["comedy", "family", "romance", "drama"]),
            ("late", ["thriller", "horror", "crime"]),
        ]
        for (needle, boosts) in pairs where p.contains(needle) {
            for b in boosts where hay.contains(b) {
                score += 4
            }
        }
        return score
    }

    private static func contextualSuggestions(for query: String, results: [SearchResult]) -> [String] {
        var out: [String] = []
        var seen = Set<String>()

        func add(_ s: String) {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard t.count >= 2, seen.insert(t.lowercased()).inserted else { return }
            out.append(t)
        }

        // Follow-ups derived from the prompt itself.
        let q = query.lowercased()
        if q.contains("comedy") || q.contains("funny") {
            add("stand-up specials")
            add("short comedy skits")
        }
        if q.contains("family") || q.contains("kids") {
            add("animation for the family")
            add("feel-good family films")
        }
        if q.contains("thriller") || q.contains("dark") || q.contains("late") {
            add("crime thrillers")
            add("suspense dramas")
        }
        if q.contains("doc") {
            add("sports documentaries")
            add("true stories")
        }
        if q.contains("cozy") || q.contains("rain") || q.contains("chill") {
            add("comfort comedy")
            add("gentle dramas")
        }

        // Suggestions from result categories / titles.
        for item in results.prefix(8) {
            if let category = item.category, !category.isEmpty {
                add("more \(category)")
            }
        }
        for item in results.prefix(3) {
            add("like \(item.title)")
        }

        let defaults = [
            "feel-good movies",
            "quick watches",
            "family night",
            "late-night thrillers",
            "documentary picks",
        ]
        for d in defaults { add(d) }

        return Array(out.prefix(6))
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

    /// Full account summary (name, email, phone, address, plan, profiles) — `GET /api/viewer/settings`.
    func fetchViewerSettings() async throws -> ViewerSettingsResponse {
        let (data, response) = try await api.request(path: "api/viewer/settings")
        guard response.statusCode == 200 else {
            throw api.parseAPIError(data: data, status: response.statusCode)
        }
        return try api.decode(ViewerSettingsResponse.self, from: data)
    }
}
