import SafariServices
import SwiftUI
import WebKit

// MARK: - SFSafariViewController (Apple-recommended in-app browser)

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

// MARK: - Authenticated WK browser (injects NextAuth cookies so account/subscription pages work)

/// Secure in-app browser that shows the host (certificate trust via HTTPS) and syncs
/// session cookies both ways so signed-in users reach `/browse/account` correctly.
struct AuthenticatedWebBrowser: View {
    let url: URL
    var title: String = "Story Time"
    var onSessionEstablished: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var pageTitle: String = ""
    @State private var currentHost: String = ""

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

                AuthWebView(
                    url: url,
                    pageTitle: $pageTitle,
                    currentHost: $currentHost,
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
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct AuthWebView: UIViewRepresentable {
    let url: URL
    @Binding var pageTitle: String
    @Binding var currentHost: String
    var onSessionEstablished: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.backgroundColor = .black
        webView.isOpaque = false
        webView.scrollView.backgroundColor = .black

        Task {
            await CookieBridge.injectSharedCookies(into: webView.configuration.websiteDataStore)
            await MainActor.run {
                webView.load(URLRequest(url: url))
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
            Task {
                await CookieBridge.exportCookies(from: webView.configuration.websiteDataStore)
                await checkSessionSuccess(webView)
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if let url = navigationAction.request.url {
                parent.currentHost = url.host ?? parent.currentHost
            }
            decisionHandler(.allow)
        }

        @MainActor
        private func checkSessionSuccess(_ webView: WKWebView) async {
            guard !didNotifySession else { return }
            guard let path = webView.url?.path.lowercased() else { return }
            // Confirm session via API when leaving auth routes for app destinations.
            let successHints = ["profiles", "browse", "account"]
            let isSuccess = successHints.contains(where: { path.contains($0) })
                && !path.contains("auth/signin")
                && !path.contains("auth/signup")
            guard isSuccess else { return }

            // Confirm session via API
            if let session = try? await AuthService.shared.fetchSession(), session.user != nil {
                didNotifySession = true
                parent.onSessionEstablished?()
            }
        }
    }
}

enum CookieBridge {
    /// Push HTTPCookieStorage (app API client) → WKWebsiteDataStore
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

    /// Pull WK cookies → HTTPCookieStorage so URLSession auth works after in-app web login.
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
