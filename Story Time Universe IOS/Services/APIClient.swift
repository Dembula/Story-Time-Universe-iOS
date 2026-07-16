import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case unauthorized
    case paymentRequired(String)
    case server(String)
    case decoding(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid request URL."
        case .unauthorized: return "Please sign in again."
        case .paymentRequired(let message): return message
        case .server(let message): return message
        case .decoding(let message): return "Could not read server response: \(message)"
        case .network(let message): return message
        }
    }
}

final class APIClient {
    static let shared = APIClient()

    let session: URLSession
    private let decoder: JSONDecoder
    private let cookieStorage: HTTPCookieStorage

    private init() {
        cookieStorage = HTTPCookieStorage.shared
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = cookieStorage
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.timeoutIntervalForRequest = 45
        config.timeoutIntervalForResource = 120
        config.waitsForConnectivity = true
        session = URLSession(configuration: config)
        decoder = JSONDecoder()
    }

    func clearCookies() {
        cookieStorage.cookies?.forEach { cookieStorage.deleteCookie($0) }
    }

    func setViewerProfileCookie(_ profileId: String?) {
        let host = AppConfig.apiBaseURL.host ?? "story-time.online"
        if let existing = cookieStorage.cookies {
            for cookie in existing where cookie.name == AppConfig.viewerProfileCookieName
                || cookie.name == AppConfig.viewerProfileUnlockCookieName
            {
                cookieStorage.deleteCookie(cookie)
            }
        }
        guard let profileId, !profileId.isEmpty else { return }
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: AppConfig.viewerProfileCookieName,
            .value: profileId,
            .domain: host,
            .path: "/",
            .secure: "TRUE",
        ]
        if let cookie = HTTPCookie(properties: properties) {
            cookieStorage.setCookie(cookie)
        }
    }

    func absoluteURL(path: String, query: [URLQueryItem] = []) -> URL? {
        let cleaned = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard var components = URLComponents(string: AppConfig.apiBaseURL.absoluteString + "/" + cleaned) else {
            return nil
        }
        if !query.isEmpty {
            components.queryItems = query
        }
        return components.url
    }

    func request(
        path: String,
        method: String = "GET",
        query: [URLQueryItem] = [],
        jsonBody: [String: Any]? = nil,
        formBody: [String: String]? = nil,
        acceptsJSON: Bool = true
    ) async throws -> (Data, HTTPURLResponse) {
        guard let url = absoluteURL(path: path, query: query) else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("StoryTimeUniverseiOS/1.0", forHTTPHeaderField: "User-Agent")
        if acceptsJSON {
            request.setValue("application/json", forHTTPHeaderField: "Accept")
        }

        if let jsonBody {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
        } else if let formBody {
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            let encoded = formBody
                .map { key, value in
                    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
                    let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                    let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                    return "\(k)=\(v)"
                }
                .joined(separator: "&")
            request.httpBody = encoded.data(using: .utf8)
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.network("Invalid response.")
            }
            return (data, http)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.network(error.localizedDescription)
        }
    }

    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    func parseAPIError(data: Data, status: Int) -> APIError {
        if let body = try? decoder.decode(APIErrorBody.self, from: data), let message = body.error {
            if status == 402 || body.paymentRequired == true {
                return .paymentRequired(message)
            }
            if status == 401 {
                return .unauthorized
            }
            return .server(message)
        }
        if status == 401 { return .unauthorized }
        if status == 402 { return .paymentRequired("Complete your subscription on the web.") }
        return .server("Request failed (\(status)).")
    }
}
