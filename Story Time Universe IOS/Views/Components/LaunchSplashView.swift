import SwiftUI

struct LaunchSplashView: View {
    @State private var logoVisible = false
    @State private var titleVisible = false
    @State private var universeVisible = false
    @State private var loaderVisible = false
    @State private var progress: CGFloat = 0
    @State private var logoGlow = false
    @State private var ribbonDrift = false
    @State private var loadingPulse = false

    var body: some View {
        // Solid full-bleed black first — avoids Creators-style edge gaps from
        // undersized splash images / GeometryReader clipping.
        ZStack {
            Color.black
                .ignoresSafeArea(.all)

            atmosphere
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                brandBlock
                    .padding(.horizontal, 32)

                Spacer(minLength: 0)

                loaderBlock
                    .padding(.horizontal, 48)
                    .padding(.bottom, 56)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaPadding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .ignoresSafeArea(.all)
        .onAppear { startSequence() }
    }

    // MARK: - Brand

    private var brandBlock: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Theme.accent.opacity(logoGlow ? 0.45 : 0.22),
                                Theme.accentGold.opacity(logoGlow ? 0.18 : 0.08),
                                .clear,
                            ],
                            center: .center,
                            startRadius: 10,
                            endRadius: 130
                        )
                    )
                    .frame(width: 260, height: 260)
                    .blur(radius: 18)
                    .scaleEffect(logoGlow ? 1.08 : 0.92)

                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(red: 0.14, green: 0.10, blue: 0.05),
                                    .black,
                                ],
                                center: .center,
                                startRadius: 6,
                                endRadius: 120
                            )
                        )

                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .padding(30)

                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [Theme.accentGold, Theme.accent, Theme.accent.opacity(0.4)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2.5
                        )
                }
                .frame(width: 188, height: 188)
                .clipShape(Circle())
                .shadow(color: Theme.accent.opacity(logoGlow ? 0.65 : 0.35), radius: logoGlow ? 32 : 16, y: 4)
                .scaleEffect(logoVisible ? 1 : 0.78)
                .opacity(logoVisible ? 1 : 0)
            }
            .padding(.bottom, 10)

            Text("STORY TIME")
                .font(.system(size: 20, weight: .semibold, design: .default))
                .tracking(7)
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: true, vertical: false)
                .opacity(titleVisible ? 1 : 0)
                .offset(y: titleVisible ? 0 : 10)

            HStack(spacing: 12) {
                Capsule()
                    .fill(Theme.accent.opacity(0.85))
                    .frame(height: 1.5)
                    .frame(maxWidth: .infinity)

                Text("UNIVERSE")
                    .font(.system(size: 12, weight: .bold, design: .default))
                    .tracking(4)
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)

                Capsule()
                    .fill(Theme.accent.opacity(0.85))
                    .frame(height: 1.5)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: 280)
            .padding(.top, 14)
            .opacity(universeVisible ? 1 : 0)
            .offset(y: universeVisible ? 0 : 8)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Loader (single label — no stacked duplicate text)

    private var loaderBlock: some View {
        VStack(spacing: 18) {
            GeometryReader { bar in
                let width = bar.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 2.5)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Theme.accent.opacity(0.55),
                                    Theme.accent,
                                    Theme.accentGold,
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(width * progress, progress > 0 ? 8 : 0), height: 2.5)
                        .shadow(color: Theme.accent.opacity(0.8), radius: 6, y: 0)

                    Circle()
                        .fill(Color.white)
                        .frame(width: 7, height: 7)
                        .shadow(color: Theme.accentGold, radius: 10)
                        .shadow(color: Theme.accent, radius: 16)
                        .offset(x: max(width * progress - 3.5, 0))
                        .opacity(progress > 0.02 ? 1 : 0)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 14)

            // One Text only — Creators showed a duplicated footer from stacked labels.
            Text("LOADING YOUR UNIVERSE...")
                .font(.system(size: 11, weight: .medium, design: .default))
                .tracking(3.5)
                .foregroundStyle(Color.white)
                .opacity(loaderVisible ? (loadingPulse ? 1 : 0.55) : 0)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .opacity(loaderVisible ? 1 : 0)
        .offset(y: loaderVisible ? 0 : 12)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Atmosphere

    private var atmosphere: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [
                                Theme.accent.opacity(0.28),
                                Theme.accent.opacity(0.06),
                                .clear,
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: w * 1.35, height: h * 0.42)
                    .rotationEffect(.degrees(-28))
                    .offset(
                        x: ribbonDrift ? -w * 0.28 : -w * 0.36,
                        y: ribbonDrift ? -h * 0.28 : -h * 0.32
                    )
                    .blur(radius: 36)

                Ellipse()
                    .fill(Theme.accentGold.opacity(0.12))
                    .frame(width: w * 0.7, height: h * 0.22)
                    .rotationEffect(.degrees(-18))
                    .offset(
                        x: ribbonDrift ? -w * 0.1 : -w * 0.18,
                        y: -h * 0.22
                    )
                    .blur(radius: 50)

                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [
                                Theme.accent.opacity(0.22),
                                Theme.accent.opacity(0.05),
                                .clear,
                            ],
                            startPoint: .bottomLeading,
                            endPoint: .topTrailing
                        )
                    )
                    .frame(width: w * 1.4, height: h * 0.38)
                    .rotationEffect(.degrees(22))
                    .offset(
                        x: ribbonDrift ? -w * 0.32 : -w * 0.4,
                        y: ribbonDrift ? h * 0.38 : h * 0.42
                    )
                    .blur(radius: 40)
            }
            .frame(width: w, height: h)
            // Bleed past edges then clip so blur never reveals a light seam.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .clipped()
        }
        .ignoresSafeArea(.all)
    }

    // MARK: - Sequence

    private func startSequence() {
        withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) {
            ribbonDrift = true
        }

        withAnimation(.spring(response: 0.85, dampingFraction: 0.78)) {
            logoVisible = true
        }

        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true).delay(0.35)) {
            logoGlow = true
        }

        withAnimation(.easeOut(duration: 0.55).delay(0.28)) {
            titleVisible = true
        }

        withAnimation(.easeOut(duration: 0.55).delay(0.48)) {
            universeVisible = true
        }

        withAnimation(.easeOut(duration: 0.5).delay(0.7)) {
            loaderVisible = true
        }

        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true).delay(0.85)) {
            loadingPulse = true
        }

        withAnimation(.easeInOut(duration: 2.35).delay(0.85)) {
            progress = 1
        }
    }
}
