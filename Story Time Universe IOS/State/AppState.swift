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
        /// Offline with downloads available — no network catalogue required.
        case offlineDownloads
    }

    @Published var route: Route = .loading
    @Published var session: AuthSession?
    @Published var activeProfile: ViewerProfile?
    @Published var subscription: ViewerSubscription?
    @Published var bootstrapError: String?
    @Published var isBusy = false

    private let network = NetworkMonitor.shared

    /// Always land on profiles after auth — never auto-enter last profile on launch.
    func bootstrap() async {
        OrientationLock.unlockPortrait()
        route = .loading
        bootstrapError = nil
        APIClient.shared.setViewerProfileCookie(nil)
        activeProfile = nil

        let splashStarted = ContinuousClock.now
        let minimumSplash: Duration = .milliseconds(2800)

        // Offline-first: if we have downloads and no network, go straight to offline library.
        if !network.isOnline && !DownloadManager.shared.completedRecords.isEmpty {
            await waitRemainingSplash(from: splashStarted, minimum: minimumSplash)
            route = .offlineDownloads
            return
        }

        do {
            let session = try await AuthService.shared.fetchSession()
            self.session = session
            if session?.user != nil {
                subscription = try? await ViewerAPI.shared.fetchSubscription()
            }
            await waitRemainingSplash(from: splashStarted, minimum: minimumSplash)

            if session?.user != nil {
                route = .profiles
            } else if !network.isOnline && !DownloadManager.shared.completedRecords.isEmpty {
                route = .offlineDownloads
            } else {
                route = .signIn
            }
        } catch {
            session = nil
            bootstrapError = error.localizedDescription
            await waitRemainingSplash(from: splashStarted, minimum: minimumSplash)
            if !network.isOnline && !DownloadManager.shared.completedRecords.isEmpty {
                route = .offlineDownloads
            } else {
                route = .signIn
            }
        }
    }

    private func waitRemainingSplash(from start: ContinuousClock.Instant, minimum: Duration) async {
        let elapsed = ContinuousClock.now - start
        if elapsed < minimum {
            try? await Task.sleep(for: minimum - elapsed)
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
        await ViewerAPI.shared.reportSessionTelemetry()
        route = .profiles
    }

    func signUp(email: String, password: String, name: String?) async throws {
        isBusy = true
        defer { isBusy = false }
        let session = try await AuthService.shared.signUp(email: email, password: password, name: name)
        self.session = session
        APIClient.shared.setViewerProfileCookie(nil)
        activeProfile = nil
        subscription = try? await ViewerAPI.shared.fetchSubscription()
        await ViewerAPI.shared.reportSessionTelemetry()
        route = .profiles
    }

    /// Called after successful browser-based sign-up / payment handoff.
    func completeWebAuth() async {
        isBusy = true
        defer { isBusy = false }
        do {
            if let session = try await AuthService.shared.adoptWebSession(), session.user != nil {
                self.session = session
                APIClient.shared.setViewerProfileCookie(nil)
                activeProfile = nil
                subscription = try? await ViewerAPI.shared.fetchSubscription()
                await ViewerAPI.shared.reportSessionTelemetry()
                route = .profiles
            }
        } catch {
            bootstrapError = error.localizedDescription
        }
    }

    func deleteAccount(password: String) async throws {
        isBusy = true
        defer { isBusy = false }
        try await AuthService.shared.deleteAccount(password: password)
        session = nil
        activeProfile = nil
        subscription = nil
        APIClient.shared.setViewerProfileCookie(nil)
        route = .signIn
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
        Task { await ViewerAPI.shared.reportSessionTelemetry() }
    }

    func switchProfile() {
        activeProfile = nil
        APIClient.shared.setViewerProfileCookie(nil)
        OrientationLock.unlockPortrait()
        route = .profiles
    }

    func openOfflineLibrary() {
        route = .offlineDownloads
    }

    func leaveOfflineLibrary() {
        if session?.user != nil {
            route = activeProfile != nil ? .main : .profiles
        } else {
            route = .signIn
        }
    }

    var needsPaymentAttention: Bool {
        guard let status = subscription?.status?.uppercased() else { return false }
        return ["PAST_DUE", "CANCELED", "CANCELLED", "EXPIRED"].contains(status)
    }
}
