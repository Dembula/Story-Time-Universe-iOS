import Foundation
import SwiftUI
import Combine
import WebKit

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
    /// Shared main tab selection so Account can jump to Downloads, Home, etc.
    @Published var selectedMainTab: MainTab = .home
    /// Bottom tab bar visibility (hide while scrolling down).
    @Published var tabBarVisible = true

    /// Present subscription / PPV App Store paywall (never web checkout for digital goods).
    @Published var showPaywall = false
    @Published var paywallContext: PaywallContext = .subscribe

    private let network = NetworkMonitor.shared
    /// Coalesces concurrent signup-dismiss + handoff-callback adoption attempts.
    private var webAuthAdoptionTask: Task<Bool, Never>?

    func presentPaywall(_ context: PaywallContext = .subscribe) {
        paywallContext = context
        showPaywall = true
    }

    func refreshSubscriptionFromServer() async {
        subscription = try? await ViewerAPI.shared.fetchSubscription()
        // Soft poll if Apple purchased but server lag.
        if !hasActiveServerSubscription, StoreService.shared.hasActiveSubscriptionEntitlement {
            for _ in 0..<5 {
                try? await Task.sleep(nanoseconds: 800_000_000)
                subscription = try? await ViewerAPI.shared.fetchSubscription()
                if hasActiveServerSubscription { break }
            }
        }
    }

    /// Server reports a usable subscription.
    var hasActiveServerSubscription: Bool {
        guard let status = subscription?.status?.uppercased() else {
            // Some backends only send plan when active.
            if let plan = subscription?.plan, !plan.isEmpty { return true }
            return false
        }
        if ["ACTIVE", "TRIALING", "PAID", "PENDING"].contains(status) { return true }
        if status.contains("ACTIVE") || status.contains("PAID") || status.contains("TRIAL") { return true }
        return false
    }

    /// Combined gate: server entitlement (primary) or Apple is still syncing.
    var hasStreamingAccess: Bool {
        if hasActiveServerSubscription { return true }
        if StoreService.shared.hasActiveSubscriptionEntitlement { return true }
        return false
    }

    /// Always land on profiles after auth — never auto-enter last profile on launch.
    func bootstrap() async {
        OrientationLock.unlockPortrait()
        route = .loading
        bootstrapError = nil
        APIClient.shared.setViewerProfileCookie(nil)
        activeProfile = nil

        let splashStarted = ContinuousClock.now
        let minimumSplash: Duration = .milliseconds(2800)

        // Offline-first: wait for real path status, then jump to downloads if needed.
        await network.waitForInitialPath()
        DownloadManager.shared.validateOfflineLibrary()
        if !network.isOnline && !DownloadManager.shared.completedRecords.isEmpty {
            await waitRemainingSplash(from: splashStarted, minimum: minimumSplash)
            route = .offlineDownloads
            return
        }

        do {
            let session = try await withTimeout(seconds: 10) {
                try await AuthService.shared.fetchSession()
            }
            self.session = session
            if session?.user != nil {
                subscription = try? await ViewerAPI.shared.fetchSubscription()
                await syncParentalHintsFromSettings()
            }
            await waitRemainingSplash(from: splashStarted, minimum: minimumSplash)

            if session?.user != nil {
                route = .profiles
                if needsPaymentAttention {
                    presentPaywall(.subscribe)
                }
            } else if !DownloadManager.shared.completedRecords.isEmpty && !network.isOnline {
                route = .offlineDownloads
            } else {
                route = .signIn
            }
        } catch {
            session = nil
            bootstrapError = error.localizedDescription
            await waitRemainingSplash(from: splashStarted, minimum: minimumSplash)
            // Prefer offline library whenever we have playable downloads and session failed
            // (airplane mode, captive portal, timeout, API down).
            if !DownloadManager.shared.completedRecords.isEmpty,
               !network.isOnline || (error as? APIError).map({
                   if case .network = $0 { return true }
                   return false
               }) == true {
                route = .offlineDownloads
            } else if !DownloadManager.shared.completedRecords.isEmpty && !network.isOnline {
                route = .offlineDownloads
            } else {
                route = .signIn
            }
        }
    }

    private func withTimeout<T>(seconds: Double, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw APIError.network("Connection timed out.")
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
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
        await refreshSubscriptionFromServer()
        await ViewerAPI.shared.reportSessionTelemetry()
        route = .profiles
        if !hasActiveServerSubscription {
            presentPaywall(needsPaymentAttention ? .reactivate : .subscribe)
        }
    }

    func signUp(email: String, password: String, name: String?) async throws {
        isBusy = true
        defer { isBusy = false }
        let session = try await AuthService.shared.signUp(email: email, password: password, name: name)
        self.session = session
        APIClient.shared.setViewerProfileCookie(nil)
        activeProfile = nil
        await refreshSubscriptionFromServer()
        await ViewerAPI.shared.reportSessionTelemetry()
        route = .profiles
        // New accounts always choose a plan via App Store (3.1.1).
        if !hasActiveServerSubscription {
            presentPaywall(.subscribe)
        }
    }

    /// Called after successful browser-based sign-up / payment handoff.
    /// Retries cookie session adoption so late-arriving NextAuth cookies still work.
    /// Concurrent callers (sheet onDismiss + success callback) share one adoption run.
    @discardableResult
    func completeWebAuth() async -> Bool {
        if let existing = webAuthAdoptionTask {
            return await existing.value
        }
        // Already signed in from a previous handoff.
        if session?.user != nil {
            route = .profiles
            return true
        }

        let task = Task { @MainActor () -> Bool in
            self.isBusy = true
            defer { self.isBusy = false }

            // Export from the default WK store (signup uses this store).
            await CookieBridge.exportCookies(from: WKWebsiteDataStore.default())

            for attempt in 0..<8 {
                if attempt > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(350_000_000 * attempt))
                    await CookieBridge.exportCookies(from: WKWebsiteDataStore.default())
                }
                do {
                    if let session = try await AuthService.shared.adoptWebSession(), session.user != nil {
                        self.session = session
                        APIClient.shared.setViewerProfileCookie(nil)
                        self.activeProfile = nil
                        self.subscription = try? await ViewerAPI.shared.fetchSubscription()
                        await ViewerAPI.shared.reportSessionTelemetry()
                        self.route = .profiles
                        self.bootstrapError = nil
                        return true
                    }
                } catch {
                    self.bootstrapError = error.localizedDescription
                }
            }
            return false
        }
        webAuthAdoptionTask = task
        let result = await task.value
        webAuthAdoptionTask = nil
        return result
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
        tabBarVisible = true
        Task {
            await ViewerAPI.shared.reportSessionTelemetry()
            await syncParentalHintsFromSettings()
        }
    }

    /// Pull maturity flags from viewer settings when the API exposes them. PIN stays on-device.
    func syncParentalHintsFromSettings() async {
        guard let settings = try? await ViewerAPI.shared.fetchViewerSettings() else { return }
        let prefs = settings.preferences
        ParentalControls.shared.applyRemoteMaturityHints(
            enabled: prefs?.parentalControlsEnabled,
            maxAge: prefs?.resolvedMaxMaturityAge
        )
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

    /// Switch to the in-app Downloads tab (or offline library when completely offline).
    func openDownloads() {
        if !NetworkMonitor.shared.isOnline && !DownloadManager.shared.completedRecords.isEmpty {
            openOfflineLibrary()
            return
        }
        if route != .main {
            route = .main
        }
        selectedMainTab = .downloads
    }

    func leaveOfflineLibrary() {
        if session?.user != nil {
            route = activeProfile != nil ? .main : .profiles
        } else {
            route = .signIn
        }
    }

    var needsPaymentAttention: Bool {
        if hasActiveServerSubscription { return false }
        if session?.user == nil { return false }
        // Active Apple entitlement while server catches up — still prompt if play fails.
        guard let status = subscription?.status?.uppercased() else {
            // Missing subscription object after account create / lapsed empty response.
            return !StoreService.shared.hasActiveSubscriptionEntitlement
        }
        return ["PAST_DUE", "CANCELED", "CANCELLED", "EXPIRED", "INACTIVE", "NONE"].contains(status)
            || status.isEmpty
    }

    /// Pay-per-title accounts unlock films via App Store consumable purchase.
    var isPayPerViewAccount: Bool {
        subscription?.isPayPerViewModel == true
    }
}
