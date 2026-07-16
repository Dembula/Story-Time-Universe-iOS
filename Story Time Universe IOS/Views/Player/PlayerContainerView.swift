import AVKit
import Combine
import SwiftUI

struct PlayerContainerView: View {
    let contentId: String
    let title: String
    var episodeId: String?
    var isTrailer: Bool = false

    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = PlayerViewModel()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player = model.player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else if model.isLoading {
                ProgressView(isTrailer ? "Loading trailer…" : "Loading…")
                    .tint(Theme.accent)
                    .foregroundStyle(.white)
            } else if let error = model.errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(Theme.accent)
                    Text(error)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .padding(.horizontal)
                    Button("Close") { close() }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                        .foregroundStyle(.black)
                }
            }

            VStack {
                HStack {
                    Button { close() } label: {
                        Image(systemName: "xmark")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    Spacer()
                    Text(isTrailer ? "Trailer · \(title)" : title)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer()
                    Color.clear.frame(width: 40, height: 40)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                Spacer()
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .task {
            OrientationLock.lockLandscape()
            await model.start(contentId: contentId, episodeId: episodeId, trailer: isTrailer)
        }
        .onDisappear {
            model.stop()
            OrientationLock.unlockPortrait()
        }
    }

    private func close() {
        model.stop()
        OrientationLock.unlockPortrait()
        dismiss()
    }
}

@MainActor
final class PlayerViewModel: ObservableObject {
    @Published var player: AVPlayer?
    @Published var isLoading = true
    @Published var errorMessage: String?

    private var contentId: String = ""
    private var progressTimer: AnyCancellable?
    private var endObserver: NSObjectProtocol?
    private var watchedSeconds: Double = 0
    private var lastSavedPosition: Double = 0

    func start(contentId: String, episodeId: String?, trailer: Bool = false) async {
        self.contentId = contentId
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let bundle = try await ViewerAPI.shared.fetchPlaybackBundle(
                contentId: contentId,
                episodeId: episodeId,
                trailer: trailer
            )
            guard let url = bundle.streamURL else {
                throw APIError.server("No playable stream was returned for this title.")
            }

            let resumeAt: Int
            if trailer {
                resumeAt = 0
            } else {
                let progress = try await ViewerAPI.shared.fetchWatchProgress(contentId: contentId)
                resumeAt = progress.position
            }
            let asset = Self.authenticatedAsset(for: url)
            let item = AVPlayerItem(asset: asset)
            let avPlayer = AVPlayer(playerItem: item)
            avPlayer.automaticallyWaitsToMinimizeStalling = true
            self.player = avPlayer

            if !trailer, resumeAt > 5 {
                let time = CMTime(seconds: Double(resumeAt), preferredTimescale: 600)
                await avPlayer.seek(to: time)
            }

            avPlayer.play()
            if !trailer {
                beginProgressReporting(player: avPlayer)
            }

            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.flushProgress(final: true)
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop() {
        flushProgress(final: true)
        progressTimer?.cancel()
        progressTimer = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
    }

    private func beginProgressReporting(player: AVPlayer) {
        progressTimer = Timer.publish(every: 8, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.flushProgress(final: false)
            }
    }

    private func flushProgress(final: Bool) {
        guard let player, !contentId.isEmpty else { return }
        let position = player.currentTime().seconds
        guard position.isFinite, position >= 0 else { return }
        let duration = player.currentItem?.duration.seconds
        let dur = (duration?.isFinite == true) ? duration : nil

        if abs(position - lastSavedPosition) < 3, !final { return }
        lastSavedPosition = position
        watchedSeconds = max(watchedSeconds, position)

        Task {
            await ViewerAPI.shared.saveWatchProgress(
                contentId: contentId,
                positionSeconds: position,
                durationSeconds: dur
            )
            if final, watchedSeconds > 5 {
                await ViewerAPI.shared.recordWatchSession(
                    contentId: contentId,
                    durationSeconds: watchedSeconds
                )
            }
        }
    }

    private static func authenticatedAsset(for url: URL) -> AVURLAsset {
        var headers: [String: String] = [
            "User-Agent": "StoryTimeUniverseiOS/1.0",
            "Accept": "*/*",
        ]
        if let cookies = HTTPCookieStorage.shared.cookies(for: url), !cookies.isEmpty {
            let cookieHeader = HTTPCookie.requestHeaderFields(with: cookies)
            for (key, value) in cookieHeader {
                headers[key] = value
            }
        } else if let all = HTTPCookieStorage.shared.cookies {
            let host = url.host ?? AppConfig.apiBaseURL.host ?? ""
            let matched = all.filter { cookie in
                host.hasSuffix(cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")))
                    || cookie.domain == host
            }
            if !matched.isEmpty {
                let cookieHeader = HTTPCookie.requestHeaderFields(with: matched)
                for (key, value) in cookieHeader {
                    headers[key] = value
                }
            }
        }
        return AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
    }
}
