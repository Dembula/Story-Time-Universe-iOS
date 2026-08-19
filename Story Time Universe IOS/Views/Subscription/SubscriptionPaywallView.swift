import StoreKit
import SwiftUI

/// Native App Store subscription / PPV paywall (Guideline 3.1.1).
struct SubscriptionPaywallView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var store = StoreService.shared
    @Environment(\.dismiss) private var dismiss

    var context: PaywallContext = .subscribe
    var onFinished: (() -> Void)?

    @State private var selectedProductID: String?
    @State private var localError: String?
    @State private var didComplete = false
    @State private var showYearly = false
    @State private var successMessage: String?

    private var currentProductID: String? {
        store.activeSubscriptionProductID
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                LinearGradient(
                    colors: [Theme.accent.opacity(0.22), .clear, Theme.accentGold.opacity(0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 22) {
                        header

                        if context == .changePlan, let currentProductID {
                            currentPlanBadge(currentProductID)
                        }

                        if context != .ppv, !store.subscriptionProducts.isEmpty {
                            billingToggle
                        }

                        productList
                        legalCopy
                        footerActions
                    }
                    .padding(22)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundStyle(Theme.accent)
                    .disabled(store.purchaseInFlight)
                }
            }
            .task {
                store.start()
                await store.refreshProducts()
                await store.refreshEntitlements()
                if selectedProductID == nil {
                    selectedProductID = preferredDefaultProductID
                }
            }
            .interactiveDismissDisabled(store.purchaseInFlight)
        }
        .preferredColorScheme(.dark)
    }

    private var navTitle: String {
        switch context {
        case .subscribe: return "Choose a Plan"
        case .reactivate: return "Reactivate"
        case .changePlan: return "Change Plan"
        case .ppv: return "Unlock Title"
        }
    }

    private var preferredDefaultProductID: String? {
        switch context {
        case .ppv:
            return store.ppvProduct?.id
        case .changePlan:
            return nil
        default:
            return filteredSubscriptionProducts.first(where: { $0.id == StoreProducts.standardMonthly })?.id
                ?? filteredSubscriptionProducts.first?.id
        }
    }

    private var filteredSubscriptionProducts: [Product] {
        store.subscriptionProducts.filter { product in
            guard let period = product.subscription?.subscriptionPeriod else { return true }
            if showYearly {
                return period.unit == .year
            } else {
                return period.unit == .month
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 88, height: 88)
                .shadow(color: Theme.accent.opacity(0.4), radius: 20, y: 8)

            Text(headline)
                .font(.title2.bold())
                .foregroundStyle(Theme.foreground)
                .multilineTextAlignment(.center)

            Text(subheadline)
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    private var headline: String {
        switch context {
        case .subscribe: return "Subscribe to Story Time"
        case .reactivate: return "Reactivate your access"
        case .changePlan: return "Change your plan"
        case .ppv(_, let title): return title.map { "Unlock \($0)" } ?? "Unlock this title"
        }
    }

    private var subheadline: String {
        switch context {
        case .ppv:
            return "One-time purchase via Apple. Payment is handled securely by the App Store."
        case .changePlan:
            return "Select a new plan below. Upgrades take effect immediately; downgrades apply at the end of your current billing period."
        default:
            return "Payment is handled securely by Apple. Subscriptions auto-renew unless cancelled at least 24 hours before the period ends."
        }
    }

    // MARK: - Current plan badge

    private func currentPlanBadge(_ productID: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green.opacity(0.9))
            VStack(alignment: .leading, spacing: 2) {
                Text("Current plan")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.muted)
                Text(StoreProducts.displayName(forProductId: productID))
                    .font(.headline)
                    .foregroundStyle(Theme.foreground)
            }
            Spacer()
            if let product = store.subscriptionProducts.first(where: { $0.id == productID }) {
                Text(product.displayPrice + periodSuffix(for: product))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accentGold)
            }
        }
        .padding(14)
        .background(Color.green.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.green.opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Billing toggle

    private var billingToggle: some View {
        HStack(spacing: 0) {
            billingTab("Monthly", isActive: !showYearly) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showYearly = false
                    selectedProductID = nil
                }
            }
            billingTab("Yearly — Save ~17%", isActive: showYearly) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showYearly = true
                    selectedProductID = nil
                }
            }
        }
        .padding(3)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func billingTab(_ title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isActive ? .black : Theme.muted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(isActive ? Theme.accent : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Product list

    @ViewBuilder
    private var productList: some View {
        if store.isLoadingProducts && displayProducts.isEmpty {
            ProgressView()
                .tint(Theme.accent)
                .padding(.vertical, 40)
        } else if displayProducts.isEmpty {
            VStack(spacing: 12) {
                Text(store.lastError ?? "Subscription plans aren't available right now. Check your network connection, make sure you're signed into the App Store, and try again.")
                    .font(.subheadline)
                    .foregroundStyle(store.lastError == nil ? Theme.muted : .red.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                Button("Try again") {
                    Task { await store.refreshProducts() }
                }
                .foregroundStyle(Theme.accent)
            }
            .padding(.vertical, 20)
        } else {
            VStack(spacing: 12) {
                ForEach(displayProducts, id: \.id) { product in
                    productCard(product)
                }
            }
        }

        if let successMessage {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(successMessage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green.opacity(0.9))
            }
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
        }

        if let localError {
            Text(localError)
                .font(.footnote)
                .foregroundStyle(.red.opacity(0.95))
                .multilineTextAlignment(.center)
        }
    }

    private var displayProducts: [Product] {
        switch context {
        case .ppv:
            if let ppv = store.ppvProduct { return [ppv] }
            return []
        default:
            return filteredSubscriptionProducts
        }
    }

    private func productCard(_ product: Product) -> some View {
        let selected = selectedProductID == product.id
        let isCurrent = product.id == currentProductID
        let changeLabel = planChangeLabel(for: product)

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedProductID = product.id
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(StoreProducts.displayName(forProductId: product.id))
                                .font(.headline)
                                .foregroundStyle(Theme.foreground)
                            if isCurrent {
                                Text("CURRENT")
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Theme.accent.opacity(0.2))
                                    .foregroundStyle(Theme.accent)
                                    .clipShape(Capsule())
                            }
                        }
                        Text(product.displayPrice + periodSuffix(for: product))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accentGold)
                    }
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(selected ? Theme.accent : Theme.muted)
                }

                ForEach(StoreProducts.features(forProductId: product.id), id: \.self) { feature in
                    Label(feature, systemImage: "checkmark")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                        .labelStyle(.titleAndIcon)
                }

                if let changeLabel, context == .changePlan, !isCurrent {
                    Text(changeLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(changeLabel.contains("Upgrade") ? .green.opacity(0.9) : Theme.accentGold)
                        .padding(.top, 2)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(selected ? 0.1 : 0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isCurrent ? Color.green.opacity(0.4) : (selected ? Theme.accent : Theme.border),
                            lineWidth: (selected || isCurrent) ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(store.purchaseInFlight)
    }

    private func planChangeLabel(for product: Product) -> String? {
        guard let currentID = currentProductID else { return nil }
        let currentPrice = store.subscriptionProducts.first(where: { $0.id == currentID })?.price ?? 0
        let newPrice = product.price

        if newPrice > currentPrice {
            return "Upgrade — takes effect immediately"
        } else if newPrice < currentPrice {
            return "Downgrade — applies at end of billing period"
        }
        return nil
    }

    private func periodSuffix(for product: Product) -> String {
        guard let period = product.subscription?.subscriptionPeriod else { return "" }
        let unit = period.unit.shortLabel
        let value = period.value
        if value == 1 { return " / \(unit)" }
        return " / \(value) \(unit)s"
    }

    // MARK: - Legal

    private var legalCopy: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Payment will be charged to your Apple ID. Subscription automatically renews unless cancelled at least 24 hours before the end of the current period. Manage or cancel in Settings → Apple ID → Subscriptions.")
                .font(.caption2)
                .foregroundStyle(Theme.muted)
            HStack(spacing: 16) {
                Link("Terms of Use", destination: AppConfig.termsOfUseURL)
                Link("Privacy Policy", destination: AppConfig.privacyPolicyURL)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Footer

    private var footerActions: some View {
        VStack(spacing: 12) {
            Button {
                Task { await purchaseSelected() }
            } label: {
                Group {
                    if store.purchaseInFlight {
                        ProgressView().tint(.black)
                    } else {
                        Text(primaryButtonTitle)
                            .fontWeight(.bold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [Theme.accentGold, Theme.accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .foregroundStyle(.black)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .disabled(store.purchaseInFlight || selectedProduct == nil || selectedProductID == currentProductID)
            .opacity((selectedProduct == nil || selectedProductID == currentProductID) ? 0.55 : 1)

            Button {
                Task { await restore() }
            } label: {
                Text("Restore Purchases")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.muted)
            }
            .disabled(store.purchaseInFlight)

            if store.hasActiveSubscriptionEntitlement || currentProductID != nil {
                Button {
                    openManageSubscriptions()
                } label: {
                    Text("Manage Subscription in Settings")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    private var primaryButtonTitle: String {
        if let selectedProductID, selectedProductID == currentProductID {
            return "This is your current plan"
        }
        switch context {
        case .ppv: return "Unlock with Apple"
        case .reactivate: return "Subscribe with Apple"
        case .changePlan:
            if let selectedProduct, let currentID = currentProductID,
               let currentProduct = store.subscriptionProducts.first(where: { $0.id == currentID }) {
                if selectedProduct.price > currentProduct.price {
                    return "Upgrade with Apple"
                } else {
                    return "Downgrade with Apple"
                }
            }
            return "Change plan with Apple"
        case .subscribe: return "Subscribe with Apple"
        }
    }

    private var selectedProduct: Product? {
        displayProducts.first { $0.id == selectedProductID }
    }

    // MARK: - Actions

    private func purchaseSelected() async {
        guard let product = selectedProduct else { return }
        guard product.id != currentProductID else { return }
        localError = nil
        successMessage = nil
        do {
            switch context {
            case .ppv(let contentId, _):
                _ = try await store.purchasePPVUnlock(contentId: contentId)
            default:
                _ = try await store.purchaseSubscription(product)
            }
            await appState.refreshSubscriptionFromServer()
            didComplete = true
            withAnimation { successMessage = "Plan changed successfully!" }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            onFinished?()
            dismiss()
        } catch {
            let message = error.localizedDescription
            if message.localizedCaseInsensitiveContains("cancel") {
                localError = nil
            } else {
                localError = message
            }
        }
    }

    private func restore() async {
        localError = nil
        do {
            try await store.restorePurchases()
            await appState.refreshSubscriptionFromServer()
            didComplete = true
            onFinished?()
            dismiss()
        } catch {
            localError = error.localizedDescription
        }
    }

    private func openManageSubscriptions() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else { return }
        Task {
            try? await AppStore.showManageSubscriptions(in: scene)
        }
    }
}
