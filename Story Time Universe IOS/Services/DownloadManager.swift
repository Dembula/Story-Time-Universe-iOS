import AVFoundation
import Combine
import Foundation

/// Manages offline downloads for in-app-only playback.
///
/// Downloads are **account-scoped**: only the signed-in owner can list or play them.
/// Signing out clears access (files stay on disk for that account’s next login).
/// Another account never sees or plays someone else’s downloads.
///
/// HLS titles are stored as an iOS-managed `.movpkg` via `AVAssetDownloadURLSession`.
/// Progressive fallbacks are written into Application Support. Neither is exposed
/// to the Files app.
@MainActor
final class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()

    private static let offlineAccountDefaultsKey = "downloads.offlineAccountId"

    /// Content-key → record for the **active** account only (empty when signed out).
    @Published private(set) var records: [String: DownloadRecord] = [:]

    /// Account currently allowed to see/play downloads (`nil` = signed out → no access).
    private(set) var activeAccountId: String?

    /// Set by the app delegate when iOS relaunches us to finish background transfers.
    var backgroundCompletionHandler: (() -> Void)?

    /// Full library across accounts. Key = `owner::contentKey`.
    private var library: [String: DownloadRecord] = [:]

    private var avSession: AVAssetDownloadURLSession!
    private var fileSession: URLSession!

    private var avTaskKeys: [Int: String] = [:]
    private var fileTaskKeys: [Int: String] = [:]
    private var keyToTask: [String: URLSessionTask] = [:]
    private var keyExpectedDuration: [String: Double] = [:]
    private var progressObservations: [String: NSKeyValueObservation] = [:]
    private var lastProgressPublish: [String: Date] = [:]

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

        loadLibrary()
        // Restore last signed-in account for offline cold start (cleared on logout).
        if let saved = UserDefaults.standard.string(forKey: Self.offlineAccountDefaultsKey), !saved.isEmpty {
            activeAccountId = saved
        }
        publishActiveRecords()
        validateOfflineLibrary()
        reconnectInFlightTasks()
    }

    nonisolated static func makeKey(contentId: String, episodeId: String?) -> String {
        if let episodeId, !episodeId.isEmpty { return "\(contentId)|\(episodeId)" }
        return contentId
    }

    private static func libraryKey(owner: String, contentKey: String) -> String {
        "\(owner)::\(contentKey)"
    }

    // MARK: - Account binding

    /// Bind downloads to this account (sign-in / session restore). Pass `nil` on logout.
    func bindAccount(_ accountId: String?) {
        let trimmed = accountId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = (trimmed?.isEmpty == false) ? trimmed : nil
        activeAccountId = resolved
        if let resolved {
            UserDefaults.standard.set(resolved, forKey: Self.offlineAccountDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.offlineAccountDefaultsKey)
        }
        publishActiveRecords()
    }

    /// Sign-out: revoke access immediately (files kept for the same account later).
    func clearAccountAccess() {
        bindAccount(nil)
    }

    /// Permanently remove every download owned by this account (e.g. account deletion).
    func wipeDownloads(forAccount accountId: String) {
        let owned = library.filter { $0.value.ownerAccountId == accountId }
        for (libKey, record) in owned {
            keyToTask[libKey]?.cancel()
            keyToTask[libKey] = nil
            progressObservations[libKey]?.invalidate()
            progressObservations[libKey] = nil
            if let url = record.localURL {
                try? FileManager.default.removeItem(at: url)
            }
            library.removeValue(forKey: libKey)
        }
        if activeAccountId == accountId {
            publishActiveRecords()
        }
        saveLibrary()
    }

    // MARK: - Queries (active account only)

    func record(forKey key: String) -> DownloadRecord? { records[key] }

    func record(contentId: String, episodeId: String?) -> DownloadRecord? {
        records[Self.makeKey(contentId: contentId, episodeId: episodeId)]
    }

    /// A local asset to play offline for the **active** account, or nil.
    func offlineAsset(contentId: String, episodeId: String?) -> AVURLAsset? {
        guard activeAccountId != nil,
              let record = record(contentId: contentId, episodeId: episodeId),
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

    var hasPlayableDownloadsForActiveAccount: Bool {
        !completedRecords.isEmpty
    }

    // MARK: - Start / cancel / delete

    func startDownload(_ spec: DownloadSpec) {
        if ParentalControls.shared.blockDownloads { return }
        guard let owner = activeAccountId, !owner.isEmpty else { return }

        let contentKey = spec.key
        let libKey = Self.libraryKey(owner: owner, contentKey: contentKey)
        if let existing = library[libKey],
           existing.state == .completed || existing.state == .downloading || existing.state == .queued {
            return
        }

        let record = DownloadRecord(
            key: contentKey,
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
            episodeNumber: spec.episodeNumber,
            ownerAccountId: owner
        )
        library[libKey] = record
        publishActiveRecords()
        saveLibrary()
        if let seconds = spec.durationSeconds, seconds > 0 {
            keyExpectedDuration[libKey] = Double(seconds)
        }

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
                    self.fail(libraryKey: libKey)
                    return
                }
                let isHLS = (bundle.playback?.type?.contains("mpegurl") ?? false)
                    || url.absoluteString.contains(".m3u8")
                self.beginTransfer(libraryKey: libKey, url: url, title: spec.title, isHLS: isHLS)
            } catch {
                self.fail(libraryKey: libKey)
            }
        }
    }

    private func beginTransfer(libraryKey: String, url: URL, title: String, isHLS: Bool) {
        guard var record = library[libraryKey] else { return }
        record.isHLS = isHLS
        record.state = .downloading
        library[libraryKey] = record
        publishActiveRecords()
        saveLibrary()

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
                fail(libraryKey: libraryKey)
                return
            }
            task.taskDescription = libraryKey
            avTaskKeys[task.taskIdentifier] = libraryKey
            keyToTask[libraryKey] = task
            observeProgress(task: task, libraryKey: libraryKey)
            task.resume()
        } else {
            let task = fileSession.downloadTask(with: url)
            task.taskDescription = libraryKey
            fileTaskKeys[task.taskIdentifier] = libraryKey
            keyToTask[libraryKey] = task
            observeProgress(task: task, libraryKey: libraryKey)
            task.resume()
        }
    }

    private func observeProgress(task: URLSessionTask, libraryKey: String) {
        progressObservations[libraryKey]?.invalidate()
        progressObservations[libraryKey] = task.progress.observe(\.fractionCompleted, options: [.new]) { [weak self] progress, _ in
            let fraction = progress.fractionCompleted
            Task { @MainActor in
                self?.publishProgress(libraryKey: libraryKey, fraction: fraction)
            }
        }
    }

    private func publishProgress(libraryKey: String, fraction: Double) {
        let clamped = min(max(fraction, 0), 0.99)
        if let last = lastProgressPublish[libraryKey], Date().timeIntervalSince(last) < 0.25, clamped < 0.99 {
            return
        }
        lastProgressPublish[libraryKey] = Date()
        update(libraryKey: libraryKey) {
            if clamped > $0.progress {
                $0.progress = clamped
            }
            if $0.state == .queued { $0.state = .downloading }
        }
    }

    func cancelDownload(key: String) {
        guard let libKey = libraryKeyForActiveContentKey(key) else { return }
        keyToTask[libKey]?.cancel()
        keyToTask[libKey] = nil
        progressObservations[libKey]?.invalidate()
        progressObservations[libKey] = nil
        keyExpectedDuration[libKey] = nil
        lastProgressPublish[libKey] = nil
        if let record = library[libKey], record.state != .completed {
            if let url = record.localURL {
                try? FileManager.default.removeItem(at: url)
            }
            library.removeValue(forKey: libKey)
            publishActiveRecords()
            saveLibrary()
        }
    }

    func deleteDownload(key: String) {
        guard let libKey = libraryKeyForActiveContentKey(key) else { return }
        keyToTask[libKey]?.cancel()
        keyToTask[libKey] = nil
        progressObservations[libKey]?.invalidate()
        progressObservations[libKey] = nil
        keyExpectedDuration[libKey] = nil
        lastProgressPublish[libKey] = nil
        if let record = library[libKey], let url = record.localURL {
            try? FileManager.default.removeItem(at: url)
        }
        library.removeValue(forKey: libKey)
        publishActiveRecords()
        saveLibrary()
    }

    func deleteDownload(contentId: String, episodeId: String?) {
        deleteDownload(key: Self.makeKey(contentId: contentId, episodeId: episodeId))
    }

    private func libraryKeyForActiveContentKey(_ contentKey: String) -> String? {
        guard let owner = activeAccountId else { return nil }
        return Self.libraryKey(owner: owner, contentKey: contentKey)
    }

    // MARK: - Mutation helpers

    private func fail(libraryKey: String) {
        update(libraryKey: libraryKey) { $0.state = .failed }
        saveLibrary()
    }

    private func update(libraryKey: String, _ mutate: (inout DownloadRecord) -> Void) {
        guard var record = library[libraryKey] else { return }
        mutate(&record)
        library[libraryKey] = record
        publishActiveRecords()
    }

    private func publishActiveRecords() {
        guard let owner = activeAccountId else {
            records = [:]
            return
        }
        var next: [String: DownloadRecord] = [:]
        for record in library.values where record.ownerAccountId == owner {
            next[record.key] = record
        }
        records = next
    }

    // MARK: - Persistence

    private func loadLibrary() {
        guard let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode([DownloadRecord].self, from: data)
        else { return }

        var map: [String: DownloadRecord] = [:]
        var purgedOrphans = false
        for var record in decoded {
            if record.state == .downloading || record.state == .queued {
                record.state = .failed
            }
            if record.state == .completed, record.localURL == nil {
                record.state = .failed
            }
            // Legacy device-wide downloads (no owner) are inaccessible — remove for privacy.
            guard let owner = record.ownerAccountId?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !owner.isEmpty
            else {
                if let url = record.localURL {
                    try? FileManager.default.removeItem(at: url)
                }
                purgedOrphans = true
                continue
            }
            record.ownerAccountId = owner
            let libKey = Self.libraryKey(owner: owner, contentKey: record.key)
            map[libKey] = record
        }
        library = map
        if purgedOrphans {
            saveLibrary()
        }
    }

    private func saveLibrary() {
        let array = Array(library.values)
        guard let data = try? JSONEncoder().encode(array) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    private func reconnectInFlightTasks() {
        avSession.getAllTasks { [weak self] tasks in
            guard let self else { return }
            for task in tasks {
                guard let libKey = task.taskDescription else { continue }
                self.avTaskKeys[task.taskIdentifier] = libKey
                self.keyToTask[libKey] = task
                self.observeProgress(task: task, libraryKey: libKey)
                self.update(libraryKey: libKey) { $0.state = .downloading }
            }
            self.saveLibrary()
        }
        fileSession.getAllTasks { [weak self] tasks in
            guard let self else { return }
            for task in tasks {
                guard let libKey = task.taskDescription else { continue }
                self.fileTaskKeys[task.taskIdentifier] = libKey
                self.keyToTask[libKey] = task
                self.observeProgress(task: task, libraryKey: libKey)
                self.update(libraryKey: libKey) { $0.state = .downloading }
            }
            self.saveLibrary()
        }
    }

    func validateOfflineLibrary() {
        var changed = false
        for (libKey, record) in library where record.state == .completed {
            if record.localURL == nil {
                var fixed = record
                fixed.state = .failed
                library[libKey] = fixed
                changed = true
            }
        }
        if changed {
            publishActiveRecords()
            saveLibrary()
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
        let identifier = assetDownloadTask.taskIdentifier
        Task { @MainActor in
            guard let libKey = self.avTaskKeys[identifier] else { return }
            self.update(libraryKey: libKey) {
                $0.relativePath = DownloadRecord.storagePath(for: location.standardizedFileURL)
            }
            self.saveLibrary()
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
        var progress = expected > 0 ? min(loaded / expected, 0.99) : 0
        let identifier = assetDownloadTask.taskIdentifier
        Task { @MainActor in
            guard let libKey = self.avTaskKeys[identifier] else { return }
            if progress <= 0, let duration = self.keyExpectedDuration[libKey], duration > 0 {
                progress = min(loaded / duration, 0.99)
            }
            self.publishProgress(libraryKey: libKey, fraction: progress)
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
        let fm = FileManager.default
        let dir = fileDownloadsDir
        let filename = "\(downloadTask.taskDescription ?? UUID().uuidString).mp4"
            .replacingOccurrences(of: "|", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        let dest = dir.appendingPathComponent(filename)
        try? fm.removeItem(at: dest)
        var moved = false
        do {
            try fm.moveItem(at: location, to: dest)
            moved = true
        } catch {
            moved = false
        }
        let relative = moved ? DownloadRecord.storagePath(for: dest) : nil
        Task { @MainActor in
            guard let libKey = self.fileTaskKeys[identifier] else { return }
            self.update(libraryKey: libKey) {
                $0.relativePath = relative
                if relative == nil { $0.state = .failed }
            }
            self.saveLibrary()
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
            ? min(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite), 0.99)
            : 0
        let identifier = downloadTask.taskIdentifier
        Task { @MainActor in
            guard let libKey = self.fileTaskKeys[identifier] else { return }
            self.publishProgress(libraryKey: libKey, fraction: progress)
            if totalBytesExpectedToWrite > 0 {
                self.update(libraryKey: libKey) { $0.totalBytes = totalBytesExpectedToWrite }
            }
        }
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
            let libKey = self.avTaskKeys[identifier] ?? self.fileTaskKeys[identifier]
            self.avTaskKeys[identifier] = nil
            self.fileTaskKeys[identifier] = nil
            guard let libKey else { return }
            self.keyToTask[libKey] = nil
            self.progressObservations[libKey]?.invalidate()
            self.progressObservations[libKey] = nil
            self.keyExpectedDuration[libKey] = nil
            self.lastProgressPublish[libKey] = nil

            if cancelled { return }

            if error != nil {
                self.update(libraryKey: libKey) { $0.state = .failed }
                self.saveLibrary()
                return
            }

            self.update(libraryKey: libKey) { record in
                if record.relativePath != nil {
                    record.progress = 1
                    record.state = record.localURL != nil ? .completed : .failed
                } else {
                    record.state = .failed
                }
            }
            self.saveLibrary()
        }
    }
}
