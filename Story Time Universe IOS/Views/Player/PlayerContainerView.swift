import AVFoundation
import Combine
import SwiftUI
import UIKit

// MARK: - Player container (Netflix-inspired)

struct PlayerContainerView: View {
    let contentId: String
    let title: String
    var episodeId: String?
    var isTrailer: Bool = false
    var episodes: [EpisodePlaybackInfo] = []
    /// When true, skip resume progress and start at 0.
    var forceRestart: Bool = false

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @StateObject private var model = PlayerViewModel()

    @State private var controlsVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var isLocked = false
    @State private var brightness = Double(UIScreen.main.brightness)
    @State private var brightnessBase = Double(UIScreen.main.brightness)
    @State private var isAdjustingBrightness = false
    @State private var seekBurst: SeekBurst?
    @State private var seekBurstTask: Task<Void, Never>?
    @State private var currentEpisodeId: String?
    @State private var showEndCreditsPrompt = false
    @State private var showNearEndNext = false
    @State private var nearEndSuppressed = false
    @State private var nextCountdown = 8
    @State private var countdownTask: Task<Void, Never>?
    @State private var showRestart = true
    @State private var restartConsumed = false
    @State private var restartTask: Task<Void, Never>?
    @State private var didUnlockOrientation = false
    @State private var showPPVPaywall = false
    @State private var isRetryingAfterPurchase = false
    @State private var scrubPosition: Double = 0
    @State private var scrubDuration: Double = 1
    @State private var resolvedEpisodes: [EpisodePlaybackInfo] = []
    /// Fit (letterbox) vs fill (crop edges to cover the screen). Toggle only — no pinch zoom.
    @State private var fillsScreen = false

    private let haptic = UIImpactFeedbackGenerator(style: .light)

    private var effectiveEpisodes: [EpisodePlaybackInfo] {
        resolvedEpisodes.isEmpty ? episodes : resolvedEpisodes
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player = model.player {
                PlayerLayerView(player: player, fillScreen: fillsScreen)
                    .ignoresSafeArea()
                    .clipped()

                playerGestureLayer

                if let burst = seekBurst {
                    DoubleTapSeekOverlay(isForward: burst.isForward, totalSeconds: burst.totalSeconds)
                        .id(burst.token)
                        .allowsHitTesting(false)
                }

                if isAdjustingBrightness && !isLocked {
                    brightnessHUD.allowsHitTesting(false)
                }

                // Captions stay visible even when chrome is hidden.
                if !isTrailer, let caption = model.subtitles.activeText, model.subtitles.isEnabled {
                    subtitleOverlay(caption)
                        .allowsHitTesting(false)
                        .zIndex(5)
                }

                if isLocked {
                    lockedChrome
                        .opacity(controlsVisible ? 1 : 0)
                        .allowsHitTesting(controlsVisible)
                        .animation(.easeInOut(duration: 0.38), value: controlsVisible)
                } else if !showEndCreditsPrompt {
                    mainChrome(player: player)
                        .opacity(controlsVisible ? 1 : 0)
                        .allowsHitTesting(controlsVisible)
                        .animation(.easeInOut(duration: 0.38), value: controlsVisible)
                }

                if showNearEndNext, nextEpisode != nil, !showEndCreditsPrompt, !isLocked {
                    nearEndNextBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if showEndCreditsPrompt, nextEpisode != nil {
                    endCreditsNextOverlay
                        .transition(.opacity)
                }
            } else if model.isLoading {
                ProgressView(isTrailer ? "Loading trailer…" : "Loading…")
                    .tint(Theme.accent)
                    .foregroundStyle(.white)
            } else if let error = model.errorMessage {
                errorChrome(error)
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .task {
            haptic.prepare()
            OrientationLock.lockLandscape()
            currentEpisodeId = episodeId
            brightness = Double(UIScreen.main.brightness)
            await model.start(
                contentId: contentId,
                episodeId: episodeId,
                trailer: isTrailer,
                forceRestart: forceRestart
            )
            await resolveEpisodeQueueIfNeeded()
            scheduleHideControls()
        }
        .onDisappear {
            hideTask?.cancel()
            countdownTask?.cancel()
            restartTask?.cancel()
            seekBurstTask?.cancel()
            // If PiP is active, keep the AVPlayer alive for the system mini player.
            if PictureInPictureManager.shared.isActive {
                unlockOrientationOnce()
                PictureInPictureManager.shared.onStopWhileDetached = { [model] in
                    model.stop()
                    PictureInPictureManager.shared.detach()
                }
                return
            }
            model.stop()
            PictureInPictureManager.shared.detach()
            unlockOrientationOnce()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            guard model.isPlaying, !isTrailer else { return }
            PictureInPictureManager.shared.startIfPossible()
        }
        .onChange(of: model.isPlaying) { _, playing in
            if playing {
                scheduleHideControls()
            } else if !showEndCreditsPrompt {
                showControls(persistent: true)
            }
        }
        .onChange(of: model.didReachEnd) { _, ended in
            guard ended, !isTrailer, nextEpisode != nil else { return }
            presentEndCreditsNext()
        }
        .onChange(of: brightness) { _, value in
            UIScreen.main.brightness = CGFloat(min(1, max(0, value)))
        }
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
            updateNearEndPrompt()
            updateScrubMirror()
        }
        .sheet(isPresented: $showPPVPaywall) {
            SubscriptionPaywallView(
                context: .ppv(contentId: contentId, title: title)
            ) {
                Task { await retryPlayAfterPurchase() }
            }
            .environmentObject(appState)
        }
    }

    private var currentIndex: Int? {
        guard let currentEpisodeId else { return nil }
        return effectiveEpisodes.firstIndex { $0.episodeId == currentEpisodeId }
    }

    private var nextEpisode: EpisodePlaybackInfo? {
        guard let idx = currentIndex, idx + 1 < effectiveEpisodes.count else { return nil }
        return effectiveEpisodes[idx + 1]
    }

    private var episodeTitleLine: String {
        if isTrailer { return "Trailer · \(title)" }
        if let current = effectiveEpisodes.first(where: { $0.episodeId == currentEpisodeId }) {
            return "\(current.episodeLabel)  \"\(current.title)\""
        }
        return title
    }

    // MARK: Chrome

    @ViewBuilder
    private func mainChrome(player: AVPlayer) -> some View {
        ZStack {
            VStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 100)
                Spacer()
                LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 150)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 18)
                    .padding(.top, 8)

