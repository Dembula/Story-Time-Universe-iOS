import SwiftUI
import UIKit

/// Loads remote images with shared disk cache, prefetch support, and multi-URL fallbacks.
struct RemoteImage: View {
    let urls: [URL]
    var contentMode: ContentMode = .fill
    /// Prefer taller artwork — skip landscape frames when better candidates exist.
    var preferPortrait: Bool = false

    @State private var image: UIImage?
    @State private var failed = false

    init(url: URL?, contentMode: ContentMode = .fill, preferPortrait: Bool = false) {
        self.urls = url.map { [$0] } ?? []
        self.contentMode = contentMode
        self.preferPortrait = preferPortrait
    }

    init(urls: [URL], contentMode: ContentMode = .fill, preferPortrait: Bool = false) {
        self.urls = urls
        self.contentMode = contentMode
        self.preferPortrait = preferPortrait
    }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .transition(.opacity)
            } else if failed || urls.isEmpty {
                placeholder
            } else {
                placeholder
                ProgressView()
                    .tint(Theme.accent)
                    .scaleEffect(0.85)
            }
        }
        .clipped()
        .animation(.easeOut(duration: 0.2), value: image != nil)
        .task(id: taskKey) {
            await load()
        }
    }

    private var taskKey: String {
        urls.map(\.absoluteString).joined(separator: "|") + (preferPortrait ? "|p" : "|l")
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.12, blue: 0.14),
                    Color(red: 0.06, green: 0.06, blue: 0.07),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "film")
                .font(.title2)
                .foregroundStyle(Theme.muted.opacity(0.55))
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
    }

    private func load() async {
        guard !urls.isEmpty else {
            failed = true
            image = nil
            return
        }

        // Instant memory hits — no spinner flash on revisit.
        for url in urls.prefix(4) {
            if let cached = ImageCache.shared.memoryImage(for: url) {
                image = cached
                failed = false
                return
            }
        }

        failed = false
        if let loaded = await ImageLoader.shared.loadFirst(of: urls, preferPortrait: preferPortrait) {
            image = loaded
            failed = false
        } else if image == nil {
            failed = true
        }
    }
}
