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

        let ids = StoreProducts.allProductIDs
        var products: [Product] = []
        var lastErrorMessage: String?

        // Pass 1: bulk request (normal path).
        for attempt in 0..<3 {
            if attempt > 0 {
                try? await Task.sleep(nanoseconds: UInt64(350_000_000 * attempt))
            }
            do {
                products = try await Product.products(for: ids)
                if !products.isEmpty { break }
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }

        // Pass 2: per-id (helps some incomplete ASC catalogs / StoreKit Config edge cases).
        if products.isEmpty {
            var byId: [String: Product] = [:]
            for id in ids {
                do {
                    let found = try await Product.products(for: [id])
                    for p in found { byId[p.id] = p }
                } catch {
                    lastErrorMessage = error.localizedDescription
                }
            }
            products = Array(byId.values)
        }

        subscriptionProducts = products
            .filter { StoreProducts.isSubscription($0.id) }
            .sorted { $0.price < $1.price }
        ppvProduct = products.first { StoreProducts.isPPV($0.id) }

        if products.isEmpty {
            lastError = Self.emptyCatalogMessage(ids: ids, storeError: lastErrorMessage)
            #if DEBUG
            print("[StoreService] EMPTY catalog. ids=\(ids) error=\(lastErrorMessage ?? "none") bundle=\(Bundle.main.bundleIdentifier ?? "?")")
            #endif
        } else {
            lastError = nil
            #if DEBUG
            let missing = Set(ids).subtracting(products.map(\.id))
            print("[StoreService] Loaded \(products.count)/\(ids.count): \(products.map(\.id)) missing=\(missing)")
            #endif
        }
    }

    private static func emptyCatalogMessage(ids: [String], storeError: String?) -> String {
        let idList = ids.joined(separator: "\n• ")
        let err = storeError.map { "\nStoreKit error: \($0)\n" } ?? "\n"
        #if DEBUG
        return """
        StoreKit returned 0 of \(ids.count) products.\(err)
        Bundle: \(Bundle.main.bundleIdentifier ?? "?")

        Looking for:
        • \(idList)

        IF YOU'RE IN SIMULATOR / XCODE RUN:
        Scheme “Story Time Universe IOS” → Run → Options → StoreKit Configuration
        must be “Products.storekit” (not None). Then Clean Build Folder and Run ▶ again.

        IF YOU'RE ON TESTFLIGHT (top status bar says TestFlight):
        Local .storekit NEVER applies. Products load only from App Store Connect when
        each IAP has price + localization and Paid Apps Agreement is Active.
        Status “Prepare for Submission” with missing price often returns 0 products.
        """
        #else
        return """
        Subscriptions are not available from the App Store yet.\(err)
        Make sure In-App Purchases for Story Time Universe are complete in App Store Connect, then try again later.
        """
        #endif
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
                lastError = error.localizedDescription
            }
        }
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

    private static func payloadString(
        jwsRepresentation: String,
        transaction: Transaction
    ) -> String {
        if !jwsRepresentation.isEmpty {
            return jwsRepresentation
        }
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

    private static func appAccountToken(for contentId: String) -> UUID {
        let namespace = UUID(uuidString: "6BA7B810-9DAD-11D1-80B4-00C04FD430C8")!
        return uuidV5(name: contentId, namespace: namespace)
    }

    private static func uuidV5(name: String, namespace: UUID) -> UUID {
        var namespaceBytes = withUnsafeBytes(of: namespace.uuid) { Array($0) }
        let nameBytes = Array(name.utf8)
        var digest = [UInt8](repeating: 0, count: 16)
        for (i, b) in (namespaceBytes + nameBytes).enumerated() {
            digest[i % 16] ^= b &+ UInt8(i & 0xFF)
        }
        digest[6] = (digest[6] & 0x0F) | 0x50
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