                Spacer()

                HStack(spacing: 54) {
                    transportButton("gobackward.10") {
                        model.seek(by: -10)
                        lightHaptic()
                    }
                    Button {
                        model.togglePlayPause()
                        showControls(persistent: !model.isPlaying)
                    } label: {
                        Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 40, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 70, height: 70)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    transportButton("goforward.10") {
                        model.seek(by: 10)
                        lightHaptic()
                    }
                }

                Spacer()

                if !effectiveEpisodes.isEmpty, !isTrailer {
                    episodeStrip
                        .padding(.bottom, 8)
                }

                bottomTransport(player: player)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }

            HStack {
                BrightnessSlider(brightness: $brightness)
                    .padding(.leading, 14)
                Spacer()
            }
        }
    }

    private func subtitleOverlay(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(.system(size: 18, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.9), radius: 2, y: 1)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(.horizontal, 40)
                .padding(.bottom, controlsVisible && !effectiveEpisodes.isEmpty ? 150 : (controlsVisible ? 90 : 36))
                .animation(.easeInOut(duration: 0.2), value: controlsVisible)
        }
        .allowsHitTesting(false)
    }

    private var episodeStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Episodes")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.75))
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(effectiveEpisodes) { episode in
                        let isCurrent = episode.episodeId == currentEpisodeId
                        Button {
                            playEpisode(episode)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.white.opacity(0.12))
                                        .frame(width: 132, height: 74)
                                    if let thumb = episode.thumbnailUrl {
                                       let urls = MediaURL.candidates(posterUrl: thumb, backdropUrl: nil, videoUrl: nil, preferBackdrop: true)
                                       if !urls.isEmpty {
                                        RemoteImage(urls: urls)
                                            .frame(width: 132, height: 74)
                                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                       }
                                    }
                                    if isCurrent {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(Theme.accent, lineWidth: 2)
                                            .frame(width: 132, height: 74)
                                    }
                                }
                                Text(episode.episodeLabel)
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(isCurrent ? Theme.accent : .white.opacity(0.7))
                                Text(episode.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .frame(width: 132, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 34, height: 34)
                .shadow(color: Theme.accent.opacity(0.5), radius: 8, y: 0)
                .accessibilityHidden(true)

            Text(episodeTitleLine)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .shadow(color: .black.opacity(0.65), radius: 3)

            if !isTrailer {
                Button {
                    model.seek(to: 0)
                    model.play()
                    lightHaptic()
                    showControls(persistent: false)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Restart")
            }

            Spacer(minLength: 8)

            Button {
                lightHaptic()
                withAnimation(.easeInOut(duration: 0.2)) {
                    fillsScreen.toggle()
                }
                showControls(persistent: false)
            } label: {
                Image(systemName: fillsScreen
                      ? "arrow.down.right.and.arrow.up.left"
                      : "arrow.up.left.and.arrow.down.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(fillsScreen ? Theme.accent : .white)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(fillsScreen ? "Fit to screen" : "Fill screen")

            if !model.subtitles.availableTracks.isEmpty {
                Button {
                    lightHaptic()
                    model.subtitles.isEnabled.toggle()
                } label: {
                    Image(systemName: model.subtitles.isEnabled ? "captions.bubble.fill" : "captions.bubble")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(model.subtitles.isEnabled ? Theme.accent : .white)
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
            }

            if !isTrailer, PictureInPictureManager.shared.isPossible || model.player != nil {
                Button {
                    lightHaptic()
                    PictureInPictureManager.shared.startIfPossible()
                } label: {
                    Image(systemName: "pip.enter")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Picture in Picture")
            }

            Button {
                lightHaptic()
                isLocked = true
                showControls(persistent: false)
            } label: {
                Image(systemName: "lock.open.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)

            Button { close() } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private func bottomTransport(player: AVPlayer) -> some View {
        VStack(spacing: 10) {
            PlayerProgressBar(player: player, accent: Theme.accent) { scrubbing in
                if scrubbing { hideTask?.cancel() } else { scheduleHideControls() }
            }

            if nextEpisode != nil, !isTrailer {
                HStack {
                    Spacer()
                    Button { playNext() } label: {
                        Label("Next Episode", systemImage: "forward.end.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.95))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var lockedChrome: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    lightHaptic()
                    isLocked = false
                    showControls(persistent: !model.isPlaying)
                } label: {
                    Image(systemName: "lock.fill")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .padding(.trailing, 18)
                .padding(.top, 10)
            }
            Spacer()
        }
    }

    private var nearEndNextBar: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                HStack(spacing: 10) {
                    Button {
                        showNearEndNext = false
                        nearEndSuppressed = true
                        countdownTask?.cancel()
                    } label: {
                        Text("Watch Credits")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button { playNext() } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill")
                                .font(.caption.weight(.bold))
                            Text(nextCountdown > 0 ? "Next Episode · \(nextCountdown)" : "Next Episode")
                                .font(.subheadline.weight(.bold))
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(alignment: .leading) {
                            GeometryReader { geo in
                                let p = nextCountdown > 0 ? (1 - Double(nextCountdown) / 8.0) : 1
                                Color.black.opacity(0.1)
                                    .frame(width: max(0, geo.size.width * p))
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.trailing, 20)
                .padding(.bottom, 26)
            }
        }
    }

    private var endCreditsNextOverlay: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    HStack(spacing: 10) {
                        Button {
                            showEndCreditsPrompt = false
                            countdownTask?.cancel()
                            showControls(persistent: true)
                        } label: {
                            Text("Watch Credits")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button { playNext() } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "play.fill")
                                Text(nextCountdown > 0 ? "Next Episode · \(nextCountdown)" : "Next Episode")
                                    .fontWeight(.bold)
                            }
                            .foregroundStyle(.black)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.trailing, 22)
                    .padding(.bottom, 30)
                }
            }
        }
    }

    private func errorChrome(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: model.needsPurchase ? "cart.fill" : "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(Theme.accent)
            Text(error)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding(.horizontal)
            if model.needsPurchase {
                Button(appState.isPayPerViewAccount ? "Unlock to Watch" : "Subscribe with Apple") {
                    Task {
                        if appState.isPayPerViewAccount {
                            await unlockFromPlayer()
                        } else {
                            appState.presentPaywall(.reactivate)
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .foregroundStyle(.black)
            }
            Button("Close") { close() }
                .buttonStyle(.bordered)
                .tint(.white)
        }
    }

    private func transportButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(radius: 6)
                .frame(width: 54, height: 54)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var brightnessHUD: some View {
        HStack {
            VStack(spacing: 8) {
                Image(systemName: "sun.max.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                Capsule()
                    .fill(Color.white.opacity(0.25))
                    .frame(width: 5, height: 100)
                    .overlay(alignment: .bottom) {
                        Capsule()
                            .fill(Color.white)
                            .frame(height: max(6, 100 * brightness))
                    }
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.leading, 18)
            Spacer()
        }
    }

    private var playerGestureLayer: some View {
        GeometryReader { geo in
            let third = geo.size.width / 3
            HStack(spacing: 0) {
                Color.clear
                    .frame(width: third)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 8)
                            .onChanged { value in
                                guard !isLocked else { return }
                                let vertical = abs(value.translation.height)
                                let horizontal = abs(value.translation.width)
                                guard vertical > horizontal || isAdjustingBrightness else { return }
                                if !isAdjustingBrightness {
                                    isAdjustingBrightness = true
                                    brightnessBase = brightness
                                    hideTask?.cancel()
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        controlsVisible = false
                                    }
                                }
                                // Smooth, proportional brightness — full screen height ≈ full range.
                                let delta = -Double(value.translation.height) / Double(max(geo.size.height * 0.65, 1))
                                let next = min(1, max(0, brightnessBase + delta))
                                brightness = brightness * 0.2 + next * 0.8
                            }
                            .onEnded { _ in
                                withAnimation(.easeOut(duration: 0.18)) {
                                    isAdjustingBrightness = false
                                }
                                // Keep chrome faded; it returns on the next tap (same as normal playback).
                                if model.isPlaying {
                                    scheduleHideControls()
                                }
                            }
                    )
                    .onTapGesture(count: 2) { doubleTapSeek(by: -10) }
                    .onTapGesture { if !isAdjustingBrightness { toggleControls() } }

                Color.clear
                    .frame(width: third)
                    .contentShape(Rectangle())
                    .onTapGesture { toggleControls() }

                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { doubleTapSeek(by: 10) }
                    .onTapGesture { toggleControls() }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: Actions

    private func doubleTapSeek(by delta: Double) {
        guard !isLocked else { return }
        controlsVisible = false
        hideTask?.cancel()
        model.seek(by: delta)
        lightHaptic()

        let forward = delta > 0
        let prior = (seekBurst?.isForward == forward) ? (seekBurst?.totalSeconds ?? 0) : 0
        withAnimation(.easeOut(duration: 0.15)) {
            seekBurst = SeekBurst(isForward: forward, totalSeconds: prior + abs(Int(delta)), token: UUID())
        }
        seekBurstTask?.cancel()
        seekBurstTask = Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeIn(duration: 0.22)) { seekBurst = nil }
            }
        }
    }

    private func offerRestartWindow() {
        // Restart lives in the chrome overlay — it fades with controls and returns on tap.
        showRestart = !isTrailer
        restartConsumed = false
        restartTask?.cancel()
        restartTask = nil
    }

    private func playEpisode(_ episode: EpisodePlaybackInfo) {
        guard episode.episodeId != currentEpisodeId else {
            showControls(persistent: false)
            return
        }
        countdownTask?.cancel()
        showEndCreditsPrompt = false
        showNearEndNext = false
        nearEndSuppressed = false
        currentEpisodeId = episode.episodeId
        lightHaptic()
        Task {
            await model.start(contentId: contentId, episodeId: episode.episodeId, trailer: false)
            scheduleHideControls()
        }
    }

    private func resolveEpisodeQueueIfNeeded() async {
        guard !isTrailer, episodes.isEmpty, NetworkMonitor.shared.isOnline else {
            if currentEpisodeId == nil { currentEpisodeId = episodeId }
            return
        }
        guard let detail = try? await ViewerAPI.shared.fetchContentDetail(id: contentId),
              let seasons = detail.seasons, !seasons.isEmpty else { return }

        var list: [EpisodePlaybackInfo] = []
        for season in seasons {
            let sNum = season.seasonNumber ?? 1
            for episode in season.episodes ?? [] {
                let eNum = episode.episodeNumber ?? (list.count + 1)
                list.append(
                    EpisodePlaybackInfo(
                        episodeId: episode.id,
                        title: episode.title ?? "Episode \(eNum)",
                        episodeLabel: "S\(sNum) E\(eNum)",
                        thumbnailUrl: episode.thumbnailUrl,
                        durationSeconds: episode.duration
                    )
                )
            }
        }
        guard !list.isEmpty else { return }
        resolvedEpisodes = list
        if currentEpisodeId == nil {
            currentEpisodeId = episodeId ?? list.first?.episodeId
        }
        ImagePrefetcher.prefetch(
            list.map {
                MediaURL.candidates(posterUrl: $0.thumbnailUrl, backdropUrl: nil, videoUrl: nil, preferBackdrop: true)
            },
            preferPortrait: false
        )
    }

    private func updateScrubMirror() {
        guard let player = model.player else { return }
        let t = player.currentTime().seconds
        if t.isFinite { scrubPosition = max(0, t) }
        let d = player.currentItem?.duration.seconds ?? 0
        if d.isFinite, d > 0 { scrubDuration = d }
    }

    private func updateNearEndPrompt() {
        guard !isTrailer, !isLocked, !showEndCreditsPrompt, nextEpisode != nil else { return }
        guard !nearEndSuppressed else { return }
        guard scrubDuration > 40 else { return }
        let remaining = scrubDuration - scrubPosition
        if remaining <= 25, remaining > 0.5, !showNearEndNext {
            withAnimation(.easeInOut(duration: 0.3)) { showNearEndNext = true }
            startNextCountdown(autoPlay: false)
        }
    }

    private func presentEndCreditsNext() {
        countdownTask?.cancel()
        controlsVisible = false
        showNearEndNext = false
        nextCountdown = 8
        withAnimation(.easeInOut(duration: 0.28)) { showEndCreditsPrompt = true }
        startNextCountdown(autoPlay: true)
    }

    private func startNextCountdown(autoPlay: Bool) {
        countdownTask?.cancel()
        nextCountdown = 8
        countdownTask = Task {
            while nextCountdown > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                await MainActor.run { nextCountdown -= 1 }
            }
            if Task.isCancelled { return }
            if autoPlay {
                await MainActor.run { playNext() }
            }
        }
    }

    private func playNext() {
        guard let next = nextEpisode else {
            close()
            return
        }
        countdownTask?.cancel()
        showEndCreditsPrompt = false
        showNearEndNext = false
        nearEndSuppressed = false
        currentEpisodeId = next.episodeId
        Task {
            await model.start(contentId: contentId, episodeId: next.episodeId, trailer: false)
            scheduleHideControls()
        }
    }

    private func toggleControls() {
        if isLocked {
            showControls(persistent: true)
            return
        }
        if controlsVisible {
            hideTask?.cancel()
            withAnimation(.easeInOut(duration: 0.38)) {
                controlsVisible = false
            }
        } else {
            showControls(persistent: !model.isPlaying)
        }
    }

    private func showControls(persistent: Bool) {
        hideTask?.cancel()
        withAnimation(.easeInOut(duration: 0.32)) {
            controlsVisible = true
        }
        if !persistent { scheduleHideControls() }
    }

    private func scheduleHideControls() {
        hideTask?.cancel()
        guard isLocked || model.isPlaying else { return }
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard isLocked || model.isPlaying else { return }
                withAnimation(.easeInOut(duration: 0.45)) {
                    controlsVisible = false
                }
            }
        }
    }

    private func unlockOrientationOnce() {
        didUnlockOrientation = true
        OrientationLock.unlockPortrait()
    }

    private func close() {
        hideTask?.cancel()
        countdownTask?.cancel()
        restartTask?.cancel()
        model.stop()
        unlockOrientationOnce()
        dismiss()
    }

    private func lightHaptic() {
        haptic.impactOccurred(intensity: 0.55)
        haptic.prepare()
    }

    private func unlockFromPlayer() async {
        model.isLoading = true
        model.errorMessage = nil
        defer { model.isLoading = false }
        let access = await ViewerAPI.shared.resolveTitleAccess(
            contentId: contentId,
            isPayPerViewAccount: true,
            isTrailer: false
        )
        switch access {
        case .playable:
            await model.start(contentId: contentId, episodeId: currentEpisodeId, trailer: isTrailer)
        case .requiresInAppPurchase:
            model.isLoading = false
            showPPVPaywall = true
        case .blocked(let message):
            model.errorMessage = message
            model.needsPurchase = true
        }
    }

    private func retryPlayAfterPurchase() async {
        guard !isRetryingAfterPurchase else { return }
        isRetryingAfterPurchase = true
        defer { isRetryingAfterPurchase = false }
        showPPVPaywall = false
        try? await Task.sleep(nanoseconds: 800_000_000)
        await model.start(contentId: contentId, episodeId: currentEpisodeId, trailer: isTrailer)
        if model.player != nil { scheduleHideControls() }
    }
}

// MARK: - Seek burst

private struct SeekBurst: Equatable {
    let isForward: Bool
    let totalSeconds: Int
    let token: UUID
}

/// Netflix-style double-tap: ring + “10” that slides out and fades; stacks total.
private struct DoubleTapSeekOverlay: View {
    let isForward: Bool
    let totalSeconds: Int

    @State private var ringScale: CGFloat = 0.7
    @State private var ringOpacity: Double = 0
    @State private var numberOffset: CGFloat = 0
    @State private var numberOpacity: Double = 1

    var body: some View {
        HStack {
            if isForward { Spacer(minLength: 0) }

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.85), lineWidth: 2.5)
                    .frame(width: 76, height: 76)
                    .scaleEffect(ringScale)
                    .opacity(ringOpacity)

                Text("\(totalSeconds)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .offset(x: numberOffset)
                    .opacity(numberOpacity)
                    .shadow(radius: 4)
            }
            .padding(.horizontal, max(48, UIScreen.main.bounds.width * 0.12))

            if !isForward { Spacer(minLength: 0) }
        }
        .onAppear {
            ringScale = 0.72
            ringOpacity = 0
            numberOffset = 0
            numberOpacity = 1
            withAnimation(.easeOut(duration: 0.22)) {
                ringScale = 1.05
                ringOpacity = 1
            }
            withAnimation(.easeInOut(duration: 0.55).delay(0.12)) {
                numberOffset = isForward ? 34 : -34
                numberOpacity = 0
                ringOpacity = 0.15
            }
        }
    }
}

