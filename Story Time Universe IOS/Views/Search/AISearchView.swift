import SwiftUI

/// Chat-style AI search: prompt clears on send, AI replies with a written report + picks.
struct AISearchView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var parental = ParentalControls.shared
    var onSwitchToStandard: () -> Void

    @State private var query = ""
    @State private var turns: [AIChatTurn] = []
    @State private var isSearching = false
    @State private var selected: ContentItem?
    @FocusState private var fieldFocused: Bool

    private let starterPrompts = [
        "Feel-good comedy for a rainy night",
        "Something intense for late night",
        "Family night picks",
        "A quick watch under an hour",
        "Documentary that feels real",
        "Cozy and comforting",
    ]

    private var profileAge: Int? { appState.activeProfile?.age }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                chatPane
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

    private var chatPane: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if turns.isEmpty {
                        emptyState
                    }

                    ForEach(turns) { turn in
                        userBubble(turn.prompt)
                        assistantBlock(turn)
                            .id(turn.id)
                    }

                    if isSearching {
                        thinkingRow
                            .id("thinking")
                    }

                    Color.clear.frame(height: 4).id("chatBottom")
                }
                .padding(16)
            }
            .onChange(of: turns.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: isSearching) { _, _ in
                scrollToBottom(proxy)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Ask like you’d ask a friend", systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(Theme.foreground)
            Text("Describe a mood or situation — I’ll interpret it, explain what I’m looking for, and suggest titles from Story Time.")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var thinkingRow: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(Theme.accent)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                Text("Thinking…")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.foreground)
                Text("Interpreting your vibe and scanning the catalogue.")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                ProgressView()
                    .tint(Theme.accent)
                    .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func userBubble(_ text: String) -> some View {
        HStack {
            Spacer(minLength: 40)
            Text(text)
                .font(.body)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.accent.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func assistantBlock(_ turn: AIChatTurn) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.accent)
                Text("AI")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.accent)
                Spacer()
            }

            if let error = turn.error {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.red)
            } else if let report = turn.report {
                Text(report)
                    .font(.subheadline)
                    .foregroundStyle(Theme.foreground.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !turn.moodTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(turn.moodTags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Theme.muted)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.white.opacity(0.06))
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            let picks = filtered(turn.results)
            if !picks.isEmpty {
                Text("Recommended for you")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.foreground)
                    .padding(.top, 4)

                ForEach(picks) { item in
                    Button {
                        selected = item.asContentItem
                    } label: {
                        resultRow(item)
                    }
                    .buttonStyle(.plain)
                    Divider().background(Theme.border)
                }
            }

            if !turn.suggestions.isEmpty {
                Text("Ask next")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 6)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(turn.suggestions, id: \.self) { suggestion in
                            Button {
                                Task { await send(suggestion) }
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
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if turns.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(starterPrompts, id: \.self) { prompt in
                            Button {
                                Task { await send(prompt) }
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
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Describe a vibe…", text: $query, axis: .vertical)
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
                        Task { await send(query) }
                    }

                Button {
                    Task { await send(query) }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.bold))
                        .foregroundStyle(canSend ? .black : Theme.muted)
                        .frame(width: 44, height: 44)
                        .background(canSend ? Theme.accent : Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .disabled(!canSend || isSearching)
                .accessibilityLabel("Send")
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

    private var canSend: Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
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
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func filtered(_ results: [SearchResult]) -> [SearchResult] {
        let allowed = Set(parental.filter(results.map(\.asContentItem), profileAge: profileAge).map(\.id))
        return results.filter { allowed.contains($0.id) }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.28)) {
            proxy.scrollTo(isSearching ? "thinking" : "chatBottom", anchor: .bottom)
        }
    }

    private func send(_ raw: String) async {
        let prompt = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard prompt.count >= 2, !isSearching else { return }

        // Chat behaviour: clear the composer immediately.
        query = ""
        fieldFocused = false
        isSearching = true

        let pending = AIChatTurn(
            prompt: prompt,
            report: nil,
            moodTags: [],
            results: [],
            suggestions: [],
            error: nil
        )
        turns.append(pending)
        let turnId = pending.id

        do {
            let response = try await ViewerAPI.shared.aiSearch(query: prompt)
            let report = response.reasoning?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? (response.reasoning ?? "")
                : ViewerAPI.buildAIReport(
                    prompt: prompt,
                    results: response.results,
                    searchLenses: [],
                    usedRemoteAI: !response.usedFallback
                )

            if let index = turns.firstIndex(where: { $0.id == turnId }) {
                turns[index].report = report
                turns[index].moodTags = Self.moodChips(from: prompt)
                turns[index].results = response.results
                turns[index].suggestions = response.suggestions
            }
            ImagePrefetcher.prefetchPosters(response.results.map(\.asContentItem))
        } catch {
            if let index = turns.firstIndex(where: { $0.id == turnId }) {
                turns[index].error = error.localizedDescription
                turns[index].report = "I hit a snag while thinking that through. Try again in a moment."
            }
        }

        isSearching = false
    }

    private static func moodChips(from prompt: String) -> [String] {
        let q = prompt.lowercased()
        var tags: [String] = []
        func add(_ t: String) { if !tags.contains(t) { tags.append(t) } }
        if q.contains("cozy") || q.contains("rain") || q.contains("comfort") { add("Cozy") }
        if q.contains("feel") || q.contains("wholesome") { add("Feel-good") }
        if q.contains("late") || q.contains("dark") || q.contains("intense") { add("Late night") }
        if q.contains("funny") || q.contains("comedy") || q.contains("laugh") { add("Comedy") }
        if q.contains("family") || q.contains("kids") { add("Family") }
        if q.contains("thriller") || q.contains("mystery") { add("Thriller") }
        if q.contains("horror") || q.contains("scary") { add("Horror") }
        if q.contains("doc") { add("Documentary") }
        if q.contains("quick") || q.contains("short") { add("Quick watch") }
        if q.contains("romance") || q.contains("date") { add("Romance") }
        return Array(tags.prefix(5))
    }
}

private struct AIChatTurn: Identifiable {
    let id = UUID()
    let prompt: String
    var report: String?
    var moodTags: [String]
    var results: [SearchResult]
    var suggestions: [String]
    var error: String?
}
