import SwiftUI

struct SignInView: View {
    @EnvironmentObject private var appState: AppState
    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""
    @State private var errorMessage: String?
    @State private var showPassword = false
    @State private var glow = false
    @State private var browser: BrowserSheet?
    @FocusState private var focusedField: Field?

    private enum Field { case name, email, password }
    private enum Mode: String { case signIn, signUp }

    private struct BrowserSheet: Identifiable {
        let id = UUID()
        let url: URL
        let title: String
        let authenticated: Bool
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            Circle()
                .fill(Theme.accent.opacity(0.28))
                .frame(width: 320, height: 320)
                .blur(radius: 70)
                .offset(x: -90, y: -220)
                .scaleEffect(glow ? 1.08 : 0.92)

            Circle()
                .fill(Theme.accentGold.opacity(0.16))
                .frame(width: 260, height: 260)
                .blur(radius: 55)
                .offset(x: 120, y: 260)
                .scaleEffect(glow ? 1.05 : 0.95)

            LinearGradient(
                colors: [.clear, Theme.accent.opacity(0.08), .black.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 22) {
                    Spacer(minLength: 36)

                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 118, height: 118)
                        .shadow(color: Theme.accent.opacity(0.5), radius: 28, y: 10)

                    VStack(spacing: 6) {
                        Text("Story Time Universe")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(Theme.foreground)
                        Text(mode == .signIn ? "Sign in to watch" : "Create your account")
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                    }

                    // Mode toggle
                    HStack(spacing: 0) {
                        modeTab(.signIn, title: "Sign In")
                        modeTab(.signUp, title: "Sign Up")
                    }
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                    .padding(.horizontal, 28)

                    VStack(spacing: 14) {
                        if mode == .signUp {
                            fieldCard {
                                TextField("Name (optional)", text: $name)
                                    .textContentType(.name)
                                    .focused($focusedField, equals: .name)
                                    .foregroundStyle(Theme.foreground)
                            }
                        }

                        fieldCard {
                            TextField("Email", text: $email)
                                .textContentType(.username)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($focusedField, equals: .email)
                                .foregroundStyle(Theme.foreground)
                        }

                        fieldCard {
                            HStack {
                                Group {
                                    if showPassword {
                                        TextField("Password", text: $password)
                                    } else {
                                        SecureField("Password", text: $password)
                                    }
                                }
                                .textContentType(mode == .signUp ? .newPassword : .password)
                                .focused($focusedField, equals: .password)
                                .foregroundStyle(Theme.foreground)

                                Button { showPassword.toggle() } label: {
                                    Image(systemName: showPassword ? "eye.slash" : "eye")
                                        .foregroundStyle(Theme.muted)
                                }
                            }
                        }

                        if mode == .signUp {
                            Text("Password must be at least 6 characters.")
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red.opacity(0.95))
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button {
                            Task { await submit() }
                        } label: {
                            Group {
                                if appState.isBusy {
                                    ProgressView().tint(.black)
                                } else {
                                    Text(mode == .signIn ? "Sign In" : "Create Account")
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
                            .shadow(color: Theme.accent.opacity(0.35), radius: 16, y: 8)
                        }
                        .disabled(appState.isBusy || email.isEmpty || password.isEmpty)
                        .opacity(email.isEmpty || password.isEmpty ? 0.55 : 1)

                        // In-app Safari View Controller flows (Apple guideline)
                        VStack(spacing: 10) {
                            Button {
                                browser = BrowserSheet(
                                    url: mode == .signIn ? AppConfig.viewerSignInURL : AppConfig.viewerSignUpURL,
                                    title: mode == .signIn ? "Sign In" : "Sign Up",
                                    authenticated: true
                                )
                            } label: {
                                Label(
                                    mode == .signIn ? "Sign in with secure browser" : "Sign up with secure browser",
                                    systemImage: "safari"
                                )
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.accentGold)
                            }

                            Button {
                                browser = BrowserSheet(
                                    url: AppConfig.forgotPasswordURL,
                                    title: "Reset Password",
                                    authenticated: false
                                )
                            } label: {
                                Text("Forgot password?")
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(Theme.muted)
                            }
                        }
                        .padding(.top, 4)
                    }
                    .padding(20)
                    .background(.ultraThinMaterial.opacity(0.9))
                    .background(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [Theme.accent.opacity(0.45), Theme.accentGold.opacity(0.15), Color.white.opacity(0.08)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .padding(.horizontal, 22)

                    if !DownloadManager.shared.completedRecords.isEmpty {
                        Button {
                            appState.openOfflineLibrary()
                        } label: {
                            Label("Watch downloads offline", systemImage: "arrow.down.circle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                        }
                        .padding(.top, 4)
                    }

                    Spacer(minLength: 40)
                }
            }
        }
        .onAppear {
            if let message = appState.bootstrapError {
                errorMessage = message
            }
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) {
                glow = true
            }
        }
        .sheet(item: $browser) { item in
            if item.authenticated {
                AuthenticatedWebBrowser(url: item.url, title: item.title) {
                    Task {
                        await appState.completeWebAuth()
                        browser = nil
                    }
                }
            } else {
                SafariView(url: item.url)
                    .ignoresSafeArea()
            }
        }
    }

    private func modeTab(_ value: Mode, title: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                mode = value
                errorMessage = nil
            }
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(mode == value ? Theme.accent : Color.clear)
                .foregroundStyle(mode == value ? .black : Theme.muted)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func fieldCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding()
            .background(Color.black.opacity(0.45))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func submit() async {
        errorMessage = nil
        focusedField = nil
        do {
            if mode == .signIn {
                try await appState.signIn(email: email, password: password)
            } else {
                guard password.count >= 6 else {
                    errorMessage = "Password must be at least 6 characters."
                    return
                }
                try await appState.signUp(email: email, password: password, name: name.isEmpty ? nil : name)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
