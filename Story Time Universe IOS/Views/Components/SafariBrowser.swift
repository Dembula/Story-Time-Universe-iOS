import SafariServices
import SwiftUI
import WebKit

// MARK: - SFSafariViewController

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        config.barCollapsingEnabled = true
        let vc = SFSafariViewController(url: url, configuration: config)
        vc.preferredControlTintColor = UIColor(Theme.accent)
        vc.dismissButtonStyle = .close
        return vc
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

// MARK: - In-app browser modes

enum WebBrowserMode {
    /// After native sign-in: inject app session cookies for account/billing pages.
    case account
    /// Fresh signup funnel — cookies sync out to the app so we can adopt the session.
    case signUp
    /// Pay-per-view / unlock checkout (PayFast etc.). Injects session, allows external payment hosts.
    case checkout(contentId: String)
}

/// Secure in-app browser. For **signUp**, exports NextAuth cookies and signals the host when
/// the session is live so the Universe app can route to Profiles automatically.
struct AuthenticatedWebBrowser: View {
    let url: URL
    var title: String = "Story Time"
    var mode: WebBrowserMode = .account
    /// Called after cookies are exported and a live session is detected (signup) or checkout completes.
    var onSessionEstablished: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var pageTitle: String = ""
    @State private var currentHost: String = ""
    @State private var statusHint: String = ""
    @State private var hasFinishedHandoff = false

    private var showsHintBar: Bool {
        switch mode {
        case .signUp, .checkout: return !statusHint.isEmpty
        case .account: return false
        }
    }

    private var cancelLabel: String {
        switch mode {
        case .signUp: return "Cancel"
        case .checkout: return "Close"
        case .account: return "Done"
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.green)
                    Text(currentHost.isEmpty ? (url.host ?? "story-time.online") : currentHost)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.06))

                if showsHintBar {
                    Text(statusHint)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Theme.accentGold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Theme.accentSoft)
                }

                AuthWebView(
                    url: url,
                    mode: mode,
                    pageTitle: $pageTitle,
                    currentHost: $currentHost,
                    statusHint: $statusHint,
                    onSessionEstablished: {
                        guard !hasFinishedHandoff else { return }
                        hasFinishedHandoff = true
                        onSessionEstablished?()
                        switch mode {
                        case .signUp, .checkout:
                            dismiss()
                        case .account:
                            break
                        }
                    }
                )
            }
            .background(Theme.background)
            .navigationTitle(pageTitle.isEmpty ? title : pageTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(cancelLabel) { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled({
            if case .signUp = mode { return true }
            return false
        }())
        .onAppear {
            switch mode {
            case .checkout:
                statusHint = "Complete payment to unlock this title, then you’ll return to watch."
            case .signUp:
                statusHint = "Complete terms, account, and payment here. The app will sign you in when ready."
            case .account:
                break
            }
        }
    }
}

// MARK: - WKWebView

private struct AuthWebView: UIViewRepresentable {
    let url: URL
    let mode: WebBrowserMode
    @Binding var pageTitle: String
    @Binding var currentHost: String
    @Binding var statusHint: String
    var onSessionEstablished: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Use default store after the host clears shared cookies — non-persistent stores
        // historically lost NextAuth tokens on export. Default is more reliable for handoff.
        config.websiteDataStore = .default()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.applicationNameForUserAgent = "StoryTimeUniverseiOS"

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = DeviceIdentity.userAgent
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = {
            if case .signUp = mode { return false }
            return true
        }()
        webView.backgroundColor = .black
        webView.isOpaque = false
        webView.scrollView.backgroundColor = .black

        context.coordinator.bind(webView: webView)

