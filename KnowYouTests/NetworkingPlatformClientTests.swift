import XCTest
@testable import KnowYou

final class NetworkingPlatformClientTests: XCTestCase {
    func testSessionExpiryClassificationOnlyMatchesExplicitAuthFailures() {
        XCTAssertTrue(NetworkingPlatformClientError.invalidOrExpiredSession.requiresReauthentication)
        XCTAssertTrue(NetworkingPlatformClientError.httpError(status: 401, body: "expired JWT").requiresReauthentication)
        XCTAssertFalse(NetworkingPlatformClientError.httpError(status: 503, body: "unavailable").requiresReauthentication)
        XCTAssertFalse(NetworkingPlatformClientError.invalidResponse.requiresReauthentication)
    }

    func testRefreshSessionMapsUnprocessableTokenToReauthentication() {
        let recorder = TransportRecorder(responses: [.failure(status: 422, body: "expired")])
        var client = NetworkingPlatformClient(config: config)
        client.transport = recorder.transport

        XCTAssertThrowsError(try client.refreshSession(refreshToken: "expired-refresh")) { error in
            XCTAssertEqual(error as? NetworkingPlatformClientError, .invalidOrExpiredSession)
        }
    }

    private let config = NetworkingPlatformConfig(
        supabaseURL: URL(string: "https://example.supabase.co")!,
        publishableKey: "publishable-key"
    )
    private let machineAuthFixture = (
        email: "knw-machine@users.knowyou.app",
        passphrase: ["machine", "test", "pass"].joined(separator: "-")
    )

