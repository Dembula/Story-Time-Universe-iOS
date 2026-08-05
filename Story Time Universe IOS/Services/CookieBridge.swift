import Foundation
import WebKit

/// Bidirectional cookie bridge between WKWebView and the app `URLSession` jar.
/// Critical for in-app web signup → native session handoff (NextAuth).
enum CookieBridge {
    static func injectSharedCookies(into store: WKWebsiteDataStore) async {
        guard let cookies = HTTPCookieStorage.shared.cookies else { return }
        let jar = store.httpCookieStore
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let group = DispatchGroup()
            for cookie in cookies where isStoryTimeCookie(cookie) {
                group.enter()
                jar.setCookie(cookie) { group.leave() }
            }
            group.notify(queue: .main) { continuation.resume() }
        }
    }

    /// Push WK cookies into `HTTPCookieStorage.shared` used by `APIClient`.
    static func exportCookies(from store: WKWebsiteDataStore) async {
        let cookies: [HTTPCookie] = await withCheckedContinuation { continuation in
            store.httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
        applyToSharedStorage(cookies)
    }

    /// Collect every Story Time cookie currently visible in shared storage (debug / Cookie header).
    static func sharedStoryTimeCookies() -> [HTTPCookie] {
        (HTTPCookieStorage.shared.cookies ?? []).filter(isStoryTimeCookie)
    }

    /// Build a `Cookie:` header value for an API request to the production origin.
    static func cookieHeader(for url: URL) -> String? {
        let storage = HTTPCookieStorage.shared
        var byName: [String: HTTPCookie] = [:]

        // Prefer store matches for the exact URL first.
        for cookie in storage.cookies(for: url) ?? [] {
            byName[cookie.name] = cookie
        }

        // Always merge all Story Time cookies so WK-exported NextAuth tokens are not
        // dropped by fussy domain matching (host-only, leading-dot, www).
        for cookie in sharedStoryTimeCookies() {
            if let existing = byName[cookie.name] {
                // Prefer cookies whose domain clearly matches production.
                let existingScore = domainScore(existing.domain)
                let newScore = domainScore(cookie.domain)
                if newScore > existingScore || (newScore == existingScore && cookie.value.count >= existing.value.count) {
                    byName[cookie.name] = cookie
                }
            } else {
                byName[cookie.name] = cookie
            }
        }

        let cookies = Array(byName.values)
        guard !cookies.isEmpty else { return nil }
        // Manually join — requestHeaderFields can drop cookies whose domain doesn't match `url`.
        let header = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        return header.isEmpty ? nil : header
    }

    private static func domainScore(_ domain: String) -> Int {
        let d = domain.lowercased()
        if d == "story-time.online" || d == ".story-time.online" { return 3 }
        if d.contains("story-time.online") { return 2 }
        if d.contains("story-time") { return 1 }
        return 0
    }

    // MARK: - Internals

    private static func applyToSharedStorage(_ cookies: [HTTPCookie]) {
        let storage = HTTPCookieStorage.shared
        for cookie in cookies {
            guard isStoryTimeCookie(cookie) else { continue }

            // Always store the original cookie as WebKit produced it.
            storage.setCookie(cookie)

            // Also plant domain/path variants so URLSession matches api/web host reliably.
            for variant in domainVariants(of: cookie) {
                storage.setCookie(variant)
            }
        }
    }

    static func isStoryTimeCookie(_ cookie: HTTPCookie) -> Bool {
        let domain = cookie.domain.lowercased()
        let name = cookie.name.lowercased()
        if domain.contains("story-time.online") || domain.contains("story-time") { return true }
        if name.contains("next-auth") || name.hasPrefix("__secure-next-auth") || name.hasPrefix("__host-next-auth") {
            return true
        }
        if name.hasPrefix("st_") { return true }
        return false
    }

    /// Produce safe host-matching copies; never invent broken `__Host-` cookies with Domain.
    private static func domainVariants(of cookie: HTTPCookie) -> [HTTPCookie] {
        // `__Host-` cookies MUST NOT have a Domain attribute — skip variants.
        if cookie.name.hasPrefix("__Host-") {
            return []
        }

        let hosts = ["story-time.online", ".story-time.online", "www.story-time.online"]
        var result: [HTTPCookie] = []
        for host in hosts {
            var props: [HTTPCookiePropertyKey: Any] = [
                .name: cookie.name,
                .value: cookie.value,
                .path: cookie.path.isEmpty ? "/" : cookie.path,
                .domain: host,
            ]
            if cookie.isSecure || cookie.name.hasPrefix("__Secure-") {
                props[.secure] = "TRUE"
            }
            if let exp = cookie.expiresDate {
                props[.expires] = exp
            }
            // Do NOT force SameSite — some NextAuth builds reject rewritten policies.
            if let rebuilt = HTTPCookie(properties: props) {
                result.append(rebuilt)
            }
        }
        return result
    }
}
