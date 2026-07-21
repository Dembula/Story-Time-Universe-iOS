import Foundation

enum AppConfig {
    /// Production API / viewer origin.
    static let webBaseURL = URL(string: "https://story-time.online")!
    static let apiBaseURL = webBaseURL

    /// Viewer sign-up landing (terms gate when required).
    static let viewerSignUpURL = URL(string: "https://story-time.online/auth/signup")!

    static let viewerProfileCookieName = "st_viewer_profile"
    static let viewerProfileUnlockCookieName = "st_viewer_profile_unlock"

    static let sessionCookieHints = [
        "next-auth.session-token",
        "__Secure-next-auth.session-token",
        "next-auth.csrf-token",
        "__Host-next-auth.csrf-token",
    ]
}
