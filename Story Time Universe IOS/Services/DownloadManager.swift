import AVFoundation
import Combine
import Foundation

/// Manages offline downloads for in-app-only playback.
///
/// HLS titles are stored as an iOS-managed `.movpkg` via `AVAssetDownloadURLSession`
/// (the same mechanism Netflix/TV+ use). Progressive fallbacks are written into the
/// app's Application Support container. Neither location is exposed to the Files app,
/// and the media can't be shared or exported as a plain mp4.
@MainActor
final class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()

    @Published private(set) var records: [String: DownloadRecord] = [:]

    /// Set by the app delegate when iOS relaunches us to finish background transfers.
    var backgroundCompletionHandler: (() -> Void)?

    private var avSession: AVAssetDownloadURLSession!
    private var fileSession: URLSession!

    private var avTaskKeys: [Int: String] = [:]
    private var fileTaskKeys: [Int: String] = [:]
    private var keyToTask: [String: URLSessionTask] = [:]

    private let storeURL: URL
    nonisolated private let fileDownloadsDir: URL

    private override init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        storeURL = support.appendingPathComponent("downloads.json")
        fileDownloadsDir = support.appendingPathComponent("OfflineMedia", isDirectory: true)
        try? FileManager.default.createDirectory(at: fileDownloadsDir, withIntermediateDirectories: true)

        super.init()

        let hlsConfig = URLSessionConfiguration.background(withIdentifier: "com.storytime.universe.downloads.hls")
        hlsConfig.httpCookieStorage = HTTPCookieStorage.shared
        hlsConfig.allowsCellularAccess = true
        avSession = AVAssetDownloadURLSession(
            configuration: hlsConfig,
            assetDownloadDelegate: self,
            delegateQueue: .main
        )

        let fileConfig = URLSessionConfiguration.background(withIdentifier: "com.storytime.universe.downloads.file")
        fileConfig.httpCookieStorage = HTTPCookieStorage.shared
        fileConfig.allowsCellularAccess = true
        fileSession = URLSession(configuration: fileConfig, delegate: self, delegateQueue: .main)

        loadRecords()
        reconnectInFlightTasks()
    }

    static func makeKey(contentId: String, episodeId: String?) -> String {
        if let episodeId, !episodeId.isEmpty { return "\(contentId)|\(episodeId)" }
        return contentId
    }

    // MARK: - Queries

    func record(forKey key: String) -> DownloadRecord? { records[key] }

    func record(contentId: String, episodeId: String?) -> DownloadRecord? {
        records[Self.makeKey(contentId: contentId, episodeId: episodeId)]
    }

    /// A local asset to play offline, or nil if not downloaded.
    func offlineAsset(contentId: String, episodeId: String?) -> AVURLAsset? {
        guard let record = record(contentId: contentId, episodeId: episodeId),
              record.isPlayableOffline,
              let url = record.localURL,
              FileManager.default.fileExists(atPath: url.path)
        else { return nil }
        return AVURLAsset(url: url)
    }

    var completedRecords: [DownloadRecord] {
        records.values.filter { $0.state == .completed }.sorted { $0.createdAt > $1.createdAt }
    }

    var activeRecords: [DownloadRecord] {
        records.values
            .filter { $0.state == .downloading || $0.state == .queued || $0.state == .failed }
            .sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Start / cancel / delete

    func startDownload(_ spec: DownloadSpec) {
        let key = spec.key
        if let existing = records[key], existing.state == .completed || existing.state == .downloading || existing.state == .queued {
            return
        }

        var record = DownloadRecord(
            key: key,
            contentId: spec.contentId,
            episodeId: spec.episodeId,
            title: spec.title,
            subtitle: spec.subtitle,
            posterUrl: spec.posterUrl,
            type: spec.type,
            relativePath: nil,
            isHLS: true,
            state: .queued,
            progress: 0,
            totalBytes: 0,
            createdAt: Date(),
            durationSeconds: spec.durationSeconds,
            seasonNumber: spec.seasonNumber,
            episodeNumber: spec.episodeNumber
        )
        records[key] = record
        saveRecords()

        // Warm the poster into the disk cache so it shows while offline.
        if let poster = spec.posterUrl {
            let urls = MediaURL.candidates(posterUrl: poster, backdropUrl: nil, videoUrl: nil, preferBackdrop: false)
            Task { await ImageLoader.shared.prefetch(urls: urls, preferPortrait: true) }
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                let bundle = try await ViewerAPI.shared.fetchPlaybackBundle(
                    contentId: spec.contentId,
                    episodeId: spec.episodeId,
                    trailer: false
                )
                guard let url = bundle.streamURL else {
                    self.fail(key: key)
                    return
                }
                let isHLS = (bundle.playback?.type?.contains("mpegurl") ?? false)
                    || url.absoluteString.contains(".m3u8")
                self.beginTransfer(key: key, url: url, title: spec.title, isHLS: isHLS)
            } catch {
                self.fail(key: key)
            }
        }
    }

    private func beginTransfer(key: String, url: URL, title: String, isHLS: Bool) {
        guard var record = records[key] else { return }
        record.isHLS = isHLS
        record.state = .downloading
        records[key] = record
        saveRecords()

        if isHLS {
            let cookies = HTTPCookieStorage.shared.cookies(for: url) ?? []
            let options: [String: Any] = [AVURLAssetHTTPCookiesKey: cookies]
            let asset = AVURLAsset(url: url, options: options)
            guard let task = avSession.makeAssetDownloadTask(
                asset: asset,
                assetTitle: title,
                assetArtworkData: nil,
                options: nil
            ) else {
                fail(key: key)
                return
            }
            task.taskDescription = key
            avTaskKeys[task.taskIdentifier] = key
            keyToTask[key] = task
            task.resume()
        } else {
            let task = fileSession.downloadTask(with: url)
            task.taskDescription = key
            fileTaskKeys[task.taskIdentifier] = key
            keyToTask[key] = task
            task.resume()
        }
    }

    func cancelDownload(key: String) {
        keyToTask[key]?.cancel()
        keyToTask[key] = nil
        if let record = records[key], record.state != .completed {
            if let url = record.localURL {
                try? FileManager.default.removeItem(at: url)
            }
            records.removeValue(forKey: key)
            saveRecords()
        }
    }

    func deleteDownload(key: String) {
        keyToTask[key]?.cancel()
        keyToTask[key] = nil
        if let record = records[key], let url = record.localURL {
            try? FileManager.default.removeItem(at: url)
        }
        records.removeValue(forKey: key)
        saveRecords()
    }

    func deleteDownload(contentId: String, episodeId: String?) {
        deleteDownload(key: Self.makeKey(contentId: contentId, episodeId: episodeId))
    }

    // MARK: - Mutation helpers

    private func fail(key: String) {
        guard var record = records[key] else { return }
        record.state = .failed
        records[key] = record
        saveRecords()
    }

    private func update(key: String, _ mutate: (inout DownloadRecord) -> Void) {
        guard var record = records[key] else { return }
        mutate(&record)
        records[key] = record
    }

    // MARK: - Persistence

    private func loadRecords() {
        guard let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode([DownloadRecord].self, from: data)
        else { return }
        var map: [String: DownloadRecord] = [:]
        for var record in decoded {
            // Any download interrupted by a crash/relaunch that never finished is marked failed
            // unless the background session reattaches to it below.
            if record.state == .downloading || record.state == .queued {
                record.state = .failed
            }
            map[record.key] = record
        }
        records = map
    }

    private func saveRecords() {
        let array = Array(records.values)
        guard let data = try? JSONEncoder().encode(array) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    private func reconnectInFlightTasks() {
        avSession.getAllTasks { [weak self] tasks in
            guard let self else { return }
            for task in tasks {
                guard let key = task.taskDescription else { continue }
                self.avTaskKeys[task.taskIdentifier] = key
                self.keyToTask[key] = task
                self.update(key: key) { $0.state = .downloading }
            }
            self.saveRecords()
        }
        fileSession.getAllTasks { [weak self] tasks in
            guard let self else { return }
            for task in tasks {
                guard let key = task.taskDescription else { continue }
                self.fileTaskKeys[task.taskIdentifier] = key
                self.keyToTask[key] = task
                self.update(key: key) { $0.state = .downloading }
            }
            self.saveRecords()
        }
    }
}

