import Foundation

/// Result of `POST /api/viewer/ppv` — unlock a title for Pay Per View accounts.
struct PpvCheckoutResponse: Codable, Hashable {
    let success: Bool?
    let requiresPayment: Bool?
    let alreadyOwned: Bool?
    let checkoutUrl: String?
    let error: String?

    var checkoutURL: URL? {
        guard let checkoutUrl, !checkoutUrl.isEmpty else { return nil }
        return URL(string: checkoutUrl)
    }
}

enum TitleAccessResult: Equatable {
    /// Stream / player may start.
    case playable
    /// Title requires a StoreKit consumable unlock (no external checkout in-app).
    case requiresInAppPurchase(contentId: String)
    case blocked(String)
}

extension ViewerSubscription {
    /// True when account was set up as pay-per-title (not unlimited subscription).
    var isPayPerViewModel: Bool {
        let model = viewerModel?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        let plan = plan?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        return Self.looksLikePayPerView(model) || Self.looksLikePayPerView(plan)
    }

    private static func looksLikePayPerView(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        if value == "PPV" || value == "PPV_FILM" || value == "PAY_PER_VIEW" { return true }
        if value.contains("PPV") { return true }
        if value.contains("PAY_PER_VIEW") || value.contains("PAY-PER-VIEW") || value.contains("PAY PER VIEW") {
            return true
        }
        if value.contains("SINGLE") && (value.contains("TITLE") || value.contains("FILM") || value.contains("VIEW")) {
            return true
        }
        return false
    }
}
