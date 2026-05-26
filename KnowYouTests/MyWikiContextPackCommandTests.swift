import XCTest
@testable import KnowYou

final class MyWikiContextPackCommandTests: XCTestCase {
    func testCommandReturnsJSONContextPackForQuery() throws {
        let project = try makeProject()

        let result = MyWikiContextPackCommand.run(
            arguments: [
                "KnowYou",
                "--my-wiki-context",
                "--project-root", project.path,
                "--query", "agent context",
                "--max-items", "3",
                "--character-budget", "1200",
            ]
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stderr, "")

        let pack = try JSONDecoder().decode(MyWikiContextPack.self, from: Data(result.stdout.utf8))
        XCTAssertEqual(pack.query, "agent context")
        XCTAssertTrue(pack.queryPlan.terms.contains("agent"))
        XCTAssertEqual(pack.items.first?.citation.relativePath, "wiki/concepts/agent-context.md")
        XCTAssertEqual(pack.items.first?.title, "Agent Context")
        XCTAssertEqual(pack.citations, pack.items.map(\.citation))
    }

    func testCommandAcceptsBackgroundAsPreferredInput() throws {
        let project = try makeProject()

        let result = MyWikiContextPackCommand.run(
            arguments: [
                "KnowYou",
                "--my-wiki-context",
                "--project-root", project.path,
                "--background", "An external agent needs context about agent context retrieval from My Wiki before answering.",
                "--max-items", "3",
                "--character-budget", "1200",
            ]
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stderr, "")

        let pack = try JSONDecoder().decode(MyWikiContextPack.self, from: Data(result.stdout.utf8))
        XCTAssertTrue(pack.query.contains("external agent"))
        XCTAssertEqual(pack.items.first?.citation.relativePath, "wiki/concepts/agent-context.md")
        XCTAssertTrue(pack.items.first?.matchedTerms.contains("agent") == true)
    }

    func testCommandPrettyPrintsJSONWhenRequested() throws {
        let project = try makeProject()

        let result = MyWikiContextPackCommand.run(
            arguments: [
                "KnowYou",
                "--my-wiki-context",
                "--project-root", project.path,
                "--query", "agent context",
                "--pretty",
            ]
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("\n  \"items\""))
        XCTAssertTrue(result.stdout.hasSuffix("\n"))
    }

    func testCommandReturnsUsageErrorWhenRequiredOptionsAreMissing() {
        let result = MyWikiContextPackCommand.run(
            arguments: ["KnowYou", "--my-wiki-context", "--query", "agent context"]
        )

        XCTAssertEqual(result.exitCode, 2)
        XCTAssertEqual(result.stdout, "")
        XCTAssertTrue(result.stderr.contains("Usage: KnowYou --my-wiki-context"))
        XCTAssertTrue(result.stderr.contains("Missing required option: --project-root"))
    }

    func testCommandReturnsUsageErrorForInvalidNumericOptions() throws {
        let project = try makeProject()

        let result = MyWikiContextPackCommand.run(
            arguments: [
                "KnowYou",
                "--my-wiki-context",
                "--project-root", project.path,
                "--query", "agent context",
                "--max-items", "many",
            ]
        )

        XCTAssertEqual(result.exitCode, 2)
        XCTAssertEqual(result.stdout, "")
        XCTAssertTrue(result.stderr.contains("Invalid integer for --max-items: many"))
    }

    func testCommandReturnsEmptyPackForMissingProjectDirectory() throws {
        let missingProject = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)

        let result = MyWikiContextPackCommand.run(
            arguments: [
                "KnowYou",
                "--my-wiki-context",
                "--project-root", missingProject.path,
                "--query", "agent context",
            ]
        )

        XCTAssertEqual(result.exitCode, 0)

