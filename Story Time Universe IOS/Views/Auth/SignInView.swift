import SwiftUI

struct SignInView: View {
    @EnvironmentObject private var appState: AppState
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var showPassword = false
    @FocusState private var focusedField: Field?

    private enum Field { case email, password }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 40)

                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 140, height: 140)
                    .shadow(color: Theme.accent.opacity(0.35), radius: 24, y: 8)

                VStack(spacing: 8) {
                    Text("Story Time Universe")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Theme.foreground)
                    Text("Sign in to watch")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                }

                VStack(spacing: 14) {
                    TextField("Email", text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .email)
                        .padding()
                        .background(Theme.card)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
                        .clipShape(RoundedRectangle(cornerRadius: 14))

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

                        Button {
                            showPassword.toggle()
                        } label: {
                            Image(systemName: showPassword ? "eye.slash" : "eye")
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    .padding()
                    .background(Theme.card)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 24)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Button {
                    Task { await submit() }
                } label: {
                    Group {
                        if appState.isBusy {
                            ProgressView().tint(.black)
                        } else {
                            Text("Sign In")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.accent)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(appState.isBusy || email.isEmpty || password.isEmpty)
                .opacity(email.isEmpty || password.isEmpty ? 0.5 : 1)
                .padding(.horizontal, 24)

                Link("Create an account on the web", destination: AppConfig.signUpURL)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.accentGold)

                Spacer(minLength: 40)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .onAppear {
            if let message = appState.bootstrapError {
                errorMessage = message
            }
        }
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
