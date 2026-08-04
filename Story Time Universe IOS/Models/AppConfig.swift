import Foundation

enum AppConfig {
    /// Production API / viewer origin.
    static let webBaseURL = URL(string: "https://story-time.online")!
    static let apiBaseURL = webBaseURL

    // MARK: - Auth (opened in-app via secure browser)

    static let viewerSignInURL = URL(string: "https://story-time.online/auth/signin")!
    /// Canonical signup entry (terms gate first). source marks iOS so web can adapt later.
    static let viewerSignUpURLForApp = URL(string: "https://story-time.online/auth/signup?source=ios_app&platform=ios")!
    static let viewerSignUpURL = viewerSignUpURLForApp
    static let forgotPasswordURL = URL(string: "https://story-time.online/auth/forgot-password")!
    static let packageOnboardingURL = URL(string: "https://story-time.online/onboarding/package")!

    // MARK: - Account management web paths (AuthenticatedWebBrowser — cookie session)

    static let accountURL = webBaseURL.appendingPathComponent("browse/account")
    static let accountSetupURL = webBaseURL.appendingPathComponent("browse/account/setup")
    static let renewSubscriptionURL = webBaseURL.appendingPathComponent("browse/account/renew")
    static let changePlanURL = webBaseURL.appendingPathComponent("browse/account/change-plan")
    static let settingsURL = webBaseURL.appendingPathComponent("browse/settings")
    static let profilesURL = webBaseURL.appendingPathComponent("profiles")

    static let viewerProfileCookieName = "st_viewer_profile"
    static let viewerProfileUnlockCookieName = "st_viewer_profile_unlock"

    static let sessionCookieHints = [
        "next-auth.session-token",
        "__Secure-next-auth.session-token",
        "next-auth.csrf-token",
        "__Host-next-auth.csrf-token",
    ]
}
