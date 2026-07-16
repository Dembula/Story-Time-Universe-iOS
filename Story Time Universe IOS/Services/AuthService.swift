import Foundation

actor AuthService {
    static let shared = AuthService()
    private let api = APIClient.shared

    struct CSRFResponse: Decodable {
        let csrfToken: String
    }

    func fetchSession() async throws -> AuthSession? {
        let (data, response) = try await api.request(path: "api/auth/session")
        guard response.statusCode == 200 else {
            if response.statusCode == 401 { return nil }
            throw api.parseAPIError(data: data, status: response.statusCode)
        }
        if data.isEmpty || String(data: data, encoding: .utf8) == "null" {
            return nil
        }
        let session = try api.decode(AuthSession.self, from: data)
        guard session.user?.email != nil || session.user?.id != nil else { return nil }
        return session
    }

    func signIn(email: String, password: String) async throws -> AuthSession {
        let (csrfData, csrfResponse) = try await api.request(path: "api/auth/csrf")
        guard csrfResponse.statusCode == 200 else {
            throw api.parseAPIError(data: csrfData, status: csrfResponse.statusCode)
        }
        let csrf = try api.decode(CSRFResponse.self, from: csrfData)

        let form: [String: String] = [
            "csrfToken": csrf.csrfToken,
            "email": email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            "password": password,
            "callbackUrl": AppConfig.webBaseURL.absoluteString + "/profiles",
            "json": "true",
        ]

        let (data, response) = try await api.request(
            path: "api/auth/callback/credentials-viewer",
            method: "POST",
            formBody: form,
            acceptsJSON: true
        )

        if !(200...299).contains(response.statusCode) && response.statusCode != 302 {
            // Some NextAuth builds return 200 with URL / error JSON
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = obj["error"] as? String {
                throw APIError.server(error == "CredentialsSignin" ? "Invalid email or password." : error)
            }
            throw api.parseAPIError(data: data, status: response.statusCode)
        }

        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = obj["error"] as? String, !error.isEmpty {
            throw APIError.server(error == "CredentialsSignin" ? "Invalid email or password." : error)
        }

        guard let session = try await fetchSession(), session.user != nil else {
            throw APIError.server("Sign-in succeeded but no session was created.")
        }
        return session
    }

    func signOut() async {
        if let csrfData = try? await api.request(path: "api/auth/csrf").0,
           let csrf = try? api.decode(CSRFResponse.self, from: csrfData) {
            _ = try? await api.request(
                path: "api/auth/signout",
                method: "POST",
                formBody: [
                    "csrfToken": csrf.csrfToken,
                    "callbackUrl": AppConfig.webBaseURL.absoluteString,
                    "json": "true",
                ]
            )
        }
        api.clearCookies()
    }
}
