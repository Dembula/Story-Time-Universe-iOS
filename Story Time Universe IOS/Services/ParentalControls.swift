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
        case ...12: return "Kids (up to 12)"
        case 13...15: return "Teen (up to 15)"
        case 16...17: return "Young adult (up to 17)"
        default: return "Adult (unrestricted)"
        }
    }
}
