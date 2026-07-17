import Foundation

/// Mirrors Story Time Production `src/lib/content-types.ts` (commit 34d2d13+).
/// Home rows fill as creators upload — no app update needed for these known types.
enum CatalogueTypes {
    struct RowDefinition: Identifiable, Hashable {
        let id: String
        /// One or more API `Content.type` values (Comedy = skits + stand-up, like web).
        let typeValues: [String]
        /// Optional genre filter on `category` (e.g. Comedy Shows).
        let categoryFilter: String?
        let title: String
        /// When true, Home keeps a visible empty slot until titles arrive.
        let reserveEmptySlot: Bool

        init(
            id: String,
            typeValues: [String],
            categoryFilter: String? = nil,
            title: String,
            reserveEmptySlot: Bool
        ) {
            self.id = id
            self.typeValues = typeValues
            self.categoryFilter = categoryFilter
            self.title = title
            self.reserveEmptySlot = reserveEmptySlot
        }

        init(id: String, typeValue: String, title: String, reserveEmptySlot: Bool) {
            self.init(
                id: id,
                typeValues: [typeValue],
                categoryFilter: nil,
                title: title,
                reserveEmptySlot: reserveEmptySlot
            )
        }
    }

    /// Singular labels — `CONTENT_TYPE_LABELS`
    static let labels: [String: String] = [
        "MOVIE": "Movie",
        "DOCUMENTARY": "Documentary",
        "SHORT_FILM": "Short Film",
        "SERIES": "Series",
        "SHOW": "Show",
        "PODCAST": "Podcast",
        "COMEDY_SKIT": "Comedy Skit",
        "STAND_UP": "Stand-Up",
        "ANIMATION": "Animation",
        "SPORTS": "Sports",
        "MUSIC_VIDEO": "Music Video",
        "LIVE_EVENT": "Live Event",
        "REALITY": "Reality",
        "NEWS": "News",
        "EDUCATIONAL": "Educational",
        "WEB_SERIES": "Web Series",
    ]

    /// Plural labels — `contentTypePluralLabel`
    static let pluralLabels: [String: String] = [
        "MOVIE": "Movies",
        "SERIES": "Series",
        "SHOW": "Shows",
        "DOCUMENTARY": "Documentaries",
        "SHORT_FILM": "Short Films",
        "PODCAST": "Podcasts",
        "COMEDY_SKIT": "Comedy Skits",
        "STAND_UP": "Stand-Up",
        "ANIMATION": "Animation",
        "SPORTS": "Sports",
        "MUSIC_VIDEO": "Music Videos",
        "LIVE_EVENT": "Live Events",
        "REALITY": "Reality",
        "WEB_SERIES": "Web Series",
        "NEWS": "News",
        "EDUCATIONAL": "Educational",
    ]

    /// Long-form types that support seasons/episodes (`LONG_FORM_TYPES`).
    static let longFormTypes: Set<String> = [
        "SERIES", "SHOW", "PODCAST", "WEB_SERIES", "REALITY", "NEWS",
    ]

    /// All uploadable catalogue type strings (`ALL_CATALOGUE_TYPE_VALUES`).
    static let allCatalogueTypeValues: [String] = [
        "MOVIE", "SERIES", "SHOW", "DOCUMENTARY", "SHORT_FILM", "PODCAST",
        "COMEDY_SKIT", "STAND_UP", "ANIMATION", "SPORTS", "MUSIC_VIDEO",
        "LIVE_EVENT", "REALITY", "WEB_SERIES", "NEWS", "EDUCATIONAL",
    ]

    /// `VIEWER_NAV_CATEGORIES` — reserved empty slots so uploads light them up.
    /// Order matches Production browse home (Movies → … → Podcasts).
    static let primaryHomeRows: [RowDefinition] = [
        .init(id: "MOVIE", typeValue: "MOVIE", title: "Movies", reserveEmptySlot: true),
        .init(id: "SERIES", typeValue: "SERIES", title: "Series", reserveEmptySlot: true),
        .init(id: "ANIMATION", typeValue: "ANIMATION", title: "Animation", reserveEmptySlot: true),
        .init(id: "SPORTS", typeValue: "SPORTS", title: "Sports", reserveEmptySlot: true),
        // Web Comedy row = COMEDY_SKIT + STAND_UP
        .init(
            id: "COMEDY",
            typeValues: ["COMEDY_SKIT", "STAND_UP"],
            title: "Comedy",
            reserveEmptySlot: true
        ),
        .init(id: "DOCUMENTARY", typeValue: "DOCUMENTARY", title: "Documentaries", reserveEmptySlot: true),
        .init(id: "SHOW", typeValue: "SHOW", title: "Shows", reserveEmptySlot: true),
        .init(id: "PODCAST", typeValue: "PODCAST", title: "Podcasts", reserveEmptySlot: true),
    ]

    /// Overflow formats + browse extras (shown once they have titles).
    /// Matches `VIEWER_NAV_MORE_CATEGORIES` types (excluding Student Films) plus Live Events / Comedy Shows.
    static let secondaryHomeRows: [RowDefinition] = [
        .init(id: "LIVE_EVENT", typeValue: "LIVE_EVENT", title: "Live Events", reserveEmptySlot: false),
        .init(
            id: "COMEDY_SHOWS",
            typeValues: ["SHOW"],
            categoryFilter: "Comedy",
            title: "Comedy Shows",
            reserveEmptySlot: false
        ),
        .init(id: "SHORT_FILM", typeValue: "SHORT_FILM", title: "Short Films", reserveEmptySlot: false),
        .init(id: "MUSIC_VIDEO", typeValue: "MUSIC_VIDEO", title: "Music Videos", reserveEmptySlot: false),
        .init(id: "REALITY", typeValue: "REALITY", title: "Reality", reserveEmptySlot: false),
        .init(id: "WEB_SERIES", typeValue: "WEB_SERIES", title: "Web Series", reserveEmptySlot: false),
        .init(id: "NEWS", typeValue: "NEWS", title: "News", reserveEmptySlot: false),
        .init(id: "EDUCATIONAL", typeValue: "EDUCATIONAL", title: "Educational", reserveEmptySlot: false),
    ]

    static var allHomeRows: [RowDefinition] { primaryHomeRows + secondaryHomeRows }

    static var allTrackedTypeValues: Set<String> {
        Set(allHomeRows.flatMap(\.typeValues)).union(allCatalogueTypeValues)
    }

    static func pluralTitle(for typeValue: String) -> String {
        if let known = pluralLabels[typeValue] { return known }
        let raw = labels[typeValue] ?? typeValue
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
        return raw
    }

    static func isLongForm(_ type: String?) -> Bool {
        guard let type else { return false }
        return longFormTypes.contains(type.uppercased())
    }
}

struct HomeCatalogRow: Identifiable, Hashable {
    let id: String
    let typeValue: String
    let title: String
    let items: [ContentItem]
    let reserveEmptySlot: Bool

    var shouldDisplay: Bool {
        !items.isEmpty || reserveEmptySlot
    }
}
