import AVFoundation
import UIKit

/// Portrait everywhere except during playback (landscape-only then).
enum OrientationLock {
    private(set) static var allowed: UIInterfaceOrientationMask = .portrait

    static func lockLandscape() {
        allowed = .landscape
        // Slight delay reduces fullScreenCover + rotation fighting.
        DispatchQueue.main.async {
            force(orientation: .landscapeRight)
        }
    }

    /// Restore portrait after leaving the player — multiple passes to survive dismiss animations.
    static func unlockPortrait() {
        allowed = .portrait
        DispatchQueue.main.async {
            force(orientation: .portrait)
        }
        for delay in [0.3, 0.6, 1.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard allowed == .portrait else { return }
                force(orientation: .portrait)
            }
        }
    }

    private static func force(orientation: UIInterfaceOrientation) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first
        else { return }

        if #available(iOS 16.0, *) {
            let mask: UIInterfaceOrientationMask = orientation == .portrait ? .portrait : .landscape
            let pref = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: mask)
            scene.requestGeometryUpdate(pref) { _ in }
            scene.windows.forEach { window in
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
        }

        UIDevice.current.setValue(orientation.rawValue, forKey: "orientation")
        UIViewController.attemptRotationToDeviceOrientation()
    }
}

final class OrientationAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
        } catch {
            print("AudioSession launch configuration failed: \(error)")
        }
        return true
    }

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        OrientationLock.allowed
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        DownloadManager.shared.backgroundCompletionHandler = completionHandler
    }
}
