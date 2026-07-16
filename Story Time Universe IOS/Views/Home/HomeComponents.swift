import SwiftUI

struct HeroCarousel: View {
    let items: [ContentItem]
    @Binding var index: Int
    var onPlay: (ContentItem) -> Void
    var onOpen: (ContentItem) -> Void

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = min(width * 1.15, 480)

            VStack(spacing: 12) {
                TabView(selection: $index) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                        HeroCard(
                            item: item,
                            width: width,
                            height: height,
                            onPlay: { onPlay(item) },
                            onOpen: { onOpen(item) }
                        )
                        .tag(idx)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.horizontal, 12)

                HStack(spacing: 6) {
                    ForEach(items.indices, id: \.self) { i in
                        Capsule()
                            .fill(i == index ? Theme.accent : Color.white.opacity(0.28))
                            .frame(width: i == index ? 18 : 6, height: 6)
                    }
                }
            }
            .frame(width: width, height: height + 24)
        }
        .frame(height: min(UIScreen.main.bounds.width * 1.15, 480) + 24)
        .task(id: items.count) {
            await autoCycle()
        }
    }

    private func autoCycle() async {
        guard items.count > 1 else { return }
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled, items.count > 1 else { return }
            withAnimation(.easeInOut(duration: 0.45)) {
                index = (index + 1) % items.count
            }
        }
    }
}

struct HeroCard: View {
    let item: ContentItem
    var width: CGFloat
    var height: CGFloat
    var onPlay: () -> Void
    var onOpen: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            RemoteImage(urls: item.backdropCandidates)
                .frame(width: width - 24, height: height)

            LinearGradient(
                colors: [.clear, .black.opacity(0.35), .black.opacity(0.92)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 10) {
                Text("Featured")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())

                Text(item.title)
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.65)
                    .fixedSize(horizontal: false, vertical: true)

                Text(
                    [item.displayType, item.category]
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
                            .background(Color.white.opacity(0.16))
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("More info")
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: width - 24, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct ContentRowView: View {
    let title: String
    let items: [ContentItem]
    var onSelect: (ContentItem) -> Void

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.title3.bold())
                    .foregroundStyle(Theme.foreground)
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
                    .font(.caption.weight(.semibold))
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
            RemoteImage(urls: item.posterCandidates)
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
