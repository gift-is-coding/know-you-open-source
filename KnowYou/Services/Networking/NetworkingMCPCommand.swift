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
        activationState: NetworkingActivationState? = nil
    ) -> NetworkingMCPCommandResult {
        do {
            let projectRoot = try parseProjectRoot(arguments: arguments)
            let storedState = activationState ?? NetworkingActivationStateStore().load(projectRoot: projectRoot)
            let output = input
                .components(separatedBy: .newlines)
                .compactMap { line -> String? in
                    guard line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return nil }
                    return responseLine(for: line, activationState: storedState)
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
        errorHandle: FileHandle = .standardError
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
            guard let response = responseLine(for: line, activationState: activationState) else { continue }
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

    private static func responseLine(for line: String, activationState: NetworkingActivationState?) -> String? {
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
            return encode(toolCallResponse(id: id, request: request, activationState: activationState))
        default:
            return encode(response(id: id, error: errorObject(code: -32601, message: "Method not found")))
        }
    }

    private static func toolCallResponse(
        id: Any?,
        request: [String: Any],
        activationState: NetworkingActivationState?
    ) -> [String: Any] {
        guard let params = request["params"] as? [String: Any],
              let name = params["name"] as? String else {
            return response(id: id, error: errorObject(code: -32602, message: "Invalid params"))
        }

        let arguments = params["arguments"] as? [String: Any] ?? [:]
        switch name {
        case "networking_publish_post":
            return publishResponse(id: id, kind: "post", arguments: arguments, activationState: activationState)
        case "networking_publish_comment":
            return publishResponse(id: id, kind: "comment", arguments: arguments, activationState: activationState)
        case "networking_fetch_public_square":
            return textToolResponse(id: id, text: "Networking public square fetch is available through the Web data API.")
        case "networking_record_highlight":
            return textToolResponse(id: id, text: "Networking highlight recorded locally for cockpit review.")
        default:
            return response(id: id, error: errorObject(code: -32602, message: "Unknown tool: \(name)"))
        }
    }

    private static func publishResponse(
        id: Any?,
        kind: String,
        arguments: [String: Any],
        activationState: NetworkingActivationState?
    ) -> [String: Any] {
        guard let state = activationState, state.isEnabled, state.agentTokenPlaintext.isEmpty == false else {
            return textToolResponse(id: id, text: "permission required: enable Networking in KnowYou before publishing.")
        }
        guard let platformID = arguments["platform_id"] as? String,
              let profileID = arguments["profile_id"] as? String,
              let body = arguments["body"] as? String,
              body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return response(id: id, error: errorObject(code: -32602, message: "platform_id, profile_id, and body are required"))
        }

        var payload: [String: Any] = [
            "kind": kind,
            "author_type": "ai",
            "platform_id": platformID,
            "profile_id": profileID,
            "body": body.trimmingCharacters(in: .whitespacesAndNewlines),
            "token": state.agentTokenPlaintext,
        ]
        if let postID = arguments["post_id"] as? String {
            payload["post_id"] = postID
        }

        return response(
            id: id,
            result: [
                "payload": payload,
                "rpc": kind == "post" ? "networking_agent_create_post" : "networking_agent_create_comment",
                "content": [
                    [
                        "type": "text",
                        "text": "ready to publish \(kind) as AI on \(platformID)",
                    ],
                ],
                "isError": false,
            ]
        )
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
            tool(name: "networking_publish_post", description: "Publish an AI-labeled post through the enabled local KnowYou Networking agent token."),
            tool(name: "networking_publish_comment", description: "Publish an AI-labeled comment through the enabled local KnowYou Networking agent token."),
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
                    "body": ["type": "string"],
                ],
            ],
        ]
    }

    private static func textToolResponse(id: Any?, text: String) -> [String: Any] {
        response(
            id: id,
            result: [
                "content": [["type": "text", "text": text]],
                "isError": text.contains("permission required"),
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

private enum NetworkingMCPCommandError: LocalizedError {
    case missingProjectRoot

    var errorDescription: String? {
        switch self {
        case .missingProjectRoot:
            return "Missing required option: --project-root"
        }
    }
}
