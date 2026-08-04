import Foundation

/// Response from production `GET /api/viewer/settings` (account summary mirror of the web settings page).
struct ViewerSettingsResponse: Codable, Hashable {
    let account: ViewerAccountDetails?
    let address: ViewerAddressDetails?
    let preferences: ViewerPreferenceDetails?
    let paymentMethods: [ViewerPaymentMethodDetails]?
    let profiles: [ViewerSettingsProfile]?
    let activeProfileId: String?
    let subscription: ViewerSettingsSubscription?
    let warnings: [String]?
}

struct ViewerAccountDetails: Codable, Hashable {
    let name: String?
    let email: String?
    let phoneNumber: String?
    let onboardingComplete: Bool?
}

struct ViewerAddressDetails: Codable, Hashable {
    let residentialAddress: String?
    let city: String?
    let provinceState: String?
    let postalCode: String?
    let country: String?

    var isEmpty: Bool {
        [residentialAddress, city, provinceState, postalCode]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .isEmpty
    }

    var formattedLines: [String] {
        var lines: [String] = []
        if let line = residentialAddress?.trimmedNonEmpty { lines.append(line) }
        var cityLine: [String] = []
        if let city = city?.trimmedNonEmpty { cityLine.append(city) }
        if let province = provinceState?.trimmedNonEmpty { cityLine.append(province) }
        if let postal = postalCode?.trimmedNonEmpty { cityLine.append(postal) }
        if !cityLine.isEmpty { lines.append(cityLine.joined(separator: ", ")) }
        if let country = country?.trimmedNonEmpty { lines.append(country) }
        return lines
    }
}

struct ViewerPreferenceDetails: Codable, Hashable {
    let notifyEmail: Bool?
    let playbackQuality: String?
}

struct ViewerPaymentMethodDetails: Codable, Hashable, Identifiable {
    let id: String
    let label: String?
    let lastFour: String?
    let isDefault: Bool?
}

struct ViewerSettingsProfile: Codable, Hashable, Identifiable {
    let id: String
    let name: String?
    let age: Int?
    let dateOfBirth: String?
    let pinEnabled: Bool?
}

struct ViewerSettingsSubscription: Codable, Hashable {
    let id: String?
    let plan: String?
    let viewerModel: String?
    let deviceCount: Int?
    let profileLimit: Int?
    let status: String?
}

private extension String {
    var trimmedNonEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
