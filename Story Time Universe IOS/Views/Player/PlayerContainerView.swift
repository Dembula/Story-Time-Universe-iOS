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
    @State private var controlsVisible = true
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player = model.player {
                PlayerLayerView(player: player)
                    .ignoresSafeArea()

                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { toggleControls() }

                controlsOverlay(player: player)
                    .opacity(controlsVisible ? 1 : 0)
                    .allowsHitTesting(controlsVisible)
                    .animation(.easeInOut(duration: 0.25), value: controlsVisible)
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
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .task {
            OrientationLock.lockLandscape()
            await model.start(contentId: contentId, episodeId: episodeId, trailer: isTrailer)
            scheduleHideControls()
        }
        .onDisappear {
            hideTask?.cancel()
            model.stop()
            OrientationLock.unlockPortrait()
        }
        .onChange(of: model.isPlaying) { _, playing in
            if playing {
                scheduleHideControls()
            } else {
                showControls(persistent: true)
            }
        }
    }

    @ViewBuilder
    private func controlsOverlay(player: AVPlayer) -> some View {
        ZStack {
            LinearGradient(
                colors: [.black.opacity(0.55), .clear, .clear, .black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture { toggleControls() }

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
                        .shadow(radius: 4)
                    Spacer()
                    Color.clear.frame(width: 40, height: 40)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                Spacer()

                Button {
                    model.togglePlayPause()
                    showControls(persistent: !model.isPlaying)
                } label: {
                    Image(systemName: model.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 64))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white)
                        .shadow(radius: 8)
                }

                Spacer()

                PlayerProgressBar(player: player)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
            }
        }
    }

    private func toggleControls() {
        if controlsVisible {
            controlsVisible = false
            hideTask?.cancel()
        } else {
            showControls(persistent: !model.isPlaying)
        }
    }

    private func showControls(persistent: Bool) {
        controlsVisible = true
        hideTask?.cancel()
        if !persistent {
            scheduleHideControls()
        }
    }

    private func scheduleHideControls() {
        hideTask?.cancel()
        guard model.isPlaying else { return }
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if model.isPlaying {
                    controlsVisible = false
                }
            }
        }
    }

    private func close() {
        hideTask?.cancel()
        model.stop()
        OrientationLock.unlockPortrait()
        dismiss()
    }
}

private struct PlayerLayerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspect
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player {
            controller.player = player
        }
    }
}

private struct PlayerProgressBar: View {
    let player: AVPlayer
    @State private var current: Double = 0
    @State private var duration: Double = 1
    @State private var isScrubbing = false
    @State private var scrubValue: Double = 0

    var body: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: { isScrubbing ? scrubValue : current },
                    set: { scrubValue = $0 }
                ),
                in: 0...max(duration, 0.1),
                onEditingChanged: { editing in
                    isScrubbing = editing
                    if !editing {
                        let time = CMTime(seconds: scrubValue, preferredTimescale: 600)
                        player.seek(to: time)
                        current = scrubValue
                    }
                }
            )
            .tint(Theme.accent)

            HStack {
                Text(format(current))
                Spacer()
                Text(format(duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white.opacity(0.85))
        }
        .onReceive(Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()) { _ in
            guard !isScrubbing else { return }
            let seconds = player.currentTime().seconds
            if seconds.isFinite { current = max(0, seconds) }
            let total = player.currentItem?.duration.seconds ?? 0
            if total.isFinite, total > 0 { duration = total }
        }
    }

    private func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

@MainActor
final class PlayerViewModel: ObservableObject {
    @Published var player: AVPlayer?
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published var isPlaying = false

    private var contentId: String = ""
    private var progressTimer: AnyCancellable?
    private var endObserver: NSObjectProtocol?
    private var timeControlObserver: NSKeyValueObservation?
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
            observePlayback(avPlayer)

            if !trailer, resumeAt > 5 {
                let time = CMTime(seconds: Double(resumeAt), preferredTimescale: 600)
                await avPlayer.seek(to: time)
            }

            avPlayer.play()
            isPlaying = true
            if !trailer {
                beginProgressReporting(player: avPlayer)
            }

            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.isPlaying = false
                    self?.flushProgress(final: true)
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func togglePlayPause() {
        guard let player else { return }
        if player.timeControlStatus == .playing {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    func stop() {
        flushProgress(final: true)
        progressTimer?.cancel()
        progressTimer = nil
        timeControlObserver?.invalidate()
        timeControlObserver = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        isPlaying = false
    }

    private func observePlayback(_ player: AVPlayer) {
        timeControlObserver?.invalidate()
        timeControlObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor in
                self?.isPlaying = player.timeControlStatus == .playing
            }
        }
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
