import XCTest
@testable import KnowYou

final class NetworkingPlatformClientTests: XCTestCase {
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

    func testHandoffURLUsesFragmentSessionAndPlatformThenOmitsTokensFromQuery() throws {
        let config = NetworkingBackendConfiguration(
            supabaseURL: URL(string: "https://example.supabase.co")!,
            publishableKey: "publishable-key",
            webBaseURL: URL(string: "https://networking.knowyou.app")!
        )
        let session = NetworkingPlatformSession(accessToken: "access-token", refreshToken: "refresh-token", userID: "user-1")

        let url = try NetworkingWebHandoffURLBuilder(configuration: config)
            .handoffURL(session: session, platformID: "knowyou-jobs")

        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "networking.knowyou.app")
        XCTAssertEqual(url.path, "/auth/handoff")
        XCTAssertNil(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertTrue(url.fragment?.contains("access_token=access-token") == true)
        XCTAssertTrue(url.fragment?.contains("refresh_token=refresh-token") == true)
        XCTAssertTrue(url.fragment?.contains("platform=knowyou-jobs") == true)
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

    func testUpsertPersonUsesMergeDuplicatesAndReturnsRowID() throws {
        let recorder = TransportRecorder(responses: [
            .json([["id": "person-uuid"]]),
        ])
        var client = NetworkingPlatformClient(config: config)
        client.transport = recorder.transport
        let session = NetworkingPlatformSession(accessToken: "access-1", refreshToken: "refresh-1", userID: "user-1")

        let personID = try client.upsertPerson(session: session, displayName: "Tianfu Wu", handle: "tianfu-wu")

        XCTAssertEqual(personID, "person-uuid")
        let request = try XCTUnwrap(recorder.requests.first)
        XCTAssertEqual(request.url?.path, "/rest/v1/people")
        XCTAssertTrue(request.url?.query?.contains("on_conflict=user_id") ?? false)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Prefer"), "resolution=merge-duplicates,return=representation")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-1")
        let body = try bodyJSON(of: request)
        XCTAssertEqual(body["user_id"] as? String, "user-1")
        XCTAssertEqual(body["handle"] as? String, "tianfu-wu")
    }

