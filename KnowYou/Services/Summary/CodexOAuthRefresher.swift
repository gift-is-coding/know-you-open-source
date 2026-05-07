import Foundation

enum CodexOAuthRefreshError: Error, LocalizedError, Equatable {
    case requestFailed
    case invalidResponse
    case missingAccountID
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .requestFailed:
            return "Codex OAuth refresh failed. Sign in with Codex CLI, then retest Codex Auth."
        case .invalidResponse:
            return "Codex OAuth refresh returned an invalid response."
        case .missingAccountID:
            return "Codex OAuth refresh did not include a usable account identity."
        case .writeFailed:
            return "Codex OAuth credentials could not be updated."
        }
    }
}

struct CodexOAuthRefresher: Sendable {
    static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    static let tokenURL = URL(string: "https://auth.openai.com/oauth/token")!

    private let session: URLSession
    private let now: @Sendable () -> Date

    init(
        session: URLSession = .shared,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.session = session
        self.now = now
    }

    func refresh(
        _ credential: CodexOAuthCredential,
        using store: CodexAuthStore
    ) async throws -> CodexOAuthCredential {
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody(refreshToken: credential.refreshToken)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw CodexOAuthRefreshError.requestFailed
        }

        guard
            let httpResponse = response as? HTTPURLResponse,
            (200..<300).contains(httpResponse.statusCode)
        else {
            throw CodexOAuthRefreshError.requestFailed
        }

        let payload: RefreshResponse
        do {
            payload = try JSONDecoder().decode(RefreshResponse.self, from: data)
        } catch {
            throw CodexOAuthRefreshError.invalidResponse
        }

        guard
            !payload.accessToken.isEmpty,
            !payload.refreshToken.isEmpty,
            payload.expiresIn > 0
        else {
            throw CodexOAuthRefreshError.invalidResponse
        }

        guard let accountID = CodexJWT.accountID(from: payload.accessToken) else {
            throw CodexOAuthRefreshError.missingAccountID
        }

        let refreshedAt = now()
        let refreshed = CodexOAuthCredential(
            accessToken: payload.accessToken,
            refreshToken: payload.refreshToken,
            expiresAt: refreshedAt.addingTimeInterval(TimeInterval(payload.expiresIn)),
            accountID: accountID,
            source: credential.source
        )

        do {
            try store.writeCredential(refreshed, refreshedAt: refreshedAt)
        } catch {
            throw CodexOAuthRefreshError.writeFailed
        }

        return refreshed
    }

    private func formBody(refreshToken: String) -> Data {
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken),
        ]
        return Data((components.percentEncodedQuery ?? "").utf8)
    }
}

private struct RefreshResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}
