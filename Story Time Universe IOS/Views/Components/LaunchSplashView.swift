import SwiftUI

/// Simple elegant launch splash — black field, ST logo, quiet progress bar.
struct LaunchSplashView: View {
    @State private var logoVisible = false
    @State private var barVisible = false
    @State private var progress: CGFloat = 0.08

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 140, height: 140)
                    .opacity(logoVisible ? 1 : 0)
                    .scaleEffect(logoVisible ? 1 : 0.94)
                    .accessibilityLabel("Story Time Universe")

                Spacer(minLength: 0)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 2)

                        Capsule()
                            .fill(Color.white.opacity(0.85))
                            .frame(width: max(geo.size.width * progress, 4), height: 2)
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                }
                .frame(width: 96, height: 8)
                .opacity(barVisible ? 1 : 0)
                .padding(.bottom, 56)
                .accessibilityLabel("Loading")
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .onAppear { runEntrance() }
    }

    private func runEntrance() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000)

            withAnimation(.easeOut(duration: 0.55)) {
                logoVisible = true
            }

            try? await Task.sleep(nanoseconds: 220_000_000)

            withAnimation(.easeOut(duration: 0.4)) {
                barVisible = true
            }

            withAnimation(.easeInOut(duration: 2.35)) {
                progress = 0.92
            }
        }
    }
}
