import Foundation

enum AppConfig {
    /// Production viewer web app — payments & account management open here.
    static let webBaseURL = URL(string: "https://story-time.online")!
    static let apiBaseURL = webBaseURL

    static let renewSubscriptionURL = webBaseURL.appendingPathComponent("browse/account/renew")
    static let accountURL = webBaseURL.appendingPathComponent("browse/account")
    static let changePlanURL = webBaseURL.appendingPathComponent("browse/account/change-plan")
    static let packageOnboardingURL = webBaseURL.appendingPathComponent("onboarding/package")
    static let signUpURL = webBaseURL.appendingPathComponent("auth/signup")

    static let viewerProfileCookieName = "st_viewer_profile"
    static let viewerProfileUnlockCookieName = "st_viewer_profile_unlock"

    static let sessionCookieHints = [
        "next-auth.session-token",
        "__Secure-next-auth.session-token",
        "next-auth.csrf-token",
        "__Host-next-auth.csrf-token",
    ]
}
