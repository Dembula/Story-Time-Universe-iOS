import SwiftUI

struct SubscriptionInfoView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var store = StoreService.shared
    @Environment(\.dismiss) private var dismiss

    private var subscription: ViewerSubscription? { appState.subscription }

    private var planTitle: String {
        if let currentID = store.activeSubscriptionProductID {
            return StoreProducts.displayName(forProductId: currentID)
        }
        let raw = subscription?.plan?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if raw.isEmpty {
            if appState.isPayPerViewAccount { return "Pay Per View" }
            return "No active plan"
        }
        switch raw.uppercased() {
        case "BASE_1", "BASE": return "Base"
        case "STANDARD_3", "STANDARD": return "Standard"
        case "FAMILY_5", "FAMILY": return "Family"
        case "PPV": return "Pay Per View"
        default: return raw.replacingOccurrences(of: "_", with: " ")
        }
    }

    private var statusLabel: String {
        if store.hasActiveSubscriptionEntitlement {
            return "Active"
        }
        let status = (subscription?.status ?? "").uppercased()
        if status.isEmpty { return "Inactive" }
        switch status {
        case "ACTIVE", "TRIALING": return "Active"
        case "PAST_DUE": return "Past due"
        case "CANCELED", "CANCELLED": return "Canceled"
        case "EXPIRED": return "Expired"
        default: return status.capitalized
        }
    }

    private var statusColor: Color {
        switch statusLabel {
        case "Active": return .green.opacity(0.9)
        case "Past due": return .orange
        case "Canceled", "Expired": return .red.opacity(0.8)
        default: return Theme.muted
        }
    }

    private var renewalLine: String? {
        guard let end = subscription?.currentPeriodEnd?.trimmingCharacters(in: .whitespacesAndNewlines),
              !end.isEmpty else { return nil }
        if subscription?.cancelAtPeriodEnd == true {
            return "Access ends \(friendlyDate(end))"
        }
        return "Renews \(friendlyDate(end))"
    }

    private var priceLabel: String? {
        guard let currentID = store.activeSubscriptionProductID,
              let product = store.subscriptionProducts.first(where: { $0.id == currentID }) else { return nil }
        let suffix: String
        if let period = product.subscription?.subscriptionPeriod {
            suffix = period.unit == .year ? " / year" : " / month"
        } else {
            suffix = ""
        }
        return product.displayPrice + suffix
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    summaryCard

                    actionButtons

                    Text("Subscriptions are billed through your Apple ID. Manage, upgrade, downgrade, or cancel anytime in Settings → Apple ID → Subscriptions.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }
                .padding(20)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Subscription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
            .task {
                store.start()
                await store.refreshEntitlements()
                await appState.refreshSubscriptionFromServer()
            }
        }
        .preferredColorScheme(.dark)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(planTitle)
                    .font(.title3.bold())
                    .foregroundStyle(Theme.foreground)
                Spacer()
                Text(statusLabel)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.15))
                    .foregroundStyle(statusColor)
                    .clipShape(Capsule())
            }

            if let priceLabel {
                row(title: "Price", value: priceLabel)
            }

            if let renewalLine {
                row(title: "Billing", value: renewalLine)
            }
            if let limit = subscription?.profileLimit {
                row(title: "Profiles", value: "Up to \(limit)")
            }
            if let devices = subscription?.deviceCount {
                row(title: "Devices", value: "\(devices)")
            }
            if appState.isPayPerViewAccount {
                row(title: "Model", value: "Unlock titles individually")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    appState.presentPaywall(.changePlan)
                }
            } label: {
                Text("Change Plan")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            if store.hasActiveSubscriptionEntitlement || store.activeSubscriptionProductID != nil {
                Button {
                    openManageSubscriptions()
                } label: {
                    Text("Manage in App Store Settings")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.accent.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }

            if !store.hasActiveSubscriptionEntitlement, store.activeSubscriptionProductID == nil {
                Button {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        appState.presentPaywall(.reactivate)
                    }
                } label: {
                    Text("Reactivate Subscription")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accentGold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.accentGold.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
    }

    private func row(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.foreground)
                .multilineTextAlignment(.trailing)
        }
    }

    private func friendlyDate(_ raw: String) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) {
            return date.formatted(date: .abbreviated, time: .omitted)
        }
        if let prefix = raw.split(separator: "T").first {
            return String(prefix)
        }
        return raw
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
