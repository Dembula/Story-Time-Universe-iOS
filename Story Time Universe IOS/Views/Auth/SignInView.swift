import SwiftUI

struct SignInView: View {
    @EnvironmentObject private var appState: AppState
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var showPassword = false
    @State private var glow = false
    @FocusState private var focusedField: Field?

    private enum Field { case email, password }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            // Brand atmosphere
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
                        .frame(width: 128, height: 128)
                        .shadow(color: Theme.accent.opacity(0.5), radius: 28, y: 10)

                    VStack(spacing: 6) {
                        Text("Story Time Universe")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(Theme.foreground)
                        Text("Sign in to watch")
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                    }

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

                                Button {
                                    showPassword.toggle()
                                } label: {
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
                            Task { await submit() }
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

                        Link(destination: AppConfig.viewerSignUpURL) {
                            Text("Sign up")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.accentGold)
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
            try await appState.signIn(email: email, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