    func testRegisterAgentTokenSendsHashNotPlaintext() throws {
        let recorder = TransportRecorder(responses: [.json([])])
        var client = NetworkingPlatformClient(config: config)
        client.transport = recorder.transport
        let session = NetworkingPlatformSession(accessToken: "access-1", refreshToken: "refresh-1", userID: "user-1")

        try client.registerAgentToken(
            session: session,
            personID: "person-uuid",
            tokenPlaintext: "knw_agent_secret",
            label: "Local KnowYou Networking agent"
        )

        let request = try XCTUnwrap(recorder.requests.first)
        XCTAssertEqual(request.url?.path, "/rest/v1/agent_tokens")
        let body = try bodyJSON(of: request)
        XCTAssertEqual(body["token_hash"] as? String, NetworkingPlatformClient.tokenHash("knw_agent_secret"))
        XCTAssertEqual(body["scope"] as? [String], ["profile:write"])
        let raw = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        XCTAssertFalse(raw.contains("knw_agent_secret"))
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

    func testActivationRunnerHappyPathBuildsPlatformState() throws {
        let recorder = TransportRecorder(responses: [
            .json(["created": true]),
            .json([
                "access_token": "access-1",
                "refresh_token": "refresh-1",
                "user": ["id": "user-1"],
            ]),
            .json([["id": "person-uuid"]]),
            .json([["id": "career-uuid"]]),
            .json([]),
            .json([]),
        ])
        var client = NetworkingPlatformClient(config: config)
        client.transport = recorder.transport
        var runner = NetworkingActivationRunner(client: client)
        let authFixture = machineAuthFixture
        runner.tokenGenerator = { "knw_agent_fixed" }
        runner.credentialGenerator = { _ in
            NetworkingMachineCredentials(
                email: authFixture.email,
                password: authFixture.passphrase
            )
        }

        let state = try runner.activate(
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
        XCTAssertEqual(state.authEmail, authFixture.email)
        XCTAssertEqual(state.authPassword, authFixture.passphrase)
        XCTAssertEqual(state.agentTokenPlaintext, "knw_agent_fixed")
        XCTAssertEqual(state.platformProfileID(forLocalProfileID: "profile-career"), "career-uuid")
        XCTAssertEqual(recorder.requests.count, 6)
        XCTAssertEqual(recorder.requests.last?.url?.path, "/rest/v1/community_memberships")
    }

    func testActivationRunnerReusesStoredMachineCredentialsWithSignIn() throws {
        let recorder = TransportRecorder(responses: [
            .json([
                "access_token": "access-existing",
                "refresh_token": "refresh-existing",
                "user": ["id": "user-existing"],
            ]),
            .json([["id": "person-uuid"]]),
            .json([]),
        ])
        var client = NetworkingPlatformClient(config: config)
        client.transport = recorder.transport
        var runner = NetworkingActivationRunner(client: client)
        let unusedCredential = ["unused"].joined()
        runner.credentialGenerator = { _ in
            XCTFail("stored credentials should be used instead of generating a fresh machine user")
            return NetworkingMachineCredentials(email: "unused@example.com", password: unusedCredential)
        }
        let previousState = NetworkingActivationState(
            isEnabled: true,
            personID: "person-uuid",
            agentTokenPlaintext: "old-agent-token",
            supabaseURL: config.supabaseURL,
            publishableKey: config.publishableKey,
            authEmail: machineAuthFixture.email,
            authPassword: machineAuthFixture.passphrase,
            mode: .platform
        )

        let state = try runner.activate(
            personName: "Tianfu Wu",
            handle: "tianfu-wu",
            approvedProfiles: [],
            previousState: previousState
        )

        XCTAssertEqual(state.authEmail, machineAuthFixture.email)
        XCTAssertEqual(state.authPassword, machineAuthFixture.passphrase)
        XCTAssertEqual(state.userID, "user-existing")
        XCTAssertEqual(recorder.requests.first?.url?.path, "/auth/v1/token")
        XCTAssertTrue(recorder.requests.first?.url?.query?.contains("grant_type=password") ?? false)
        XCTAssertFalse(recorder.requests.contains { $0.url?.path == "/auth/v1/signup" })
    }

    func testActivationRunnerRetriesPendingStoredCredentialsThroughIdempotentSignup() throws {
        let recorder = TransportRecorder(responses: [
            .json(["created": false, "alreadyExists": true]),
            .json([
                "access_token": "access-retry",
                "refresh_token": "refresh-retry",
                "user": ["id": "user-retry"],
            ]),
            .json([["id": "person-retry"]]),
            .json([]),
        ])
        var client = NetworkingPlatformClient(config: config)
        client.transport = recorder.transport
        let runner = NetworkingActivationRunner(client: client)
        let pendingState = NetworkingActivationState(
            isEnabled: false,
            personID: "",
            agentTokenPlaintext: "",
            supabaseURL: config.supabaseURL,
            publishableKey: config.publishableKey,
            authEmail: machineAuthFixture.email,
            authPassword: machineAuthFixture.passphrase,
            mode: .localSandbox
        )

        let state = try runner.activate(
            personName: "Tianfu Wu",
            handle: "tianfu-wu",
            approvedProfiles: [],
            previousState: pendingState
        )

        XCTAssertEqual(recorder.requests.first?.url?.path, "/functions/v1/networking-machine-signup")
        XCTAssertEqual(state.authEmail, machineAuthFixture.email)
        XCTAssertEqual(state.userID, "user-retry")
    }

    func testActivationRunnerReportsFailingStep() {
        let recorder = TransportRecorder(responses: [
            .failure(status: 422, body: "machine user rejected"),
        ])
        var client = NetworkingPlatformClient(config: config)
        client.transport = recorder.transport
        var runner = NetworkingActivationRunner(client: client)
        let authFixture = machineAuthFixture
        runner.credentialGenerator = { _ in
            NetworkingMachineCredentials(
                email: authFixture.email,
                password: authFixture.passphrase
            )
        }

        XCTAssertThrowsError(
            try runner.activate(personName: "Tianfu Wu", handle: "tianfu-wu", approvedProfiles: [])
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("machine platform identity"))
            XCTAssertTrue(error.localizedDescription.contains("422"))
            XCTAssertFalse(error.localizedDescription.contains("sign-in failed"))
        }
        XCTAssertEqual(recorder.requests.count, 1)
    }

    func testActivationRunnerDoesNotCreateReplacementIdentityWhenStoredCredentialsAreMissing() {
        let recorder = TransportRecorder(responses: [])
        var client = NetworkingPlatformClient(config: config)
        client.transport = recorder.transport
        let runner = NetworkingActivationRunner(client: client)
        let previousState = NetworkingActivationState(
            isEnabled: true, personID: "existing-person", agentTokenPlaintext: "",
            supabaseURL: config.supabaseURL, publishableKey: config.publishableKey, mode: .platform
        )

        XCTAssertThrowsError(try runner.activate(
            personName: "Tianfu Wu", handle: "tianfu-wu", approvedProfiles: [], previousState: previousState
        )) { error in
            XCTAssertTrue(error.localizedDescription.contains("secure credentials are unavailable"))
        }
        XCTAssertTrue(recorder.requests.isEmpty)
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
