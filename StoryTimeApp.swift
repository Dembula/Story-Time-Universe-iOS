import SwiftUI

@main
struct StoryTimeApp: App {
    @UIApplicationDelegateAdaptor(OrientationAppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .onAppear {
                    OrientationLock.unlockPortrait()
                    StoreService.shared.start()
                }
                .sheet(isPresented: $appState.showPaywall) {
                    SubscriptionPaywallView(context: appState.paywallContext) {
                        Task { await appState.refreshSubscriptionFromServer() }
                    }
                    .environmentObject(appState)
                }
        }
    }
}
