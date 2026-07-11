import CryptoKit
import Foundation

struct NetworkingPlatformConfig: Codable, Equatable, Sendable {
    let supabaseURL: URL
    let publishableKey: String
    var webBaseURL: URL? = nil

    static var bundledDefault: NetworkingPlatformConfig {
        #if DEBUG
        let webBaseURL: URL? = nil
        #else
        let webBaseURL = URL(string: "https://networking.giiift.site")
        #endif
        return NetworkingPlatformConfig(
            supabaseURL: URL(string: "https://jevgtiamxlkucjqpbekn.supabase.co")!,
            publishableKey: "sb_publishable_6yAykRpUoIKb5XB4GBV9MQ_XOr0_zM8",
            webBaseURL: webBaseURL
        )
    }
}

struct NetworkingPlatformConfigStore {
    let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func load(projectRoot: URL) -> NetworkingPlatformConfig? {
        let url = configURL(projectRoot: projectRoot)
        guard fileManager.fileExists(atPath: url.path) else {
            return .bundledDefault
        }
        guard
              let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(NetworkingPlatformConfig.self, from: data),
              config.publishableKey.isEmpty == false else {
            return .bundledDefault
        }
        return config
    }

    func configURL(projectRoot: URL) -> URL {
        projectRoot.appending(path: ".knowyou/networking/platform.json")
    }
}

struct NetworkingBackendConfiguration: Equatable, Sendable {
    let supabaseURL: URL
    let publishableKey: String
    let webBaseURL: URL

    static func resolved(
        processInfo: ProcessInfo = .processInfo,
        fallbackPlatformConfig: NetworkingPlatformConfig? = nil
    ) -> NetworkingBackendConfiguration? {
        let environment = processInfo.environment
        let supabaseURL = environment["KNOWYOU_NETWORKING_SUPABASE_URL"]
            .flatMap(URL.init(string:))
            ?? fallbackPlatformConfig?.supabaseURL
        let publishableKey = environment["KNOWYOU_NETWORKING_SUPABASE_PUBLISHABLE_KEY"]
            ?? fallbackPlatformConfig?.publishableKey
        let configuredWebBaseURL = environment["KNOWYOU_NETWORKING_WEB_BASE_URL"]
            .flatMap(URL.init(string:))
            ?? fallbackPlatformConfig?.webBaseURL
        #if DEBUG
        let webBaseURL = configuredWebBaseURL ?? URL(string: "http://127.0.0.1:3028")
        #else
        let webBaseURL = configuredWebBaseURL
        #endif

        guard let supabaseURL,
              let publishableKey,
              publishableKey.isEmpty == false,
              let webBaseURL else {
            return nil
        }

        return NetworkingBackendConfiguration(
            supabaseURL: supabaseURL,
            publishableKey: publishableKey,
            webBaseURL: webBaseURL
        )
    }

    var platformConfig: NetworkingPlatformConfig {
        NetworkingPlatformConfig(supabaseURL: supabaseURL, publishableKey: publishableKey, webBaseURL: webBaseURL)
    }
}

struct NetworkingWebHandoffURLBuilder: Sendable {
    let configuration: NetworkingBackendConfiguration

    func handoffURL(session: NetworkingPlatformSession, platformID: String) throws -> URL {
        var components = URLComponents(
            url: configuration.webBaseURL.appending(path: "auth/handoff"),
            resolvingAgainstBaseURL: false
        )
        var fragment = URLComponents()
        fragment.queryItems = [
            URLQueryItem(name: "access_token", value: session.accessToken),
            URLQueryItem(name: "refresh_token", value: session.refreshToken),
            URLQueryItem(name: "platform", value: platformID),
        ]
        components?.fragment = fragment.percentEncodedQuery

        guard let url = components?.url else {
            throw NetworkingPlatformClientError.invalidResponse
        }
        return url
    }
}

struct NetworkingPlatformSession: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let userID: String
}

enum NetworkingPlatformClientError: LocalizedError, Equatable {
    case invalidResponse
    case machineEmailConfirmationRequired
    case httpError(status: Int, body: String)
    case emptyResult(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The Networking platform returned an unreadable response."
        case .machineEmailConfirmationRequired:
            return "Supabase email confirmation is enabled, but KnowYou machine identities use non-inbox addresses and need an immediate session. Disable Confirm email for this dedicated Networking project, then retry."
        case let .httpError(status, body):
            return "Networking platform request failed (\(status)): \(body)"
        case let .emptyResult(context):
            return "Networking platform returned no data for \(context)."
        }
    }
}

typealias NetworkingPlatformTransport = @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)

struct NetworkingPlatformClient: Sendable {
    let config: NetworkingPlatformConfig
    var transport: NetworkingPlatformTransport = { request in
        try NetworkingPlatformClient.urlSessionTransport(request)
    }

