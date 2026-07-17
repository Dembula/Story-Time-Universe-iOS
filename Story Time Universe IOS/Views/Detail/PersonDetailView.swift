import SwiftUI

struct PersonDetailView: View {
    let route: PersonRoute

    @State private var preview: PersonPreview?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedContent: ContentItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if isLoading {
                    ProgressView()
                        .tint(Theme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else if let preview {
                    if let blurb = preview.blurb?.trimmingCharacters(in: .whitespacesAndNewlines), !blurb.isEmpty {
                        Text(blurb)
                            .font(.body)
                            .foregroundStyle(Theme.foreground.opacity(0.92))
                            .fixedSize(horizontal: false, vertical: true)
                    } else if let bio = effectiveBio(preview), !bio.isEmpty {
                        Text(bio)
                            .font(.body)
                            .foregroundStyle(Theme.foreground.opacity(0.92))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let bio = effectiveBio(preview),
                       let blurb = preview.blurb?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !blurb.isEmpty,
                       bio != blurb,
                       !bio.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("About")
                                .font(.title3.bold())
                                .foregroundStyle(Theme.foreground)
                            Text(bio)
                                .font(.body)
                                .foregroundStyle(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    statsRow(preview)

                    if let genres = preview.topGenres, !genres.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Known for")
                                .font(.title3.bold())
                                .foregroundStyle(Theme.foreground)
                            FlowChips(items: genres)
                        }
                    }

                    if let credits = preview.credits, !credits.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Credits")
                                .font(.title3.bold())
                                .foregroundStyle(Theme.foreground)
                            LazyVGrid(
                                columns: [
                                    GridItem(.flexible(), spacing: 12),
                                    GridItem(.flexible(), spacing: 12),
                                    GridItem(.flexible(), spacing: 12),
                                ],
                                spacing: 14
                            ) {
                                ForEach(credits) { credit in
                                    Button {
                                        selectedContent = credit.asContentItem
                                    } label: {
                                        VStack(alignment: .leading, spacing: 6) {
                                            RemoteImage(urls: credit.posterCandidates)
                                                .frame(height: 150)
                                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                            Text(credit.title)
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.white)
                                                .lineLimit(2)
                                            Text(credit.role)
                                                .font(.caption2)
                                                .foregroundStyle(Theme.muted)
                                                .lineLimit(1)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                } else if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red.opacity(0.9))
                }
            }
            .padding(20)
            .padding(.bottom, 28)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(preview?.displayName ?? route.fallbackName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedContent) { item in
            ContentDetailView(contentId: item.id, seed: item)
        }
        .task { await load() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            avatar
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(preview?.displayName ?? route.fallbackName)
                        .font(.title2.bold())
                        .foregroundStyle(Theme.foreground)
                    if preview?.verified == true {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(Theme.accent)
                    }
                }

                let roles = preview?.roles?.filter { !$0.isEmpty } ?? []
                if !roles.isEmpty {
                    Text(roles.joined(separator: " · "))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.accentGold)
                } else if let role = route.fallbackRole, !role.isEmpty {
                    Text(role)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.accentGold)
                }

                if let count = preview?.productionCount, count > 0 {
                    Text("\(count) production\(count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var avatar: some View {
        let size: CGFloat = 88
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Theme.accent.opacity(0.75), Theme.profileColor(for: route.id)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)

            if let preview, !preview.imageCandidates.isEmpty {
                RemoteImage(urls: preview.imageCandidates, contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Text(preview?.initials ?? initials(from: route.fallbackName))
                    .font(.title.bold())
                    .foregroundStyle(.white)
            }
        }
    }

    private func statsRow(_ preview: PersonPreview) -> some View {
        HStack(spacing: 12) {
            if let followers = preview.followerCount {
                statChip(title: "Followers", value: "\(followers)")
            }
            if let following = preview.followingCount {
                statChip(title: "Following", value: "\(following)")
            }
            if let count = preview.productionCount {
                statChip(title: "Titles", value: "\(count)")
            }
        }
    }

    private func statChip(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline.bold())
                .foregroundStyle(.white)
            Text(title)
                .font(.caption2)
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func effectiveBio(_ preview: PersonPreview) -> String? {
        let fromPreview = preview.bio?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let fromPreview, !fromPreview.isEmpty { return fromPreview }
        let fallback = route.fallbackBio?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (fallback?.isEmpty == false) ? fallback : nil
    }

    private func initials(from name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let chars = parts.compactMap(\.first)
        return chars.isEmpty ? String(name.prefix(1)).uppercased() : String(chars).uppercased()
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let loaded = try await ViewerAPI.shared.fetchPerson(route: route)
            preview = loaded
            if let credits = loaded.credits {
                ImagePrefetcher.prefetchPosters(credits.map(\.asContentItem))
            }
        } catch {
            // Fall back to the credit’s own bio so the page still feels useful.
            if let bio = route.fallbackBio?.trimmingCharacters(in: .whitespacesAndNewlines), !bio.isEmpty {
                preview = PersonPreview(
                    personId: route.personId ?? route.crewMemberId ?? route.fallbackName,
                    displayName: route.fallbackName,
                    imageUrl: nil,
                    roles: route.fallbackRole.map { [$0] },
                    bio: bio,
                    blurb: nil,
                    productionCount: nil,
                    followerCount: nil,
                    followingCount: nil,
                    verified: false,
                    profileHref: nil,
                    latestProject: nil,
                    topGenres: nil,
                    isCreator: nil,
                    creatorUserId: nil,
                    credits: nil
                )
            } else {
                errorMessage = "Couldn’t load this person’s profile. \(error.localizedDescription)"
            }
        }
    }
}

private struct FlowChips: View {
    let items: [String]

    var body: some View {
        FlexibleChipWrap(items: items)
    }
}

/// Simple wrapping chip row without a third-party layout lib.
private struct FlexibleChipWrap: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { item in
                        Text(item)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.foreground)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    /// Rough wrap into rows of ~3 chips for phone widths.
    private var rows: [[String]] {
        stride(from: 0, to: items.count, by: 3).map { start in
            Array(items[start..<min(start + 3, items.count)])
        }
    }
}
