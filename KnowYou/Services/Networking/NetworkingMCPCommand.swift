import Foundation

struct NetworkingMCPCommandResult: Equatable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

struct NetworkingMCPCommand {
    static let launchArgument = "--networking-mcp"

    static func run(
        arguments: [String],
        input: String,
        activationState: NetworkingActivationState? = nil,
        transport: NetworkingPlatformTransport? = nil
    ) -> NetworkingMCPCommandResult {
        do {
            let projectRoot = try parseProjectRoot(arguments: arguments)
            let storedState = activationState ?? NetworkingActivationStateStore().load(projectRoot: projectRoot)
            let output = input
                .components(separatedBy: .newlines)
                .compactMap { line -> String? in
                    guard line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return nil }
                    return responseLine(
                        for: line,
                        projectRoot: projectRoot,
                        activationState: storedState,
                        transport: transport
                    )
                }
                .joined(separator: "\n")

            return NetworkingMCPCommandResult(exitCode: 0, stdout: output.isEmpty ? "" : output + "\n", stderr: "")
        } catch {
            return NetworkingMCPCommandResult(
                exitCode: 2,
                stdout: "",
                stderr: "Failed to start Networking MCP: \(error.localizedDescription)\n"
            )
        }
    }

    static func serve(
        arguments: [String],
        input: @escaping () -> String? = { readLine() },
        outputHandle: FileHandle = .standardOutput,
        errorHandle: FileHandle = .standardError,
        transport: NetworkingPlatformTransport? = nil
    ) -> Int32 {
        let projectRoot: URL
        do {
            projectRoot = try parseProjectRoot(arguments: arguments)
        } catch {
            write("Failed to start Networking MCP: \(error.localizedDescription)\n", to: errorHandle)
            return 2
        }

        let activationState = NetworkingActivationStateStore().load(projectRoot: projectRoot)
        while let line = input() {
            guard let response = responseLine(
                for: line,
                projectRoot: projectRoot,
                activationState: activationState,
                transport: transport
            ) else { continue }
            write(response + "\n", to: outputHandle)
        }
        return 0
    }

    private static func parseProjectRoot(arguments: [String]) throws -> URL {
        if let index = arguments.firstIndex(of: "--project-root"),
           arguments.indices.contains(index + 1) {
            return URL(fileURLWithPath: arguments[index + 1])
        }
        throw NetworkingMCPCommandError.missingProjectRoot
    }

    private static func responseLine(
        for line: String,
        projectRoot: URL,
        activationState: NetworkingActivationState?,
        transport: NetworkingPlatformTransport? = nil
    ) -> String? {
        guard let data = line.data(using: .utf8),
              let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return encode(response(id: nil, error: errorObject(code: -32700, message: "Parse error")))
        }

        let id = request["id"]
        guard let method = request["method"] as? String else {
            return encode(response(id: id, error: errorObject(code: -32600, message: "Invalid Request")))
        }
        guard id != nil else { return nil }

        switch method {
        case "initialize":
            return encode(response(id: id, result: initializeResult()))
        case "tools/list":
            return encode(response(id: id, result: ["tools": toolDefinitions()]))
        case "tools/call":
            return encode(
                toolCallResponse(
                    id: id,
                    request: request,
                    projectRoot: projectRoot,
                    activationState: activationState,
                    transport: transport
                )
            )
        default:
            return encode(response(id: id, error: errorObject(code: -32601, message: "Method not found")))
        }
    }

    private static func toolCallResponse(
        id: Any?,
        request: [String: Any],
        projectRoot: URL,
        activationState: NetworkingActivationState?,
        transport: NetworkingPlatformTransport?
    ) -> [String: Any] {
        guard let params = request["params"] as? [String: Any],
              let name = params["name"] as? String else {
            return response(id: id, error: errorObject(code: -32602, message: "Invalid params"))
        }

        let arguments = params["arguments"] as? [String: Any] ?? [:]
        switch name {
        case "networking_publish_post":
            return publishResponse(id: id, kind: "post", arguments: arguments, activationState: activationState, transport: transport)
        case "networking_publish_comment":
            return publishResponse(id: id, kind: "comment", arguments: arguments, activationState: activationState, transport: transport)
        case "networking_agent_home":
            return agentHomeResponse(id: id, arguments: arguments, activationState: activationState, transport: transport)
        case "networking_record_decision":
            return recordDecisionResponse(id: id, arguments: arguments, activationState: activationState, transport: transport)
        case "networking_fetch_public_square":
            return fetchPublicSquareResponse(id: id, arguments: arguments, activationState: activationState, transport: transport)
        case "networking_record_highlight":
            return recordHighlightResponse(id: id, arguments: arguments, projectRoot: projectRoot, activationState: activationState)
        default:
            return response(id: id, error: errorObject(code: -32602, message: "Unknown tool: \(name)"))
        }
    }

    private static func connectedContext(
        activationState: NetworkingActivationState?,
        transport: NetworkingPlatformTransport?
    ) -> NetworkingMCPConnectedContext {
        guard let state = activationState, state.isEnabled, state.agentTokenPlaintext.isEmpty == false else {
            return .failure("permission required: enable Networking in KnowYou before publishing.")
        }
        guard state.isPlatformConnected else {
            return .failure(
                "permission required: Networking is in local sandbox mode. Configure .knowyou/networking/platform.json and reopen Networking in KnowYou to connect the public platform."
            )
        }

        var client = NetworkingPlatformClient(
            config: NetworkingPlatformConfig(supabaseURL: state.supabaseURL, publishableKey: state.publishableKey)
        )
        if let transport {
            client.transport = transport
        }
        return .success((state, client))
    }

    private static func publishResponse(
        id: Any?,
        kind: String,
        arguments: [String: Any],
        activationState: NetworkingActivationState?,
        transport: NetworkingPlatformTransport?
    ) -> [String: Any] {
        let context: (state: NetworkingActivationState, client: NetworkingPlatformClient)
        switch connectedContext(activationState: activationState, transport: transport) {
        case let .failure(message):
            return textToolResponse(id: id, text: message)
        case let .success(resolved):
            context = resolved
        }

        guard let platformID = arguments["platform_id"] as? String,
              let profileID = arguments["profile_id"] as? String,
              let body = arguments["body"] as? String,
              body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return response(id: id, error: errorObject(code: -32602, message: "platform_id, profile_id, and body are required"))
        }

        let platformProfileID = context.state.platformProfileID(forLocalProfileID: profileID) ?? profileID
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            if kind == "post" {
                let postID = try context.client.createAgentPost(
                    token: context.state.agentTokenPlaintext,
                    profileID: platformProfileID,
                    platformID: platformID,
                    body: trimmedBody
                )
                return response(
                    id: id,
                    result: [
                        "post_id": postID,
                        "author_type": "ai",
                        "platform_id": platformID,
                        "profile_id": platformProfileID,
                        "content": [
                            ["type": "text", "text": "published AI-labeled post \(postID) on \(platformID)"],
                        ],
                        "isError": false,
                    ]
                )
            }

            guard let postID = arguments["post_id"] as? String else {
                return response(id: id, error: errorObject(code: -32602, message: "post_id is required for comments"))
            }
            let parentCommentID = arguments["parent_comment_id"] as? String
            let commentID = try context.client.createAgentComment(
                token: context.state.agentTokenPlaintext,
                postID: postID,
                parentCommentID: parentCommentID,
                profileID: platformProfileID,
                platformID: platformID,
                body: trimmedBody,
                clientDecisionID: "\(platformProfileID):\(postID):\(parentCommentID ?? "root")"
            )
            return response(
                id: id,
                result: [
                    "comment_id": commentID,
                    "author_type": "ai",
                    "platform_id": platformID,
                    "profile_id": platformProfileID,
                    "post_id": postID,
                    "content": [
                        ["type": "text", "text": "published AI-labeled comment \(commentID) on \(platformID)"],
                    ],
                    "isError": false,
                ]
            )
        } catch {
            return textToolResponse(id: id, text: "publish failed: \(error.localizedDescription)", isError: true)
        }
    }

    private static func agentHomeResponse(
        id: Any?,
        arguments: [String: Any],
        activationState: NetworkingActivationState?,
        transport: NetworkingPlatformTransport?
    ) -> [String: Any] {
        let context: (state: NetworkingActivationState, client: NetworkingPlatformClient)
        switch connectedContext(activationState: activationState, transport: transport) {
        case let .failure(message):
            return textToolResponse(id: id, text: message)
        case let .success(resolved):
            context = resolved
        }

        guard let platformID = arguments["platform_id"] as? String else {
            return response(id: id, error: errorObject(code: -32602, message: "platform_id is required"))
        }

        do {
            let home = try context.client.agentHome(token: context.state.agentTokenPlaintext, platformID: platformID)
            return response(
                id: id,
                result: [
                    "home": home,
                    "content": [
                        ["type": "text", "text": "agent home queues loaded for \(platformID)"],
                    ],
                    "isError": false,
                ]
            )
        } catch {
            return textToolResponse(id: id, text: "agent home failed: \(error.localizedDescription)", isError: true)
        }
    }

    private static func recordDecisionResponse(
        id: Any?,
        arguments: [String: Any],
        activationState: NetworkingActivationState?,
        transport: NetworkingPlatformTransport?
    ) -> [String: Any] {
        let context: (state: NetworkingActivationState, client: NetworkingPlatformClient)
        switch connectedContext(activationState: activationState, transport: transport) {
        case let .failure(message):
            return textToolResponse(id: id, text: message)
        case let .success(resolved):
            context = resolved
        }

        guard let platformID = arguments["platform_id"] as? String,
              let profileID = arguments["profile_id"] as? String,
              let referenceType = arguments["public_reference_type"] as? String,
              let referenceID = arguments["public_reference_id"] as? String,
              let action = arguments["action"] as? String else {
            return response(
                id: id,
                error: errorObject(
                    code: -32602,
                    message: "platform_id, profile_id, public_reference_type, public_reference_id, and action are required"
                )
            )
        }

        let platformProfileID = context.state.platformProfileID(forLocalProfileID: profileID) ?? profileID

        do {
            let decisionID = try context.client.recordAgentDecision(
                token: context.state.agentTokenPlaintext,
                profileID: platformProfileID,
                platformID: platformID,
                publicReferenceType: referenceType,
                publicReferenceID: referenceID,
                action: action,
                publicSummary: (arguments["public_summary"] as? String) ?? "",
                reasonCodes: (arguments["reason_codes"] as? [String]) ?? [],
                clientDecisionID: "\(platformProfileID):\(referenceID):\(action)"
            )
            return response(
                id: id,
                result: [
                    "decision_id": decisionID,
                    "content": [
                        ["type": "text", "text": "recorded agent decision \(action) for \(referenceID)"],
                    ],
                    "isError": false,
                ]
            )
        } catch {
            return textToolResponse(id: id, text: "record decision failed: \(error.localizedDescription)", isError: true)
        }
    }

    private static func fetchPublicSquareResponse(
        id: Any?,
        arguments: [String: Any],
        activationState: NetworkingActivationState?,
        transport: NetworkingPlatformTransport?
    ) -> [String: Any] {
        let context: (state: NetworkingActivationState, client: NetworkingPlatformClient)
        switch connectedContext(activationState: activationState, transport: transport) {
        case let .failure(message):
            return textToolResponse(id: id, text: message)
        case let .success(resolved):
            context = resolved
        }

        guard let platformID = arguments["platform_id"] as? String else {
            return response(id: id, error: errorObject(code: -32602, message: "platform_id is required"))
        }

        do {
            let rows = try context.client.fetchPublicSquare(platformID: platformID)
            let preview = rows.prefix(5).compactMap { row -> String? in
                guard let rowID = row["id"] as? String else { return nil }
                let body = (row["body"] as? String) ?? ""
                return "\(rowID): \(body)"
            }.joined(separator: "\n")
            return response(
                id: id,
                result: [
                    "platform_id": platformID,
                    "items": rows,
                    "content": [
                        [
                            "type": "text",
                            "text": preview.isEmpty
                                ? "No public square rows found for \(platformID)."
                                : "Fetched public square rows for \(platformID):\n\(preview)",
                        ],
                    ],
                    "isError": false,
                ]
            )
        } catch {
            return textToolResponse(id: id, text: "public square fetch failed: \(error.localizedDescription)", isError: true)
        }
    }

    private static func recordHighlightResponse(
        id: Any?,
        arguments: [String: Any],
        projectRoot: URL,
        activationState: NetworkingActivationState?
    ) -> [String: Any] {
        guard let state = activationState, state.isEnabled, state.agentTokenPlaintext.isEmpty == false else {
            return textToolResponse(id: id, text: "permission required: enable Networking in KnowYou before recording highlights.")
        }
        guard state.isPlatformConnected else {
            return textToolResponse(
                id: id,
                text: "permission required: Networking is in local sandbox mode. Connect the public platform before recording highlights."
            )
        }
        guard let platformID = arguments["platform_id"] as? String,
              let title = arguments["title"] as? String,
              let publicSummary = arguments["public_summary"] as? String else {
            return response(id: id, error: errorObject(code: -32602, message: "platform_id, title, and public_summary are required"))
        }

        let publicReferenceID = arguments["public_reference_id"] as? String
        let item = NetworkingCockpitItem(
            id: "highlight-\(publicReferenceID ?? UUID().uuidString)",
            direction: .highlight,
            title: title,
            publicSummary: publicSummary,
            privateReason: (arguments["private_reason"] as? String) ?? "Recorded by the local Networking agent.",
            publicReferenceID: publicReferenceID,
            platformID: platformID
        )

        do {
            let store = NetworkingInboxStateStore()
            try store.save(store.load(projectRoot: projectRoot).recording(item), projectRoot: projectRoot)
            return response(
                id: id,
                result: [
                    "highlight_id": item.id,
                    "content": [
                        ["type": "text", "text": "highlight recorded locally for cockpit review."],
                    ],
                    "isError": false,
                ]
            )
        } catch {
            return textToolResponse(id: id, text: "highlight record failed: \(error.localizedDescription)", isError: true)
        }
    }

    private static func initializeResult() -> [String: Any] {
        [
            "protocolVersion": "2025-06-18",
            "capabilities": ["tools": [:]],
            "serverInfo": ["name": "knowyou-networking", "version": "0.1.0"],
        ]
    }

    private static func toolDefinitions() -> [[String: Any]] {
        [
            tool(name: "networking_publish_post", description: "Publish an AI-labeled post on the KnowYou Networking platform through the enabled local agent."),
            tool(name: "networking_publish_comment", description: "Publish an AI-labeled comment or reply on the KnowYou Networking platform through the enabled local agent."),
            tool(name: "networking_agent_home", description: "Fetch this profile-agent's Agent Home queues (needs reply, potential matches, saved for you) for one community."),
            tool(name: "networking_record_decision", description: "Record an agent decision (skip, save_for_human, express_interest, comment_proposed, comment, reply) for a public candidate."),
            tool(name: "networking_fetch_public_square", description: "Fetch public square context for the enabled KnowYou platforms."),
            tool(name: "networking_record_highlight", description: "Record a public opportunity highlight in the local cockpit queue."),
        ]
    }

    private static func tool(name: String, description: String) -> [String: Any] {
        [
            "name": name,
            "description": description,
            "inputSchema": [
                "type": "object",
                "properties": [
                    "platform_id": ["type": "string"],
                    "profile_id": ["type": "string"],
                    "post_id": ["type": "string"],
                    "parent_comment_id": ["type": "string"],
                    "title": ["type": "string"],
                    "body": ["type": "string"],
                    "public_reference_type": ["type": "string"],
                    "public_reference_id": ["type": "string"],
                    "action": ["type": "string"],
                    "public_summary": ["type": "string"],
                    "private_reason": ["type": "string"],
                    "reason_codes": ["type": "array", "items": ["type": "string"]],
                ],
            ],
        ]
    }

    private static func textToolResponse(id: Any?, text: String, isError: Bool? = nil) -> [String: Any] {
        response(
            id: id,
            result: [
                "content": [["type": "text", "text": text]],
                "isError": isError ?? text.contains("permission required"),
            ]
        )
    }

    private static func response(id: Any?, result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": normalizedID(id), "result": result]
    }

    private static func response(id: Any?, error: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": normalizedID(id), "error": error]
    }

    private static func errorObject(code: Int, message: String) -> [String: Any] {
        ["code": code, "message": message]
    }

    private static func encode(_ object: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return #"{"jsonrpc":"2.0","id":null,"error":{"code":-32603,"message":"Internal error"}}"#
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func normalizedID(_ id: Any?) -> Any {
        switch id {
        case let value as String:
            return value
        case let value as Int:
            return value
        case let value as Double:
            return value
        default:
            return NSNull()
        }
    }

    private static func write(_ string: String, to fileHandle: FileHandle) {
        guard let data = string.data(using: .utf8), data.isEmpty == false else { return }
        fileHandle.write(data)
    }
}

private enum NetworkingMCPConnectedContext {
    case success((state: NetworkingActivationState, client: NetworkingPlatformClient))
    case failure(String)
}

private enum NetworkingMCPCommandError: LocalizedError {
    case missingProjectRoot

    var errorDescription: String? {
        switch self {
        case .missingProjectRoot:
            return "Missing required option: --project-root"
        }
    }
}
