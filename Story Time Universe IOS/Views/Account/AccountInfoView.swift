import SwiftUI

/// Native summary of the viewer’s web account details (no subscription picker / web shell).
struct AccountInfoView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var settings: ViewerSettingsResponse?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && settings == nil {
                    ProgressView("Loading your details…")
                        .tint(Theme.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            heroCard

                            if let errorMessage {
                                Text(errorMessage)
                                    .font(.footnote)
                                    .foregroundStyle(.red.opacity(0.9))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 4)
                            }

                            sectionCard(title: "Personal details", systemImage: "person.fill") {
                                infoRow(label: "Full name", value: displayName)
                                infoRow(label: "Email", value: displayEmail)
                                infoRow(label: "Phone number", value: displayPhone)
                            }

                            sectionCard(title: "Address", systemImage: "house.fill") {
                                if addressLines.isEmpty {
                                    Text("No address on file yet.")
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.muted)
                                } else {
                                    ForEach(Array(addressLines.enumerated()), id: \.offset) { _, line in
                                        Text(line)
                                            .font(.body)
                                            .foregroundStyle(Theme.foreground)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }

                            sectionCard(title: "Subscription", systemImage: "rectangle.stack.fill") {
                                infoRow(label: "Plan", value: planLabel)
                                infoRow(label: "Status", value: statusLabel)
                                if let model = modelLabel {
                                    infoRow(label: "Account type", value: model)
                                }
                                if let devices = settings?.subscription?.deviceCount {
                                    infoRow(label: "Devices", value: "\(devices)")
                                }
                                if let limit = settings?.subscription?.profileLimit {
                                    infoRow(label: "Profile limit", value: "\(limit)")
                                }
                            }

                            if let methods = settings?.paymentMethods, !methods.isEmpty {
                                sectionCard(title: "Payment methods", systemImage: "creditcard.fill") {
                                    ForEach(methods) { method in
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(method.label?.nilIfEmpty ?? "Card")
                                                    .font(.body.weight(.medium))
                                                    .foregroundStyle(Theme.foreground)
                                                if let last = method.lastFour?.nilIfEmpty {
                                                    Text("•••• \(last)")
                                                        .font(.caption)
                                                        .foregroundStyle(Theme.muted)
                                                }
                                            }
                                            Spacer()
                                            if method.isDefault == true {
                                                Text("Default")
                                                    .font(.caption2.weight(.bold))
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 4)
                                                    .background(Theme.accentSoft)
                                                    .foregroundStyle(Theme.accentGold)
                                                    .clipShape(Capsule())
                                            }
                                        }
                                    }
                                }
                            }

                            if let profiles = settings?.profiles, !profiles.isEmpty {
                                sectionCard(title: "Profiles", systemImage: "person.2.fill") {
                                    ForEach(profiles) { profile in
                                        HStack(spacing: 12) {
                                            ZStack {
                                                Circle()
                                                    .fill(Theme.profileColor(for: profile.id))
                                                    .frame(width: 36, height: 36)
                                                Text(String((profile.name ?? "?").prefix(1)).uppercased())
                                                    .font(.subheadline.bold())
                                                    .foregroundStyle(.white)
                                            }
                                            VStack(alignment: .leading, spacing: 2) {
                                                HStack(spacing: 6) {
                                                    Text(profile.name ?? "Profile")
                                                        .font(.body.weight(.semibold))
                                                        .foregroundStyle(Theme.foreground)
                                                    if profile.id == settings?.activeProfileId
                                                        || profile.id == appState.activeProfile?.id {
                                                        Text("Active")
                                                            .font(.caption2.weight(.bold))
                                                            .foregroundStyle(Theme.accent)
                                                    }
                                                }
                                                Text(profileAgeLabel(profile))
                                                    .font(.caption)
                                                    .foregroundStyle(Theme.muted)
                                            }
                                            Spacer()
                                            if profile.pinEnabled == true {
                                                Image(systemName: "lock.fill")
                                                    .font(.caption)
                                                    .foregroundStyle(Theme.muted)
                                            }
                                        }
                                    }
                                }
                            }

                            if let prefs = settings?.preferences {
                                sectionCard(title: "Preferences", systemImage: "slider.horizontal.3") {
                                    infoRow(
                                        label: "Email notifications",
                                        value: (prefs.notifyEmail ?? true) ? "On" : "Off"
                                    )
                                    infoRow(
                                        label: "Playback quality",
                                        value: (prefs.playbackQuality ?? "auto").capitalized
                                    )
                                }
                            }

                            Text("This is a read-only summary of what you set up on Story Time. Contact support if something needs updating.")
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                                .padding(.horizontal, 4)
                                .padding(.top, 4)
                                .padding(.bottom, 24)
                        }
                        .padding(20)
                    }
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Account info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
            .task { await load() }
            .refreshable { await load() }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Display helpers

    private var displayName: String {
        settings?.account?.name?.nilIfEmpty
            ?? appState.session?.user?.name
            ?? appState.activeProfile?.name
            ?? "—"
    }

    private var displayEmail: String {
        settings?.account?.email?.nilIfEmpty
            ?? appState.session?.user?.email
            ?? "—"
    }

    private var displayPhone: String {
        settings?.account?.phoneNumber?.nilIfEmpty ?? "Not provided"
    }

    private var addressLines: [String] {
        settings?.address?.formattedLines ?? []
    }

    private var planLabel: String {
        let plan = settings?.subscription?.plan ?? appState.subscription?.plan
        return friendlyPlan(plan)
    }

    private var statusLabel: String {
        settings?.subscription?.status
            ?? appState.subscription?.status
            ?? "—"
    }

    private var modelLabel: String? {
        let raw = (settings?.subscription?.viewerModel ?? appState.subscription?.viewerModel)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw, !raw.isEmpty else { return nil }
        if raw.uppercased().contains("PPV") || raw.uppercased().contains("PAY") {
            return "Pay Per View"
        }
        return raw.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private var heroCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Theme.profileColor(for: appState.activeProfile?.id ?? "a"),
                                Theme.accent.opacity(0.75),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)
                Text(String(displayName.prefix(1)).uppercased())
                    .font(.title.bold())
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.title3.bold())
                    .foregroundStyle(Theme.foreground)
                Text(displayEmail)
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                if let profile = appState.activeProfile {
                    Text("Watching as \(profile.name) · \(profile.ageLabel)")
                        .font(.caption)
                        .foregroundStyle(Theme.accentGold)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.10), Color.white.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
    }

    private func sectionCard<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accentGold)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func infoRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.muted)
            Text(value)
                .font(.body)
                .foregroundStyle(Theme.foreground)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }

    private func profileAgeLabel(_ profile: ViewerSettingsProfile) -> String {
        var parts: [String] = []
        if let age = profile.age {
            if age <= 12 { parts.append("Kids") }
            else if age <= 15 { parts.append("Teen") }
            else { parts.append("Adult") }
            parts.append("Age \(age)")
        }
        return parts.isEmpty ? "Profile" : parts.joined(separator: " · ")
    }

    private func friendlyPlan(_ plan: String?) -> String {
        guard let plan, !plan.isEmpty else {
            return appState.isPayPerViewAccount ? "Pay Per View" : "No plan"
        }
        switch plan.uppercased() {
        case "BASE_1": return "Base"
        case "STANDARD_3": return "Standard"
        case "FAMILY_5": return "Family"
        case "PPV_FILM", "PPV", "PAY_PER_VIEW": return "Pay Per View"
        default:
            if plan.uppercased().contains("PPV") { return "Pay Per View" }
            return plan.replacingOccurrences(of: "_", with: " ")
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await ViewerAPI.shared.fetchViewerSettings()
            settings = loaded
            errorMessage = nil
            if appState.subscription == nil {
                appState.subscription = try? await ViewerAPI.shared.fetchSubscription()
            }
        } catch {
            // Fall back to session + subscription already in app state.
            errorMessage = "Couldn’t refresh full details. Showing what we have on this device."
            if settings == nil {
                settings = ViewerSettingsResponse(
                    account: ViewerAccountDetails(
                        name: appState.session?.user?.name,
                        email: appState.session?.user?.email,
                        phoneNumber: nil,
                        onboardingComplete: nil
                    ),
                    address: nil,
                    preferences: nil,
                    paymentMethods: nil,
                    profiles: appState.activeProfile.map {
                        [ViewerSettingsProfile(
                            id: $0.id,
                            name: $0.name,
                            age: $0.age,
                            dateOfBirth: $0.dateOfBirth,
                            pinEnabled: $0.pinEnabled
                        )]
                    },
                    activeProfileId: appState.activeProfile?.id,
                    subscription: appState.subscription.map {
                        ViewerSettingsSubscription(
                            id: $0.id,
                            plan: $0.plan,
                            viewerModel: $0.viewerModel,
                            deviceCount: $0.deviceCount,
                            profileLimit: $0.profileLimit,
                            status: $0.status
                        )
                    },
                    warnings: nil
                )
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