// MARK: - Brightness

private struct BrightnessSlider: View {
    @Binding var brightness: Double
    private let trackHeight: CGFloat = 132
    private let trackWidth: CGFloat = 5

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: brightness > 0.55 ? "sun.max.fill" : "sun.min.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
            ZStack(alignment: .bottom) {
                Capsule().fill(.white.opacity(0.22)).frame(width: trackWidth, height: trackHeight)
                Capsule()
                    .fill(Color.white)
                    .frame(width: trackWidth, height: max(trackWidth, trackHeight * CGFloat(min(1, max(0, brightness)))))
                    .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.86), value: brightness)
            }
            .frame(width: 44, height: trackHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let ratio = 1 - (value.location.y / trackHeight)
                        let next = min(1, max(0, Double(ratio)))
                        brightness = brightness * 0.2 + next * 0.8
                    }
            )
        }
    }
}

// MARK: - Video layer (lightweight AVPlayerLayer — avoids AVPlayerViewController thrash)

private struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    /// `true` = crop to fill the screen; `false` = fit with letterboxing (default).
    var fillScreen: Bool = false

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = fillScreen ? .resizeAspectFill : .resizeAspect
        view.backgroundColor = .black
        view.clipsToBounds = true
        PictureInPictureManager.shared.attach(playerLayer: view.playerLayer)
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
        let gravity: AVLayerVideoGravity = fillScreen ? .resizeAspectFill : .resizeAspect
        if uiView.playerLayer.videoGravity != gravity {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.2)
            uiView.playerLayer.videoGravity = gravity
            CATransaction.commit()
        }
        PictureInPictureManager.shared.attach(playerLayer: uiView.playerLayer)
    }

    static func dismantleUIView(_ uiView: PlayerUIView, coordinator: ()) {
        // Keep the layer attached while PiP is running so the mini player stays alive.
        if !PictureInPictureManager.shared.isActive {
            PictureInPictureManager.shared.detach()
        }
    }

    final class PlayerUIView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

