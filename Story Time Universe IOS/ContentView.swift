import SwiftUI

/// Placeholder kept for the synchronized folder; app entry is `StoryTimeApp`.
struct ContentView: View {
    var body: some View {
        Text("Story Time Universe")
            .foregroundStyle(Theme.foreground)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
    }
}

#Preview {
    ContentView()
        .preferredColorScheme(.dark)
}
