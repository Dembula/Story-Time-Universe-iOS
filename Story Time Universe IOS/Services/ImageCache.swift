import Foundation
import UIKit

/// Memory + on-disk cache for catalogue artwork so posters survive app restarts.
final class ImageCache {
    static let shared = ImageCache()

    private let memory = NSCache<NSURL, UIImage>()
    private let ioQueue = DispatchQueue(label: "com.storytime.imagecache", qos: .utility)
    private let folderURL: URL

    private init() {
        memory.countLimit = 400
        memory.totalCostLimit = 120 * 1024 * 1024

        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        folderURL = caches.appendingPathComponent("StoryTimeImageCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        // Trim very old files in the background (30+ days).
        ioQueue.async { [folderURL] in
            Self.trimDisk(at: folderURL, olderThanDays: 30, maxBytes: 400 * 1024 * 1024)
        }
    }

    func memoryImage(for url: URL) -> UIImage? {
        memory.object(forKey: url as NSURL)
    }

    func image(for url: URL) async -> UIImage? {
        if let mem = memoryImage(for: url) { return mem }

        let fileURL = diskURL(for: url)
        let data: Data? = await withCheckedContinuation { cont in
            ioQueue.async {
                cont.resume(returning: try? Data(contentsOf: fileURL))
            }
        }
        guard let data, data.count > 256, let image = UIImage(data: data) else { return nil }
        storeMemory(image, for: url)
        return image
    }

    func store(_ image: UIImage, data: Data?, for url: URL) {
        storeMemory(image, for: url)
        let payload = data ?? image.jpegData(compressionQuality: 0.88)
        guard let payload, payload.count > 256 else { return }
        let fileURL = diskURL(for: url)
        ioQueue.async {
            try? payload.write(to: fileURL, options: .atomic)
        }
    }

    private func storeMemory(_ image: UIImage, for url: URL) {
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        memory.setObject(image, forKey: url as NSURL, cost: cost)
    }

    private func diskURL(for url: URL) -> URL {
        let name = url.absoluteString.sha256Hex
        return folderURL.appendingPathComponent(name).appendingPathExtension("img")
    }

    private static func trimDisk(at folder: URL, olderThanDays: Int, maxBytes: Int) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let cutoff = Date().addingTimeInterval(-TimeInterval(olderThanDays * 24 * 60 * 60))
        var entries: [(url: URL, date: Date, size: Int)] = []

        for file in files {
            let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let date = values?.contentModificationDate ?? .distantPast
            let size = values?.fileSize ?? 0
            if date < cutoff {
                try? fm.removeItem(at: file)
            } else {
                entries.append((file, date, size))
            }
        }

        var total = entries.reduce(0) { $0 + $1.size }
        guard total > maxBytes else { return }
        for entry in entries.sorted(by: { $0.date < $1.date }) {
            try? fm.removeItem(at: entry.url)
            total -= entry.size
            if total <= maxBytes { break }
        }
    }
}

private extension String {
    var sha256Hex: String {
        // Lightweight stable key without CryptoKit dependency surface in older targets.
        var hash: UInt64 = 5381
        for byte in utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        var hash2: UInt64 = 0xcbf29ce484222325
        for byte in utf8 {
            hash2 ^= UInt64(byte)
            hash2 = hash2 &* 0x100000001b3
        }
        return String(format: "%016llx%016llx", hash, hash2)
    }
}
