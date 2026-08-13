import SwiftUI

/// Professional AI search sheet — results above, composer pinned to the bottom.
struct AISearchView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var parental = ParentalControls.shared
    var onSwitchToStandard: () -> Void

    @State private var query = ""
    @State private var result: AISearchResult?
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var selected: ContentItem?
    @FocusState private var fieldFocused: Bool

    private let starterPrompts = [
        "Feel-good comedy",
        "Late-night thriller",
        "Family night",
        "Quick watch",
        "Documentary",
        "Something cozy",
    ]

    private var profileAge: Int? { appState.activeProfile?.age }

    private var visibleResults: [SearchResult] {
        guard let results = result?.results else { return [] }
        return filtered(results)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                resultsPane
                Divider().background(Theme.border)
                composer
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("AI Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onSwitchToStandard)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 10) {
                        Text("BETA")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.1))
                            .foregroundStyle(Theme.muted)
                            .clipShape(Capsule())
                        Button("Standard") {
                            onSwitchToStandard()
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.accent)
                    }
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationDestination(item: $selected) { item in
                ContentDetailView(contentId: item.id, seed: item)
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var resultsPane: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    intro

                    if isSearching {
                        HStack(spacing: 10) {
                            ProgressView().tint(Theme.accent)
                            Text("Finding matches…")
                                .font(.subheadline)
                                .foregroundStyle(Theme.muted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
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
                        suggestionChips(suggestions)
                    }

                    if !visibleResults.isEmpty {
                        Text("Suggestions")
                            .font(.headline)
                            .foregroundStyle(Theme.foreground)

                        LazyVStack(spacing: 0) {
                            ForEach(visibleResults) { item in
                                Button {
                                    selected = item.asContentItem
                                } label: {
                                    resultRow(item)
                                }
                                .buttonStyle(.plain)
                                Divider().background(Theme.border)
                            }
                        }
                    } else if result != nil, !isSearching {
                        ContentUnavailableView(
                            "No matches",
                            systemImage: "sparkles",
                            description: Text("Try a simpler prompt — a mood, genre, or title.")
                        )
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    Color.clear.frame(height: 8).id("bottom")
                }
                .padding(20)
            }
            .onChange(of: visibleResults.map(\.id)) { _, _ in
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Describe what you feel like watching", systemImage: "sparkles")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.foreground)
            Text("Ask for a mood, genre, or vibe — we’ll suggest titles from the Story Time catalogue.")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(starterPrompts, id: \.self) { prompt in
                        Button {
                            query = prompt
                            Task { await runAISearch() }
                        } label: {
                            Text(prompt)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Theme.foreground)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.08))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField("e.g. cozy comedy for a rainy evening", text: $query, axis: .vertical)
                    .lineLimit(1...4)
                    .textInputAutocapitalization(.sentences)
                    .focused($fieldFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Theme.border, lineWidth: 1)
                    )
                    .onSubmit {
                        Task { await runAISearch() }
                    }

                Button {
                    Task { await runAISearch() }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.bold))
                        .foregroundStyle(canSearch ? .black : Theme.muted)
                        .frame(width: 44, height: 44)
                        .background(canSearch ? Theme.accent : Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .disabled(!canSearch || isSearching)
                .accessibilityLabel("Search")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var canSearch: Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
    }

    private func suggestionChips(_ suggestions: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Try also")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.muted)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button {
                            query = suggestion
                            Task { await runAISearch() }
                        } label: {
                            Text(suggestion)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Theme.accent)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Theme.accent.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func resultRow(_ item: SearchResult) -> some View {
        HStack(spacing: 12) {
            RemoteImage(urls: item.posterCandidates, preferPortrait: true)
                .frame(width: 52, height: 78)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(
                    [item.type, item.category]
                        .compactMap { $0 }
                        .filter { !$0.isEmpty }
                        .joined(separator: " · ")
                )
                .font(.caption)
                .foregroundStyle(Theme.muted)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.muted)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func filtered(_ results: [SearchResult]) -> [SearchResult] {
        let allowed = Set(parental.filter(results.map(\.asContentItem), profileAge: profileAge).map(\.id))
        return results.filter { allowed.contains($0.id) }
    }

    private func runAISearch() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return }
        fieldFocused = false
        isSearching = true
        errorMessage = nil
        defer { isSearching = false }
        do {
            let response = try await ViewerAPI.shared.aiSearch(query: q)
            result = response
            ImagePrefetcher.prefetchPosters(response.results.map(\.asContentItem))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