// MARK: - Progress + scrub circle

private struct PlayerProgressBar: View {
    let player: AVPlayer
    let accent: Color
    var onScrubbingChanged: (Bool) -> Void = { _ in }

    @State private var current: Double = 0
    @State private var duration: Double = 1
    @State private var isScrubbing = false
    @State private var scrubValue: Double = 0

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let width = max(geo.size.width, 1)
                let value = isScrubbing ? scrubValue : current
                let fraction = duration > 0 ? min(max(value / duration, 0), 1) : 0
                let thumbX = width * CGFloat(fraction)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.28))
                        .frame(height: 4)

                    Capsule()
                        .fill(accent)
                        .frame(width: max(thumbX, 0), height: 4)

                    // Scrub handle (Netflix-like knobb)
                    Circle()
                        .fill(accent)
                        .frame(width: isScrubbing ? 16 : 12, height: isScrubbing ? 16 : 12)
                        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                        .offset(x: max(0, thumbX - (isScrubbing ? 8 : 6)))
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            if !isScrubbing {
                                isScrubbing = true
                                onScrubbingChanged(true)
                            }
                            let ratio = min(max(g.location.x / width, 0), 1)
                            scrubValue = Double(ratio) * duration
                        }
                        .onEnded { _ in
                            let time = CMTime(seconds: scrubValue, preferredTimescale: 600)
                            player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
                            current = scrubValue
                            isScrubbing = false
                            onScrubbingChanged(false)
                        }
                )
            }
            .frame(height: 28)

            HStack {
                Text(format(isScrubbing ? scrubValue : current))
                Spacer()
                // Remaining time like Netflix references
                Text("-\(format(max(0, duration - (isScrubbing ? scrubValue : current))))")
            }
            .font(.caption.monospacedDigit().weight(.medium))
            .foregroundStyle(.white.opacity(0.9))
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
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - View model (crash-hardened)

