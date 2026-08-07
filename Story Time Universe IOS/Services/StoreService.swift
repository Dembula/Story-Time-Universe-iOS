import Combine
import Foundation
import StoreKit

/// StoreKit 2 purchase + entitlement service for subscriptions and PPV unlocks.
@MainActor
final class StoreService: ObservableObject {
    static let shared = StoreService()

    @Published private(set) var subscriptionProducts: [Product] = []
    @Published private(set) var ppvProduct: Product?
    @Published private(set) var purchasedProductIDs: Set<String> = []
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var purchaseInFlight = false
    @Published var lastError: String?

    private var updatesTask: Task<Void, Never>?
    private var started = false

    private init() {}

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        started = true
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                await self.handle(update)
            }
        }
        Task {
            await refreshProducts()
            await refreshEntitlements()
        }
    }

    // MARK: - Catalog

    func refreshProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        let requested = StoreProducts.allProductIDs
        // Prefer Array (same order as StoreProducts) — StoreKit ignores unknown IDs silently.
        let ids = requested

        do {
            // Brief settle helps first launch after install when App Store is still warming up.
            var products: [Product] = []
            var lastErrorMessage: String?
            for attempt in 0..<3 {
                if attempt > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(400_000_000 * attempt))
                }
                do {
                    products = try await Product.products(for: ids)
                    if !products.isEmpty { break }
                } catch {
                    lastErrorMessage = error.localizedDescription
                }
            }

            subscriptionProducts = products
                .filter { StoreProducts.isSubscription($0.id) }
                .sorted { $0.price < $1.price }
            ppvProduct = products.first { StoreProducts.isPPV($0.id) }

            if products.isEmpty {
                let idList = ids.joined(separator: "\n• ")
                let errExtra = lastErrorMessage.map { "\nStoreKit said: \($0)\n" } ?? ""
                #if DEBUG
                lastError = """
                App Store returned 0 of \(ids.count) products.
                \(errExtra)
                Looking for:
                • \(idList)

                DEBUG RUN CHECK:
                1. Product → Scheme → Edit Scheme → Run → Options
                2. StoreKit Configuration must say:
                   Products.storekit
                   (path: Story Time Universe IOS/Configuration/Products.storekit)
                3. If it says “None”, open that file from the menu.
                4. Stop app, Clean Build Folder, Run again from Xcode (not an old install icon).

                TestFlight / App Store builds never use the .storekit file — products must be Ready in App Store Connect for this bundle.
                """
                #else
                lastError = """
                App Store returned 0 of \(ids.count) products for com.storytime.universe.
                \(errExtra)
                Looking for:
                • \(idList)

                Finish In-App Purchases under Story Time Universe in App Store Connect (price + localization), with Paid Apps Agreement active, then try again in TestFlight with a Sandbox Apple ID.
                """
                #endif
            } else {
                lastError = nil
                #if DEBUG
                print("[StoreService] Loaded \(products.count)/\(ids.count) products: \(products.map(\.id))")
                #endif
            }
        } catch {
            lastError = error.localizedDescription
            subscriptionProducts = []
            ppvProduct = nil
        }
    }

    func refreshEntitlements() async {
        var active: Set<String> = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.revocationDate == nil {
                active.insert(transaction.productID)
            }
        }
        purchasedProductIDs = active
    }

    var hasActiveSubscriptionEntitlement: Bool {
        purchasedProductIDs.contains { StoreProducts.isSubscription($0) }
    }

    var activeSubscriptionProductID: String? {
        purchasedProductIDs.first { StoreProducts.isSubscription($0) }
    }

    // MARK: - Purchase

    /// Purchase a subscription product and sync entitlement to Story Time account.
    @discardableResult
    func purchaseSubscription(_ product: Product) async throws -> Transaction {
        guard StoreProducts.isSubscription(product.id) else {
            throw APIError.server("Invalid subscription product.")
        }
        purchaseInFlight = true
        lastError = nil
        defer { purchaseInFlight = false }

        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            let jws = verification.jwsRepresentation
            try await activateSubscriptionOnServer(transaction, signedTransactionInfo: jws)
            await transaction.finish()
            await refreshEntitlements()
            return transaction
        case .userCancelled:
            throw APIError.server("Purchase cancelled.")
        case .pending:
            throw APIError.server("Purchase is pending approval. Try again after it completes.")
        @unknown default:
            throw APIError.server("Purchase could not be completed.")
        }
    }

    /// Purchase a one-time PPV unlock for a content id, then notify backend.
    @discardableResult
    func purchasePPVUnlock(contentId: String) async throws -> Transaction {
        guard let product = ppvProduct else {
            await refreshProducts()
            guard let product = ppvProduct else {
                throw APIError.server("Title unlock is not available yet. Try again later.")
            }
            return try await purchasePPV(product: product, contentId: contentId)
        }
        return try await purchasePPV(product: product, contentId: contentId)
    }

    private func purchasePPV(product: Product, contentId: String) async throws -> Transaction {
        purchaseInFlight = true
        lastError = nil
        defer { purchaseInFlight = false }

        // Tag purchase so App Store Server / backend can match content.
        let result = try await product.purchase(options: [
            .appAccountToken(Self.appAccountToken(for: contentId)),
        ])
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            let jws = verification.jwsRepresentation
            try await activatePPVOnServer(transaction, contentId: contentId, signedTransactionInfo: jws)
            await transaction.finish()
            await refreshEntitlements()
            return transaction
        case .userCancelled:
            throw APIError.server("Purchase cancelled.")
        case .pending:
            throw APIError.server("Purchase is pending approval. Try again after it completes.")
        @unknown default:
            throw APIError.server("Purchase could not be completed.")
        }
    }

    func restorePurchases() async throws {
        purchaseInFlight = true
        lastError = nil
        defer { purchaseInFlight = false }

        try await AppStore.sync()
        await refreshEntitlements()

        // Re-activate most recent active subscription entitlement with backend.
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard transaction.revocationDate == nil else { continue }
            if StoreProducts.isSubscription(transaction.productID) {
                try await activateSubscriptionOnServer(
                    transaction,
                    signedTransactionInfo: result.jwsRepresentation
                )
                return
            }
        }
        throw APIError.server("No active subscription found for this Apple ID.")
    }

    // MARK: - Transaction updates

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else { return }
        if StoreProducts.isSubscription(transaction.productID) {
            do {
                try await activateSubscriptionOnServer(
                    transaction,
                    signedTransactionInfo: result.jwsRepresentation
                )
                await transaction.finish()
            } catch {
                // Leave unfinished so StoreKit retries activation.
                lastError = error.localizedDescription
            }
        }
        // PPV consumables need contentId at purchase time — never finish orphaned updates here.
        await refreshEntitlements()
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw APIError.server("Could not verify purchase with Apple. \(error.localizedDescription)")
        case .verified(let safe):
            return safe
        }
    }

    // MARK: - Backend activate

    private func activateSubscriptionOnServer(
        _ transaction: Transaction,
        signedTransactionInfo: String
    ) async throws {
        let payload = Self.payloadString(
            jwsRepresentation: signedTransactionInfo,
            transaction: transaction
        )
        try await ViewerAPI.shared.activateAppleSubscription(
            productId: transaction.productID,
            transactionId: String(transaction.id),
            originalTransactionId: String(transaction.originalID),
            signedTransactionInfo: payload,
            environment: Self.environmentLabel(transaction.environment),
            planCode: StoreProducts.planCode(forProductId: transaction.productID)
        )
    }

    private func activatePPVOnServer(
        _ transaction: Transaction,
        contentId: String,
        signedTransactionInfo: String
    ) async throws {
        let payload = Self.payloadString(
            jwsRepresentation: signedTransactionInfo,
            transaction: transaction
        )
        try await ViewerAPI.shared.activateApplePPV(
            contentId: contentId,
            productId: transaction.productID,
            transactionId: String(transaction.id),
            originalTransactionId: String(transaction.originalID),
            signedTransactionInfo: payload,
            environment: Self.environmentLabel(transaction.environment)
        )
    }

    /// Prefer JWS from `VerificationResult.jwsRepresentation` (not on `Transaction` itself).
    private static func payloadString(
        jwsRepresentation: String,
        transaction: Transaction
    ) -> String {
        if !jwsRepresentation.isEmpty {
            return jwsRepresentation
        }
        // Fallback payload for backends that accept decoded transaction JSON.
        if let utf8 = String(data: transaction.jsonRepresentation, encoding: .utf8), !utf8.isEmpty {
            return utf8
        }
        return transaction.jsonRepresentation.base64EncodedString()
    }

    private static func environmentLabel(_ environment: AppStore.Environment) -> String {
        switch environment {
        case .sandbox: return "Sandbox"
        case .production: return "Production"
        case .xcode: return "Xcode"
        default: return "Production"
        }
    }

    /// Deterministic UUID for appAccountToken (must be UUID format for StoreKit).
    private static func appAccountToken(for contentId: String) -> UUID {
        // Namespace UUID for Story Time content mapping.
        let namespace = UUID(uuidString: "6BA7B810-9DAD-11D1-80B4-00C04FD430C8")!
        return uuidV5(name: contentId, namespace: namespace)
    }

    private static func uuidV5(name: String, namespace: UUID) -> UUID {
        var namespaceBytes = withUnsafeBytes(of: namespace.uuid) { Array($0) }
        let nameBytes = Array(name.utf8)
        // Simple non-crypto mix for stable UUID-shaped token (StoreKit only needs UUID).
        var digest = [UInt8](repeating: 0, count: 16)
        for (i, b) in (namespaceBytes + nameBytes).enumerated() {
            digest[i % 16] ^= b &+ UInt8(i & 0xFF)
        }
        digest[6] = (digest[6] & 0x0F) | 0x50 // version 5-ish
        digest[8] = (digest[8] & 0x3F) | 0x80
        return UUID(uuid: (
            digest[0], digest[1], digest[2], digest[3],
            digest[4], digest[5], digest[6], digest[7],
            digest[8], digest[9], digest[10], digest[11],
            digest[12], digest[13], digest[14], digest[15]
        ))
    }
}

extension Product.SubscriptionPeriod.Unit {
    var shortLabel: String {
        switch self {
        case .day: return "day"
        case .week: return "week"
        case .month: return "month"
        case .year: return "year"
        @unknown default: return "period"
        }
    }
}
