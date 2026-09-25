import SwiftUI

struct HeroCarousel: View {
    let items: [ContentItem]
    @Binding var index: Int
    var fullBleed: Bool = false
    var onPlay: (ContentItem) -> Void
    var onOpen: (ContentItem) -> Void

    /// Bumped on user swipe so auto-cycle restarts with a fresh pause.
    @State private var interactionEpoch = 0
    @State private var advancingProgrammatically = false

    private var heroHeight: CGFloat {
        fullBleed
            ? min(UIScreen.main.bounds.height * 0.62, 560)
            : min(UIScreen.main.bounds.width * 1.15, 480)
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = fullBleed ? heroHeight : min(width * 1.15, 480)

            ZStack(alignment: .bottom) {
                TabView(selection: $index) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                        HeroCard(
                            item: item,
                            width: width,
                            height: height,
                            fullBleed: fullBleed,
                            onPlay: { onPlay(item) },
                            onOpen: { onOpen(item) }
                        )
                        .tag(idx)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(width: width, height: height)
                // Prevent off-screen pages from looking like background video motion.
                .clipped()
                .onChange(of: index) { _, _ in
                    if advancingProgrammatically {
                        advancingProgrammatically = false
                        return
                    }
                    // User swiped — cancel the running cycle and wait 5s before resuming.
                    interactionEpoch += 1
                }

                if items.count > 1 {
                    HStack(spacing: 6) {
                        ForEach(items.indices, id: \.self) { i in
                            Capsule()
                                .fill(i == index ? Color.white : Color.white.opacity(0.35))
                                .frame(width: i == index ? 18 : 6, height: 6)
                        }
                    }
                    .padding(.bottom, fullBleed ? 18 : 8)
                }
            }
            .frame(width: width, height: height)
            .clipShape(
                fullBleed
                    ? AnyShape(Rectangle())
                    : AnyShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            )
            .padding(.horizontal, fullBleed ? 0 : 12)
        }
        .frame(height: heroHeight + (fullBleed ? 0 : 24))
        .task(id: "\(items.count)-\(interactionEpoch)") {
            await autoCycle()
        }
    }

    private func autoCycle() async {
        guard items.count > 1 else { return }
        // After load or user swipe: wait 5s before the next automatic flip.
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        guard !Task.isCancelled else { return }

        while !Task.isCancelled {
            guard items.count > 1 else { return }
            await MainActor.run {
                advancingProgrammatically = true
                // Avoid long cross-fades that make adjacent frames feel like video.
                var transaction = Transaction(animation: .easeInOut(duration: 0.35))
                transaction.disablesAnimations = false
                withTransaction(transaction) {
                    index = (index + 1) % items.count
                }
            }
            try? await Task.sleep(nanoseconds: 5_500_000_000)
        }
    }
}

/// Type erasure for clipShape switch
private struct AnyShape: Shape {
    private let pathBuilder: (CGRect) -> Path
    init<S: Shape>(_ shape: S) {
        pathBuilder = { shape.path(in: $0) }
    }
    func path(in rect: CGRect) -> Path { pathBuilder(rect) }
}

struct HeroCard: View {
    let item: ContentItem
    var width: CGFloat
    var height: CGFloat
    var fullBleed: Bool = false
    var onPlay: () -> Void
    var onOpen: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            RemoteImage(urls: item.heroBackdropCandidates)
                .frame(width: width - (fullBleed ? 0 : 24), height: height)
                .clipped()
                .allowsHitTesting(false)

            // Top fade for status/title overlay readability
            LinearGradient(
                colors: [.black.opacity(fullBleed ? 0.55 : 0.2), .clear, .clear],
                startPoint: .top,
                endPoint: .center
            )

