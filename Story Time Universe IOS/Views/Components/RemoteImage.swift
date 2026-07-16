import SwiftUI
import UIKit

/// Loads remote images with shared cookie storage so authenticated preview URLs work.
struct RemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?
    @State private var failed = false
    @State private var loading = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if failed || url == nil {
                placeholder
            } else {
                ZStack {
                    placeholder
                    ProgressView()
                        .tint(Theme.accent)
                        .scaleEffect(0.85)
                }
            }
        }
        .background(Theme.card)
        .task(id: url?.absoluteString) {
            await load()
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color.white.opacity(0.06), Color.white.opacity(0.02)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "film")
                .font(.title2)
                .foregroundStyle(Theme.muted.opacity(0.7))
        }
    }

    private func load() async {
        guard let url else {
            image = nil
            failed = true
            return
        }
        if let cached = ImageCache.shared.image(for: url) {
            image = cached
            failed = false
            return
        }
        loading = true
        failed = false
        defer { loading = false }

        var request = URLRequest(url: url)
        request.setValue("StoryTimeUniverseiOS/1.0", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .returnCacheDataElseLoad

        do {
            let (data, response) = try await APIClient.shared.session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let uiImage = UIImage(data: data)
            else {
                failed = true
                image = nil
                return
            }
            ImageCache.shared.set(uiImage, for: url)
            image = uiImage
            failed = false
        } catch {
            failed = true
            image = nil
        }
    }
}

final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSURL, UIImage>()

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func set(_ image: UIImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }
}
