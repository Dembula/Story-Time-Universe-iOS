import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch appState.route {
            case .loading:
                LaunchSplashView()
                    .transition(splashExit)
                    .zIndex(2)
            case .signIn:
                SignInView()
                    .transition(contentEnter)
            case .profiles:
                ProfilesView()
                    .transition(contentEnter)
            case .main:
                MainTabView()
                    .transition(contentEnter)
            case .offlineDownloads:
                OfflineDownloadsGate()
                    .transition(contentEnter)
            }
        }
        .animation(.easeInOut(duration: 0.55), value: appState.route)
        .task {
            await appState.bootstrap()
        }
    }

    /// Splash dissolves up and out — feels like the brand lifts into the app.
    private var splashExit: AnyTransition {
        .asymmetric(
            insertion: .opacity,
            removal: .opacity
                .combined(with: .scale(scale: 1.04, anchor: .center))
                .combined(with: .offset(y: -12))
        )
    }

    /// Destination screens rise softly from the same black bed.
    private var contentEnter: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 10)),
            removal: .opacity
        )
    }
}

/// Full-screen offline entry when catalogue/network isn't available.
struct OfflineDownloadsGate: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var network = NetworkMonitor.shared

    var body: some View {
        DownloadsView()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if appState.session?.user != nil {
                        Button("Back") { appState.leaveOfflineLibrary() }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if network.isOnline {
                        Button("Sign In") {
                            appState.route = .signIn
                        }
                    }
                }
                ToolbarItem(placement: .principal) {
                    if !network.isOnline {
                        Text("You're offline · Downloads only")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Theme.accent, in: Capsule())
                    }
                }
            }
            .onAppear {
                DownloadManager.shared.validateOfflineLibrary()
            }
    }
}