// MARK: - AVAssetDownloadDelegate (HLS)

extension DownloadManager: AVAssetDownloadDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        assetDownloadTask: AVAssetDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let relative = location.relativePath
        let identifier = assetDownloadTask.taskIdentifier
        Task { @MainActor in
            guard let key = self.avTaskKeys[identifier] else { return }
            self.update(key: key) { $0.relativePath = relative }
            self.saveRecords()
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        assetDownloadTask: AVAssetDownloadTask,
        didLoad timeRange: CMTimeRange,
        totalTimeRangeLoaded loadedTimeRanges: [NSValue],
        timeRangeExpectedToLoad: CMTimeRange
    ) {
        var loaded = 0.0
        for value in loadedTimeRanges {
            loaded += value.timeRangeValue.duration.seconds
        }
        let expected = timeRangeExpectedToLoad.duration.seconds
        let progress = expected > 0 ? min(loaded / expected, 1) : 0
        let identifier = assetDownloadTask.taskIdentifier
        Task { @MainActor in
            guard let key = self.avTaskKeys[identifier] else { return }
            self.update(key: key) {
                $0.progress = progress
                if $0.state == .queued { $0.state = .downloading }
            }
        }
    }
}

// MARK: - URLSessionDownloadDelegate (progressive fallback)

