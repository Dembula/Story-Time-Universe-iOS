import SwiftUI

/// Orange-accent AI search sheet with vibe chips and production API fallbacks.
struct AISearchView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var parental = ParentalControls.shared
    var onSwitchToStandard: () -> Void

    @State private var query = ""
    @State private var result: AISearchResult?
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var selected: ContentItem?

    private let vibeChips = [
        "Feel-good",
        "Late night",
        "Family night",
        "Quick watch",
        "Documentary",
        "Comedy vibes",
    ]

    private var profileAge: Int? { appState.activeProfile?.age }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    searchField
                    vibeChipRow

                    if isSearching {
                        ProgressView("Thinking…")
                            .tint(Theme.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)
                    }

                    if let reasoning = result?.reasoning, !reasoning.isEmpty {
                        Text(reasoning)
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.card)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    if let suggestions = result?.suggestions, !suggestions.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(suggestions, id: \.self) { suggestion in
                                    Button {
                                        query = suggestion
                                        Task { await runAISearch() }
                                    } label: {
                                        Text(suggestion)
                                            .font(.caption.weight(.semibold))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(Theme.accent.opacity(0.18))
                                            .foregroundStyle(Theme.accent)
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    if let results = result?.results, !results.isEmpty {
                        LazyVStack(spacing: 0) {
                            ForEach(filtered(results)) { item in
                                Button {
                                    selected = item.asContentItem
                                } label: {
                                    HStack(spacing: 12) {
                                        RemoteImage(urls: item.posterCandidates, preferPortrait: true)
                                            .frame(width: 56, height: 84)
                                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(item.title)
                                                .font(.body.weight(.semibold))
                                                .foregroundStyle(Theme.foreground)
                                                .lineLimit(2)
                                            Text(
                                                [item.type, item.category]
                                                    .compactMap { $0 }
                                                    .filter { !$0.isEmpty }
                                                    .joined(separator: " · ")
                                            )
                                            .font(.caption)
                                            .foregroundStyle(Theme.muted)
                                        }
                                        Spacer()
                                    }
                                    .padding(.vertical, 10)
                                }
                                .buttonStyle(.plain)
                                Divider().background(Theme.border)
                            }
                        }
                    } else if result != nil, !isSearching {
                        Text("No matches yet — try another vibe.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                            .padding(.top, 8)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    Button(action: onSwitchToStandard) {
                        Text("Switch to Standard Search")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Theme.accent.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .padding(.top, 8)
                }
                .padding(20)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("AI Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Text("BETA")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.accent.opacity(0.2))
                        .foregroundStyle(Theme.accent)
                        .clipShape(Capsule())
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onSwitchToStandard)
                }
            }
            .navigationDestination(item: $selected) { item in
                ContentDetailView(contentId: item.id, seed: item)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Describe a vibe")
                    .font(.headline)
                    .foregroundStyle(Theme.foreground)
                Text("Orange AI picks from the Story Time catalogue.")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    private var searchField: some View {
        HStack {
            TextField("cozy comedy for a rainy evening…", text: $query, axis: .vertical)
                .lineLimit(2...4)
                .textInputAutocapitalization(.sentences)
            Button {
                Task { await runAISearch() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 ? Theme.accent : Theme.muted)
            }
            .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 || isSearching)
        }
        .padding(14)
        .background(Theme.card)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.accent.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var vibeChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(vibeChips, id: \.self) { chip in
                    Button {
                        query = chip
                        Task { await runAISearch() }
                    } label: {
                        Text(chip)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.08))
                            .foregroundStyle(Theme.foreground)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func filtered(_ results: [SearchResult]) -> [SearchResult] {
        let allowed = Set(parental.filter(results.map(\.asContentItem), profileAge: profileAge).map(\.id))
        return results.filter { allowed.contains($0.id) }
    }

    private func runAISearch() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return }
        isSearching = true
        errorMessage = nil
        defer { isSearching = false }
        do {
            result = try await ViewerAPI.shared.aiSearch(query: q)
            if let items = result?.results {
                ImagePrefetcher.prefetchPosters(items.map(\.asContentItem))
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
