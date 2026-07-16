import SwiftUI

@main
struct StoryTimeApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .preferredColorScheme(.dark)
                .accentColor(Theme.accent)
        }
    }
}
