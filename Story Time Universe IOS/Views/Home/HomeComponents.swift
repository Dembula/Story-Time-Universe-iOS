import SwiftUI

struct HeroCarousel: View {
    let items: [ContentItem]
    @Binding var index: Int
    var fullBleed: Bool = false
    var onPlay: (ContentItem) -> Void
    var onOpen: (ContentItem) -> Void

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
        .task(id: items.count) {
            await autoCycle()
        }
    }

    private func autoCycle() async {
        guard items.count > 1 else { return }
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 5_500_000_000)
            guard !Task.isCancelled, items.count > 1 else { return }
            withAnimation(.easeInOut(duration: 0.45)) {
                index = (index + 1) % items.count
            }
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
            RemoteImage(urls: item.backdropCandidates)
                .frame(width: width - (fullBleed ? 0 : 24), height: height)

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
                    [item.displayType, item.category, item.year.map(String.init)]
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

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.title3.bold())
                        .foregroundStyle(Theme.foreground)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 20)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                            Button { onSelect(item) } label: {
                                PosterCard(
                                    item: item,
                                    rank: title.lowercased().contains("trending") ? idx + 1 : nil
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
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
}

struct ContinueWatchingRow: View {
    let items: [ContinueWatchingItem]
    var onSelect: (ContinueWatchingItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 4) {
                Text("Continue Watching")
                    .font(.title3.bold())
                    .foregroundStyle(Theme.foreground)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 20)

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
            }
        }
    }
}

struct PosterCard: View {
    let item: ContentItem
    var rank: Int? = nil

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(urls: item.posterCandidates, preferPortrait: true)
                .frame(width: 118, height: 176)

            LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .center, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if let category = item.category, !category.isEmpty {
                    Text(category)
                        .font(.caption2)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
            }
            .padding(8)

            if let rank {
                Text("\(rank)")
                    .font(.system(size: 52, weight: .black))
                    .foregroundStyle(.white.opacity(0.92))
                    .shadow(radius: 4)
                    .offset(x: -6, y: -36)
            }
        }
        .frame(width: 118, height: 176)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
