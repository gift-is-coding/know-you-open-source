import XCTest
@testable import KnowYou

final class NetworkingPlatformClientTests: XCTestCase {
    private let config = NetworkingPlatformConfig(
        supabaseURL: URL(string: "https://example.supabase.co")!,
        publishableKey: "publishable-key"
    )

    func testTokenHashMatchesSHA256Hex() {
        XCTAssertEqual(
            NetworkingPlatformClient.tokenHash("abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    func testSignInAnonymouslyPostsSignupAndParsesSession() throws {
        let recorder = TransportRecorder(responses: [
            .json([
                "access_token": "access-1",
                "refresh_token": "refresh-1",
                "user": ["id": "user-1"],
            ]),
        ])
        var client = NetworkingPlatformClient(config: config)
        client.transport = recorder.transport

        let session = try client.signInAnonymously()

        XCTAssertEqual(session, NetworkingPlatformSession(accessToken: "access-1", refreshToken: "refresh-1", userID: "user-1"))
        let request = try XCTUnwrap(recorder.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/auth/v1/signup")
        XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "publishable-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer publishable-key")
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
        runner.tokenGenerator = { "knw_agent_fixed" }

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
        XCTAssertEqual(state.agentTokenPlaintext, "knw_agent_fixed")
        XCTAssertEqual(state.platformProfileID(forLocalProfileID: "profile-career"), "career-uuid")
        XCTAssertEqual(recorder.requests.count, 5)
        XCTAssertEqual(recorder.requests.last?.url?.path, "/rest/v1/community_memberships")
    }

    func testActivationRunnerReportsFailingStep() {
        let recorder = TransportRecorder(responses: [
            .failure(status: 422, body: "anonymous sign-ins disabled"),
        ])
        var client = NetworkingPlatformClient(config: config)
        client.transport = recorder.transport
        let runner = NetworkingActivationRunner(client: client)

        XCTAssertThrowsError(
            try runner.activate(personName: "Tianfu Wu", handle: "tianfu-wu", approvedProfiles: [])
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("anonymous platform identity"))
            XCTAssertTrue(error.localizedDescription.contains("422"))
        }
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
        XCTAssertTrue(state.profileIDMapping.isEmpty)
        XCTAssertFalse(state.isPlatformConnected)
    }

    private func bodyJSON(of request: URLRequest) throws -> [String: Any] {
        let data = try XCTUnwrap(request.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
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
