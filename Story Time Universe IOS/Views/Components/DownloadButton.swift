import SwiftUI

struct DownloadButton: View {
    enum Style {
        case icon
        case labeled
    }

    let spec: DownloadSpec
    var style: Style = .icon

    @ObservedObject private var downloads = DownloadManager.shared
    @State private var confirmDelete = false

    private var record: DownloadRecord? { downloads.record(forKey: spec.key) }
    private var state: DownloadState? { record?.state }
    private var progress: Double { record?.progress ?? 0 }

    var body: some View {
        Button(action: handleTap) {
            switch style {
            case .icon: iconContent
            case .labeled: labeledContent
            }
        }
        .buttonStyle(.plain)
        .confirmationDialog("Remove download?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Download", role: .destructive) {
                downloads.deleteDownload(key: spec.key)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the offline copy from this device.")
        }
    }

    // MARK: - Icon style (episode rows / compact)

    @ViewBuilder
    private var iconContent: some View {
        switch state {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(Theme.accent)
        case .downloading, .queued:
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.25), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: max(progress, 0.02))
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "stop.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.white)
            }
            .frame(width: 26, height: 26)
        case .failed:
            Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                .font(.title3)
                .foregroundStyle(.orange)
        case .paused, .none:
            Image(systemName: "arrow.down.circle")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    // MARK: - Labeled style (hero action row)

    @ViewBuilder
    private var labeledContent: some View {
        HStack(spacing: 8) {
            switch state {
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                Text("Downloaded")
            case .downloading, .queued:
                ZStack {
                    Circle().stroke(Color.white.opacity(0.25), lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: max(progress, 0.02))
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 16, height: 16)
                Text("\(Int(progress * 100))%")
            case .failed:
                Image(systemName: "arrow.clockwise")
                Text("Retry")
            case .paused, .none:
                Image(systemName: "arrow.down.to.line")
                Text("Download")
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.16))
        .clipShape(Capsule())
    }

    private func handleTap() {
        switch state {
        case .completed:
            confirmDelete = true
        case .downloading, .queued:
            downloads.cancelDownload(key: spec.key)
        case .failed, .paused, .none:
            downloads.startDownload(spec)
        }
    }
}
