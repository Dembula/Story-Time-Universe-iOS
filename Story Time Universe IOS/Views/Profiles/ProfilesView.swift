import SwiftUI

struct ProfilesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var profiles: [ViewerProfile] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var pinProfile: ViewerProfile?
    @State private var pin = ""
    @State private var selectingId: String?
    @State private var showCreate = false

    private let columns = [GridItem(.adaptive(minimum: 100, maximum: 120), spacing: 20)]

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            LinearGradient(
                colors: [Theme.accent.opacity(0.18), .clear, .black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 36)
                    Spacer()
                    Button("Sign Out") {
                        Task { await appState.signOut() }
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                Spacer(minLength: 24)

                Text("Choose your profile")
                    .font(.title2.bold())
                    .foregroundStyle(Theme.foreground)
                    .padding(.bottom, 28)

                if isLoading {
                    ProgressView().tint(Theme.accent)
                } else if profiles.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: columns, spacing: 24) {
                        ForEach(profiles) { profile in
                            Button {
                                Task { await select(profile) }
                            } label: {
                                ProfileAvatar(profile: profile, isLoading: selectingId == profile.id)
                            }
                            .disabled(selectingId != nil)
                        }

                        Button {
                            showCreate = true
                        } label: {
                            VStack(spacing: 10) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(Color.white.opacity(0.08))
                                        .frame(width: 96, height: 96)
                                    Image(systemName: "plus")
                                        .font(.title)
                                        .foregroundStyle(Theme.foreground)
                                }
                                Text("Add")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Theme.muted)
                            }
                        }
                    }
                    .padding(.horizontal, 28)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding()
                }

                if appState.needsPaymentAttention {
                    paymentBanner
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                }

                Spacer()
            }
        }
        .task { await load() }
        .sheet(item: $pinProfile) { profile in
            PinEntrySheet(profileName: profile.name, pin: $pin) {
                Task { await activate(profile, pin: pin) }
            }
            .presentationDetents([.height(280)])
        }
        .sheet(isPresented: $showCreate) {
            CreateProfileSheet {
                showCreate = false
                await load()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Text("No profiles yet")
                .foregroundStyle(Theme.muted)
            Button("Create profile") { showCreate = true }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .foregroundStyle(.black)
        }
    }

    private var paymentBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Subscription needs attention")
                .font(.headline)
                .foregroundStyle(Theme.foreground)
            Text("Renew or pay on the website — payments are not taken in the app.")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
            Link(destination: AppConfig.renewSubscriptionURL) {
                Text("Renew on Web")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.accent)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(16)
        .background(Theme.accentSoft)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.accent.opacity(0.35)))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            profiles = try await ViewerAPI.shared.fetchProfiles()
            appState.subscription = try? await ViewerAPI.shared.fetchSubscription()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func select(_ profile: ViewerProfile) async {
        if profile.pinEnabled == true {
            pin = ""
            pinProfile = profile
            return
        }
        await activate(profile, pin: nil)
    }

    private func activate(_ profile: ViewerProfile, pin: String?) async {
        selectingId = profile.id
        errorMessage = nil
        defer { selectingId = nil }
        do {
            let active = try await ViewerAPI.shared.activateProfile(id: profile.id, pin: pin)
            pinProfile = nil
            appState.selectProfile(active)
        } catch let error as APIError {
            if case .paymentRequired = error {
                errorMessage = error.localizedDescription
                pinProfile = nil
            } else if profile.pinEnabled == true {
                errorMessage = error.localizedDescription
            } else {
                errorMessage = error.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ProfileAvatar: View {
    let profile: ViewerProfile
    var isLoading = false

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Theme.profileColor(for: profile.id),
                                Theme.profileColor(for: profile.id).opacity(0.7),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 96, height: 96)
                if isLoading {
                    ProgressView().tint(.white)
                } else {
                    Text(String(profile.name.prefix(1)).uppercased())
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(.white)
                }
                if profile.pinEnabled == true {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .padding(6)
                        .background(.black.opacity(0.55))
                        .clipShape(Circle())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(8)
                }
            }
            Text(profile.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.foreground)
                .lineLimit(1)
            Text(profile.ageLabel)
                .font(.caption2)
                .foregroundStyle(Theme.muted)
        }
    }
}

struct PinEntrySheet: View {
    let profileName: String
    @Binding var pin: String
    var onSubmit: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            Text("Enter PIN for \(profileName)")
                .font(.headline)
            SecureField("4-digit PIN", text: $pin)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .padding()
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Button("Continue", action: onSubmit)
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .foregroundStyle(.black)
                .disabled(pin.count != 4)
            Button("Cancel") { dismiss() }
                .foregroundStyle(Theme.muted)
        }
        .padding(24)
        .presentationBackground(Theme.surface)
    }
}

struct CreateProfileSheet: View {
    var onCreated: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var year = Calendar.current.component(.year, from: Date()) - 21
    @State private var month = 1
    @State private var day = 1
    @State private var pin = ""
    @State private var usePin = false
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    TextField("Name", text: $name)
                    Picker("Year", selection: $year) {
                        ForEach((1920...Calendar.current.component(.year, from: Date())).reversed(), id: \.self) {
                            Text(String($0)).tag($0)
                        }
                    }
                    Picker("Month", selection: $month) {
                        ForEach(1...12, id: \.self) { Text(String($0)).tag($0) }
                    }
                    Picker("Day", selection: $day) {
                        ForEach(1...31, id: \.self) { Text(String($0)).tag($0) }
                    }
                }
                Section("PIN (optional)") {
                    Toggle("Protect with PIN", isOn: $usePin)
                    if usePin {
                        SecureField("4-digit PIN", text: $pin)
                            .keyboardType(.numberPad)
                    }
                }
                if let error {
                    Text(error).foregroundStyle(.red)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("New Profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task { await create() }
                    }
                    .disabled(busy || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func create() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            _ = try await ViewerAPI.shared.createProfile(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                birthYear: year,
                birthMonth: month,
                birthDay: day,
                pin: usePin ? pin : nil
            )
            await onCreated()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
