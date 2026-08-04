import Foundation
import UIKit

enum DeviceIdentity {
    /// User-Agent that production classifies as `mobile` (looks for “iphone”) and identifies this app for admin logs.
    static var userAgent: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        let os = UIDevice.current.systemVersion.replacingOccurrences(of: ".", with: "_")
        let model = UIDevice.current.model // "iPhone" / "iPad"
        // Retain "iPhone" / "iPad" tokens so server-side deviceType → mobile/tablet.
        return "Mozilla/5.0 (\(model); CPU \(model == "iPad" ? "OS" : "iPhone OS") \(os) like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) StoryTimeUniverseiOS/\(version).\(build) Mobile/\(model)"
    }

    static var platform: String {
        UIDevice.current.userInterfaceIdiom == .pad ? "ios_ipad" : "ios_iphone"
    }

    static var deviceSummary: String {
        "\(UIDevice.current.model) · iOS \(UIDevice.current.systemVersion)"
    }
}