        let pack = try JSONDecoder().decode(MyWikiContextPack.self, from: Data(result.stdout.utf8))
        XCTAssertEqual(pack.query, "agent context")
        XCTAssertTrue(pack.items.isEmpty)
        XCTAssertTrue(pack.citations.isEmpty)
    }

    func testLaunchModeRecognizesMyWikiContextCommand() {
        XCTAssertEqual(
            LaunchMode(arguments: ["KnowYou", "--my-wiki-context"]),
            .myWikiContext
        )
    }

    func testLaunchModeRecognizesMyWikiMCPCommand() {
        XCTAssertEqual(
            LaunchMode(arguments: ["KnowYou", "--my-wiki-mcp"]),
            .myWikiMCP
        )
    }

    func testNativeMCPListsMyWikiTools() throws {
        let project = try makeProject()
        let result = MyWikiMCPCommand.run(
            arguments: ["KnowYou", "--my-wiki-mcp", "--project-root", project.path],
            input: #"{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}"# + "\n"
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stderr, "")

        let response = try decodeJSONLine(result.stdout)
        let resultObject = try XCTUnwrap(response["result"] as? [String: Any])
        let tools = try XCTUnwrap(resultObject["tools"] as? [[String: Any]])
        XCTAssertEqual(Set(tools.compactMap { $0["name"] as? String }), ["my_wiki_context", "my_wiki_read_page"])

        let readPageTool = try XCTUnwrap(tools.first { $0["name"] as? String == "my_wiki_read_page" })
        let schema = try XCTUnwrap(readPageTool["inputSchema"] as? [String: Any])
        XCTAssertEqual(schema["required"] as? [String], ["relativePath"])
    }

    func testNativeMCPServeWritesResponsesAsRequestsArrive() throws {
        let project = try makeProject()
        var requests = [
            #"{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}"#,
        ].makeIterator()
        let output = Pipe()
        let error = Pipe()

        let exitCode = MyWikiMCPCommand.serve(
            arguments: ["KnowYou", "--my-wiki-mcp", "--project-root", project.path],
            input: { requests.next() },
            outputHandle: output.fileHandleForWriting,
            errorHandle: error.fileHandleForWriting
        )
        try output.fileHandleForWriting.close()
        try error.fileHandleForWriting.close()

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8), "")
        let responseText = try XCTUnwrap(String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8))
        let response = try decodeJSONLine(responseText)
        XCTAssertNotNil(response["result"])
    }

    func testNativeMCPContextToolReturnsCitedContextForBackground() throws {
        let project = try makeProject()
        let result = MyWikiMCPCommand.run(
            arguments: ["KnowYou", "--my-wiki-mcp", "--project-root", project.path],
            input: """
            {"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"my_wiki_context","arguments":{"background":"An external agent needs context about agent context retrieval from My Wiki before answering.","max_items":3,"character_budget":1200}}}

            """
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stderr, "")

        let response = try decodeJSONLine(result.stdout)
        let resultObject = try XCTUnwrap(response["result"] as? [String: Any])
        let content = try XCTUnwrap(resultObject["content"] as? [[String: Any]])
        let text = try XCTUnwrap(content.first?["text"] as? String)
        let pack = try JSONDecoder().decode(MyWikiContextPack.self, from: Data(text.utf8))
        XCTAssertEqual(pack.items.first?.citation.relativePath, "wiki/concepts/agent-context.md")
    }

    func testNativeMCPReadPageAcceptsCitationRelativePath() throws {
        let project = try makeProject()
        let result = MyWikiMCPCommand.run(
            arguments: ["KnowYou", "--my-wiki-mcp", "--project-root", project.path],
            input: #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"my_wiki_read_page","arguments":{"relativePath":"wiki/concepts/agent-context.md"}}}"# + "\n"
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stderr, "")

        let response = try decodeJSONLine(result.stdout)
        XCTAssertNil(response["error"])
        let resultObject = try XCTUnwrap(response["result"] as? [String: Any])
        let content = try XCTUnwrap(resultObject["content"] as? [[String: Any]])
        let text = try XCTUnwrap(content.first?["text"] as? String)
        XCTAssertTrue(text.contains("My Wiki can provide cited agent context to local tools."))
    }

    func testNativeMCPReadPageRejectsTraversalInsideAllowedPrefixes() throws {
        let project = try makeProject()
        let result = MyWikiMCPCommand.run(
            arguments: ["KnowYou", "--my-wiki-mcp", "--project-root", project.path],
            input: #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"my_wiki_read_page","arguments":{"path":"raw/sources/../wiki/concepts/agent-context.md"}}}"# + "\n"
        )

        XCTAssertEqual(result.exitCode, 0)
        let response = try decodeJSONLine(result.stdout)
        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["message"] as? String, "Invalid page path")
    }

    private func makeProject() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let project = root.appending(path: "KnowledgeOntology/KnowYouContext", directoryHint: .isDirectory)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }

        try write(
            """
            ---
            type: concept
            title: Agent Context
            ---

            # Agent Context

            My Wiki can provide cited agent context to local tools.
            """,
            to: project.appending(path: "wiki/concepts/agent-context.md")
        )

        return project
    }

    private func write(_ contents: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func decodeJSONLine(_ output: String) throws -> [String: Any] {
        let line = try XCTUnwrap(output.split(separator: "\n").first)
        let data = Data(line.utf8)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
