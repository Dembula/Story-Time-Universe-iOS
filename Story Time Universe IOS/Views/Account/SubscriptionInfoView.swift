import SwiftUI

struct SubscriptionInfoView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    private var subscription: ViewerSubscription? { appState.subscription }

    private var planTitle: String {
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
        let status = (subscription?.status ?? "").uppercased()
        if status.isEmpty {
            return StoreService.shared.hasActiveSubscriptionEntitlement ? "Active (Apple)" : "Inactive"
        }
        switch status {
        case "ACTIVE", "TRIALING": return "Active"
        case "PAST_DUE": return "Past due"
        case "CANCELED", "CANCELLED": return "Canceled"
        case "EXPIRED": return "Expired"
        default: return status.capitalized
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    summaryCard

                    Button {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            appState.presentPaywall(.changePlan)
                        }
                    } label: {
                        Text("Change plan")
                            .font(.headline)
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Theme.accent)
                            .clipShape(Capsule())
                    }

                    Text("Subscriptions are billed through your Apple ID. Manage or cancel anytime in Settings → Apple ID → Subscriptions.")
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
                }
            }
            .task {
                await appState.refreshSubscriptionFromServer()
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            row(title: "Plan", value: planTitle)
            row(title: "Status", value: statusLabel)
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
}
