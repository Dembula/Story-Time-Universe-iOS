import SwiftUI

struct AccountView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Theme.profileColor(for: appState.activeProfile?.id ?? "a"))
                                .frame(width: 56, height: 56)
                            Text(String((appState.activeProfile?.name ?? "?").prefix(1)).uppercased())
                                .font(.title2.bold())
                                .foregroundStyle(.white)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(appState.activeProfile?.name ?? "Profile")
                                .font(.headline)
                            Text(appState.session?.user?.email ?? "")
                                .font(.footnote)
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    .listRowBackground(Theme.card)
                }

                Section("Subscription") {
                    LabeledContent("Plan", value: appState.subscription?.plan ?? "—")
                    LabeledContent("Status", value: appState.subscription?.status ?? "—")
                    if let end = appState.subscription?.currentPeriodEnd {
                        LabeledContent("Renews", value: formatDate(end))
                    }

                    Link(destination: AppConfig.renewSubscriptionURL) {
                        Label("Renew / Pay on Web", systemImage: "safari")
                            .foregroundStyle(Theme.accent)
                    }
                    Link(destination: AppConfig.changePlanURL) {
                        Label("Change plan on Web", systemImage: "arrow.triangle.2.circlepath")
                            .foregroundStyle(Theme.accentGold)
                    }
                    Link(destination: AppConfig.accountURL) {
                        Label("Manage account on Web", systemImage: "person.crop.circle")
                    }
                }
                .listRowBackground(Theme.card)

                Section {
                    Text("Payments are handled only on the Story Time website. The app never processes card payments.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                        .listRowBackground(Theme.card)
                }

                Section {
                    Button("Switch Profile") {
                        appState.switchProfile()
                    }
                    Button("Sign Out", role: .destructive) {
                        Task { await appState.signOut() }
                    }
                }
                .listRowBackground(Theme.card)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Account")
            .task {
                appState.subscription = try? await ViewerAPI.shared.fetchSubscription()
            }
        }
    }

    private func formatDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let date else { return iso }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}
