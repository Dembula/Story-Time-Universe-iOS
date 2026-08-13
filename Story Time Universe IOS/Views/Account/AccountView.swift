import SwiftUI

struct AccountView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var parental = ParentalControls.shared
    @State private var webDestination: WebDestination?
    @State private var showDelete = false
    @State private var showParental = false
    @State private var showAgeAssurance = false
    @State private var showAccountInfo = false
    @State private var showPlaybackHelp = false
    @State private var showSubscriptionInfo = false

    private struct WebDestination: Identifiable {
        let id = UUID()
        let url: URL
        let title: String
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    profileHeaderCard

                    settingsGroup(title: nil) {
                        settingsRow(
                            title: "Account info",
                            subtitle: appState.session?.user?.email ?? "Name, email, phone, address and plan",
                            systemImage: "person.crop.circle"
                        ) {
                            showAccountInfo = true
                        }
                    }

                    settingsGroup(title: nil) {
                        settingsRow(title: "Subscription", subtitle: subscriptionSubtitle, systemImage: "rectangle.stack.fill") {
                            showSubscriptionInfo = true
                        }
                        if appState.needsPaymentAttention {
                            settingsRow(title: "Reactivate access", subtitle: "Subscribe again with Apple", systemImage: "exclamationmark.circle") {
                                appState.presentPaywall(.reactivate)
                            }
                        }
                        settingsRow(title: "Change plan", subtitle: "Packages billed through the App Store", systemImage: "arrow.triangle.2.circlepath") {
                            appState.presentPaywall(.changePlan)
                        }
                        settingsRow(title: "Downloads", subtitle: "View offline titles", systemImage: "arrow.down.circle") {
                            appState.openDownloads()
                        }
                    }

                    settingsGroup(title: "Privacy & Family") {
                        settingsRow(
                            title: "Parental Controls",
                            subtitle: parental.isEnabled ? "On · \(parental.maturityLabel)" : "Off · age assurance via profiles",
                            systemImage: "lock.shield.fill"
                        ) {
                            showParental = true
                        }
                        settingsRow(
                            title: "Age Assurance",
                            subtitle: "How we verify age · current profile: \(appState.activeProfile?.ageLabel ?? "—")",
                            systemImage: "figure.and.child.holdinghands"
                        ) {
                            showAgeAssurance = true
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Allow Notifications on This iPhone")
                            .font(.headline)
                            .foregroundStyle(Theme.foreground)
                        Text("You’ll get updates for new titles, continue watching, and account activity when notifications are enabled in iOS Settings.")
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .padding(.top, 4)

                    HStack(spacing: 10) {
                        quickAction(title: "Switch\nProfile", systemImage: "person.2.fill") {
                            appState.switchProfile()
                        }
                        quickAction(title: "Account\nInfo", systemImage: "person.text.rectangle") {
                            showAccountInfo = true
                        }
                        quickAction(title: "Playback\nHelp", systemImage: "play.rectangle.fill") {
                            showPlaybackHelp = true
                        }
                    }

                    VStack(spacing: 0) {
                        Button {
                            Task { await appState.signOut() }
                        } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .foregroundStyle(.red.opacity(0.95))
                        }
                        Divider().background(Theme.border)
                        Button {
                            showDelete = true
                        } label: {
                            Label("Delete Account", systemImage: "trash")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .foregroundStyle(.red.opacity(0.85))
                        }
                    }
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(20)
                .padding(.bottom, 40)
                .trackScrollForTabBar()
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Account")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .task {
                await appState.refreshSubscriptionFromServer()
            }
            .sheet(item: $webDestination) { dest in
                AuthenticatedWebBrowser(url: dest.url, title: dest.title, mode: .account)
            }
            .sheet(isPresented: $showAccountInfo) {
                AccountInfoView()
                    .environmentObject(appState)
            }
            .sheet(isPresented: $showPlaybackHelp) {
                PlaybackHelpView()
            }
            .sheet(isPresented: $showParental) {
                ParentalControlsView()
            }
            .sheet(isPresented: $showSubscriptionInfo) {
                SubscriptionInfoView()
                    .environmentObject(appState)
            }
            .sheet(isPresented: $showDelete) {
                DeleteAccountView()
            }
            .sheet(isPresented: $showAgeAssurance) {
                AgeAssuranceView()
            }
        }
    }

    private var subscriptionSubtitle: String {
        let plan = friendlyPlan(appState.subscription?.plan)
        let status = appState.subscription?.status ?? "—"
        return "\(plan) · \(status)"
    }

    private var profileHeaderCard: some View {
        Button {
            showAccountInfo = true
        } label: {
            HStack(spacing: 14) {
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
                        .frame(width: 56, height: 56)
                    Text(String((appState.activeProfile?.name ?? "?").prefix(1)).uppercased())
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(appState.activeProfile?.name ?? appState.session?.user?.name ?? "Account")
                        .font(.headline)
                        .foregroundStyle(Theme.foreground)
                    Text("Account info, subscription and settings")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.muted)
            }
            .padding(16)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func settingsGroup(title: String?, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 4)
            }
            VStack(spacing: 0) {
                content()
            }
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func settingsRow(title: String, subtitle: String?, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.foreground)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func quickAction(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(height: 28)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func openWeb(_ url: URL, title: String) {
        webDestination = WebDestination(url: url, title: title)
    }

    private func friendlyPlan(_ plan: String?) -> String {
        guard let plan else {
            if appState.isPayPerViewAccount { return "Pay Per View" }
            return "No plan"
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
}

// MARK: - Parental Controls

struct ParentalControlsView: View {
    @ObservedObject private var parental = ParentalControls.shared
    @Environment(\.dismiss) private var dismiss
    @State private var pinInput = ""
    @State private var unlockError: String?
    @State private var unlocked = false
    @State private var newPIN = ""
    @State private var confirmPIN = ""

    var body: some View {
        NavigationStack {
            Form {
                if parental.hasPIN && !unlocked {
                    Section("Enter PIN to manage") {
                        SecureField("4-digit PIN", text: $pinInput)
                            .keyboardType(.numberPad)
                        if let unlockError {
                            Text(unlockError).foregroundStyle(.red)
                        }
                        Button("Unlock") {
                            if parental.verifyPIN(pinInput) {
                                unlocked = true
                                unlockError = nil
                            } else {
                                unlockError = "Incorrect PIN."
                            }
                        }
                    }
                } else {
                    Section {
                        Toggle("Enable Parental Controls", isOn: $parental.isEnabled)
                        Text("When enabled, catalogue titles above the maturity limit are hidden. Profile date of birth provides age assurance for each profile.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Section("Maturity limit") {
                        Picker("Maximum content age", selection: $parental.maxMaturityAge) {
                            Text("Kids (12)").tag(12)
                            Text("Teen (15)").tag(15)
                            Text("Young adult (17)").tag(17)
                            Text("Adult (18+)").tag(18)
                        }
                    }

                    Section("Restrictions") {
                        Toggle("Require PIN to switch profiles", isOn: $parental.requirePinToSwitchProfile)
                        Toggle("Require PIN before playback", isOn: $parental.requirePinForPlayer)
                        Toggle("Block new downloads", isOn: $parental.blockDownloads)
                    }

                    Section("PIN") {
                        if parental.hasPIN {
                            Text("PIN is active on this device")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            SecureField("New PIN (optional)", text: $newPIN)
                                .keyboardType(.numberPad)
                            SecureField("Confirm new PIN", text: $confirmPIN)
                                .keyboardType(.numberPad)
                            Button("Update PIN") {
                                guard newPIN.count == 4, newPIN == confirmPIN else { return }
                                parental.setPIN(newPIN)
                                newPIN = ""
                                confirmPIN = ""
                            }
                            Button("Remove PIN", role: .destructive) {
                                parental.clearPIN()
                            }
                        } else {
                            SecureField("Set 4-digit PIN", text: $newPIN)
                                .keyboardType(.numberPad)
                            SecureField("Confirm PIN", text: $confirmPIN)
                                .keyboardType(.numberPad)
                            Button("Save PIN") {
                                guard newPIN.count == 4, newPIN == confirmPIN else { return }
                                parental.setPIN(newPIN)
                                newPIN = ""
                                confirmPIN = ""
                            }
                        }
                        Text("PIN is stored on this device only. Maturity limits may sync from your account settings when available; the PIN does not sync from the website.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Section("Age Assurance") {
                        Text("Each viewer profile is created with a date of birth. Kids, Teen and Adult labels are used for age assurance throughout the app.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Parental Controls")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                if !parental.hasPIN { unlocked = true }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Delete Account

struct DeleteAccountView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirmation = ""
    @State private var errorMessage: String?
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("This permanently deletes your Story Time account and associated data. This cannot be undone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Confirm") {
                    SecureField("Account password", text: $password)
                    TextField("Type DELETE to confirm", text: $confirmation)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
                Section {
                    Button(role: .destructive) {
                        Task { await delete() }
                    } label: {
                        if isWorking {
                            ProgressView()
                        } else {
                            Text("Delete Account Permanently")
                        }
                    }
                    .disabled(isWorking || password.isEmpty || confirmation.uppercased() != "DELETE")
                }
            }
            .navigationTitle("Delete Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func delete() async {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            try await appState.deleteAccount(password: password)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Age Assurance (in-app controls for App Store 2.3.6)

struct AgeAssuranceView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var parental = ParentalControls.shared
    @Environment(\.dismiss) private var dismiss

    private var profile: ViewerProfile? { appState.activeProfile }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    infoCard {
                        Label("How age is verified", systemImage: "checkmark.shield.fill")
                            .font(.headline)
                            .foregroundStyle(Theme.accentGold)
                        Text("Each profile is created with a date of birth. Story Time uses that age for catalogue eligibility and parental maturity limits on this device.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                    }

                    infoCard {
                        Text("Active profile")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.muted)
                        Text(profile?.name ?? "No profile selected")
                            .font(.title3.bold())
                            .foregroundStyle(Theme.foreground)
                        HStack(spacing: 10) {
                            badge(profile?.ageLabel ?? "—")
                            if let age = profile?.age {
                                badge("Age \(age)")
                            }
                        }
                        if let dob = profile?.dateOfBirth, !dob.isEmpty {
                            Text("Date of birth on file: \(formatDOB(dob))")
                                .font(.footnote)
                                .foregroundStyle(Theme.muted)
                        }
                    }

                    infoCard {
                        Text("Parental maturity gate")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.muted)
                        Text(parental.isEnabled ? "Enabled · \(parental.maturityLabel)" : "Off — only the profile age limit applies")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.foreground)
                        Text("Titles rated above the allowed age are hidden from Home, Search, See All, My List, and related rows while parental controls are on.")
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)
                    }

                    infoCard {
                        Text("This device")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.muted)
                        Text(DeviceIdentity.deviceSummary)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.foreground)
                        Text("Sign-ins and watch activity from this app are reported as iOS so the platform can attribute views correctly.")
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)
                    }
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle("Age Assurance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func infoCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.accentSoft)
            .foregroundStyle(Theme.accentGold)
            .clipShape(Capsule())
    }

    private func formatDOB(_ raw: String) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) {
            return d.formatted(date: .abbreviated, time: .omitted)
        }
        if raw.count >= 10 {
            return String(raw.prefix(10))
        }
        return raw
    }
}
