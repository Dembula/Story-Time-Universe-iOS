import SwiftUI

/// Colourful Netflix-style AI search sheet.
struct AISearchView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var parental = ParentalControls.shared
    var onSwitchToStandard: () -> Void

    @State private var query = ""
    @State private var result: AISearchResult?
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var selected: ContentItem?
    @State private var pulse = false

    private let vibeChips: [(label: String, colors: [Color])] = [
        ("Feel-good", [Color(red: 1.0, green: 0.55, blue: 0.2), Color(red: 1.0, green: 0.75, blue: 0.3)]),
        ("Late night", [Color(red: 0.45, green: 0.25, blue: 0.95), Color(red: 0.9, green: 0.3, blue: 0.7)]),
        ("Family night", [Color(red: 0.2, green: 0.75, blue: 0.55), Color(red: 0.35, green: 0.85, blue: 0.95)]),
        ("Quick watch", [Color(red: 1.0, green: 0.35, blue: 0.4), Color(red: 1.0, green: 0.6, blue: 0.2)]),
        ("Documentary", [Color(red: 0.25, green: 0.55, blue: 1.0), Color(red: 0.4, green: 0.85, blue: 1.0)]),
        ("Comedy vibes", [Color(red: 1.0, green: 0.7, blue: 0.15), Color(red: 1.0, green: 0.4, blue: 0.35)]),
    ]

    private var profileAge: Int? { appState.activeProfile?.age }

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGlow

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        headerCard
                        searchField
                        vibeChipRow

                        if isSearching {
                            HStack(spacing: 10) {
                                ProgressView().tint(Theme.accent)
                                Text("Finding your vibe…")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Theme.foreground)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 12)
                        }

                        if let reasoning = result?.reasoning, !reasoning.isEmpty {
                            reasoningCard(reasoning)
                        }

                        if let suggestions = result?.suggestions, !suggestions.isEmpty {
                            suggestionRow(suggestions)
                        }

                        if let results = result?.results, !results.isEmpty {
                            resultsSection(filtered(results))
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
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    LinearGradient(
                                        colors: [Theme.accent.opacity(0.85), Color(red: 1.0, green: 0.4, blue: 0.35)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .padding(.top, 8)
                    }
                    .padding(20)
                    .padding(.bottom, 24)
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("AI Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Text("BETA")
                        .font(.caption2.weight(.black))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            LinearGradient(
                                colors: [Theme.accent, Theme.accentGold],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundStyle(.black)
                        .clipShape(Capsule())
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onSwitchToStandard)
                        .foregroundStyle(Theme.accent)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationDestination(item: $selected) { item in
                ContentDetailView(contentId: item.id, seed: item)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var backgroundGlow: some View {
        ZStack {
            Theme.background
            Circle()
                .fill(Theme.accent.opacity(pulse ? 0.28 : 0.14))
                .frame(width: 280, height: 280)
                .blur(radius: 70)
                .offset(x: -90, y: -180)
            Circle()
                .fill(Color(red: 1.0, green: 0.35, blue: 0.55).opacity(pulse ? 0.22 : 0.1))
                .frame(width: 260, height: 260)
                .blur(radius: 80)
                .offset(x: 110, y: -40)
            Circle()
                .fill(Theme.accentGold.opacity(0.12))
                .frame(width: 220, height: 220)
                .blur(radius: 60)
                .offset(x: 40, y: 220)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var headerCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Theme.accent, Color(red: 1.0, green: 0.35, blue: 0.5)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 54, height: 54)
                    .shadow(color: Theme.accent.opacity(0.5), radius: 12, y: 4)
                Image(systemName: "sparkles")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("What’s the vibe?")
                    .font(.title3.bold())
                    .foregroundStyle(Theme.foreground)
                Text("Describe a mood — we’ll pick Story Time titles for you.")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Theme.accent.opacity(0.7), Theme.accentGold.opacity(0.35), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.2
                        )
                )
        )
    }

    private var searchField: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("cozy comedy for a rainy evening…", text: $query, axis: .vertical)
                .lineLimit(2...4)
                .textInputAutocapitalization(.sentences)
                .foregroundStyle(Theme.foreground)

            Button {
                Task { await runAISearch() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(
                        LinearGradient(
                            colors: canSearch
                                ? [Theme.accent, Color(red: 1.0, green: 0.4, blue: 0.35)]
                                : [Theme.muted, Theme.muted],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .disabled(!canSearch || isSearching)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Theme.accent.opacity(0.55), lineWidth: 1.5)
                )
        )
        .shadow(color: Theme.accent.opacity(0.15), radius: 16, y: 6)
    }

    private var canSearch: Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
    }

    private var vibeChipRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TRY A VIBE")
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(Theme.muted)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(vibeChips, id: \.label) { chip in
                        Button {
                            query = chip.label
                            Task { await runAISearch() }
                        } label: {
                            Text(chip.label)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(
                                    LinearGradient(colors: chip.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                                )
                                .clipShape(Capsule())
                                .shadow(color: chip.colors.first?.opacity(0.4) ?? .clear, radius: 8, y: 3)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func reasoningCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("AI thinking", systemImage: "sparkles")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.accentGold)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.foreground.opacity(0.9))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Theme.accent.opacity(0.18), Color(red: 1.0, green: 0.35, blue: 0.5).opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Theme.accent.opacity(0.35), lineWidth: 1)
                )
        )
    }

    private func suggestionRow(_ suggestions: [String]) -> some View {
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
                            .background(Theme.accentGold.opacity(0.2))
                            .foregroundStyle(Theme.accentGold)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func resultsSection(_ items: [SearchResult]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Picks for you")
                .font(.headline)
                .foregroundStyle(Theme.foreground)

            LazyVStack(spacing: 0) {
                ForEach(items) { item in
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
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Theme.accent)
                        }
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    Divider().background(Theme.border)
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
