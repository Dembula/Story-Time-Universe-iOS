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
                    Button(contextAllowsDismiss ? "Close" : "Not now") {
                        dismiss()
                    }
                    .foregroundStyle(Theme.accent)
                    .disabled(store.purchaseInFlight)
                }
            }
            .task {
                store.start()
                await store.refreshProducts()
                if selectedProductID == nil {
                    selectedProductID = preferredDefaultProductID
                }
            }
            .interactiveDismissDisabled(store.purchaseInFlight)
        }
        .preferredColorScheme(.dark)
    }

    private var contextAllowsDismiss: Bool {
        switch context {
        case .subscribe: return true
        case .reactivate, .changePlan, .ppv: return true
        }
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
        default:
            return store.subscriptionProducts.first(where: { $0.id == StoreProducts.standardMonthly })?.id
                ?? store.subscriptionProducts.first?.id
        }
    }

    // MARK: - Sections

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
        case .subscribe:
            return "Subscribe to Story Time"
        case .reactivate:
            return "Reactivate your access"
        case .changePlan:
            return "Pick a different plan"
        case .ppv(_, let title):
            return title.map { "Unlock \($0)" } ?? "Unlock this title"
        }
    }

    private var subheadline: String {
        switch context {
        case .ppv:
            return "One-time purchase via Apple. Payment is handled securely by the App Store."
        default:
            return "Payment is handled securely by Apple. Subscriptions auto-renew unless cancelled at least 24 hours before the period ends."
        }
    }

    @ViewBuilder
    private var productList: some View {
        if store.isLoadingProducts && displayProducts.isEmpty {
            ProgressView()
                .tint(Theme.accent)
                .padding(.vertical, 40)
        } else if displayProducts.isEmpty {
            VStack(spacing: 12) {
                Text(store.lastError ?? "Plans are temporarily unavailable.")
                    .font(.footnote)
                    .foregroundStyle(.red.opacity(0.9))
                    .multilineTextAlignment(.center)
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
            return store.subscriptionProducts
        }
    }

    private func productCard(_ product: Product) -> some View {
        let selected = selectedProductID == product.id
        return Button {
            selectedProductID = product.id
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(StoreProducts.displayName(forProductId: product.id))
                            .font(.headline)
                            .foregroundStyle(Theme.foreground)
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
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(selected ? 0.1 : 0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selected ? Theme.accent : Theme.border, lineWidth: selected ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(store.purchaseInFlight)
    }

    private func periodSuffix(for product: Product) -> String {
        guard let period = product.subscription?.subscriptionPeriod else { return "" }
        let unit = period.unit.shortLabel
        let value = period.value
        if value == 1 { return " / \(unit)" }
        return " / \(value) \(unit)s"
    }

    private var legalCopy: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Payment will be charged to your Apple ID. Subscription automatically renews unless cancelled at least 24 hours before the end of the current period. Manage or cancel in Settings → Apple ID → Subscriptions.")
                .font(.caption2)
                .foregroundStyle(Theme.muted)
            HStack(spacing: 16) {
                Link("Terms of Use", destination: URL(string: "https://story-time.online/terms")!)
                Link("Privacy Policy", destination: URL(string: "https://story-time.online/privacy")!)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

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
            .disabled(store.purchaseInFlight || selectedProduct == nil)
            .opacity(selectedProduct == nil ? 0.55 : 1)

            Button {
                Task { await restore() }
            } label: {
                Text("Restore Purchases")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.muted)
            }
            .disabled(store.purchaseInFlight)
        }
    }

    private var primaryButtonTitle: String {
        switch context {
        case .ppv: return "Unlock with Apple"
        case .reactivate: return "Subscribe with Apple"
        case .changePlan: return "Change plan with Apple"
        case .subscribe: return "Subscribe with Apple"
        }
    }

    private var selectedProduct: Product? {
        displayProducts.first { $0.id == selectedProductID }
    }

    // MARK: - Actions

    private func purchaseSelected() async {
        guard let product = selectedProduct else { return }
        localError = nil
        do {
            switch context {
            case .ppv(let contentId, _):
                _ = try await store.purchasePPVUnlock(contentId: contentId)
            default:
                _ = try await store.purchaseSubscription(product)
            }
            await appState.refreshSubscriptionFromServer()
            didComplete = true
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
}
