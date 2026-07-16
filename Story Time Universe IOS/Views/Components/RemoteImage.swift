import SwiftUI

struct RemoteImage: View {
    let url: URL?
    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable()
                    case .failure:
                        placeholder
                    case .empty:
                        ZStack {
                            placeholder
                            ProgressView().tint(Theme.accent)
                        }
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .background(Theme.card)
    }

    private var placeholder: some View {
        ZStack {
            Theme.card
            Image(systemName: "film")
                .font(.title2)
                .foregroundStyle(Theme.muted)
        }
    }
}
