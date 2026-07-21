import SwiftUI

struct AccountView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    profileHero

                    subscriptionCard

                    VStack(spacing: 12) {
                        Button {
                            appState.switchProfile()
                        } label: {
                            Label("Switch Profile", systemImage: "person.2.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Theme.accentSoft)
                                .foregroundStyle(Theme.accentGold)
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.accent.opacity(0.35)))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }

                        Button(role: .destructive) {
                            Task { await appState.signOut() }
                        } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.red.opacity(0.12))
                                .foregroundStyle(.red.opacity(0.95))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                }
                .padding(20)
                .padding(.bottom, 24)
            }
            .background {
                ZStack {
                    Theme.background
                    Circle()
                        .fill(Theme.accent.opacity(0.14))
                        .frame(width: 280, height: 280)
                        .blur(radius: 60)
                        .offset(x: 120, y: -180)
                }
                .ignoresSafeArea()
            }
            .navigationTitle("Account")
            .task {
                appState.subscription = try? await ViewerAPI.shared.fetchSubscription()
            }
        }
    }

    private var profileHero: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Theme.profileColor(for: appState.activeProfile?.id ?? "a"),
                                Theme.accent.opacity(0.7),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 68, height: 68)
                Text(String((appState.activeProfile?.name ?? "?").prefix(1)).uppercased())
                    .font(.title.bold())
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(appState.activeProfile?.name ?? "Profile")
                    .font(.title3.bold())
                    .foregroundStyle(Theme.foreground)
                Text(appState.session?.user?.email ?? "")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                if let label = appState.activeProfile?.ageLabel {
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.accentSoft)
                        .foregroundStyle(Theme.accentGold)
                        .clipShape(Capsule())
                }
            }
            Spacer()
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.08), Color.white.opacity(0.03)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.border))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var subscriptionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Subscription")
                    .font(.headline)
                Spacer()
                Text(appState.subscription?.status ?? "—")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(statusColor.opacity(0.18))
                    .foregroundStyle(statusColor)
                    .clipShape(Capsule())
            }

            infoRow(title: "Plan", value: friendlyPlan(appState.subscription?.plan))
            if let end = appState.subscription?.currentPeriodEnd {
                infoRow(title: "Period ends", value: formatDate(end))
            }
            if let model = appState.subscription?.viewerModel {
                infoRow(title: "Model", value: model.replacingOccurrences(of: "_", with: " ").capitalized)
            }
        }
        .padding(18)
        .background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.accent.opacity(0.2)))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func infoRow(title: String, value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(Theme.muted)
            Spacer()
            Text(value).foregroundStyle(Theme.foreground).fontWeight(.semibold)
        }
        .font(.subheadline)
    }

    private var statusColor: Color {
        switch appState.subscription?.status?.uppercased() {
        case "ACTIVE", "TRIAL_ACTIVE": return .green
        case "PAST_DUE": return Theme.accent
        default: return Theme.muted
        }
    }

    private func friendlyPlan(_ plan: String?) -> String {
        guard let plan else { return "—" }
        switch plan.uppercased() {
        case "BASE_1": return "Base (1 profile)"
        case "STANDARD_3": return "Standard (3 profiles)"
        case "FAMILY_5": return "Family (5 profiles)"
        case "PPV_FILM": return "Single title"
        default: return plan.replacingOccurrences(of: "_", with: " ")
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
