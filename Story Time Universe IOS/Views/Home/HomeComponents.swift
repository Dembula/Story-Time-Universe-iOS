import SwiftUI

struct HeroCarousel: View {
    let items: [ContentItem]
    @Binding var index: Int
    var onPlay: (ContentItem) -> Void
    var onOpen: (ContentItem) -> Void

    var body: some View {
        VStack(spacing: 14) {
            TabView(selection: $index) {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                    HeroCard(item: item, onPlay: { onPlay(item) }, onOpen: { onOpen(item) })
                        .tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 420)

            HStack(spacing: 6) {
                ForEach(items.indices, id: \.self) { i in
                    Capsule()
                        .fill(i == index ? Theme.accent : Color.white.opacity(0.25))
                        .frame(width: i == index ? 18 : 6, height: 6)
                }
            }
        }
    }
}

struct HeroCard: View {
    let item: ContentItem
    var onPlay: () -> Void
    var onOpen: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            RemoteImage(url: item.backdropURL ?? item.posterURL)
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 420)
                .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.55), .black],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 12) {
                if item.featured == true {
                    Text("Featured")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }

                Text(item.title.uppercased())
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Text([item.displayType, item.category].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " • "))
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)

                HStack(spacing: 12) {
                    Button(action: onPlay) {
                        Label("Play", systemImage: "play.fill")
                            .font(.headline)
                            .foregroundStyle(Theme.playButtonForeground)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Theme.playButton)
                            .clipShape(Capsule())
                    }

                    Button(action: onOpen) {
                        Image(systemName: "plus")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .background(Color.white.opacity(0.15))
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("More info")
                }
            }
            .padding(20)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 16)
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
                                PosterCard(item: item, rank: title.lowercased().contains("top") || title.lowercased().contains("trending") ? idx + 1 : nil)
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
            HStack {
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
                                    RemoteImage(url: item.posterURL)
                                        .scaledToFill()
                                        .frame(width: 160, height: 96)
                                        .clipped()

                                    ProgressView(value: item.progress)
                                        .tint(Theme.accent)
                                        .padding(.horizontal, 4)
                                        .padding(.bottom, 4)
                                }
                                .frame(width: 160, height: 96)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                                Text(item.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.foreground)
                                    .lineLimit(1)
                                    .frame(width: 160, alignment: .leading)
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
            RemoteImage(url: item.posterURL)
                .scaledToFill()
                .frame(width: 118, height: 176)
                .clipped()

            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if let category = item.category {
                    Text(category)
                        .font(.caption2)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
            }
            .padding(8)

            if let rank {
                Text("\(rank)")
                    .font(.system(size: 54, weight: .black))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(radius: 4)
                    .offset(x: -8, y: -40)
            }
        }
        .frame(width: 118, height: 176)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
