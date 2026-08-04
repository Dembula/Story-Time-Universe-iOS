import SwiftUI

/// In-app playback troubleshooting — no web redirect.
struct PlaybackHelpView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private let supportEmail = "support@story-time.online"
    private let supportPhoneDisplay = "+27 61 657 2691"
    private let supportPhoneTel = "+27616572691"

    private let steps: [(icon: String, title: String, detail: String)] = [
        (
            "arrow.clockwise",
            "Close the app and reopen it",
            "Fully swipe the app away from the app switcher, then open Story Time Universe again."
        ),
        (
            "wifi",
            "Check your Wi‑Fi or mobile data",
            "Make sure you have a stable connection. Try switching between Wi‑Fi and cellular if playback still stalls."
        ),
        (
            "play.rectangle",
            "Try playing again",
            "Return to the title and press Play. If this is a pay‑per‑view title, complete unlock when prompted."
        ),
        (
            "arrow.down.circle",
            "Use a download when you’re offline",
            "If you saved the title earlier, open Downloads and play it offline without streaming."
        ),
        (
            "speaker.wave.2",
            "Check silent mode and volume",
            "Turn the ring/silent switch off and raise the device volume. Also try unplugging and re-plugging headphones."
        ),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    introCard

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Try these steps")
                            .font(.headline)
                            .foregroundStyle(Theme.foreground)

                        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                            stepRow(number: index + 1, icon: step.icon, title: step.title, detail: step.detail)
                        }
                    }

                    contactCard
                }
                .padding(20)
                .padding(.bottom, 28)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Playback Help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Having trouble watching?", systemImage: "play.rectangle.fill")
                .font(.title3.bold())
                .foregroundStyle(Theme.accentGold)
            Text("Most playback issues clear with a quick restart and a solid internet connection. Work through the steps below, then contact us if it still fails.")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func stepRow(number: Int, icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.accentSoft)
                    .frame(width: 36, height: 36)
                Text("\(number)")
                    .font(.subheadline.bold())
                    .foregroundStyle(Theme.accent)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.foreground)
                }
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var contactCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Story Time Team", systemImage: "lifepreserver.fill")
                .font(.headline)
                .foregroundStyle(Theme.accentGold)

            Text("Still stuck? We’re happy to help.")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)

            Button {
                if let url = URL(string: "mailto:\(supportEmail)") {
                    openURL(url)
                }
            } label: {
                contactRow(
                    icon: "envelope.fill",
                    title: "Email",
                    value: supportEmail
                )
            }
            .buttonStyle(.plain)

            Button {
                if let url = URL(string: "tel:\(supportPhoneTel)") {
                    openURL(url)
                }
            } label: {
                contactRow(
                    icon: "phone.fill",
                    title: "Phone / WhatsApp",
                    value: supportPhoneDisplay
                )
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.accent.opacity(0.25), lineWidth: 1)
        )
    }

    private func contactRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.muted)
                Text(value)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.foreground)
            }
            Spacer()
            Image(systemName: "arrow.up.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.muted)
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
