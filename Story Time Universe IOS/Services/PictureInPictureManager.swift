import AVFoundation
import AVKit
import UIKit

/// Keeps playback alive in the system mini player when the user leaves the app.
@MainActor
final class PictureInPictureManager: NSObject, AVPictureInPictureControllerDelegate {
    static let shared = PictureInPictureManager()

    private(set) var isActive = false
    private var controller: AVPictureInPictureController?
    private weak var playerLayer: AVPlayerLayer?
    /// Called when PiP ends and the full-screen player UI is already gone.
    var onStopWhileDetached: (() -> Void)?

    private override init() {
        super.init()
    }

    func attach(playerLayer: AVPlayerLayer) {
        self.playerLayer = playerLayer
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            controller = nil
            return
        }

        if let existing = controller, existing.playerLayer === playerLayer {
            configure(existing)
            return
        }

        guard let pip = AVPictureInPictureController(playerLayer: playerLayer) else {
            controller = nil
            return
        }
        pip.delegate = self
        configure(pip)
        controller = pip
    }

    func detach() {
        if isActive {
            controller?.stopPictureInPicture()
        }
        controller = nil
        playerLayer = nil
        isActive = false
        onStopWhileDetached = nil
    }

    func startIfPossible() {
        guard let controller, controller.isPictureInPicturePossible, !controller.isPictureInPictureActive else { return }
        controller.startPictureInPicture()
    }

    var isPossible: Bool {
        controller?.isPictureInPicturePossible == true
    }

    private func configure(_ pip: AVPictureInPictureController) {
        pip.canStartPictureInPictureAutomaticallyFromInline = true
        if #available(iOS 16.0, *) {
            // Prefer retaining playback controls / continuity when returning from PiP.
            pip.requiresLinearPlayback = false
        }
    }

    // MARK: - AVPictureInPictureControllerDelegate

    nonisolated func pictureInPictureControllerWillStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Task { @MainActor in self.isActive = true }
    }

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Task { @MainActor in self.isActive = true }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        Task { @MainActor in self.isActive = false }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Task { @MainActor in
            self.isActive = false
            self.onStopWhileDetached?()
            self.onStopWhileDetached = nil
        }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        Task { @MainActor in
            completionHandler(true)
        }
    }
}
