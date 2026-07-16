import UIKit

/// Locks interface orientation while the Netflix-style player is presented.
enum OrientationLock {
    private(set) static var allowed: UIInterfaceOrientationMask = .allButUpsideDown

    static func lockLandscape() {
        allowed = .landscape
        apply(orientation: .landscapeRight)
    }

    static func unlockAll() {
        allowed = .allButUpsideDown
        apply(orientation: .portrait)
    }

    private static func apply(orientation: UIInterfaceOrientation) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first
        else { return }

        if #available(iOS 16.0, *) {
            let pref = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: allowed)
            scene.requestGeometryUpdate(pref) { _ in }
            scene.windows.forEach { $0.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations() }
        } else {
            UIDevice.current.setValue(orientation.rawValue, forKey: "orientation")
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }
}

final class OrientationAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        OrientationLock.allowed
    }
}
