import Foundation

/// Warms poster/backdrop caches as soon as catalogue rows arrive.
enum ImagePrefetcher {
    private static let maxConcurrent = 6

    static func prefetchPosters(_ items: [ContentItem]) {
        prefetch(items.map(\.posterCandidates))
    }

    static func prefetchBackdrops(_ items: [ContentItem]) {
        prefetch(items.map(\.backdropCandidates))
    }

    static func prefetchContinueWatching(_ items: [ContinueWatchingItem]) {
        prefetch(items.map(\.backdropCandidates))
    }

    static func prefetchHome(
        featured: [ContentItem],
        continueWatching: [ContinueWatchingItem],
        trending: [ContentItem],
        catalogRows: [HomeCatalogRow]
    ) {
        prefetchBackdrops(featured)
        prefetchContinueWatching(continueWatching)
        prefetchPosters(trending)
        for row in catalogRows where !row.items.isEmpty {
            prefetchPosters(row.items)
        }
    }

    static func prefetch(_ candidateLists: [[URL]]) {
        let lists = candidateLists.filter { !$0.isEmpty }
        guard !lists.isEmpty else { return }

        Task(priority: .utility) {
            await withTaskGroup(of: Void.self) { group in
                var next = 0
                let initial = min(maxConcurrent, lists.count)

                while next < initial {
                    let candidates = lists[next]
                    next += 1
                    group.addTask {
                        await ImageLoader.shared.prefetch(urls: candidates)
                    }
                }

                while await group.next() != nil {
                    if next < lists.count {
                        let candidates = lists[next]
                        next += 1
                        group.addTask {
                            await ImageLoader.shared.prefetch(urls: candidates)
                        }
                    }
                }
            }
        }
    }
}
