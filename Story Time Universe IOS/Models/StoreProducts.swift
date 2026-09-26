import Foundation

/// App Store product identifiers — create matching auto-renewable / consumable
/// products in App Store Connect with these exact IDs before submitting for review.
nonisolated enum StoreProducts {
    // MARK: Auto-renewable subscriptions (subscription group: Story Time Universe)

    static let baseMonthly = "com.storytime.universe.sub.base.monthly"
    static let standardMonthly = "com.storytime.universe.sub.standard.monthly"
    static let familyMonthly = "com.storytime.universe.sub.family.monthly"

    static let baseYearly = "com.storytime.universe.sub.base.yearly"
    static let standardYearly = "com.storytime.universe.sub.standard.yearly"
    static let familyYearly = "com.storytime.universe.sub.family.yearly"

    /// All subscription product IDs we load from the store.
    static let allSubscriptionIDs: [String] = [
        baseMonthly, standardMonthly, familyMonthly,
        baseYearly, standardYearly, familyYearly,
    ]

    // MARK: PPV unlock (consumable — one purchase unlocks one title via backend)

    static let ppvUnlock = "com.storytime.universe.ppv.unlock"

    static let allProductIDs: [String] = allSubscriptionIDs + [ppvUnlock]

    /// Map our App Store product → production plan code used by `GET /api/viewer/subscription`.
    static func planCode(forProductId productId: String) -> String {
        switch productId {
        case baseMonthly, baseYearly: return "BASE_1"
        case standardMonthly, standardYearly: return "STANDARD_3"
        case familyMonthly, familyYearly: return "FAMILY_5"
        case ppvUnlock: return "PPV"
        default: return "BASE_1"
        }
    }

    static func displayName(forProductId productId: String) -> String {
        switch productId {
        case baseMonthly, baseYearly: return "Base"
        case standardMonthly, standardYearly: return "Standard"
        case familyMonthly, familyYearly: return "Family"
        case ppvUnlock: return "Title Unlock"
        default: return "Story Time"
        }
    }

    static func profileLimit(forProductId productId: String) -> Int {
        switch productId {
        case baseMonthly, baseYearly: return 1
        case standardMonthly, standardYearly: return 3
        case familyMonthly, familyYearly: return 5
        default: return 1
        }
    }

    /// Resolve profile limit from a server plan code (`BASE_1`, `STANDARD_3`, …).
    static func profileLimit(forPlanCode plan: String?) -> Int {
        let code = plan?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        switch code {
        case "BASE_1", "BASE": return 1
        case "STANDARD_3", "STANDARD": return 3
        case "FAMILY_5", "FAMILY": return 5
        default:
            if code.contains("FAMILY") { return 5 }
            if code.contains("STANDARD") { return 3 }
            return 1
        }
    }

    /// Base (R29) plans include a free trial in App Store Connect / StoreKit config.
    static func includesFreeTrial(productId: String) -> Bool {
        productId == baseMonthly || productId == baseYearly
    }

    static func features(forProductId productId: String) -> [String] {
        let limit = profileLimit(forProductId: productId)
        var list = [
            "Stream Story Time catalogue",
            "\(limit) profile\(limit == 1 ? "" : "s")",
            "Continue watching & downloads",
        ]
        if includesFreeTrial(productId: productId) {
            list.insert("7-day free trial", at: 0)
        }
        list.append("Cancel anytime in App Store settings")
        return list
    }

    static func isSubscription(_ productId: String) -> Bool {
        allSubscriptionIDs.contains(productId)
    }

    static func isPPV(_ productId: String) -> Bool {
        productId == ppvUnlock
    }
}

/// Why the paywall is shown — controls copy and post-purchase navigation.
nonisolated enum PaywallContext: Equatable {
    case subscribe
    case reactivate
    case changePlan
    case ppv(contentId: String, title: String?)

    var isPPV: Bool {
        if case .ppv = self { return true }
        return false
    }
}
