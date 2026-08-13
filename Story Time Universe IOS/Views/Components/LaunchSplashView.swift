import SwiftUI

/// Cinematic launch splash — matches the black system launch screen, then dissolves into the app.
struct LaunchSplashView: View {
    @State private var stage: Stage = .idle
    @State private var glowPulse = false
    @State private var progress: CGFloat = 0.08

    private enum Stage: Int, Comparable {
        case idle = 0
        case logo = 1
        case wordmark = 2
        case loader = 3

        static func < (lhs: Stage, rhs: Stage) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ambientLight
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                brandCluster

                Spacer(minLength: 0)

                footer
                    .padding(.bottom, 52)
            }
            .padding(.horizontal, 36)
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .onAppear { runEntrance() }
    }

    // MARK: - Brand

    private var brandCluster: some View {
        VStack(spacing: 22) {
            ZStack {
                // Soft brand halo — restrained, not neon.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Theme.accent.opacity(glowPulse ? 0.28 : 0.14),
                                Theme.accent.opacity(0.06),
                                .clear,
                            ],
                            center: .center,
                            startRadius: 20,
                            endRadius: 120
                        )
                    )
                    .frame(width: 240, height: 240)
                    .blur(radius: 8)
                    .scaleEffect(glowPulse ? 1.05 : 0.96)

                // Thin orbit ring while loading.
                if stage >= .loader {
                    TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { timeline in
                        let seconds = timeline.date.timeIntervalSinceReferenceDate
                        let angle = (seconds * 130).truncatingRemainder(dividingBy: 360)
                        Circle()
                            .trim(from: 0.12, to: 0.38)
                            .stroke(
                                AngularGradient(
                                    colors: [
                                        Theme.accent.opacity(0.05),
                                        Theme.accent.opacity(0.9),
                                        Theme.accentGold.opacity(0.75),
                                        Theme.accent.opacity(0.05),
                                    ],
                                    center: .center
                                ),
                                style: StrokeStyle(lineWidth: 1.75, lineCap: .round)
                            )
                            .frame(width: 168, height: 168)
                            .rotationEffect(.degrees(angle))
                    }
                    .transition(.opacity)
                }

                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 112, height: 112)
                    .shadow(color: Theme.accent.opacity(stage >= .logo ? 0.35 : 0), radius: 24, y: 8)
                    .scaleEffect(stage >= .logo ? 1 : 0.86)
                    .opacity(stage >= .logo ? 1 : 0)
            }
            .frame(height: 200)

            VStack(spacing: 10) {
                Text("STORY TIME")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .tracking(6)
                    .foregroundStyle(Color.white.opacity(0.95))

                Text("UNIVERSE")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(5)
                    .foregroundStyle(Theme.accent.opacity(0.95))
            }
            .opacity(stage >= .wordmark ? 1 : 0)
            .offset(y: stage >= .wordmark ? 0 : 12)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Story Time Universe")
    }

    // MARK: - Footer loader

    private var footer: some View {
        VStack(spacing: 14) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 2)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Theme.accent.opacity(0.4),
                                    Theme.accent,
                                    Theme.accentGold.opacity(0.9),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(geo.size.width * progress, 6), height: 2)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(width: 120, height: 10)

            Text("Preparing your library")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.45))
                .tracking(0.4)
        }
        .opacity(stage >= .loader ? 1 : 0)
        .offset(y: stage >= .loader ? 0 : 10)
        .accessibilityLabel("Loading")
    }

    // MARK: - Atmosphere

    private var ambientLight: some View {
        ZStack {
            // Top vignette wash — cinematic, not busy.
            RadialGradient(
                colors: [
                    Theme.accent.opacity(0.16),
                    Theme.accent.opacity(0.04),
                    .clear,
                ],
                center: .top,
                startRadius: 40,
                endRadius: 420
            )
            .opacity(stage >= .logo ? 1 : 0)

            RadialGradient(
                colors: [
                    Color.white.opacity(0.04),
                    .clear,
                ],
                center: UnitPoint(x: 0.5, y: 0.42),
                startRadius: 10,
                endRadius: 220
            )
            .opacity(stage >= .logo ? 1 : 0)

            // Bottom fade into pure black — matches next screens.
            LinearGradient(
                colors: [.clear, .black.opacity(0.55), .black],
                startPoint: .center,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    // MARK: - Choreography

    private func runEntrance() {
        // Keep the first frames pure black so the system launch → splash handoff is invisible.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000)

            withAnimation(.spring(response: 0.72, dampingFraction: 0.82)) {
                stage = .logo
            }

            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                glowPulse = true
            }

            try? await Task.sleep(nanoseconds: 280_000_000)

            withAnimation(.easeOut(duration: 0.55)) {
                stage = .wordmark
            }

            try? await Task.sleep(nanoseconds: 220_000_000)

            withAnimation(.easeOut(duration: 0.45)) {
                stage = .loader
            }

            // Progress eases toward completion over the minimum splash window.
            withAnimation(.easeInOut(duration: 2.35)) {
                progress = 0.92
            }
        }
    }
}
