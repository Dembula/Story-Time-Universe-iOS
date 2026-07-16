import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            switch appState.route {
            case .loading:
                LaunchSplashView()
            case .signIn:
                SignInView()
            case .profiles:
                ProfilesView()
            case .main:
                MainTabView()
            }
        }
        .task {
            await appState.bootstrap()
        }
    }
}

struct LaunchSplashView: View {
    var body: some View {
        VStack(spacing: 24) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 160, height: 160)
            ProgressView()
                .tint(Theme.accent)
        }
    }
}