    func testTokenHashMatchesSHA256Hex() {
        XCTAssertEqual(
            NetworkingPlatformClient.tokenHash("abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    func testSignUpMachineUserUsesRestrictedFunctionThenPasswordSignIn() throws {
        let recorder = TransportRecorder(responses: [
            .json(["created": true]),
            .json([
                "access_token": "access-1",
                "refresh_token": "refresh-1",
                "user": ["id": "user-1"],
            ]),
        ])
        var client = NetworkingPlatformClient(config: config)
        client.transport = recorder.transport

        let session = try client.signUp(email: machineAuthFixture.email, password: machineAuthFixture.passphrase)

        XCTAssertEqual(session, NetworkingPlatformSession(accessToken: "access-1", refreshToken: "refresh-1", userID: "user-1"))
        XCTAssertEqual(recorder.requests.count, 2)
        let createRequest = recorder.requests[0]
        XCTAssertEqual(createRequest.httpMethod, "POST")
        XCTAssertEqual(createRequest.url?.path, "/functions/v1/networking-machine-signup")
        XCTAssertEqual(createRequest.value(forHTTPHeaderField: "apikey"), "publishable-key")
        XCTAssertEqual(createRequest.value(forHTTPHeaderField: "Authorization"), "Bearer publishable-key")
        let body = try bodyJSON(of: createRequest)
        XCTAssertEqual(body["email"] as? String, machineAuthFixture.email)
        XCTAssertEqual(body["password"] as? String, machineAuthFixture.passphrase)
        let signInRequest = recorder.requests[1]
        XCTAssertEqual(signInRequest.url?.path, "/auth/v1/token")
        XCTAssertTrue(signInRequest.url?.query?.contains("grant_type=password") ?? false)
        XCTAssertFalse(recorder.requests.contains { $0.url?.path == "/auth/v1/signup" })
    }

    func testPasswordSignInUsesPasswordGrantAndParsesSession() throws {
        let recorder = TransportRecorder(responses: [
            .json([
                "access_token": "access-2",
                "refresh_token": "refresh-2",
                "user": ["id": "user-2"],
            ]),
        ])
        var client = NetworkingPlatformClient(config: config)
        client.transport = recorder.transport

        let session = try client.signIn(email: machineAuthFixture.email, password: machineAuthFixture.passphrase)

        XCTAssertEqual(session, NetworkingPlatformSession(accessToken: "access-2", refreshToken: "refresh-2", userID: "user-2"))
        let request = try XCTUnwrap(recorder.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/auth/v1/token")
        XCTAssertTrue(request.url?.query?.contains("grant_type=password") ?? false)
        let body = try bodyJSON(of: request)
        XCTAssertEqual(body["email"] as? String, machineAuthFixture.email)
        XCTAssertEqual(body["password"] as? String, machineAuthFixture.passphrase)
    }

    func testRequestEmailOTPUsesPasswordlessAuthWithoutAccountEnumerationFields() throws {
        let recorder = TransportRecorder(responses: [.json([:])])
        var client = NetworkingPlatformClient(config: config)
        client.transport = recorder.transport

        try client.requestEmailOTP(email: "person@example.com")

        let request = try XCTUnwrap(recorder.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/auth/v1/otp")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer publishable-key")
        let body = try bodyJSON(of: request)
        XCTAssertEqual(body["email"] as? String, "person@example.com")
        XCTAssertEqual(body["create_user"] as? Bool, true)
        XCTAssertNil(body["password"])
    }

    func testVerifyEmailOTPUsesEmailTypeAndDecodesSession() throws {
        let recorder = TransportRecorder(responses: [.json([
            "access_token": "otp-access",
            "refresh_token": "otp-refresh",
            "user": ["id": "otp-user"],
        ])])
        var client = NetworkingPlatformClient(config: config)
        client.transport = recorder.transport

        let session = try client.verifyEmailOTP(email: "person@example.com", token: "481296")

        XCTAssertEqual(session, NetworkingPlatformSession(accessToken: "otp-access", refreshToken: "otp-refresh", userID: "otp-user"))
        let request = try XCTUnwrap(recorder.requests.first)
        XCTAssertEqual(request.url?.path, "/auth/v1/verify")
        let body = try bodyJSON(of: request)
        XCTAssertEqual(body["type"] as? String, "email")
        XCTAssertEqual(body["email"] as? String, "person@example.com")
        XCTAssertEqual(body["token"] as? String, "481296")
    }

    func testListAndRevokeDeviceUseAuthenticatedRPCs() throws {
        let recorder = TransportRecorder(responses: [
            .json([["id": "row-1", "device_id": "mac-1", "display_name": "MacBook Pro", "last_active_at": "2026-07-12T08:00:00Z", "revoked_at": NSNull()]]),
            .rawJSON("null"),
        ])
        var client = NetworkingPlatformClient(config: config)
        client.transport = recorder.transport
        let session = NetworkingPlatformSession(accessToken: "user-access", refreshToken: "refresh", userID: "user-1")

        let devices = try client.listDevices(session: session)
        try client.revokeDevice(session: session, deviceID: "mac-1")

        XCTAssertEqual(devices.map(\.deviceID), ["mac-1"])
        XCTAssertEqual(recorder.requests.map { $0.url?.path }, [
            "/rest/v1/rpc/networking_list_devices",
            "/rest/v1/rpc/networking_revoke_device",
        ])
        XCTAssertTrue(recorder.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer user-access" })
        let revokeBody = try bodyJSON(of: recorder.requests[1])
        XCTAssertEqual(revokeBody["p_device_id"] as? String, "mac-1")
    }

    func testHandoffURLUsesOneTimeTokenAndNeverEmbedsSessionTokens() throws {
        let config = NetworkingBackendConfiguration(
            supabaseURL: URL(string: "https://example.supabase.co")!,
            publishableKey: "publishable-key",
            webBaseURL: URL(string: "https://networking.knowyou.app")!
        )
        let url = try NetworkingWebHandoffURLBuilder(configuration: config)
            .handoffURL(
                handoff: NetworkingWebHandoff(
                    tokenHash: "one-time-token-hash",
                    handoffSecret: "one-time-device-binding-secret"
                ),
                platformID: "knowyou-jobs"
            )

        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "networking.knowyou.app")
        XCTAssertEqual(url.path, "/auth/handoff")
        XCTAssertNil(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertTrue(url.fragment?.contains("token_hash=one-time-token-hash") == true)
        XCTAssertTrue(url.fragment?.contains("handoff_secret=one-time-device-binding-secret") == true)
        XCTAssertFalse(url.absoluteString.contains("access-token"))
        XCTAssertFalse(url.absoluteString.contains("refresh-token"))
        XCTAssertTrue(url.fragment?.contains("platform=knowyou-jobs") == true)
    }

    func testCreateWebHandoffUsesAuthenticatedEdgeFunctionAndReturnsOneTimeHash() throws {
        let recorder = TransportRecorder(responses: [.json([
            "token_hash": "one-time-token-hash",
            "handoff_secret": "one-time-device-binding-secret",
        ])])
        var client = NetworkingPlatformClient(config: config)
        client.transport = recorder.transport
        let session = NetworkingPlatformSession(accessToken: "access-token", refreshToken: "refresh-token", userID: "user-1")

        let handoff = try client.createWebHandoff(
            session: session,
            deviceID: "device-uuid",
            deviceToken: "device-token"
        )

        XCTAssertEqual(handoff.tokenHash, "one-time-token-hash")
        XCTAssertEqual(handoff.handoffSecret, "one-time-device-binding-secret")
        let request = try XCTUnwrap(recorder.requests.first)
        XCTAssertEqual(request.url?.path, "/functions/v1/networking-web-handoff")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
        XCTAssertFalse(String(decoding: request.httpBody ?? Data(), as: UTF8.self).contains("refresh-token"))
        let body = try bodyJSON(of: request)
        XCTAssertEqual(body["device_id"] as? String, "device-uuid")
        XCTAssertEqual(body["device_token"] as? String, "device-token")
    }

    func testBindCurrentDeviceSessionHashesTheDeviceCredential() throws {
        let recorder = TransportRecorder(responses: [.json([:])])
        var client = NetworkingPlatformClient(config: config)
        client.transport = recorder.transport
        let session = NetworkingPlatformSession(
            accessToken: "access-token",
            refreshToken: "refresh-token",
            userID: "user-1"
        )

        try client.bindCurrentDeviceSession(
            session: session,
            deviceID: "device-uuid",
            deviceToken: "device-token"
        )

        let request = try XCTUnwrap(recorder.requests.first)
        XCTAssertEqual(request.url?.path, "/rest/v1/rpc/networking_bind_current_device_session")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
        let body = try bodyJSON(of: request)
        XCTAssertEqual(body["p_device_id"] as? String, "device-uuid")
        XCTAssertEqual(
            body["p_device_token_hash"] as? String,
            NetworkingPlatformClient.tokenHash("device-token")
        )
        XCTAssertFalse(String(decoding: request.httpBody ?? Data(), as: UTF8.self).contains("\"device-token\""))
    }

    func testBackendConfigurationResolvedUsesConfiguredWebBaseURL() throws {
        let processInfo = StubProcessInfo(
            environment: [
                "KNOWYOU_NETWORKING_WEB_BASE_URL": "https://networking.knowyou.app",
            ]
        )

        let resolved = try XCTUnwrap(
            NetworkingBackendConfiguration.resolved(
                processInfo: processInfo,
                fallbackPlatformConfig: config
            )
        )

        XCTAssertEqual(resolved.supabaseURL, config.supabaseURL)
        XCTAssertEqual(resolved.publishableKey, config.publishableKey)
        XCTAssertEqual(resolved.webBaseURL, URL(string: "https://networking.knowyou.app"))
    }

    func testBackendConfigurationResolvedUsesPlatformFileWebBaseURLWithoutEnvironment() throws {
        var platformConfig = config
        platformConfig.webBaseURL = URL(string: "https://networking.giiift.site")!
        let resolved = try XCTUnwrap(NetworkingBackendConfiguration.resolved(
            processInfo: StubProcessInfo(environment: [:]),
            fallbackPlatformConfig: platformConfig
        ))
        XCTAssertEqual(resolved.webBaseURL, URL(string: "https://networking.giiift.site"))
    }

    func testBackendConfigurationResolvedFallsBackToLocalhostOnlyInDebugBuilds() {
        let processInfo = StubProcessInfo(environment: [:])
        let resolved = NetworkingBackendConfiguration.resolved(
            processInfo: processInfo,
            fallbackPlatformConfig: config
        )

        #if DEBUG
        XCTAssertEqual(resolved?.webBaseURL, URL(string: "http://127.0.0.1:3028"))
        #else
        XCTAssertNil(resolved)
        #endif
    }

    func testBundledPlatformConfigProvidesProductionBackendAndReleaseWebURL() {
        XCTAssertEqual(NetworkingPlatformConfig.bundledDefault.supabaseURL.host, "jevgtiamxlkucjqpbekn.supabase.co")
        XCTAssertFalse(NetworkingPlatformConfig.bundledDefault.publishableKey.isEmpty)
        #if DEBUG
        XCTAssertNil(NetworkingPlatformConfig.bundledDefault.webBaseURL)
        #else
        XCTAssertEqual(NetworkingPlatformConfig.bundledDefault.webBaseURL, URL(string: "https://networking.giiift.site"))
        #endif
    }

    func testPlatformConfigStoreFallsBackToBundledDefaultWhenFileIsCorrupt() throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appending(path: "networking-config-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: projectRoot) }
        let store = NetworkingPlatformConfigStore()
        let configURL = store.configURL(projectRoot: projectRoot)
        try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{not-json".utf8).write(to: configURL)

        XCTAssertEqual(store.load(projectRoot: projectRoot), .bundledDefault)
    }

    func testCreateAgentCommentSendsExplicitNullParent() throws {
        let recorder = TransportRecorder(responses: [.rawJSON("\"comment-uuid\"")])
        var client = NetworkingPlatformClient(config: config)
        client.transport = recorder.transport
        let sample = "unit-test-agent-value"

        let commentID = try client.createAgentComment(
            token: sample,
            postID: "post-uuid",
            parentCommentID: nil,
            profileID: "profile-uuid",
            platformID: "knowyou-jobs",
            body: "hello",
            clientDecisionID: "profile-uuid:post-uuid:root"
        )

        XCTAssertEqual(commentID, "comment-uuid")
        let request = try XCTUnwrap(recorder.requests.first)
        XCTAssertEqual(request.url?.path, "/rest/v1/rpc/networking_agent_create_comment")
        let body = try bodyJSON(of: request)
        XCTAssertTrue(body.keys.contains("p_parent_comment_id"))
        XCTAssertTrue(body["p_parent_comment_id"] is NSNull)
    }

    func testUpdateMembershipAutonomyModeCallsOwnerValidatedRPC() throws {
        let recorder = TransportRecorder(responses: [.rawJSON("null")])
        var client = NetworkingPlatformClient(config: config)
        client.transport = recorder.transport
        let session = NetworkingPlatformSession(accessToken: "access-1", refreshToken: "refresh-1", userID: "user-1")

        try client.updateMembershipAutonomyMode(
            session: session,
            profileID: "profile-uuid",
            communityID: "knowyou-friends",
            mode: "active"
        )

        let request = try XCTUnwrap(recorder.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/rest/v1/rpc/networking_update_autonomy_mode")
        let body = try bodyJSON(of: request)
        XCTAssertEqual(body["p_profile_id"] as? String, "profile-uuid")
        XCTAssertEqual(body["p_platform_id"] as? String, "knowyou-friends")
        XCTAssertEqual(body["p_mode"] as? String, "active")
    }

    func testAgentHomeReturnsDecodedObject() throws {
        let recorder = TransportRecorder(responses: [
            .json([
                "profileID": "profile-uuid",
                "needsReply": [],
                "potentialMatches": [["postID": "post-1"]],
                "savedForYou": [],
            ]),
        ])
        var client = NetworkingPlatformClient(config: config)
        client.transport = recorder.transport
        let sample = "unit-test-agent-value"

        let home = try client.agentHome(token: sample, platformID: "knowyou-jobs")

        XCTAssertEqual(home["profileID"] as? String, "profile-uuid")
        XCTAssertEqual((home["potentialMatches"] as? [[String: Any]])?.count, 1)
    }

    func testRecordAgentDecisionPostsBoundedPublicDecisionPayload() throws {
        let recorder = TransportRecorder(responses: [.rawJSON("\"decision-uuid\"")])
        var client = NetworkingPlatformClient(config: config)
        client.transport = recorder.transport
        let sample = "unit-test-agent-value"

        let decisionID = try client.recordAgentDecision(
            token: sample,
            profileID: "profile-uuid",
            platformID: "knowyou-jobs",
            publicReferenceType: "post",
            publicReferenceID: "post-uuid",
            action: "save_for_human",
            publicSummary: "Looks relevant, but needs human review.",
            reasonCodes: ["watching_community", "risky_content"],
            clientDecisionID: "decision-client-id"
        )

        XCTAssertEqual(decisionID, "decision-uuid")
        let request = try XCTUnwrap(recorder.requests.first)
        XCTAssertEqual(request.url?.path, "/rest/v1/rpc/networking_agent_record_decision")
        let body = try bodyJSON(of: request)
        XCTAssertEqual(body["p_action"] as? String, "save_for_human")
        XCTAssertEqual(body["p_public_reference_id"] as? String, "post-uuid")
        XCTAssertEqual(body["p_reason_codes"] as? [String], ["watching_community", "risky_content"])
    }

    func testHTTPErrorSurfacesStatusAndBody() {
        let recorder = TransportRecorder(responses: [.failure(status: 401, body: "invalid token")])
        var client = NetworkingPlatformClient(config: config)
        client.transport = recorder.transport

        XCTAssertThrowsError(try client.agentHome(token: "bad", platformID: "knowyou-jobs")) { error in
            guard case let NetworkingPlatformClientError.httpError(status, body) = error else {
                return XCTFail("unexpected error \(error)")
            }
            XCTAssertEqual(status, 401)
            XCTAssertTrue(body.contains("invalid token"))
        }
    }

    func testActivationRunnerUsesVerifiedSessionAndRegistersDevice() throws {
        let recorder = TransportRecorder(responses: [
            .rawJSON("\"person-uuid\""),
            .json([["id": "career-uuid"]]),
            .json([]),
        ])
        var client = NetworkingPlatformClient(config: config)
        client.transport = recorder.transport
        var runner = NetworkingActivationRunner(client: client)
        runner.tokenGenerator = { "knw_agent_fixed" }
        runner.deviceTokenGenerator = { "device-token-fixed" }

        let state = try runner.activate(
            session: NetworkingPlatformSession(accessToken: "access-1", refreshToken: "refresh-1", userID: "user-1"),
            email: "person@example.com",
            deviceID: "device-uuid",
            deviceDisplayName: "Tianfu's Mac",
            personName: "Tianfu Wu",
            handle: "tianfu-wu",
            approvedProfiles: [
                NetworkingProfileRegistration(
                    localProfileID: "profile-career",
                    slug: "career",
                    label: "Career / Hiring",
                    scenarioID: "jobs",
                    scenarioDescription: "For hiring and collaborations.",
                    summary: "Building KnowYou.",
                    body: "Long profile body.",
                    platformIDs: ["knowyou-jobs"]
                ),
            ]
        )

        XCTAssertTrue(state.isEnabled)
        XCTAssertEqual(state.mode, .platform)
        XCTAssertEqual(state.personID, "person-uuid")
        XCTAssertEqual(state.userID, "user-1")
        XCTAssertEqual(state.authEmail, "person@example.com")
        XCTAssertNil(state.authPassword)
        XCTAssertEqual(state.deviceID, "device-uuid")
        XCTAssertEqual(state.deviceToken, "device-token-fixed")
        XCTAssertEqual(state.agentTokenPlaintext, "knw_agent_fixed")
        XCTAssertEqual(state.platformProfileID(forLocalProfileID: "profile-career"), "career-uuid")
        XCTAssertEqual(recorder.requests.count, 3)
        XCTAssertFalse(recorder.requests.contains { $0.url?.path.contains("auth/v1") == true })
        let deviceRequest = try XCTUnwrap(recorder.requests.first { $0.url?.path == "/rest/v1/rpc/networking_begin_activation" })
        let deviceBody = try bodyJSON(of: deviceRequest)
        XCTAssertEqual(deviceBody["p_display_name"] as? String, "Tianfu Wu")
        XCTAssertEqual(deviceBody["p_handle"] as? String, "tianfu-wu")
        XCTAssertEqual(deviceBody["p_device_token_hash"] as? String, NetworkingPlatformClient.tokenHash("device-token-fixed"))
        XCTAssertEqual(deviceBody["p_agent_token_hash"] as? String, NetworkingPlatformClient.tokenHash("knw_agent_fixed"))
    }

    func testActivationRunnerReportsDeviceAuthorizationFailureWithoutAuthFallback() {
        let recorder = TransportRecorder(responses: [
            .failure(status: 409, body: "device limit reached"),
        ])
        var client = NetworkingPlatformClient(config: config)
        client.transport = recorder.transport
        let runner = NetworkingActivationRunner(client: client)

        XCTAssertThrowsError(
            try runner.activate(
                session: NetworkingPlatformSession(accessToken: "access", refreshToken: "refresh", userID: "user"),
                email: "person@example.com",
                deviceID: "device-uuid",
                deviceDisplayName: "My Mac",
                personName: "Tianfu Wu",
                handle: "tianfu-wu",
                approvedProfiles: []
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("authorizing this Mac"))
            XCTAssertTrue(error.localizedDescription.contains("three active devices"))
        }
        XCTAssertFalse(recorder.requests.contains { $0.url?.path.contains("auth/v1") == true })
        XCTAssertEqual(recorder.requests.map(\.url?.path), ["/rest/v1/rpc/networking_begin_activation"])
        XCTAssertFalse(recorder.requests.contains { $0.url?.path == "/rest/v1/people" || $0.url?.path == "/rest/v1/profiles" })
    }

    func testActivationStateDecodesLegacyJSONWithoutNewFields() throws {
        let legacy = """
        {
          "isEnabled": true,
          "personID": "local-tianfu",
          "agentTokenPlaintext": "knw_agent_local_x",
          "supabaseURL": "https://local.knowyou.invalid",
          "publishableKey": "local-dev"
        }
        """
        let state = try JSONDecoder().decode(NetworkingActivationState.self, from: Data(legacy.utf8))

        XCTAssertEqual(state.mode, .localSandbox)
        XCTAssertNil(state.userID)
        XCTAssertNil(state.authEmail)
        XCTAssertNil(state.authPassword)
        XCTAssertTrue(state.profileIDMapping.isEmpty)
        XCTAssertFalse(state.isPlatformConnected)
    }

    private func bodyJSON(of request: URLRequest) throws -> [String: Any] {
        let data = try XCTUnwrap(request.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

private final class StubProcessInfo: ProcessInfo, @unchecked Sendable {
    private let stubEnvironment: [String: String]

    init(environment: [String: String]) {
        self.stubEnvironment = environment
        super.init()
    }

    override var environment: [String: String] {
        stubEnvironment
    }
}

private final class TransportRecorder: @unchecked Sendable {
    enum StubResponse {
        case json(Any)
        case rawJSON(String)
        case failure(status: Int, body: String)
    }

    private let lock = NSLock()
    private var recordedRequests: [URLRequest] = []
    private var responses: [StubResponse]

    init(responses: [StubResponse]) {
        self.responses = responses
    }

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recordedRequests
    }

    var transport: NetworkingPlatformTransport {
        { [self] request in
            lock.lock()
            recordedRequests.append(request)
            let stub = responses.isEmpty ? StubResponse.failure(status: 599, body: "no stub") : responses.removeFirst()
            lock.unlock()
            switch stub {
            case let .json(json):
                let data = try JSONSerialization.data(withJSONObject: json)
                return (data, httpResponse(for: request, status: 200))
            case let .rawJSON(rawJSON):
                return (Data(rawJSON.utf8), httpResponse(for: request, status: 200))
            case let .failure(status: status, body: body):
                return (Data(body.utf8), httpResponse(for: request, status: status))
            }
        }
    }

    private func httpResponse(for request: URLRequest, status: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.supabase.co")!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
    }
}
