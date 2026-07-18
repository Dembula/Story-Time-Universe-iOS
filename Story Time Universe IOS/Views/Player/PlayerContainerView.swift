import AVFoundation
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
    @State private var isLocked = false
    @State private var brightness = Double(UIScreen.main.brightness)
    @State private var seekFeedback: SeekFeedback?
    @State private var seekFeedbackTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player = model.player {
                PlayerLayerView(player: player)
                    .ignoresSafeArea()

                seekTapLayer

                if seekFeedback != nil {
                    seekFeedbackOverlay
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                if isLocked {
                    lockedOverlay
                        .opacity(controlsVisible ? 1 : 0)
                        .allowsHitTesting(controlsVisible)
                        .animation(.easeInOut(duration: 0.25), value: controlsVisible)
                } else {
                    controlsOverlay(player: player)
                        .opacity(controlsVisible ? 1 : 0)
                        .allowsHitTesting(controlsVisible)
                        .animation(.easeInOut(duration: 0.25), value: controlsVisible)
                }
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

    private var seekTapLayer: some View {
        HStack(spacing: 0) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { doubleTapSeek(by: -10) }
                .onTapGesture { toggleControls() }
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { doubleTapSeek(by: 10) }
                .onTapGesture { toggleControls() }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var seekFeedbackOverlay: some View {
        if let feedback = seekFeedback {
            HStack {
                if feedback.isForward { Spacer() }
                VStack(spacing: 6) {
                    Image(systemName: feedback.isForward ? "goforward.10" : "gobackward.10")
                        .font(.system(size: 40, weight: .semibold))
                    Text("\(abs(Int(feedback.total)))s")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(28)
                .background(.ultraThinMaterial, in: Circle())
                .padding(.horizontal, 48)
                if !feedback.isForward { Spacer() }
            }
        }
    }

    private var lockedOverlay: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    isLocked = false
                    showControls(persistent: !model.isPlaying)
                } label: {
                    Image(systemName: "lock.fill")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(14)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            Spacer()
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
            .allowsHitTesting(false)

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
                    Button {
                        isLocked = true
                        showControls(persistent: false)
                    } label: {
                        Image(systemName: "lock.open")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                Spacer()

                HStack(spacing: 48) {
                    Button { doubleTapSeek(by: -10) } label: {
                        Image(systemName: "gobackward.10")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(.white)
                            .shadow(radius: 6)
                    }

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

                    Button { doubleTapSeek(by: 10) } label: {
                        Image(systemName: "goforward.10")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(.white)
                            .shadow(radius: 6)
                    }
                }

                Spacer()

                PlayerProgressBar(player: player)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
            }

            HStack {
                BrightnessSlider(brightness: $brightness)
                    .padding(.leading, 20)
                    .onChange(of: brightness) { _, newValue in
                        UIScreen.main.brightness = CGFloat(newValue)
                        showControls(persistent: !model.isPlaying)
                    }
                Spacer()
            }
        }
    }

    private func doubleTapSeek(by delta: Double) {
        guard !isLocked else { return }
        model.seek(by: delta)
        let total = (seekFeedback?.isForward == (delta > 0)) ? (seekFeedback?.total ?? 0) + delta : delta
        withAnimation(.easeInOut(duration: 0.15)) {
            seekFeedback = SeekFeedback(isForward: delta > 0, total: total)
        }
        seekFeedbackTask?.cancel()
        seekFeedbackTask = Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) { seekFeedback = nil }
            }
        }
    }

    private func toggleControls() {
        if controlsVisible {
            controlsVisible = false
            hideTask?.cancel()
        } else {
            showControls(persistent: !isLocked && !model.isPlaying)
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
        guard isLocked || model.isPlaying else { return }
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if isLocked || model.isPlaying {
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

private struct SeekFeedback: Equatable {
    let isForward: Bool
    let total: Double
}

private struct BrightnessSlider: View {
    @Binding var brightness: Double

    private let trackHeight: CGFloat = 150
    private let trackWidth: CGFloat = 4

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
                .shadow(color: .black.opacity(0.45), radius: 2, y: 1)

            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(.white.opacity(0.22))
                    .frame(width: trackWidth, height: trackHeight)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Theme.accent, Theme.accentGold],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: trackWidth, height: max(trackHeight * CGFloat(clamped), trackWidth))
                    .shadow(color: Theme.accent.opacity(0.55), radius: 6, y: 0)
            }
            .frame(width: 44, height: trackHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let ratio = 1 - (value.location.y / trackHeight)
                        brightness = min(1, max(0, Double(ratio)))
                    }
            )

            Image(systemName: "sun.min.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
        }
    }

    private var clamped: Double { min(1, max(0, brightness)) }
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
            GeometryReader { geo in
                let width = geo.size.width
                let value = isScrubbing ? scrubValue : current
                let fraction = duration > 0 ? min(max(value / duration, 0), 1) : 0

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.22))
                        .frame(height: 4)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Theme.accent, Theme.accentGold],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(width * CGFloat(fraction), 0), height: 4)
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            isScrubbing = true
                            let ratio = min(max(g.location.x / width, 0), 1)
                            scrubValue = Double(ratio) * duration
                        }
                        .onEnded { _ in
                            let time = CMTime(seconds: scrubValue, preferredTimescale: 600)
                            player.seek(to: time)
                            current = scrubValue
                            isScrubbing = false
                        }
                )
            }
            .frame(height: 22)

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

        Self.configureAudioSession()

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
            avPlayer.isMuted = false
            avPlayer.volume = 1.0
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

    func seek(by delta: Double) {
        guard let player else { return }
        let currentSeconds = player.currentTime().seconds
        guard currentSeconds.isFinite else { return }
        var target = currentSeconds + delta
        target = max(0, target)
        if let duration = player.currentItem?.duration.seconds, duration.isFinite {
            target = min(target, duration)
        }
        let time = CMTime(seconds: target, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
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

    private static func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true, options: [])
        } catch {
            print("AudioSession configuration failed: \(error)")
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
