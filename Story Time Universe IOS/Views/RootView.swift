import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            switch appState.route {
            case .loading:
                LaunchSplashView()
                    .transition(.opacity)
            case .signIn:
                SignInView()
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            case .profiles:
                ProfilesView()
                    .transition(.opacity)
            case .main:
                MainTabView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.45), value: appState.route)
        .task {
            await appState.bootstrap()
        }
    }
}
