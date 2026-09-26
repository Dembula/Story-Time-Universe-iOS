import Foundation

/// Result of `POST /api/viewer/ppv` — unlock a title for Pay Per View accounts.
nonisolated struct PpvCheckoutResponse: Codable, Hashable {
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

nonisolated enum TitleAccessResult: Equatable {
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

    /// Trial / intro period — always enforce the plan's profile cap (Base trial = 1).
    var isTrialing: Bool {
        let s = status?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        return s == "TRIALING" || s == "TRIAL" || s.contains("TRIAL")
    }

    /// Effective profile slots for this subscription (server value clamped to plan rules).
    var effectiveProfileLimit: Int {
        let fromPlan = StoreProducts.profileLimit(forPlanCode: plan)
        let fromServer = profileLimit.flatMap { $0 > 0 ? $0 : nil }
        let resolved = min(fromServer ?? fromPlan, fromPlan)
        // Never allow more profiles than the purchased/trial plan allows.
        return max(1, resolved)
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
