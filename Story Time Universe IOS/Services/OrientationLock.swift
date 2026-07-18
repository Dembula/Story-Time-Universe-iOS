import AVFoundation
import UIKit

/// Portrait everywhere except during playback (landscape-only then).
enum OrientationLock {
    private(set) static var allowed: UIInterfaceOrientationMask = .portrait

    static func lockLandscape() {
        allowed = .landscape
        force(orientation: .landscapeRight)
    }

    /// Restore portrait after leaving the player.
    static func unlockPortrait() {
        allowed = .portrait
        force(orientation: .portrait)
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
            UIViewController.attemptRotationToDeviceOrientation()
            scene.windows.forEach { window in
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
        }

        // Nudge the device orientation key so iOS completes the rotation.
        UIDevice.current.setValue(orientation.rawValue, forKey: "orientation")
        UIViewController.attemptRotationToDeviceOrientation()
    }
}

final class OrientationAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Playback category so media audio ignores the ring/silent switch.
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
}