        Task {
            switch mode {
            case .account, .checkout:
                await CookieBridge.injectSharedCookies(into: webView.configuration.websiteDataStore)
            case .signUp:
                // Ensure clean jar for a brand-new signup (host already cleared shared cookies).
                await CookieBridge.injectSharedCookies(into: webView.configuration.websiteDataStore)
            }
            await MainActor.run {
                var request = URLRequest(url: url)
                request.setValue(DeviceIdentity.userAgent, forHTTPHeaderField: "User-Agent")
                request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
                webView.load(request)
            }
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let parent: AuthWebView
        private var didNotifySession = false
        private weak var webView: WKWebView?
        private var pollTask: Task<Void, Never>?
        private var sawPackageOrPayment = false
        private var sawAccountCreated = false

        init(_ parent: AuthWebView) {
            self.parent = parent
        }

        func bind(webView: WKWebView) {
            self.webView = webView
            if case .signUp = parent.mode {
                startSignupPoller()
            }
        }

        deinit {
            pollTask?.cancel()
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.pageTitle = webView.title ?? ""
            parent.currentHost = webView.url?.host ?? ""

            if case .signUp = parent.mode {
                injectSignupUICleanup(webView)
                updateSignupHint(for: webView.url)
                noteSignupProgress(url: webView.url)
            }
            if case .checkout = parent.mode {
                updateCheckoutHint(for: webView.url)
            }

            Task { @MainActor in
                await CookieBridge.exportCookies(from: webView.configuration.websiteDataStore)
                await checkSessionSuccess(webView)
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            parent.currentHost = url.host ?? parent.currentHost

            if case .signUp = parent.mode {
                if shouldBlockSignupNavigation(url) {
                    decisionHandler(.cancel)
                    let path = url.path.lowercased()
                    // After package/payment, never dump the user on a fresh signup page;
                    // send them toward profiles so handoff can complete.
                    let bounce: URL
                    if isCreatorLikePath(path) || sawPackageOrPayment || sawAccountCreated {
                        bounce = AppConfig.profilesURL
                    } else {
                        bounce = AppConfig.viewerSignUpURLForApp
                    }
                    webView.load(URLRequest(url: bounce))
                    return
                }
                noteSignupProgress(url: url)
                // Soft-navigations: check after each navigation decision.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    await CookieBridge.exportCookies(from: webView.configuration.websiteDataStore)
                    await self.checkSessionSuccess(webView)
                }
            }
            decisionHandler(.allow)
        }

        private func noteSignupProgress(url: URL?) {
            guard let path = url?.path.lowercased() else { return }
            if path.contains("package")
                || path.contains("onboarding")
                || path.contains("payfast")
                || path.contains("payment")
                || path.contains("checkout")
            {
                sawPackageOrPayment = true
            }
            if path.contains("profiles") || path.hasPrefix("/browse") {
                sawPackageOrPayment = true
            }
            // After credentials form: web POSTs signup then redirects to package.
            if path.contains("onboarding") || path.contains("package") {
                sawAccountCreated = true
            }
            if path.contains("signup") && !path.contains("terms") {
                // User is on create form — not enough alone.
            }
        }

        private func shouldBlockSignupNavigation(_ url: URL) -> Bool {
            guard let host = url.host?.lowercased(), host.contains("story-time.online") else {
                return false // PayFast / external hosts ok
            }
            let path = url.path.lowercased()
            if path == "/" || path.isEmpty || path == "/about" || path == "/home" {
                return true
            }
            return isCreatorLikePath(path)
        }

        private func isCreatorLikePath(_ path: String) -> Bool {
            path.hasPrefix("/auth/creator")
                || path.hasPrefix("/creator")
                || path.hasPrefix("/studio")
                || path.hasPrefix("/dashboard")
                || path.hasPrefix("/admin")
                || path.hasPrefix("/auth/admin")
                || path.hasPrefix("/production")
                || path.contains("/portal/creator")
        }

        private func injectSignupUICleanup(_ webView: WKWebView) {
            let js = """
            (function() {
              try {
                document.documentElement.setAttribute('data-st-ios-app', '1');
                document.documentElement.setAttribute('data-st-platform', 'ios');
                var hide = function(el) {
                  if (!el) return;
                  el.style.setProperty('display','none','important');
                  el.setAttribute('aria-hidden','true');
                  el.setAttribute('tabindex','-1');
                  el.addEventListener('click', function(e){ e.preventDefault(); e.stopPropagation(); }, true);
                };
                var nodes = document.querySelectorAll('a, button, [role="link"]');
                for (var i = 0; i < nodes.length; i++) {
                  var el = nodes[i];
                  var t = (el.textContent || '').replace(/\\s+/g,' ').trim().toLowerCase();
                  var href = ((el.getAttribute && el.getAttribute('href')) || '').trim().toLowerCase();
                  if (
                    t.indexOf('back to home') !== -1
                    || t === 'home'
                    || href === '/'
                    || href === 'https://story-time.online/'
                    || href === 'https://story-time.online'
                    || href.indexOf('/auth/creator') === 0
                    || href.indexOf('/creator') === 0
                    || href.indexOf('/studio') === 0
                  ) {
                    hide(el);
                  }
                }
              } catch (e) {}
            })();
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        private func updateSignupHint(for url: URL?) {
            guard let path = url?.path.lowercased() else { return }
            if path.contains("terms") {
                parent.statusHint = "Accept terms, then create your account"
            } else if path.contains("onboarding") || path.contains("package") {
                parent.statusHint = "Choose a plan and complete payment — stay here until finished"
            } else if path.contains("payfast") || path.contains("payment") || path.contains("checkout") {
                parent.statusHint = "Secure payment… when it finishes you’ll return to the app"
            } else if path.contains("signup") {
                parent.statusHint = "Create your account, then pick a plan. Don’t leave this screen."
            } else if path.contains("profiles") || path.hasPrefix("/browse") {
                parent.statusHint = "Account ready — signing you into the app…"
            } else {
                parent.statusHint = "Stay in this window until your account is activated"
            }
        }

        private func updateCheckoutHint(for url: URL?) {
            guard let url else { return }
            let path = url.path.lowercased()
            let host = url.host?.lowercased() ?? ""
            if host.contains("payfast") || path.contains("checkout") || path.contains("pay") {
                parent.statusHint = "Secure payment in progress — don’t close until you finish."
            } else if path.contains("/payments/return") {
                parent.statusHint = "Confirming payment…"
            } else if path.contains("/watch") || path.contains("/browse/content") {
                parent.statusHint = "Unlocked — returning to the app to play…"
            } else {
                parent.statusHint = "Complete payment to unlock this title."
            }
        }

        private func startSignupPoller() {
            pollTask?.cancel()
            pollTask = Task { [weak self] in
                for _ in 0..<90 { // ~3 minutes at 2s
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    guard !Task.isCancelled else { return }
                    guard let self, !self.didNotifySession, let webView = self.webView else { return }
                    await MainActor.run {
                        self.parent.currentHost = webView.url?.host ?? self.parent.currentHost
                    }
                    await CookieBridge.exportCookies(from: webView.configuration.websiteDataStore)
                    await self.checkSessionSuccess(webView)
                }
            }
        }

        @MainActor
        private func checkSessionSuccess(_ webView: WKWebView) async {
            guard !didNotifySession else { return }
            guard let url = webView.url else { return }
            let path = url.path.lowercased()
            let full = url.absoluteString.lowercased()

            switch parent.mode {
            case .checkout(let contentId):
                let cid = contentId.lowercased()
                let host = url.host?.lowercased() ?? ""
                let finished =
                    path.contains("/payments/return")
                    || path.contains("/payments/success")
                    || path.contains("/payment/return")
                    || path.contains("/payment/success")
                    || full.contains("payment_status=complete")
                    || full.contains("payment_status=success")
                    || path.contains("/browse/content/\(cid)/watch")
                    || (path.contains("/browse/content/\(cid)") && full.contains("viewer_ppv"))
                    || (host.contains("payfast") && (full.contains("complete") || full.contains("success") || path.contains("return")))
                guard finished else { return }
                try? await Task.sleep(nanoseconds: 700_000_000)
                await CookieBridge.exportCookies(from: webView.configuration.websiteDataStore)
                await finishHandoff(from: webView)
                return

            case .signUp:
                await CookieBridge.exportCookies(from: webView.configuration.websiteDataStore)

                if isEarlySignupForm(path) { return }

                // Never auto-dismiss during an external payment host until a return/success URL.
                let host = url.host?.lowercased() ?? ""
                if isPaymentInProgress(host: host, path: path, full: full) {
                    return
                }

                if isCreatorLikePath(path) {
                    webView.load(URLRequest(url: AppConfig.profilesURL))
                    return
                }

                // Require a live native session after cookie export (same path adoptWebSession uses).
                guard let session = try? await AuthService.shared.adoptWebSession(),
                      session.user != nil
                else { return }

                let activated = await hasActivatedViewerAccess()

                // Package / onboarding: hand off only when access exists or payment success is visible.
                // Stay put while the user is still choosing/paying for a plan.
                if path.contains("onboarding") || path.contains("package") {
                    if activated
                        || full.contains("paid")
                        || full.contains("success")
                        || full.contains("complete")
                        || full.contains("payment_status=")
                    {
                        parent.statusHint = "Plan active — opening the app…"
                        await finishHandoff(from: webView)
                    }
                    return
                }

                // Payment return hosts / success pages / profiles / browse.
                if isSignupFinishDestination(path, full: full) {
                    parent.statusHint = "Account ready — signing you into the app…"
                    await finishHandoff(from: webView)
                    return
                }

                // After leaving package for our origin, hand off when access is live.
                if activated {
                    parent.statusHint = "Account ready — signing you into the app…"
                    await finishHandoff(from: webView)
                }

            case .account:
                return
            }
        }

        private func isEarlySignupForm(_ path: String) -> Bool {
            if path.contains("/auth/signup/terms") { return true }
            if path == "/auth/signup" { return true }
            if path.hasPrefix("/auth/signin") { return true }
            return false
        }

        /// True while the user is still on a payment processor (do not hand off yet).
        private func isPaymentInProgress(host: String, path: String, full: String) -> Bool {
            let paymentHosts = ["payfast", "paypal", "stripe", "checkout.stripe"]
            let onGateway = paymentHosts.contains(where: { host.contains($0) })
            if !onGateway { return false }
            // Allow handoff only when gateway itself signals completion/return.
            if full.contains("payment_status=complete")
                || full.contains("payment_status=success")
                || full.contains("payment_status=cancelled")
                || path.contains("return")
                || path.contains("success")
                || path.contains("complete")
                || path.contains("done")
            {
                return false
            }
            return true
        }

        private func isSignupFinishDestination(_ path: String, full: String) -> Bool {
            if path == "/profiles" || path.hasPrefix("/profiles/") { return true }
            if path == "/browse" || path.hasPrefix("/browse/") { return true }
            if path.contains("/payments/return") || path.contains("/payment/return") { return true }
            if path.contains("/payments/success") || path.contains("/payment/success") { return true }
            if path.contains("onboarding") && (full.contains("complete") || full.contains("success") || full.contains("paid=1")) {
                return true
            }
            return false
        }

        private func hasActivatedViewerAccess() async -> Bool {
            if let sub = try? await ViewerAPI.shared.fetchSubscription() {
                let status = sub.status?.uppercased() ?? ""
                if !status.isEmpty {
                    if ["ACTIVE", "TRIALING", "PAID", "PENDING", "INCOMPLETE"].contains(status) {
                        return true
                    }
                    if status.contains("ACTIVE") || status.contains("PAID") { return true }
                }
                if sub.isPayPerViewModel { return true }
                if let plan = sub.plan, !plan.isEmpty { return true }
            }
            return false
        }

        @MainActor
        private func finishHandoff(from webView: WKWebView) async {
            guard !didNotifySession else { return }
            // Final cookie pull while WK is still alive (twice with a short beat).
            await CookieBridge.exportCookies(from: webView.configuration.websiteDataStore)
            try? await Task.sleep(nanoseconds: 300_000_000)
            await CookieBridge.exportCookies(from: webView.configuration.websiteDataStore)
            // Default store is the same instance for signup, but export again for safety.
            await CookieBridge.exportCookies(from: WKWebsiteDataStore.default())

            // Verify once more before dismissing — only finish if native session is real.
            if case .signUp = parent.mode {
                guard let session = try? await AuthService.shared.adoptWebSession(),
                      session.user != nil
                else { return }
            }

            didNotifySession = true
            pollTask?.cancel()
            parent.onSessionEstablished?()
        }
    }
}
