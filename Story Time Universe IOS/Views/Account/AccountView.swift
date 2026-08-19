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
            .tabScrollCoordinateSpace()
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
    @State private var pinError: String?
    @State private var pinSuccess: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if parental.hasPIN && !unlocked {
                        lockGate
                    } else {
                        enableSection
                        if parental.isEnabled {
                            maturitySection
                            restrictionsSection
                        }
                        pinSection
                        ageAssuranceNote
                    }
                }
                .padding(20)
                .padding(.bottom, 32)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Parental Controls")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
            .onAppear {
                if !parental.hasPIN { unlocked = true }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Lock gate

    private var lockGate: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 48))
                .foregroundStyle(Theme.accent)
                .padding(.top, 24)

            Text("Enter your PIN to manage parental controls")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)

            pinDots(value: pinInput)

            numPad(value: $pinInput) {
                if parental.verifyPIN(pinInput) {
                    withAnimation(.easeInOut(duration: 0.25)) { unlocked = true }
                    unlockError = nil
                } else {
                    unlockError = "Incorrect PIN"
                    pinInput = ""
                }
            }

            if let unlockError {
                Text(unlockError)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.red)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Enable toggle

    private var enableSection: some View {
        cardSection {
            HStack {
                Image(systemName: "lock.shield.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Parental Controls")
                        .font(.headline)
                        .foregroundStyle(Theme.foreground)
                    Text(parental.isEnabled ? "Active — content is filtered" : "Off — all content visible")
                        .font(.caption)
                        .foregroundStyle(parental.isEnabled ? .green.opacity(0.9) : Theme.muted)
                }
                Spacer()
                Toggle("", isOn: $parental.isEnabled.animation(.easeInOut(duration: 0.25)))
                    .labelsHidden()
                    .tint(Theme.accent)
            }
            Text("When enabled, titles above the maturity limit are hidden from Home, Search, My List, and all browsing areas. Profile date of birth provides age assurance.")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
        }
    }

    // MARK: - Maturity picker

    private var maturitySection: some View {
        cardSection {
            Text("Maturity Limit")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.muted)
            ForEach(maturityOptions, id: \.age) { option in
                maturityRow(option)
            }
            Text("Content rated above this limit will be hidden throughout the app.")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
                .padding(.top, 4)
        }
    }

    private struct MaturityOption {
        let age: Int
        let label: String
        let description: String
        let icon: String
    }

    private var maturityOptions: [MaturityOption] {
        [
            .init(age: 7, label: "Little Kids", description: "Ages 7 and under", icon: "figure.child"),
            .init(age: 12, label: "Kids", description: "Ages 12 and under", icon: "figure.and.child.holdinghands"),
            .init(age: 15, label: "Teens", description: "Ages 15 and under", icon: "person.fill"),
            .init(age: 17, label: "Young Adults", description: "Ages 17 and under", icon: "person.2.fill"),
            .init(age: 18, label: "All Content", description: "No restrictions", icon: "globe"),
        ]
    }

    private func maturityRow(_ option: MaturityOption) -> some View {
        let selected = parental.maxMaturityAge == option.age
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                parental.maxMaturityAge = option.age
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: option.icon)
                    .font(.body)
                    .foregroundStyle(selected ? Theme.accent : Theme.muted)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.label)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.foreground)
                    Text(option.description)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Theme.accent : Theme.muted.opacity(0.4))
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Restrictions

    private var restrictionsSection: some View {
        cardSection {
            Text("Restrictions")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.muted)
            restrictionToggle("Require PIN to switch profiles", icon: "person.2.fill", isOn: $parental.requirePinToSwitchProfile)
            restrictionToggle("Require PIN before playback", icon: "play.fill", isOn: $parental.requirePinForPlayer)
            restrictionToggle("Block new downloads", icon: "arrow.down.circle", isOn: $parental.blockDownloads)
        }
    }

    private func restrictionToggle(_ title: String, icon: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(Theme.accent)
                .frame(width: 26)
            Text(title)
                .font(.body)
                .foregroundStyle(Theme.foreground)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Theme.accent)
        }
        .padding(.vertical, 4)
    }

    // MARK: - PIN management

    private var pinSection: some View {
        cardSection {
            HStack {
                Text("Device PIN")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.muted)
                Spacer()
                if parental.hasPIN {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundStyle(.green.opacity(0.8))
                        .font(.caption)
                    Text("Active")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green.opacity(0.8))
                }
            }

            if parental.hasPIN {
                Text("Your 4-digit PIN protects parental settings on this device.")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)

                HStack(spacing: 10) {
                    SecureField("New PIN", text: $newPIN)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .padding(12)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    SecureField("Confirm", text: $confirmPIN)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .padding(12)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                if let pinError {
                    Text(pinError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                if let pinSuccess {
                    Text(pinSuccess)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.green.opacity(0.9))
                }

                HStack(spacing: 12) {
                    Button {
                        attemptUpdatePIN()
                    } label: {
                        Text("Update PIN")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Theme.accent.opacity(0.15))
                            .foregroundStyle(Theme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    Button {
                        parental.clearPIN()
                        newPIN = ""
                        confirmPIN = ""
                        pinError = nil
                        pinSuccess = "PIN removed"
                        clearSuccessAfterDelay()
                    } label: {
                        Text("Remove PIN")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.red.opacity(0.12))
                            .foregroundStyle(.red.opacity(0.9))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            } else {
                Text("Set a 4-digit PIN to lock parental settings on this device.")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)

                HStack(spacing: 10) {
                    SecureField("PIN", text: $newPIN)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .padding(12)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    SecureField("Confirm", text: $confirmPIN)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .padding(12)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                if let pinError {
                    Text(pinError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                if let pinSuccess {
                    Text(pinSuccess)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.green.opacity(0.9))
                }

                Button {
                    attemptSavePIN()
                } label: {
                    Text("Set PIN")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.accent)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }

            Text("PIN is stored on this device only and does not sync.")
                .font(.caption2)
                .foregroundStyle(Theme.muted.opacity(0.7))
        }
    }

    // MARK: - Age assurance note

    private var ageAssuranceNote: some View {
        cardSection {
            Label("Age Assurance", systemImage: "checkmark.shield.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.accentGold)
            Text("Each viewer profile is created with a date of birth. Kids, Teen, and Adult labels are derived from the profile age and used for age assurance throughout the app.")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
        }
    }

    // MARK: - Helpers

    private func cardSection<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func attemptSavePIN() {
        pinError = nil
        pinSuccess = nil
        guard newPIN.count == 4, newPIN.allSatisfy(\.isNumber) else {
            pinError = "PIN must be exactly 4 digits"
            return
        }
        guard newPIN == confirmPIN else {
            pinError = "PINs don't match"
            return
        }
        parental.setPIN(newPIN)
        newPIN = ""
        confirmPIN = ""
        pinError = nil
        pinSuccess = "PIN saved successfully"
        clearSuccessAfterDelay()
    }

    private func attemptUpdatePIN() {
        pinError = nil
        pinSuccess = nil
        guard !newPIN.isEmpty else {
            pinError = "Enter a new PIN"
            return
        }
        guard newPIN.count == 4, newPIN.allSatisfy(\.isNumber) else {
            pinError = "PIN must be exactly 4 digits"
            return
        }
        guard newPIN == confirmPIN else {
            pinError = "PINs don't match"
            return
        }
        parental.setPIN(newPIN)
        newPIN = ""
        confirmPIN = ""
        pinError = nil
        pinSuccess = "PIN updated successfully"
        clearSuccessAfterDelay()
    }

    private func clearSuccessAfterDelay() {
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run { pinSuccess = nil }
        }
    }

    // MARK: - Numeric PIN pad + dots

    private func pinDots(value: String) -> some View {
        HStack(spacing: 16) {
            ForEach(0..<4, id: \.self) { i in
                Circle()
                    .fill(i < value.count ? Theme.accent : Color.white.opacity(0.15))
                    .frame(width: 18, height: 18)
                    .animation(.easeInOut(duration: 0.12), value: value.count)
            }
        }
        .padding(.vertical, 8)
    }

    private func numPad(value: Binding<String>, onComplete: @escaping () -> Void) -> some View {
        let keys: [[String]] = [["1","2","3"],["4","5","6"],["7","8","9"],["","0","⌫"]]
        return VStack(spacing: 12) {
            ForEach(keys, id: \.self) { row in
                HStack(spacing: 16) {
                    ForEach(row, id: \.self) { key in
                        if key.isEmpty {
                            Color.clear.frame(width: 70, height: 50)
                        } else {
                            Button {
                                if key == "⌫" {
                                    if !value.wrappedValue.isEmpty { value.wrappedValue.removeLast() }
                                } else if value.wrappedValue.count < 4 {
                                    value.wrappedValue.append(key)
                                    if value.wrappedValue.count == 4 {
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                            onComplete()
                                        }
                                    }
                                }
                            } label: {
                                Text(key)
                                    .font(.title2.weight(.medium).monospacedDigit())
                                    .foregroundStyle(Theme.foreground)
                                    .frame(width: 70, height: 50)
                                    .background(Color.white.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
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