            LinearGradient(
                colors: [.clear, .black.opacity(0.35), .black.opacity(0.92)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 10) {
                Text(item.displayType.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(1.2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())

                Text(item.title)
                    .font(.system(size: fullBleed ? 34 : 30, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.65)
                    .fixedSize(horizontal: false, vertical: true)

                Text(
                    [item.displayType, item.year.map(String.init)]
                        .compactMap { $0 }
                        .filter { !$0.isEmpty }
                        .joined(separator: " • ")
                )
                .font(.footnote)
                .foregroundStyle(Theme.muted)
                .lineLimit(1)

                HStack(spacing: 12) {
                    Button(action: onPlay) {
                        Label("Play", systemImage: "play.fill")
                            .font(.headline)
                            .foregroundStyle(Theme.playButtonForeground)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Theme.playButton)
                            .clipShape(Capsule())
                    }

                    Button(action: onOpen) {
                        Image(systemName: "plus")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 46, height: 46)
                            .background(Color.white.opacity(0.18))
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("More info")
                }
            }
            .padding(.horizontal, fullBleed ? 20 : 18)
            .padding(.bottom, fullBleed ? 28 : 18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: width - (fullBleed ? 0 : 24), height: height)
        .clipShape(
            fullBleed
                ? AnyShape(Rectangle())
                : AnyShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        )
    }
}

struct ContentRowView: View {
    let title: String
    let items: [ContentItem]
    var showEmptyPlaceholder: Bool = false
    var onSelect: (ContentItem) -> Void
    var onSeeAll: (() -> Void)? = nil

    @State private var rowGlow = false
    @State private var glowFadeTask: Task<Void, Never>?

    var body: some View {
        let displayItems = showsRankNumbers ? Array(items.prefix(10)) : items
        if !displayItems.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    onSeeAll?()
                } label: {
                    HStack(spacing: 4) {
                        Text(title)
                            .font(.title3.bold())
                            .foregroundStyle(Theme.foreground)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.muted)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 20)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(onSeeAll == nil)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: showsRankNumbers ? 8 : 12) {
                        ForEach(Array(displayItems.enumerated()), id: \.element.id) { idx, item in
                            Button { onSelect(item) } label: {
                                PosterCard(
                                    item: item,
                                    rank: showsRankNumbers ? idx + 1 : nil,
                                    glowActive: rowGlow,
                                    showSeriesEpisodeCue: title.lowercased().contains("series")
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                }
                .simultaneousGesture(rowScrollGlowGesture)
            }
        } else if showEmptyPlaceholder {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.title3.bold())
                    .foregroundStyle(Theme.foreground)
                    .padding(.horizontal, 20)

                HStack(spacing: 12) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                            .frame(width: 118, height: 176)
                            .overlay {
                                VStack(spacing: 8) {
                                    Image(systemName: "film")
                                        .foregroundStyle(Theme.muted.opacity(0.5))
                                    Text("Coming soon")
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(Theme.muted.opacity(0.8))
                                }
                            }
                    }
                }
                .padding(.horizontal, 20)
                .accessibilityLabel("\(title), coming soon")
            }
        }
    }

    private var showsRankNumbers: Bool {
        let t = title.lowercased()
        return t.contains("trending")
            || t.contains("top 10")
            || t.contains("top10")
            || t.hasPrefix("top ")
            || t.contains("popular")
            || t.contains("chart")
            || t.contains("most watched")
    }

    /// Only light the row when the drag is clearly horizontal so vertical page scroll stays free.
    private var rowScrollGlowGesture: some Gesture {
        DragGesture(minimumDistance: 22)
            .onChanged { value in
                let horizontal = abs(value.translation.width)
                let vertical = abs(value.translation.height)
                guard horizontal > vertical * 1.35 else { return }
                glowFadeTask?.cancel()
                if !rowGlow {
                    withAnimation(.easeOut(duration: 0.2)) { rowGlow = true }
                }
            }
            .onEnded { _ in
                glowFadeTask?.cancel()
                glowFadeTask = Task {
                    try? await Task.sleep(nanoseconds: 320_000_000)
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        withAnimation(.easeOut(duration: 0.5)) { rowGlow = false }
                    }
                }
            }
    }
}

struct ContinueWatchingRow: View {
    let items: [ContinueWatchingItem]
    var onSelect: (ContinueWatchingItem) -> Void
    var onSeeAll: (() -> Void)? = nil

