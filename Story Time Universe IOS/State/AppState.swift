import Foundation
import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    enum Route: Equatable {
        case loading
        case signIn
        case profiles
        case main
    }

    @Published var route: Route = .loading
    @Published var session: AuthSession?
    @Published var activeProfile: ViewerProfile?
    @Published var subscription: ViewerSubscription?
    @Published var bootstrapError: String?
    @Published var isBusy = false

    /// Always land on profiles after auth — never auto-enter last profile on launch.
    func bootstrap() async {
        route = .loading
        bootstrapError = nil
        APIClient.shared.setViewerProfileCookie(nil)
        activeProfile = nil

        do {
            let session = try await AuthService.shared.fetchSession()
            self.session = session
            if session?.user != nil {
                subscription = try? await ViewerAPI.shared.fetchSubscription()
                route = .profiles
            } else {
                route = .signIn
            }
        } catch {
            session = nil
            route = .signIn
            bootstrapError = error.localizedDescription
        }
    }

    func signIn(email: String, password: String) async throws {
        isBusy = true
        defer { isBusy = false }
        let session = try await AuthService.shared.signIn(email: email, password: password)
        self.session = session
        APIClient.shared.setViewerProfileCookie(nil)
        activeProfile = nil
        subscription = try? await ViewerAPI.shared.fetchSubscription()
        route = .profiles
    }

    func signOut() async {
        isBusy = true
        defer { isBusy = false }
        await AuthService.shared.signOut()
        session = nil
        activeProfile = nil
        subscription = nil
        APIClient.shared.setViewerProfileCookie(nil)
        route = .signIn
    }

    func selectProfile(_ profile: ViewerProfile) {
        activeProfile = profile
        APIClient.shared.setViewerProfileCookie(profile.id)
        route = .main
    }

    func switchProfile() {
        activeProfile = nil
        APIClient.shared.setViewerProfileCookie(nil)
        OrientationLock.unlockAll()
        route = .profiles
    }

    var needsPaymentAttention: Bool {
        guard let status = subscription?.status?.uppercased() else { return false }
        return ["PAST_DUE", "CANCELED", "CANCELLED", "EXPIRED"].contains(status)
    }
}
