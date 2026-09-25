import SwiftUI

/// Netflix-style animated AI search, branded in Story Time orange / black.
struct AISearchView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var parental = ParentalControls.shared
    var onSwitchToStandard: () -> Void

    @State private var query = ""
    @State private var turns: [AIChatTurn] = []
    @State private var isSearching = false
    @State private var selected: ContentItem?
    @State private var thinkingPulse = false
    @State private var expandedTurns: Set<UUID> = []
    @State private var feedbackByTurn: [UUID: Bool] = [:]
    @FocusState private var fieldFocused: Bool

    private let starterPrompts = [
        "I'm in the mood for something cozy",
        "Family night picks",
        "Something intense for late night",
        "Feel-good comedy",
        "A quick watch",
        "Documentary that feels real",
    ]

    private var profileAge: Int? { appState.activeProfile?.age }

    var body: some View {
        NavigationStack {
            ZStack {
                background
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    header
                    chatPane
                    composer
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(item: $selected) { item in
                ContentDetailView(contentId: item.id, seed: item)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Chrome

    private var background: some View {
        LinearGradient(
            colors: [
                Color(red: 0.14, green: 0.06, blue: 0.02),
                Color.black,
                Color.black,
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var header: some View {
        ZStack {
            VStack(spacing: 6) {
                Text("BETA")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                Text("Search")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
            }

            HStack {
                Spacer()
                Button(action: onSwitchToStandard) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var chatPane: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if turns.isEmpty {
                        emptyState
                    }

                    ForEach(turns) { turn in
                        userBubble(turn.prompt)
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .opacity
                            ))

                        assistantBlock(turn)
                            .id(turn.id)
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }

                    if isSearching {
                        thinkingRow
                            .id("thinking")
                    }

                    Color.clear.frame(height: 8).id("chatBottom")
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .animation(.easeOut(duration: 0.35), value: turns.count)
            }
            .onChange(of: turns.count) { _, _ in scrollToBottom(proxy) }
            .onChange(of: isSearching) { _, _ in scrollToBottom(proxy) }
            .onChange(of: expandedTurns) { _, _ in scrollToBottom(proxy) }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Ask for a vibe", systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Describe a mood or genre. If Story Time doesn’t carry it yet, I’ll say so and point you to what’s closest.")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            FlowStarterChips(prompts: starterPrompts) { prompt in
                Task { await send(prompt) }
            }
        }
        .padding(.top, 12)
    }

    private var thinkingRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Theme.accent.opacity(thinkingPulse ? 1 : 0.35))
                        .frame(width: 7, height: 7)
                        .scaleEffect(thinkingPulse ? 1.15 : 0.85)
                        .animation(
                            .easeInOut(duration: 0.55)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.14),
                            value: thinkingPulse
                        )
                }
                Image(systemName: "sparkle")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.accent)
                    .rotationEffect(.degrees(thinkingPulse ? 18 : -8))
                    .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: thinkingPulse)
            }
            Spacer()
        }
        .padding(.vertical, 6)
        .onAppear { thinkingPulse = true }
        .onDisappear { thinkingPulse = false }
    }

    private func userBubble(_ text: String) -> some View {
        HStack {
            Spacer(minLength: 48)
            Text(text)
                .font(.body)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(Color.white.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func assistantBlock(_ turn: AIChatTurn) -> some View {
        let sections = visibleSections(for: turn)
        let hasContent = turn.report != nil || !sections.isEmpty || turn.error != nil

        return VStack(alignment: .leading, spacing: 16) {
            if let error = turn.error {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.red.opacity(0.9))
            } else if let report = turn.report {
                Text(report)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            ForEach(sections) { section in
                resultRowSection(section)
            }

            if turn.unmetIntent, filtered(turn.results).isEmpty {
                Text("Try one of the suggestions below — those lanes are live on Story Time.")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }

            if canShowMore(turn) {
                Button {
                    withAnimation(.easeOut(duration: 0.28)) {
                        expandedTurns.insert(turn.id)
                    }
                } label: {
                    Text("Show More")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            if hasContent, turn.error == nil, !sections.isEmpty || turn.unmetIntent {
                feedbackRow(for: turn)
            }

            if !turn.suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(turn.suggestions, id: \.self) { suggestion in
                            Button {
                                Task { await send(suggestion) }
                            } label: {
                                Text(suggestion)
                                    .font(.caption.weight(.semibold))
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
    }

    private func feedbackRow(for turn: AIChatTurn) -> some View {
        HStack(spacing: 14) {
            Text("Were these results helpful?")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    feedbackByTurn[turn.id] = true
                }
            } label: {
                Image(systemName: feedbackByTurn[turn.id] == true ? "hand.thumbsup.fill" : "hand.thumbsup")
                    .font(.body)
                    .foregroundStyle(feedbackByTurn[turn.id] == true ? Theme.accent : .white.opacity(0.85))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Helpful")

            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    feedbackByTurn[turn.id] = false
                }
            } label: {
                Image(systemName: feedbackByTurn[turn.id] == false ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                    .font(.body)
                    .foregroundStyle(feedbackByTurn[turn.id] == false ? Theme.accent : .white.opacity(0.85))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Not helpful")
            Spacer()
        }
        .padding(.top, 2)
    }

    private func resultRowSection(_ section: AISearchSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(section.title)
                .font(.title3.bold())
                .foregroundStyle(.white)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(filtered(section.results)) { item in
                        Button {
                            selected = item.asContentItem
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                RemoteImage(urls: item.posterCandidates, preferPortrait: true)
                                    .frame(width: 108, height: 162)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(Theme.accent.opacity(0.15), lineWidth: 1)
                                    )
                                Text(item.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(2)
                                    .frame(width: 108, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                TextField(
                    turns.isEmpty ? "Ask for a mood or genre…" : "Add to your search or start over",
                    text: $query,
                    axis: .vertical
                )
                .lineLimit(1...3)
                .textInputAutocapitalization(.sentences)
                .focused($fieldFocused)
                .onSubmit { Task { await send(query) } }

                Button {
                    Task { await send(query) }
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "magnifyingglass")
                            .font(.title3.weight(.semibold))
                        Image(systemName: "sparkle")
                            .font(.system(size: 9, weight: .bold))
                            .offset(x: 6, y: -5)
                    }
                    .foregroundStyle(canSend ? Theme.accent : Theme.muted)
                }
                .disabled(!canSend || isSearching)
                .accessibilityLabel("Search with AI")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(Color.white.opacity(0.06))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Theme.accent.opacity(fieldFocused || canSend ? 0.95 : 0.45),
                                Theme.accentGold.opacity(fieldFocused || canSend ? 0.85 : 0.3),
                                Theme.accent.opacity(fieldFocused || canSend ? 0.7 : 0.25),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 1.4
                    )
                    .shadow(color: Theme.accent.opacity(fieldFocused ? 0.45 : 0.18), radius: fieldFocused ? 10 : 4)
            )
            .padding(.horizontal, 16)

            Text("This feature is still in Beta and may make mistakes.")
                .font(.caption2)
                .foregroundStyle(Theme.muted.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.bottom, 8)
        }
        .padding(.top, 8)
        .background(
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.85), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }

    private var canSend: Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
    }

    private func filtered(_ results: [SearchResult]) -> [SearchResult] {
        let allowed = Set(parental.filter(results.map(\.asContentItem), profileAge: profileAge).map(\.id))
        return results.filter { allowed.contains($0.id) }
    }

    private func filteredSections(_ turn: AIChatTurn) -> [AISearchSection] {
        turn.sections.compactMap { section in
            let items = filtered(section.results)
            guard !items.isEmpty else { return nil }
            return AISearchSection(title: section.title, results: items)
        }
    }

    private func visibleSections(for turn: AIChatTurn) -> [AISearchSection] {
        let all = filteredSections(turn)
        if expandedTurns.contains(turn.id) || all.count <= 2 {
            return all
        }
        return Array(all.prefix(2))
    }

    private func canShowMore(_ turn: AIChatTurn) -> Bool {
        !expandedTurns.contains(turn.id) && filteredSections(turn).count > 2
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.32)) {
            proxy.scrollTo(isSearching ? "thinking" : "chatBottom", anchor: .bottom)
        }
    }

    private func send(_ raw: String) async {
        let prompt = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard prompt.count >= 2, !isSearching else { return }

        query = ""
        fieldFocused = false
        isSearching = true

        let pending = AIChatTurn(
            prompt: prompt,
            report: nil,
            results: [],
            sections: [],
            suggestions: [],
            unmetIntent: false,
            error: nil
        )
        withAnimation(.easeOut(duration: 0.28)) {
            turns.append(pending)
        }
        let turnId = pending.id

        do {
            let response = try await ViewerAPI.shared.aiSearch(query: prompt)
            let report = (response.reasoning?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                ? (response.reasoning ?? "")
                : ViewerAPI.buildAIReport(
                    prompt: prompt,
                    results: response.results,
                    searchLenses: [],
                    usedRemoteAI: !response.usedFallback
                )

            if let index = turns.firstIndex(where: { $0.id == turnId }) {
                withAnimation(.easeOut(duration: 0.35)) {
                    turns[index].report = report
                    turns[index].results = response.results
                    turns[index].sections = response.sections
                    turns[index].suggestions = response.suggestions
                    turns[index].unmetIntent = response.unmetIntent
                }
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
}

private struct AIChatTurn: Identifiable {
    let id = UUID()
    let prompt: String
    var report: String?
    var results: [SearchResult]
    var sections: [AISearchSection]
    var suggestions: [String]
    var unmetIntent: Bool
    var error: String?
}

private struct FlowStarterChips: View {
    let prompts: [String]
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(prompts.chunked(into: 2), id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { prompt in
                        Button {
                            onSelect(prompt)
                        } label: {
                            Text(prompt)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.white.opacity(0.08))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