@MainActor
final class PlayerViewModel: ObservableObject {
    @Published var player: AVPlayer?
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published var isPlaying = false
    @Published var didReachEnd = false
    @Published var needsPurchase = false
    @Published var subtitles = SubtitleEngine()

    private var contentId = ""
    private var startGeneration = 0
    private var progressTimer: AnyCancellable?
    private var endObserver: NSObjectProtocol?
    private var failObserver: NSObjectProtocol?
    private var statusObserver: NSKeyValueObservation?
    private var timeControlObserver: NSKeyValueObservation?
    private var subtitleObserver: Any?
    private var subtitleBag: AnyCancellable?
    private var watchedSeconds: Double = 0
    private var lastSavedPosition: Double = 0
    /// Last playback position already reported to `POST /api/watch` (creator view counts).
    private var lastReportedWatchSeconds: Double = 0
    private var suppressProgressNetwork = false

    init() {
        subtitleBag = subtitles.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    func start(contentId: String, episodeId: String?, trailer: Bool = false, forceRestart: Bool = false) async {
        // Always tear down previous session first — critical for stability.
        tearDownPlayer(flushProgress: true)

        self.contentId = contentId
        startGeneration += 1
        let generation = startGeneration

        isLoading = true
        errorMessage = nil
        needsPurchase = false
        didReachEnd = false
        watchedSeconds = 0
        lastSavedPosition = 0
        lastReportedWatchSeconds = 0
        subtitles.reset()
        defer {
            if generation == startGeneration {
                isLoading = false
            }
        }

        Self.configureAudioSession()

        do {
            let asset: AVURLAsset
            let isOffline: Bool
            var subtitleTracks: [SubtitleTrack]?

            if !trailer, let offline = DownloadManager.shared.offlineAsset(contentId: contentId, episodeId: episodeId) {
                asset = offline
                isOffline = true
                // Best-effort: still pull caption tracks when online so offline downloads can caption.
                if NetworkMonitor.shared.isOnline {
                    subtitleTracks = try? await ViewerAPI.shared.fetchPlaybackBundle(
                        contentId: contentId,
                        episodeId: episodeId,
                        trailer: false
                    ).subtitles
                }
            } else {
                // Prefer a freshly fetched bundle. Cached URL only as a soft hint after re-validate.
                let bundle = try await ViewerAPI.shared.fetchPlaybackBundle(
                    contentId: contentId,
                    episodeId: episodeId,
                    trailer: trailer
                )
                guard generation == startGeneration else { return }
                guard let url = bundle.streamURL else {
                    throw APIError.server("No playable stream was returned for this title.")
                }
                asset = Self.authenticatedAsset(for: url)
                isOffline = false
                subtitleTracks = trailer ? nil : bundle.subtitles
            }

            // Soft metadata load — never crash on failure.
            do {
                let playable = try await asset.load(.isPlayable)
                guard playable else {
                    throw APIError.server("This title can’t be played right now.")
                }
            } catch let error as APIError {
                throw error
            } catch {
                // Proceed; AVPlayer will surface an error if the stream is bad.
            }

            guard generation == startGeneration else { return }

            let resumeAt: Int
            if trailer || isOffline || forceRestart {
                resumeAt = 0
            } else {
                resumeAt = (try? await ViewerAPI.shared.fetchWatchProgress(contentId: contentId).position) ?? 0
            }
            guard generation == startGeneration else { return }

            // Always brand-new item + player — never recycle primed items.
            let item = AVPlayerItem(asset: asset)
            item.preferredForwardBufferDuration = isOffline ? 0 : 8

            let avPlayer = AVPlayer(playerItem: item)
            avPlayer.automaticallyWaitsToMinimizeStalling = true
            avPlayer.isMuted = false
            avPlayer.volume = 1

            observeEnd(of: item, generation: generation)
            observeFail(of: item, generation: generation)
            observeStatus(of: item, generation: generation)
            observePlayback(avPlayer)

            self.player = avPlayer
            suppressProgressNetwork = isOffline
            beginProgressReporting()
            beginSubtitleObservation(avPlayer)
            Task { await subtitles.load(tracks: subtitleTracks) }

            if resumeAt > 5 {
                let time = CMTime(seconds: Double(resumeAt), preferredTimescale: 600)
                await avPlayer.seek(to: time)
            }
            guard generation == startGeneration else {
                avPlayer.pause()
                return
            }

            Self.configureAudioSession()
            avPlayer.play()
            isPlaying = true
        } catch let error as APIError {
            guard generation == startGeneration else { return }
            player = nil
            if case .paymentRequired = error {
                needsPurchase = true
                errorMessage = "A subscription or title unlock is required to watch."
            } else {
                errorMessage = error.localizedDescription
            }
        } catch {
            guard generation == startGeneration else { return }
            player = nil
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

    func play() {
        player?.play()
        isPlaying = true
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

    func seek(to seconds: Double) {
        guard let player else { return }
        let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func stop() {
        startGeneration += 1
        tearDownPlayer(flushProgress: true)
    }

    private func tearDownPlayer(flushProgress: Bool) {
        if flushProgress { self.flushProgress(final: true) }
        progressTimer?.cancel()
        progressTimer = nil
        if let subtitleObserver, let player {
            player.removeTimeObserver(subtitleObserver)
        }
        subtitleObserver = nil
        timeControlObserver?.invalidate()
        timeControlObserver = nil
        statusObserver?.invalidate()
        statusObserver = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        if let failObserver {
            NotificationCenter.default.removeObserver(failObserver)
            self.failObserver = nil
        }
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        isPlaying = false
        subtitles.reset()
    }

    private func beginSubtitleObservation(_ avPlayer: AVPlayer) {
        if let subtitleObserver {
            avPlayer.removeTimeObserver(subtitleObserver)
            self.subtitleObserver = nil
        }
        let interval = CMTime(seconds: 0.2, preferredTimescale: 600)
        subtitleObserver = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            let seconds = time.seconds
            guard seconds.isFinite else { return }
            Task { @MainActor in
                self.subtitles.updateTime(seconds)
            }
        }
    }

    private func observeEnd(of item: AVPlayerItem, generation: Int) {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.startGeneration == generation else { return }
                self.isPlaying = false
                self.didReachEnd = true
                self.flushProgress(final: true)
            }
        }
    }

    private func observeFail(of item: AVPlayerItem, generation: Int) {
        if let failObserver {
            NotificationCenter.default.removeObserver(failObserver)
        }
        failObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor in
                guard let self, self.startGeneration == generation else { return }
                let message = (note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?
                    .localizedDescription ?? "Playback failed."
                self.errorMessage = message
                self.isPlaying = false
            }
        }
    }

    private func observeStatus(of item: AVPlayerItem, generation: Int) {
        statusObserver?.invalidate()
        statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self, self.startGeneration == generation else { return }
                if item.status == .failed {
                    self.errorMessage = item.error?.localizedDescription ?? "Unable to play this title."
                    self.isPlaying = false
                    self.player = nil
                }
            }
        }
    }

    private func observePlayback(_ player: AVPlayer) {
        timeControlObserver?.invalidate()
        timeControlObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor in
                self?.isPlaying = player.timeControlStatus == .playing
            }
        }
    }

    private func beginProgressReporting() {
        progressTimer = Timer.publish(every: 8, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.flushProgress(final: false)
            }
    }

    private func flushProgress(final: Bool) {
        guard let player, !contentId.isEmpty, !suppressProgressNetwork else { return }
        let position = player.currentTime().seconds
        guard position.isFinite, position >= 0 else { return }
        let duration = player.currentItem?.duration.seconds
        let dur = (duration?.isFinite == true) ? duration : nil
        if abs(position - lastSavedPosition) < 3, !final { return }
        lastSavedPosition = position
        watchedSeconds = max(watchedSeconds, position)

        let cid = contentId
        let watched = watchedSeconds
        let previouslyReported = lastReportedWatchSeconds
        // Match web: POST /api/watch every ~30s of playback so creator dashboards count views.
        let delta = max(0, watched - previouslyReported)
        let shouldReportView = delta >= 30 || (final && delta >= 5)
        if shouldReportView {
            lastReportedWatchSeconds = watched
        }

        Task {
            await ViewerAPI.shared.saveWatchProgress(
                contentId: cid,
                positionSeconds: position,
                durationSeconds: dur
            )
            if shouldReportView {
                await ViewerAPI.shared.recordWatchSession(
                    contentId: cid,
                    durationSeconds: delta
                )
            }
        }
    }

    private static func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            // Playback category is required for background audio + Picture in Picture.
            try session.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay])
            try session.setActive(true, options: [])
        } catch {
            // Non-fatal.
        }
    }

    private static func authenticatedAsset(for url: URL) -> AVURLAsset {
        var headers: [String: String] = [
            "User-Agent": DeviceIdentity.userAgent,
            "Accept": "*/*",
        ]
        if let cookies = HTTPCookieStorage.shared.cookies(for: url), !cookies.isEmpty {
            let cookieHeader = HTTPCookie.requestHeaderFields(with: cookies)
            for (key, value) in cookieHeader {
                headers[key] = value
            }
        } else if let all = HTTPCookieStorage.shared.cookies {
            let host = url.host ?? AppConfig.apiBaseURL.host ?? ""
            let matched = all.filter {
                host.hasSuffix($0.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")))
                    || $0.domain == host
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
