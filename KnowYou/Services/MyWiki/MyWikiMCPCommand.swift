import Foundation

struct MyWikiMCPCommandResult: Equatable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

struct MyWikiMCPCommand {
    static let launchArgument = "--my-wiki-mcp"

    static func run(arguments: [String], input: String) -> MyWikiMCPCommandResult {
        do {
            let projectRoot = try parseProjectRoot(arguments: arguments)
            let output = input
                .components(separatedBy: .newlines)
                .compactMap { line -> String? in
                    guard line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                        return nil
                    }
                    return responseLine(for: line, projectRoot: projectRoot)
                }
                .joined(separator: "\n")

            return MyWikiMCPCommandResult(
                exitCode: 0,
                stdout: output.isEmpty ? "" : output + "\n",
                stderr: ""
            )
        } catch {
            return MyWikiMCPCommandResult(
                exitCode: 2,
                stdout: "",
                stderr: "Failed to start My Wiki MCP: \(error.localizedDescription)\n"
            )
        }
    }

    static func run(arguments: [String], inputHandle: FileHandle = .standardInput) -> MyWikiMCPCommandResult {
        let input = String(data: inputHandle.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return run(arguments: arguments, input: input)
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
            write("Failed to start My Wiki MCP: \(error.localizedDescription)\n", to: errorHandle)
            return 2
        }

        while let line = input() {
            guard let response = responseLine(for: line, projectRoot: projectRoot) else {
                continue
            }
            write(response + "\n", to: outputHandle)
        }
        return 0
    }

    private static func parseProjectRoot(arguments: [String]) throws -> URL {
        if let index = arguments.firstIndex(of: "--project-root"),
           arguments.indices.contains(index + 1) {
            return URL(fileURLWithPath: arguments[index + 1])
        }

        if let projectRoot = ProcessInfo.processInfo.environment["KNOWYOU_MY_WIKI_PROJECT"],
           projectRoot.isEmpty == false {
            return URL(fileURLWithPath: projectRoot)
        }

        throw MyWikiMCPCommandError.missingProjectRoot
    }

    private static func responseLine(for line: String, projectRoot: URL) -> String? {
        guard let data = line.data(using: .utf8),
              let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return encode(response(id: nil, error: errorObject(code: -32700, message: "Parse error")))
        }

        let id = request["id"]
        guard let method = request["method"] as? String else {
            return encode(response(id: id, error: errorObject(code: -32600, message: "Invalid Request")))
        }

        if id == nil {
            return nil
        }

        switch method {
        case "initialize":
            return encode(response(id: id, result: initializeResult()))
        case "tools/list":
            return encode(response(id: id, result: ["tools": toolDefinitions()]))
        case "tools/call":
            return encode(toolCallResponse(id: id, request: request, projectRoot: projectRoot))
        default:
            return encode(response(id: id, error: errorObject(code: -32601, message: "Method not found")))
        }
    }

    private static func toolCallResponse(id: Any?, request: [String: Any], projectRoot: URL) -> [String: Any] {
        guard let params = request["params"] as? [String: Any],
              let name = params["name"] as? String else {
            return response(id: id, error: errorObject(code: -32602, message: "Invalid params"))
        }

        let arguments = params["arguments"] as? [String: Any] ?? [:]
        switch name {
        case "my_wiki_context":
            return contextToolResponse(id: id, arguments: arguments, projectRoot: projectRoot)
        case "my_wiki_read_page":
            return readPageToolResponse(id: id, arguments: arguments, projectRoot: projectRoot)
        default:
            return response(id: id, error: errorObject(code: -32602, message: "Unknown tool: \(name)"))
        }
    }

    private static func contextToolResponse(id: Any?, arguments: [String: Any], projectRoot: URL) -> [String: Any] {
        let background = (arguments["background"] as? String) ?? (arguments["query"] as? String) ?? ""
        let maxItems = boundedInt(arguments["max_items"], defaultValue: 8, range: 1...20)
        let characterBudget = boundedInt(arguments["character_budget"], defaultValue: 6_000, range: 500...20_000)

        let pack = MyWikiContextPackService().contextPack(
            for: MyWikiContextPackRequest(
                projectRoot: projectRoot,
                query: background,
                maxItems: maxItems,
                characterBudget: characterBudget
            )
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = (try? encoder.encode(pack)) ?? Data("{}".utf8)
        return textToolResponse(id: id, text: String(decoding: data, as: UTF8.self))
    }

    private static func readPageToolResponse(id: Any?, arguments: [String: Any], projectRoot: URL) -> [String: Any] {
        guard let relativePath = citationRelativePath(from: arguments),
              isSafeRelativePath(relativePath) else {
            return response(id: id, error: errorObject(code: -32602, message: "Invalid page path"))
        }

        let url = projectRoot.appending(path: relativePath)
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return response(id: id, error: errorObject(code: -32004, message: "Page not found"))
        }

        return textToolResponse(id: id, text: contents)
    }

    private static func initializeResult() -> [String: Any] {
        [
            "protocolVersion": "2025-06-18",
            "capabilities": [
                "tools": [:],
            ],
            "serverInfo": [
                "name": "knowyou-my-wiki",
                "version": "0.1.0",
            ],
        ]
    }

    private static func toolDefinitions() -> [[String: Any]] {
        [
            [
                "name": "my_wiki_context",
                "description": "Search KnowYou My Wiki for private, cited context using a full background paragraph.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "background": [
                            "type": "string",
                            "description": "The full task background or question, not just keywords.",
                        ],
                        "query": [
                            "type": "string",
                            "description": "Optional alias for background.",
                        ],
                        "max_items": [
                            "type": "integer",
                            "minimum": 1,
                            "maximum": 20,
                            "default": 8,
                        ],
                        "character_budget": [
                            "type": "integer",
                            "minimum": 500,
                            "maximum": 20000,
                            "default": 6000,
                        ],
                    ],
                ],
            ],
            [
                "name": "my_wiki_read_page",
                "description": "Read a specific My Wiki markdown page returned as a citation.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "relativePath": [
                            "type": "string",
                            "description": "Citation relativePath returned by my_wiki_context, such as wiki/entities/brad.md.",
                        ],
                        "path": [
                            "type": "string",
                            "description": "Legacy alias for relativePath.",
                        ],
                    ],
                    "required": ["relativePath"],
                ],
            ],
        ]
    }

    private static func textToolResponse(id: Any?, text: String) -> [String: Any] {
        response(
            id: id,
            result: [
                "content": [
                    [
                        "type": "text",
                        "text": text,
                    ],
                ],
                "isError": false,
            ]
        )
    }

    private static func response(id: Any?, result: [String: Any]) -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "id": normalizedID(id),
            "result": result,
        ]
    }

    private static func response(id: Any?, error: [String: Any]) -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "id": normalizedID(id),
            "error": error,
        ]
    }

    private static func errorObject(code: Int, message: String) -> [String: Any] {
        [
            "code": code,
            "message": message,
        ]
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

    private static func boundedInt(_ value: Any?, defaultValue: Int, range: ClosedRange<Int>) -> Int {
        let parsed: Int?
        if let value = value as? Int {
            parsed = value
        } else if let value = value as? String {
            parsed = Int(value)
        } else {
            parsed = nil
        }

        return min(max(parsed ?? defaultValue, range.lowerBound), range.upperBound)
    }

    private static func citationRelativePath(from arguments: [String: Any]) -> String? {
        if let relativePath = arguments["relativePath"] as? String {
            return relativePath
        }

        return arguments["path"] as? String
    }

    private static func isSafeRelativePath(_ path: String) -> Bool {
        path.isEmpty == false
            && path.hasPrefix("/") == false
            && path.contains("..") == false
            && (path.hasPrefix("wiki/") || path.hasPrefix("raw/sources/"))
    }

    private static func write(_ string: String, to fileHandle: FileHandle) {
        guard string.isEmpty == false,
              let data = string.data(using: .utf8) else {
            return
        }
        fileHandle.write(data)
    }
}

private enum MyWikiMCPCommandError: LocalizedError {
    case missingProjectRoot

    var errorDescription: String? {
        switch self {
        case .missingProjectRoot:
            return "Missing required option: --project-root"
        }
    }
}
