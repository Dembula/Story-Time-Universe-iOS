import SwiftUI
import WebKit

struct SignInView: View {
    @EnvironmentObject private var appState: AppState
    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var showPassword = false
    @State private var glow = false
    @State private var browser: BrowserSheet?
    @FocusState private var focusedField: Field?

    private enum Field { case email, password }
    private enum Mode: String { case signIn, signUp }

    private struct BrowserSheet: Identifiable {
        let id = UUID()
        let url: URL
        let title: String
        let mode: WebBrowserMode
        let isSafariOnly: Bool
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

                    HStack(spacing: 0) {
                        modeTab(.signIn, title: "Sign In")
                        modeTab(.signUp, title: "Sign Up")
                    }
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                    .padding(.horizontal, 28)

                    VStack(spacing: 14) {
                        if mode == .signIn {
                            signInForm
                        } else {
                            signUpPrompt
                        }
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
        .sheet(item: $browser, onDismiss: {
            // Payment finished but auto-detect missed, or user closed after activation.
            Task {
                if appState.session?.user != nil {
                    if appState.route != .profiles && appState.route != .main {
                        appState.route = .profiles
                    }
                    return
                }
                let ok = await appState.completeWebAuth()
                if !ok, mode == .signUp, appState.session?.user == nil {
                    errorMessage = "If you finished signup, tap Sign In with the same email and password."
                }
            }
        }) { item in
            if item.isSafariOnly {
                SafariView(url: item.url)
                    .ignoresSafeArea()
            } else {
                AuthenticatedWebBrowser(
                    url: item.url,
                    title: item.title,
                    mode: item.mode
                ) {
                    Task {
                        // One more default-store export + robust session adopt.
                        await CookieBridge.exportCookies(from: WKWebsiteDataStore.default())
                        let ok = await appState.completeWebAuth()
                        browser = nil
                        if !ok, appState.session?.user == nil {
                            errorMessage = "Account may be ready — sign in with the email and password you just created."
                            mode = .signIn
                        }
                    }
                }
            }
        }
    }

    // MARK: - Sign In (native only — no web browser CTA)

    private var signInForm: some View {
        VStack(spacing: 14) {
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
                    .textContentType(.password)
                    .focused($focusedField, equals: .password)
                    .foregroundStyle(Theme.foreground)

                    Button { showPassword.toggle() } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .foregroundStyle(Theme.muted)
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red.opacity(0.95))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                Task { await submitSignIn() }
            } label: {
                Group {
                    if appState.isBusy {
                        ProgressView().tint(.black)
                    } else {
                        Text("Sign In")
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

            Button {
                browser = BrowserSheet(
                    url: AppConfig.forgotPasswordURL,
                    title: "Reset Password",
                    mode: .account,
                    isSafariOnly: true
                )
            } label: {
                Text("Forgot password?")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Sign Up (in-app web is the natural flow)

    private var signUpPrompt: some View {
        VStack(spacing: 16) {
            Text("New accounts are created securely on Story Time — including terms and payment — then you return here to pick a profile.")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red.opacity(0.95))
                    .multilineTextAlignment(.center)
            }

            Button {
                openSignUpBrowser()
            } label: {
                Label("Continue to Create Account", systemImage: "arrow.up.forward.app.fill")
                    .font(.headline.weight(.bold))
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

            Text("You’ll complete terms and payment in a secure window. When payment finishes, this app signs you in automatically and you’ll pick a profile.")
                .font(.caption)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
        }
    }

    private func openSignUpBrowser() {
        errorMessage = nil
        // Fresh jar so a prior session cannot masquerade as the new user.
        APIClient.shared.clearCookies()
        // Also clear default WK data for our origin so signup never inherits old NextAuth cookies.
        WKWebsiteDataStore.default().fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            let relevant = records.filter {
                $0.displayName.contains("story-time") || $0.displayName.contains("storytime")
            }
            WKWebsiteDataStore.default().removeData(
                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                for: relevant
            ) {
                DispatchQueue.main.async {
                    self.browser = BrowserSheet(
                        url: AppConfig.viewerSignUpURLForApp,
                        title: "Create Account",
                        mode: .signUp,
                        isSafariOnly: false
                    )
                }
            }
        }
    }

    private func modeTab(_ value: Mode, title: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                mode = value
                errorMessage = nil
                // Natural signup flow: open web immediately when switching to Sign Up
                if value == .signUp {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        openSignUpBrowser()
                    }
                }
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

    private func submitSignIn() async {
        errorMessage = nil
        focusedField = nil
        do {
            try await appState.signIn(email: email, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
