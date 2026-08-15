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

    private let haptic = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player = model.player {
                PlayerLayerView(player: player)
                    .ignoresSafeArea()

                playerGestureLayer

                if let burst = seekBurst {
                    DoubleTapSeekOverlay(isForward: burst.isForward, totalSeconds: burst.totalSeconds)
                        .id(burst.token)
                        .allowsHitTesting(false)
                }

                if isAdjustingBrightness && !isLocked {
                    brightnessHUD.allowsHitTesting(false)
                }

                if isLocked {
                    lockedChrome
                        .opacity(controlsVisible ? 1 : 0)
                        .allowsHitTesting(controlsVisible)
                } else if !showEndCreditsPrompt {
                    mainChrome(player: player)
                        .opacity(controlsVisible ? 1 : 0)
                        .allowsHitTesting(controlsVisible)
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
            offerRestartWindow()
            scheduleHideControls()
        }
        .onDisappear {
            hideTask?.cancel()
            countdownTask?.cancel()
            restartTask?.cancel()
            seekBurstTask?.cancel()
            model.stop()
            unlockOrientationOnce()
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
        return episodes.firstIndex { $0.episodeId == currentEpisodeId }
    }

    private var nextEpisode: EpisodePlaybackInfo? {
        guard let idx = currentIndex, idx + 1 < episodes.count else { return nil }
        return episodes[idx + 1]
    }

    private var episodeTitleLine: String {
        if isTrailer { return "Trailer · \(title)" }
        if let current = episodes.first(where: { $0.episodeId == currentEpisodeId }) {
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

    private var topBar: some View {
        HStack(spacing: 12) {
            if showRestart && !restartConsumed && !isTrailer {
                Button {
                    restartConsumed = true
                    showRestart = false
                    restartTask?.cancel()
                    model.seek(to: 0)
                    model.play()
                    lightHaptic()
                } label: {
                    Label("Restart", systemImage: "arrow.counterclockwise")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .move(edge: .leading)))
            }

            Text(episodeTitleLine)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .shadow(color: .black.opacity(0.6), radius: 4)

            Spacer(minLength: 8)

            Button {
                lightHaptic()
                isLocked = true
                showControls(persistent: false)
            } label: {
                Image(systemName: "lock.open.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)

            Button { close() } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
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
                        DragGesture(minimumDistance: 12)
                            .onChanged { value in
                                guard !isLocked else { return }
                                if !isAdjustingBrightness {
                                    guard abs(value.translation.height) > abs(value.translation.width) else { return }
                                    isAdjustingBrightness = true
                                    brightnessBase = brightness
                                    controlsVisible = false
                                    hideTask?.cancel()
                                }
                                let delta = -Double(value.translation.height) / Double(geo.size.height * 0.55)
                                brightness = min(1, max(0, brightnessBase + delta))
                            }
                            .onEnded { _ in isAdjustingBrightness = false }
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
        guard !isTrailer else {
            showRestart = false
            return
        }
        showRestart = true
        restartConsumed = false
        restartTask?.cancel()
        restartTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.3)) {
                    showRestart = false
                    restartConsumed = true
                }
            }
        }
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
        offerRestartWindow()
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
            controlsVisible = false
            hideTask?.cancel()
        } else {
            showControls(persistent: !model.isPlaying)
        }
    }

    private func showControls(persistent: Bool) {
        controlsVisible = true
        hideTask?.cancel()
        if !persistent { scheduleHideControls() }
    }

    private func scheduleHideControls() {
        hideTask?.cancel()
        guard isLocked || model.isPlaying else { return }
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if isLocked || model.isPlaying { controlsVisible = false }
            }
        }
    }

    private func unlockOrientationOnce() {
        guard !didUnlockOrientation else { return }
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
    private let trackHeight: CGFloat = 120
    private let trackWidth: CGFloat = 4

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
            ZStack(alignment: .bottom) {
                Capsule().fill(.white.opacity(0.22)).frame(width: trackWidth, height: trackHeight)
                Capsule()
                    .fill(Color.white)
                    .frame(width: trackWidth, height: max(trackWidth, trackHeight * CGFloat(min(1, max(0, brightness)))))
            }
            .frame(width: 40, height: trackHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let ratio = 1 - (value.location.y / trackHeight)
                        brightness = min(1, max(0, Double(ratio)))
                    }
            )
        }
    }
}

// MARK: - Video layer (lightweight AVPlayerLayer — avoids AVPlayerViewController thrash)

private struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
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

    private var contentId = ""
    private var startGeneration = 0
    private var progressTimer: AnyCancellable?
    private var endObserver: NSObjectProtocol?
    private var failObserver: NSObjectProtocol?
    private var statusObserver: NSKeyValueObservation?
    private var timeControlObserver: NSKeyValueObservation?
    private var watchedSeconds: Double = 0
    private var lastSavedPosition: Double = 0
    /// Last playback position already reported to `POST /api/watch` (creator view counts).
    private var lastReportedWatchSeconds: Double = 0
    private var suppressProgressNetwork = false

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
        defer {
            if generation == startGeneration {
                isLoading = false
            }
        }

        Self.configureAudioSession()

        do {
            let asset: AVURLAsset
            let isOffline: Bool

            if !trailer, let offline = DownloadManager.shared.offlineAsset(contentId: contentId, episodeId: episodeId) {
                asset = offline
                isOffline = true
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
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
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
