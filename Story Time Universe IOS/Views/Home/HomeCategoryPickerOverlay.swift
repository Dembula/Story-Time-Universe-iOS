import SwiftUI

/// Netflix-style full-screen category / genre picker.
struct HomeCategoryPickerOverlay: View {
    let filter: HomeBrowseFilter
    let discoveredGenres: [String]
    var onSelect: (HomeBrowseFilter) -> Void
    var onClose: () -> Void

    private var genres: [String] {
        var seen = Set<String>()
        var list: [String] = []
        for g in CatalogueTypes.seedGenres + discoveredGenres {
            let key = g.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, seen.insert(key.lowercased()).inserted else { continue }
            list.append(key)
        }
        return list.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.72)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 18) {
                        ForEach(CatalogueTypes.browseTypeOptions, id: \.id) { option in
                            categoryButton(
                                title: option.id == "ALL" ? "Home" : option.title,
                                selected: isTypeSelected(option.id)
                            ) {
                                if option.id == "ALL" {
                                    onSelect(.all)
                                } else {
                                    onSelect(.contentType(
                                        id: option.id,
                                        title: option.title,
                                        typeValues: option.typeValues
                                    ))
                                }
                            }
                        }

                        Text("GENRES")
                            .font(.caption.weight(.bold))
                            .tracking(1.4)
                            .foregroundStyle(Theme.muted)
                            .padding(.top, 18)

                        ForEach(genres, id: \.self) { genre in
                            categoryButton(
                                title: genre,
                                selected: {
                                    if case .genre(let g) = filter { return g.caseInsensitiveCompare(genre) == .orderedSame }
                                    return false
                                }()
                            ) {
                                onSelect(.genre(genre))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 48)
                    .padding(.bottom, 100)
                }

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.white.opacity(0.18))
                        .clipShape(Circle())
                }
                .padding(.bottom, 28)
            }
        }
    }

    private func isTypeSelected(_ id: String) -> Bool {
        switch filter {
        case .all: return id == "ALL"
        case .contentType(let selectedId, _, _): return selectedId == id
        case .genre: return false
        }
    }

    private func categoryButton(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: selected ? 28 : 24, weight: selected ? .bold : .semibold))
                .foregroundStyle(selected ? Color.white : Color.white.opacity(0.45))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}
