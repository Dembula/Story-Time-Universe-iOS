import SwiftUI

struct LaunchSplashView: View {
    @State private var pulse = false
    @State private var glow = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            Circle()
                .fill(Theme.accent.opacity(0.22))
                .frame(width: 280, height: 280)
                .blur(radius: 60)
                .scaleEffect(glow ? 1.15 : 0.9)
                .offset(y: -40)

            Circle()
                .fill(Theme.accentGold.opacity(0.12))
                .frame(width: 200, height: 200)
                .blur(radius: 40)
                .offset(x: 80, y: 120)
                .scaleEffect(glow ? 1.1 : 0.95)

            VStack(spacing: 28) {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 150, height: 150)
                    .shadow(color: Theme.accent.opacity(0.45), radius: pulse ? 28 : 12, y: 8)
                    .scaleEffect(pulse ? 1.04 : 0.96)

                VStack(spacing: 8) {
                    Text("Story Time Universe")
                        .font(.title3.bold())
                        .foregroundStyle(Theme.foreground)
                    ProgressView()
                        .tint(Theme.accent)
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulse = true
                glow = true
            }
        }
    }
}
