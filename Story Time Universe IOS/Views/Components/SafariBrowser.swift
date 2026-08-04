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
    /// Fresh signup — no prior cookies, blocks “Back to home”, only finishes after real app destinations.
    case signUp
}

/// Secure in-app browser showing host/HTTPS, with cookie sync for account pages
/// and a locked-down signup funnel so marketing “Back to home” cannot steal the flow.
struct AuthenticatedWebBrowser: View {
    let url: URL
    var title: String = "Story Time"
    var mode: WebBrowserMode = .account
    var onSessionEstablished: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var pageTitle: String = ""
    @State private var currentHost: String = ""
    @State private var statusHint: String = ""

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

                if mode == .signUp, !statusHint.isEmpty {
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
                        onSessionEstablished?()
                    }
                )
            }
            .background(Theme.background)
            .navigationTitle(pageTitle.isEmpty ? title : pageTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(mode == .signUp ? "Cancel" : "Done") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(mode == .signUp)
    }
}

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
        // Sign-up must not reuse someone else's cookies / WebsiteDataStore.
        config.websiteDataStore = mode == .signUp ? .nonPersistent() : .default()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.applicationNameForUserAgent = "StoryTimeUniverseiOS"

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = DeviceIdentity.userAgent
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = mode != .signUp
        webView.backgroundColor = .black
        webView.isOpaque = false
        webView.scrollView.backgroundColor = .black

        Task {
            if mode == .account {
                await CookieBridge.injectSharedCookies(into: webView.configuration.websiteDataStore)
            }
            await MainActor.run {
                var request = URLRequest(url: url)
                request.setValue(DeviceIdentity.userAgent, forHTTPHeaderField: "User-Agent")
                webView.load(request)
            }
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let parent: AuthWebView
        private var didNotifySession = false

        init(_ parent: AuthWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.pageTitle = webView.title ?? ""
            parent.currentHost = webView.url?.host ?? ""

            if parent.mode == .signUp {
                injectSignupUICleanup(webView)
                updateSignupHint(for: webView.url)
            }

            Task {
                if parent.mode == .account || parent.mode == .signUp {
                    await CookieBridge.exportCookies(from: webView.configuration.websiteDataStore)
                }
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

            if parent.mode == .signUp {
                if shouldBlockSignupNavigation(url) {
                    decisionHandler(.cancel)
                    // Keep the user inside the signup funnel
                    webView.load(URLRequest(url: AppConfig.viewerSignUpURLForApp))
                    return
                }
            }
            decisionHandler(.allow)
        }

        /// Marketing home breaks the funnel. Finished accounts may land on /profiles or /browse.
        private func shouldBlockSignupNavigation(_ url: URL) -> Bool {
            guard let host = url.host?.lowercased(), host.contains("story-time.online") else {
                // External payment hosts (PayFast, etc.) must be allowed.
                return false
            }
            let path = url.path.lowercased()

            // Explicitly block marketing “Back to home” and public landing.
            if path == "/" || path.isEmpty || path == "/about" || path == "/home" {
                return true
            }
            // Never drift into creator / admin tools mid-signup.
            if path.hasPrefix("/auth/creator") || path.hasPrefix("/admin") || path.hasPrefix("/auth/admin") {
                return true
            }
            return false
        }

        private func injectSignupUICleanup(_ webView: WKWebView) {
            // Hide “Back to home” and similar marketing chrome when running inside the iOS app.
            let js = """
            (function() {
              try {
                document.documentElement.setAttribute('data-st-ios-app', '1');
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
                  var href = (el.getAttribute && el.getAttribute('href')) || '';
                  href = (href || '').trim();
                  if (t.indexOf('back to home') !== -1 || t === 'home' || href === '/' || href === 'https://story-time.online/' || href === 'https://story-time.online') {
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
                parent.statusHint = "Choose a plan to activate your account — stay here until finished"
            } else if path.contains("signup") {
                parent.statusHint = "Complete signup here. Don’t leave this screen until you’re done."
            } else if path.contains("profiles") || path.hasPrefix("/browse") {
                parent.statusHint = "Almost done — opening the app…"
            } else {
                parent.statusHint = "Stay in this window until your account is ready"
            }
        }

        @MainActor
        private func checkSessionSuccess(_ webView: WKWebView) async {
            guard !didNotifySession else { return }
            guard let path = webView.url?.path.lowercased() else { return }

            // Keep the signup sheet open through terms + payment package selection.
            // Only finish once they reach the app destinations.
            let finishPaths: [String]
            if parent.mode == .signUp {
                finishPaths = ["/profiles", "/browse"]
            } else {
                finishPaths = ["profiles", "browse", "account"]
            }

            let isFinish: Bool
            if parent.mode == .signUp {
                isFinish = finishPaths.contains(where: { path == $0 || path.hasPrefix($0 + "/") })
                    && !path.contains("auth/")
                    && !path.contains("onboarding")
            } else {
                isFinish = finishPaths.contains(where: { path.contains($0) })
                    && !path.contains("auth/signin")
                    && !path.contains("auth/signup")
            }
            guard isFinish else { return }

            await CookieBridge.exportCookies(from: webView.configuration.websiteDataStore)
            if let session = try? await AuthService.shared.fetchSession(), session.user != nil {
                didNotifySession = true
                parent.onSessionEstablished?()
            }
        }
    }
}

enum CookieBridge {
    static func injectSharedCookies(into store: WKWebsiteDataStore) async {
        guard let cookies = HTTPCookieStorage.shared.cookies else { return }
        let jar = store.httpCookieStore
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let group = DispatchGroup()
            for cookie in cookies {
                group.enter()
                jar.setCookie(cookie) { group.leave() }
            }
            group.notify(queue: .main) { continuation.resume() }
        }
    }

    static func exportCookies(from store: WKWebsiteDataStore) async {
        let cookies: [HTTPCookie] = await withCheckedContinuation { continuation in
            store.httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
        let storage = HTTPCookieStorage.shared
        for cookie in cookies {
            let host = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            guard host.contains("story-time.online") || cookie.domain.contains("story-time") else { continue }
            storage.setCookie(cookie)
        }
    }
}