extension DownloadManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let identifier = downloadTask.taskIdentifier
        // Move the temp file synchronously (it is deleted when this method returns).
        let fm = FileManager.default
        let dir = fileDownloadsDir
        let filename = "\(downloadTask.taskDescription ?? UUID().uuidString).mp4"
            .replacingOccurrences(of: "|", with: "_")
        let dest = dir.appendingPathComponent(filename)
        try? fm.removeItem(at: dest)
        var moved = false
        do {
            try fm.moveItem(at: location, to: dest)
            moved = true
        } catch {
            moved = false
        }
        let relative = moved ? Self.relativePath(for: dest) : nil
        Task { @MainActor in
            guard let key = self.fileTaskKeys[identifier] else { return }
            self.update(key: key) {
                $0.relativePath = relative
                if relative == nil { $0.state = .failed }
            }
            self.saveRecords()
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let progress = totalBytesExpectedToWrite > 0
            ? min(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite), 1)
            : 0
        let identifier = downloadTask.taskIdentifier
        Task { @MainActor in
            guard let key = self.fileTaskKeys[identifier] else { return }
            self.update(key: key) {
                $0.progress = progress
                $0.totalBytes = totalBytesExpectedToWrite
                if $0.state == .queued { $0.state = .downloading }
            }
        }
    }

    private nonisolated static func relativePath(for url: URL) -> String {
        let home = NSHomeDirectory()
        let path = url.path
        if path.hasPrefix(home) {
            return String(path.dropFirst(home.count).drop(while: { $0 == "/" }))
        }
        return path
    }
}

// MARK: - Shared completion (both sessions)

extension DownloadManager: URLSessionTaskDelegate {
    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            let handler = self.backgroundCompletionHandler
            self.backgroundCompletionHandler = nil
            handler?()
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        let identifier = task.taskIdentifier
        let nsError = error as NSError?
        let cancelled = nsError?.code == NSURLErrorCancelled
        Task { @MainActor in
            let key = self.avTaskKeys[identifier] ?? self.fileTaskKeys[identifier]
            self.avTaskKeys[identifier] = nil
            self.fileTaskKeys[identifier] = nil
            guard let key else { return }
            self.keyToTask[key] = nil

            if cancelled {
                // Cancellation is handled by cancel/delete already.
                return
            }

            if error != nil {
                self.update(key: key) { $0.state = .failed }
                self.saveRecords()
                return
            }

            self.update(key: key) { record in
                if record.relativePath != nil {
                    record.state = .completed
                    record.progress = 1
                } else {
                    record.state = .failed
                }
            }
            self.saveRecords()
        }
    }
}
