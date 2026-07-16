import SwiftUI
import UIKit

/// Loads remote images with shared cookies and multi-URL fallbacks.
struct RemoteImage: View {
    let urls: [URL]
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?
    @State private var failed = false

    init(url: URL?, contentMode: ContentMode = .fill) {
        self.urls = url.map { [$0] } ?? []
        self.contentMode = contentMode
    }

    init(urls: [URL], contentMode: ContentMode = .fill) {
        self.urls = urls
        self.contentMode = contentMode
    }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
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
        .task(id: urls.map(\.absoluteString).joined(separator: "|")) {
            await load()
        }
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
        image = nil
        failed = false
        guard !urls.isEmpty else {
            failed = true
            return
        }

        for url in urls {
            if let cached = ImageCache.shared.image(for: url) {
                image = cached
                failed = false
                return
            }
            if let loaded = await fetchImage(url) {
                ImageCache.shared.set(loaded, for: url)
                image = loaded
                failed = false
                return
            }
        }
        failed = true
        image = nil
    }

    private func fetchImage(_ url: URL) async -> UIImage? {
        var request = URLRequest(url: url)
        request.setValue("StoryTimeUniverseiOS/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 25
        request.cachePolicy = .returnCacheDataElseLoad

        do {
            let (data, response) = try await APIClient.shared.session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            // Reject tiny/error payloads
            guard data.count > 256, let uiImage = UIImage(data: data) else { return nil }
            return uiImage
        } catch {
            return nil
        }
    }
}

final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSURL, UIImage>()

    init() {
        cache.countLimit = 300
        cache.totalCostLimit = 80 * 1024 * 1024
    }

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func set(_ image: UIImage, for url: URL) {
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        cache.setObject(image, forKey: url as NSURL, cost: cost)
    }
}
