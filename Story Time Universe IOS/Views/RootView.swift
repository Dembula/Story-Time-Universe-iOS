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
            case .offlineDownloads:
                OfflineDownloadsGate()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.45), value: appState.route)
        .task {
            await appState.bootstrap()
        }
    }
}

/// Full-screen offline entry when catalogue/network isn't available.
struct OfflineDownloadsGate: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationStack {
            DownloadsView()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        if appState.session?.user != nil {
                            Button("Back") { appState.leaveOfflineLibrary() }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Sign In") {
                            appState.route = .signIn
                        }
                    }
                }
                .safeAreaInset(edge: .top) {
                    if !NetworkMonitor.shared.isOnline {
                        Text("You're offline · Downloads only")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Theme.accent.opacity(0.9))
                    }
                }
        }
    }
}