    @State private var rowGlow = false
    @State private var glowFadeTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                onSeeAll?()
            } label: {
                HStack(spacing: 4) {
                    Text("Continue Watching")
                        .font(.title3.bold())
                        .foregroundStyle(Theme.foreground)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.muted)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(onSeeAll == nil)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(items) { item in
                        Button { onSelect(item) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                ZStack(alignment: .bottom) {
                                    RemoteImage(urls: item.backdropCandidates)
                                        .frame(width: 168, height: 96)

                                    ProgressView(value: item.progress)
                                        .tint(Theme.accent)
                                        .padding(.horizontal, 4)
                                        .padding(.bottom, 4)
                                }
                                .frame(width: 168, height: 96)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .shadow(
                                    color: Theme.accent.opacity(rowGlow ? 0.26 : 0),
                                    radius: rowGlow ? 10 : 0,
                                    y: 2
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(Theme.accent.opacity(rowGlow ? 0.16 : 0), lineWidth: 1)
                                )

                                Text(item.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.foreground)
                                    .lineLimit(1)
                                    .frame(width: 168, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 22)
                    .onChanged { value in
                        let horizontal = abs(value.translation.width)
                        let vertical = abs(value.translation.height)
                        guard horizontal > vertical * 1.35 else { return }
                        glowFadeTask?.cancel()
                        if !rowGlow {
                            withAnimation(.easeOut(duration: 0.2)) { rowGlow = true }
                        }
                    }
                    .onEnded { _ in
                        glowFadeTask?.cancel()
                        glowFadeTask = Task {
                            try? await Task.sleep(nanoseconds: 320_000_000)
                            guard !Task.isCancelled else { return }
                            await MainActor.run {
                                withAnimation(.easeOut(duration: 0.5)) { rowGlow = false }
                            }
                        }
                    }
            )
        }
    }
}

struct PosterCard: View {
    let item: ContentItem
    var rank: Int? = nil
    var glowActive: Bool = false
    /// Soft “Episode 1” cue on Series catalogue rows (even for single-episode titles).
    var showSeriesEpisodeCue: Bool = false

    var body: some View {
        Group {
            if let rank {
                HStack(alignment: .bottom, spacing: rank >= 10 ? -18 : -22) {
                    RankBadge(rank: rank)
                        .zIndex(0)
                    posterArtwork
                        .zIndex(1)
                }
                .frame(width: rank >= 10 ? 176 : 148, alignment: .trailing)
            } else {
                posterArtwork
            }
        }
        .shadow(
            color: Theme.accent.opacity(glowActive ? 0.28 : 0),
            radius: glowActive ? 10 : 0,
            y: glowActive ? 2 : 0
        )
        .scaleEffect(glowActive ? 1.015 : 1.0)
        .animation(.easeOut(duration: 0.22), value: glowActive)
    }

    private var posterArtwork: some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(urls: item.posterCandidates, preferPortrait: true)
                .frame(width: 118, height: 176)

            LinearGradient(colors: [.clear, .black.opacity(0.88)], startPoint: .center, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title.uppercased())
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(0.3)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.7), radius: 2, y: 1)

                if showSeriesEpisodeCue || item.isSeriesLike {
                    Text("Episode 1")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.accentGold.opacity(0.95))
                        .shadow(color: .black.opacity(0.6), radius: 1, y: 1)
                }
            }
            .padding(8)

            if item.showsNewBadge {
                Text("NEW")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(7)
            }
        }
        .frame(width: 118, height: 176)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.accent.opacity(glowActive ? 0.2 : 0), lineWidth: 1.2)
        )
    }
}

/// Apple TV–style rank mark: bold rounded numeral tucked behind the poster.
private struct RankBadge: View {
    let rank: Int

    var body: some View {
        ZStack {
            Text(rankLabel)
                .font(.system(size: fontSize, weight: .black, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.5))
                .offset(x: 2, y: 2)

            Text(rankLabel)
                .font(.system(size: fontSize, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color.white,
                            Color.white.opacity(0.88),
                            Theme.accent.opacity(0.92),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: Theme.accent.opacity(0.28), radius: 6, y: 0)
        }
        .frame(width: badgeWidth, height: 120, alignment: .bottomTrailing)
        .accessibilityLabel("Number \(rank)")
    }

    private var rankLabel: String { "\(rank)" }

    private var fontSize: CGFloat {
        // Keep both digits of 10 readable (full-size “10” was clipping into dots).
        rank >= 10 ? 62 : 92
    }

    private var badgeWidth: CGFloat {
        rank >= 10 ? 96 : 64
    }
}