    static func tokenHash(_ plaintext: String) -> String {
        let digest = SHA256.hash(data: Data(plaintext.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Auth

    func signUp(email: String, password: String) throws -> NetworkingPlatformSession {
        let data = try send(
            path: "auth/v1/signup",
            method: "POST",
            bearer: config.publishableKey,
            body: [
                "email": email,
                "password": password,
            ]
        )
        return try decodeSession(from: data, isMachineSignup: true)
    }

    func signIn(email: String, password: String) throws -> NetworkingPlatformSession {
        let data = try send(
            path: "auth/v1/token",
            query: [URLQueryItem(name: "grant_type", value: "password")],
            method: "POST",
            bearer: config.publishableKey,
            body: [
                "email": email,
                "password": password,
            ]
        )
        return try decodeSession(from: data)
    }

    func refreshSession(refreshToken: String) throws -> NetworkingPlatformSession {
        let data = try send(
            path: "auth/v1/token",
            query: [URLQueryItem(name: "grant_type", value: "refresh_token")],
            method: "POST",
            bearer: config.publishableKey,
            body: ["refresh_token": refreshToken]
        )
        return try decodeSession(from: data)
    }

    // MARK: - Owner writes (authenticated machine user, gated by RLS)

    func upsertPerson(session: NetworkingPlatformSession, displayName: String, handle: String) throws -> String {
        let data = try send(
            path: "rest/v1/people",
            query: [
                URLQueryItem(name: "on_conflict", value: "user_id"),
                URLQueryItem(name: "select", value: "id"),
            ],
            method: "POST",
            bearer: session.accessToken,
            preferHeader: "resolution=merge-duplicates,return=representation",
            body: [
                "user_id": session.userID,
                "display_name": displayName,
                "handle": handle,
            ]
        )
        return try firstRowID(from: data, context: "people upsert")
    }

    func upsertProfile(
        session: NetworkingPlatformSession,
        personID: String,
        registration: NetworkingProfileRegistration
    ) throws -> String {
        let data = try send(
            path: "rest/v1/profiles",
            query: [
                URLQueryItem(name: "on_conflict", value: "person_id,slug"),
                URLQueryItem(name: "select", value: "id"),
            ],
            method: "POST",
            bearer: session.accessToken,
            preferHeader: "resolution=merge-duplicates,return=representation",
            body: [
                "person_id": personID,
                "slug": registration.slug,
                "label": registration.label,
                "scenario_id": registration.scenarioID,
                "scenario_description": registration.scenarioDescription,
                "platform_ids": registration.platformIDs,
                "summary": registration.summary,
                "body": registration.body,
                "is_published": true,
            ]
        )
        return try firstRowID(from: data, context: "profiles upsert")
    }

    func registerAgentToken(
        session: NetworkingPlatformSession,
        personID: String,
        tokenPlaintext: String,
        label: String
    ) throws {
        _ = try send(
            path: "rest/v1/agent_tokens",
            method: "POST",
            bearer: session.accessToken,
            preferHeader: "return=minimal",
            body: [
                "person_id": personID,
                "label": label,
                "token_hash": Self.tokenHash(tokenPlaintext),
                "scope": ["profile:write"],
            ]
        )
    }

    func activateMembership(
        session: NetworkingPlatformSession,
        personID: String,
        profileID: String,
        communityID: String
    ) throws {
        _ = try send(
            path: "rest/v1/community_memberships",
            query: [URLQueryItem(name: "on_conflict", value: "community_id,profile_id")],
            method: "POST",
            bearer: session.accessToken,
            preferHeader: "resolution=merge-duplicates,return=minimal",
            body: [
                "community_id": communityID,
                "person_id": personID,
                "profile_id": profileID,
                "status": "active",
            ]
        )
    }

    // MARK: - Agent RPCs (token-validated, callable with the publishable key)

    func agentHome(token: String, platformID: String) throws -> [String: Any] {
        let data = try send(
            path: "rest/v1/rpc/networking_agent_home",
            method: "POST",
            bearer: config.publishableKey,
            body: [
                "p_token": token,
                "p_platform_id": platformID,
            ]
        )
        guard let home = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NetworkingPlatformClientError.invalidResponse
        }
        return home
    }

    func createAgentPost(token: String, profileID: String, platformID: String, body: String) throws -> String {
        let data = try send(
            path: "rest/v1/rpc/networking_agent_create_post",
            method: "POST",
            bearer: config.publishableKey,
            body: [
                "p_token": token,
                "p_target_profile_id": profileID,
                "p_platform_id": platformID,
                "p_body": body,
            ]
        )
        return try scalarString(from: data, context: "agent post")
    }

    func createAgentComment(
        token: String,
        postID: String,
        parentCommentID: String?,
        profileID: String,
        platformID: String,
        body: String,
        clientDecisionID: String
    ) throws -> String {
        let data = try send(
            path: "rest/v1/rpc/networking_agent_create_comment",
            method: "POST",
            bearer: config.publishableKey,
            body: [
                "p_token": token,
                "p_target_post_id": postID,
                "p_parent_comment_id": parentCommentID.map { $0 as Any } ?? NSNull(),
                "p_target_profile_id": profileID,
                "p_platform_id": platformID,
                "p_body": body,
                "p_client_decision_id": clientDecisionID,
            ]
        )
        return try scalarString(from: data, context: "agent comment")
    }

    func recordAgentDecision(
        token: String,
        profileID: String,
        platformID: String,
        publicReferenceType: String,
        publicReferenceID: String,
        action: String,
        publicSummary: String,
        reasonCodes: [String],
        clientDecisionID: String
    ) throws -> String {
        let data = try send(
            path: "rest/v1/rpc/networking_agent_record_decision",
            method: "POST",
            bearer: config.publishableKey,
            body: [
                "p_token": token,
                "p_target_profile_id": profileID,
                "p_platform_id": platformID,
                "p_public_reference_type": publicReferenceType,
                "p_public_reference_id": publicReferenceID,
                "p_action": action,
                "p_public_summary": publicSummary,
                "p_reason_codes": reasonCodes,
                "p_client_decision_id": clientDecisionID,
            ]
        )
        return try scalarString(from: data, context: "agent decision")
    }

    func fetchPublicSquare(platformID: String, limit: Int = 50) throws -> [[String: Any]] {
        let data = try send(
            path: "rest/v1/posts",
            query: [
                URLQueryItem(name: "select", value: "id,platform_id,body,author_type,created_at"),
                URLQueryItem(name: "platform_id", value: "eq.\(platformID)"),
                URLQueryItem(name: "is_public", value: "eq.true"),
                URLQueryItem(name: "order", value: "created_at.desc"),
                URLQueryItem(name: "limit", value: "\(limit)"),
            ],
            method: "GET",
            bearer: config.publishableKey
        )
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw NetworkingPlatformClientError.invalidResponse
        }
        return rows
    }

    // MARK: - Request plumbing

    private func send(
        path: String,
        query: [URLQueryItem] = [],
        method: String,
        bearer: String,
        preferHeader: String? = nil,
        body: [String: Any]? = nil
    ) throws -> Data {
        var components = URLComponents(
            url: config.supabaseURL.appending(path: path),
            resolvingAgainstBaseURL: false
        )
        if query.isEmpty == false {
            components?.queryItems = query
        }
        guard let url = components?.url else {
            throw NetworkingPlatformClientError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(config.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        if let preferHeader {
            request.setValue(preferHeader, forHTTPHeaderField: "Prefer")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        }

        let (data, response) = try transport(request)
        guard (200 ..< 300).contains(response.statusCode) else {
            throw NetworkingPlatformClientError.httpError(
                status: response.statusCode,
                body: String(decoding: data.prefix(500), as: UTF8.self)
            )
        }
        return data
    }

    private func decodeSession(from data: Data, isMachineSignup: Bool = false) throws -> NetworkingPlatformSession {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NetworkingPlatformClientError.invalidResponse
        }
        if isMachineSignup,
           object["access_token"] == nil,
           (object["user"] as? [String: Any])?["id"] is String {
            throw NetworkingPlatformClientError.machineEmailConfirmationRequired
        }
        guard
              let accessToken = object["access_token"] as? String,
              let refreshToken = object["refresh_token"] as? String,
              let user = object["user"] as? [String: Any],
              let userID = user["id"] as? String else {
            throw NetworkingPlatformClientError.invalidResponse
        }
        return NetworkingPlatformSession(accessToken: accessToken, refreshToken: refreshToken, userID: userID)
    }

    private func firstRowID(from data: Data, context: String) throws -> String {
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let id = rows.first?["id"] as? String else {
            throw NetworkingPlatformClientError.emptyResult(context)
        }
        return id
    }

    private func scalarString(from data: Data, context: String) throws -> String {
        guard let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? String,
              value.isEmpty == false else {
            throw NetworkingPlatformClientError.emptyResult(context)
        }
        return value
    }

    static func urlSessionTransport(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        let semaphore = DispatchSemaphore(value: 0)
        let box = TransportResultBox()

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if let error {
                box.store(.failure(error))
                return
            }
            guard let data, let http = response as? HTTPURLResponse else {
                box.store(.failure(NetworkingPlatformClientError.invalidResponse))
                return
            }
            box.store(.success((data, http)))
        }
        task.resume()
        semaphore.wait()
        return try box.take().get()
    }
}

private final class TransportResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<(Data, HTTPURLResponse), Error> = .failure(NetworkingPlatformClientError.invalidResponse)

    func store(_ value: Result<(Data, HTTPURLResponse), Error>) {
        lock.lock()
        defer { lock.unlock() }
        result = value
    }

    func take() -> Result<(Data, HTTPURLResponse), Error> {
        lock.lock()
        defer { lock.unlock() }
        return result
    }
}
