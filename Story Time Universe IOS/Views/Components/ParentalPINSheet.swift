import SwiftUI

/// Device-local parental PIN entry (PIN is not synced from the web).
struct ParentalPINSheet: View {
    let title: String
    let message: String
    var onCancel: () -> Void
    var onSuccess: () -> Void

    @ObservedObject private var parental = ParentalControls.shared
    @State private var pin = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                SecureField("4-digit PIN", text: $pin)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .multilineTextAlignment(.center)
                    .font(.title2.monospacedDigit())
                    .padding()
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 32)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Button("Continue") {
                    if parental.verifyPIN(pin) {
                        onSuccess()
                    } else {
                        errorMessage = "Incorrect PIN."
                        pin = ""
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(pin.count != 4)

                Spacer()
            }
            .padding(.top, 24)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
        .presentationDetents([.height(320)])
    }
}

enum ParentalPINGate {
    @MainActor
    static var needsPinToSwitchProfile: Bool {
        let p = ParentalControls.shared
        return p.isEnabled && p.requirePinToSwitchProfile && p.hasPIN
    }

    @MainActor
    static var needsPinForPlayer: Bool {
        let p = ParentalControls.shared
        return p.isEnabled && p.requirePinForPlayer && p.hasPIN
    }
}
