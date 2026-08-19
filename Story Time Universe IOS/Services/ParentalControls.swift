import Foundation
import Combine

/// Local parental controls + age assurance for App Store guideline 2.3.6.
/// Profile age from birth date provides age assurance; this store adds PIN-gated
/// maturity limits and multi-profile restrictions that parents can find under Account.
@MainActor
final class ParentalControls: ObservableObject {
    static let shared = ParentalControls()

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let enabled = "parental.enabled"
        static let pin = "parental.pin"
        static let maxMaturityAge = "parental.maxMaturityAge"
        static let requirePinToSwitchProfile = "parental.requirePinToSwitch"
        static let requirePinForPlayer = "parental.requirePinForPlayer"
        static let blockDownloads = "parental.blockDownloads"
    }

    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.enabled) }
    }

    /// Maximum allowed content minAge (e.g. 12, 15, 18). nil = unrestricted beyond profile age.
    @Published var maxMaturityAge: Int {
        didSet { defaults.set(maxMaturityAge, forKey: Keys.maxMaturityAge) }
    }

    @Published var requirePinToSwitchProfile: Bool {
        didSet { defaults.set(requirePinToSwitchProfile, forKey: Keys.requirePinToSwitchProfile) }
    }

    @Published var requirePinForPlayer: Bool {
        didSet { defaults.set(requirePinForPlayer, forKey: Keys.requirePinForPlayer) }
    }

    @Published var blockDownloads: Bool {
        didSet { defaults.set(blockDownloads, forKey: Keys.blockDownloads) }
    }

    private init() {
        isEnabled = defaults.bool(forKey: Keys.enabled)
        let stored = defaults.integer(forKey: Keys.maxMaturityAge)
        maxMaturityAge = stored > 0 ? stored : 18
        requirePinToSwitchProfile = defaults.bool(forKey: Keys.requirePinToSwitchProfile)
        requirePinForPlayer = defaults.bool(forKey: Keys.requirePinForPlayer)
        blockDownloads = defaults.bool(forKey: Keys.blockDownloads)
    }

    var hasPIN: Bool {
        !(defaults.string(forKey: Keys.pin) ?? "").isEmpty
    }

    func setPIN(_ pin: String) {
        let trimmed = pin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 4, trimmed.allSatisfy(\.isNumber) else { return }
        defaults.set(trimmed, forKey: Keys.pin)
    }

    func clearPIN() {
        defaults.removeObject(forKey: Keys.pin)
    }

    func verifyPIN(_ pin: String) -> Bool {
        guard let stored = defaults.string(forKey: Keys.pin), !stored.isEmpty else { return true }
        return stored == pin
    }

    /// Effective max age for the active profile + parental settings.
    func effectiveMaxAge(profileAge: Int?) -> Int {
        let profileLimit = profileAge ?? 18
        guard isEnabled else { return profileLimit }
        return min(profileLimit, maxMaturityAge)
    }

    func allows(contentMinAge: Int?, profileAge: Int?) -> Bool {
        let maxAllowed = effectiveMaxAge(profileAge: profileAge)
        let required = contentMinAge ?? 0
        return required <= maxAllowed
    }

    func filter(_ items: [ContentItem], profileAge: Int?) -> [ContentItem] {
        items.filter { allows(contentMinAge: $0.minAge, profileAge: profileAge) }
    }

    var maturityLabel: String {
        switch maxMaturityAge {
        case ...7: return "Little Kids (up to 7)"
        case 8...12: return "Kids (up to 12)"
        case 13...15: return "Teen (up to 15)"
        case 16...17: return "Young adult (up to 17)"
        default: return "Adult (unrestricted)"
        }
    }

    /// Best-effort sync of maturity flags from viewer settings (PIN stays on-device).
    func applyRemoteMaturityHints(enabled: Bool?, maxAge: Int?) {
        if let enabled {
            isEnabled = enabled
        }
        if let maxAge, maxAge > 0 {
            maxMaturityAge = maxAge
        }
    }
}

extension ContentItem {
    func matchesGenre(_ genre: String) -> Bool {
        let target = CatalogueTypes.canonicalGenre(from: genre) ?? genre.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return false }
        let targetKey = target.lowercased()

        if let categoryGenre = CatalogueTypes.canonicalGenre(from: category),
           categoryGenre.lowercased() == targetKey {
            return true
        }
        // Category free-text may still contain the genre name.
        if let category, category.lowercased().contains(targetKey) {
            // Avoid matching noise tags that only partially overlap known genres via coincidence.
            if CatalogueTypes.canonicalGenre(from: category) != nil || CatalogueTypes.seedGenres.contains(where: {
                category.localizedCaseInsensitiveContains($0)
            }) {
                return true
            }
        }
        if let tags = tags {
            for part in tags.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "|" }) {
                if let tagGenre = CatalogueTypes.canonicalGenre(from: String(part)),
                   tagGenre.lowercased() == targetKey {
                    return true
                }
            }
        }
        return false
    }
}
