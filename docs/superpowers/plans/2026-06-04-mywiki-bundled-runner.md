# MyWiki Bundled Runner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship MyWiki generation as an internal `KnowYou.app` capability that uses bundled `MyWikiRunner` plus the existing Diary Engine, with no user-visible `LLM Wiki.app`, npm, Node install, or second API configuration.

**Architecture:** Add a private `Contents/Resources/MyWikiRunner` runtime with fixed Node and a bundled JS headless runner. Swift resolves only that runner for product MyWiki generation, talks to it via stdin/stdout JSONL, and handles LLM requests by calling the current Diary Engine. `ThirdParty/llm_wiki` remains source input for building the runner, not a user runtime.

**Tech Stack:** Swift/XCTest, `Process`, JSONL protocol, existing `SummaryGenerating`/`LLMAPIClient`/Diary Engine config, TypeScript/Vitest, Vite library build, bash release scripts, macOS codesign/notarization checks.

---

## File Structure

- Modify: `KnowYou/Services/MyWiki/MyWikiPipelineBridge.swift`
  - Replace `.bundledHelperApp` with `.bundledRunner(MyWikiRunnerBundle)`.
  - Remove `LLM Wiki.app` as a valid MyWiki generation target.
  - Start bundled runner with JSONL bridge instead of `npm run knowyou:ingest`.
- Create: `KnowYou/Services/MyWiki/MyWikiRunnerBundle.swift`
  - Resolve `Bundle.main.resourceURL/MyWikiRunner/node` and `MyWikiRunner/mywiki-runner.js`.
  - Validate executability and product/development target rules.
- Create: `KnowYou/Services/MyWiki/MyWikiLLMBridge.swift`
  - Define JSONL request/response/error models.
  - Convert runner `llm.request` messages into Diary Engine calls.
- Modify: `KnowYou/Services/Summary/CloudSummarizer.swift`
  - Add a provider-neutral chat completion method that can accept system/user/assistant messages.
- Modify: `KnowYou/App/AppState.swift`, `KnowYou/UI/MyWiki/MyWikiPanel.swift`, `KnowYou/UI/MainWindowView.swift`
  - Stop passing `KnowledgeOntologyLauncher.defaultBundledHelperAppURL()` into MyWiki.
  - Use `MyWikiRunnerBundle.defaultURL()` for target resolution.
- Modify or delete: `KnowYou/Services/KnowledgeOntology/KnowledgeOntologyLauncher.swift`, `KnowYou/UI/KnowledgeOntology/KnowledgeOntologyPanel.swift`
  - Remove product path references to `LLM Wiki.app`; keep only if another current UI still compiles through it, and mark it unavailable for MyWiki generation.
- Modify: `ThirdParty/llm_wiki/src/stores/wiki-store.ts`
  - Add `provider: "knowyou-bridge"`.
- Create: `ThirdParty/llm_wiki/src/headless/knowyou-bridge-transport.ts`
  - Implement JSONL request/response over process stdio.
- Modify: `ThirdParty/llm_wiki/src/lib/llm-client.ts`
  - Dispatch `provider === "knowyou-bridge"` before HTTP providers.
- Modify: `ThirdParty/llm_wiki/src/headless/knowyou-ingest.ts`
  - Add `--provider knowyou-bridge`; make it the bundled runner default.
- Create: `ThirdParty/llm_wiki/vite.headless.config.ts`
  - Build `src/headless/knowyou-ingest.ts` into one JS runner bundle without `node_modules`.
- Modify: `ThirdParty/llm_wiki/package.json`
  - Add `build:knowyou-runner` script.
- Create: `scripts/build-mywiki-runner.sh`
  - Build runner bundle and assemble `build/MyWikiRunner`.
- Modify: `scripts/build-release.sh`, `scripts/release-common.sh`, `scripts/test-release-common.sh`
  - Copy runner into app resources and sign nested executable resources.
- Create: `scripts/test-mywiki-runner-package.sh`
  - Verify no `node_modules`, no `LLM Wiki.app`, and no runtime `npm run`.
- Create: `scripts/verify-mywiki-real-diary.sh`
  - Real Diary acceptance harness for ontology output.
- Modify: `docs/architecture.md`, `docs/requirements-spec.md`
  - Replace development-source/npm MyWiki runtime description with bundled runner + Diary Engine bridge.

---

### Task 1: Product Target Resolution Removes `LLM Wiki.app`

**Files:**
- Create: `KnowYou/Services/MyWiki/MyWikiRunnerBundle.swift`
- Modify: `KnowYou/Services/MyWiki/MyWikiPipelineBridge.swift`
- Modify: `KnowYou.xcodeproj/project.pbxproj`
- Test: `KnowYouTests/MyWikiPipelineBridgeTests.swift`

- [ ] **Step 1: Write failing target-resolution tests**

Append tests to `KnowYouTests/MyWikiPipelineBridgeTests.swift`:

```swift
func testResolvePipelineUsesBundledMyWikiRunnerAndIgnoresLLMWikiApp() throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }

    let resources = root.appending(path: "Resources", directoryHint: .isDirectory)
    let runner = resources.appending(path: "MyWikiRunner", directoryHint: .isDirectory)
    let node = runner.appending(path: "node")
    let script = runner.appending(path: "mywiki-runner.js")
    let llmWikiApp = resources.appending(path: "KnowledgeOntology/LLM Wiki.app", directoryHint: .isDirectory)

    try FileManager.default.createDirectory(at: llmWikiApp, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: runner, withIntermediateDirectories: true)
    try "#!/usr/bin/env bash\n".write(to: node, atomically: true, encoding: .utf8)
    try "console.log('ok')\n".write(to: script, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: node.path)

    let bundle = try MyWikiRunnerBundle(rootURL: runner)
    let target = MyWikiPipelineBridge.resolveTarget(
        bundledRunner: bundle,
        developmentSourceURL: nil
    )

    XCTAssertEqual(target.statusDescription, "Using bundled MyWiki runner: \(runner.path)")
}

func testResolvePipelineDoesNotTreatLLMWikiAppAsValidRunner() throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }

    let llmWikiApp = root.appending(path: "KnowledgeOntology/LLM Wiki.app", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: llmWikiApp, withIntermediateDirectories: true)

    let target = MyWikiPipelineBridge.resolveTarget(
        bundledRunner: nil,
        developmentSourceURL: nil
    )

    XCTAssertEqual(target, .missing)
}
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MyWikiPipelineBridgeTests
```

Expected: FAIL because `MyWikiRunnerBundle` and the new `resolveTarget(bundledRunner:developmentSourceURL:)` signature do not exist.

- [ ] **Step 3: Implement `MyWikiRunnerBundle`**

Create `KnowYou/Services/MyWiki/MyWikiRunnerBundle.swift`:

```swift
import Foundation

struct MyWikiRunnerBundle: Equatable, Sendable {
    let rootURL: URL
    let nodeURL: URL
    let scriptURL: URL

    init(rootURL: URL, fileManager: FileManager = .default) throws {
        let nodeURL = rootURL.appending(path: "node")
        let scriptURL = rootURL.appending(path: "mywiki-runner.js")
        guard fileManager.isExecutableFile(atPath: nodeURL.path) else {
            throw MyWikiPipelineBridgeError.pipelineExecutionFailed("Bundled MyWiki runner node is missing or not executable.")
        }
        guard fileManager.fileExists(atPath: scriptURL.path) else {
            throw MyWikiPipelineBridgeError.pipelineExecutionFailed("Bundled MyWiki runner script is missing.")
        }
        self.rootURL = rootURL
        self.nodeURL = nodeURL
        self.scriptURL = scriptURL
    }

    static func defaultBundleURL(bundle: Bundle = .main) -> URL? {
        bundle.resourceURL?.appending(path: "MyWikiRunner", directoryHint: .isDirectory)
    }

    static func resolveDefault(bundle: Bundle = .main, fileManager: FileManager = .default) -> MyWikiRunnerBundle? {
        guard let url = defaultBundleURL(bundle: bundle) else { return nil }
        return try? MyWikiRunnerBundle(rootURL: url, fileManager: fileManager)
    }
}
```

- [ ] **Step 4: Update target enum and resolver**

Modify `KnowYou/Services/MyWiki/MyWikiPipelineBridge.swift`:

```swift
enum MyWikiPipelineTarget: Equatable {
    case bundledRunner(MyWikiRunnerBundle)
    case developmentSource(URL)
    case missing

    var statusDescription: String {
        switch self {
        case .bundledRunner(let bundle):
            return "Using bundled MyWiki runner: \(bundle.rootURL.path)"
        case .developmentSource(let url):
            return "Using development llm_wiki pipeline: \(url.path)"
        case .missing:
            return "MyWiki runner is not available."
        }
    }
}
```

Replace `resolveTarget` with:

```swift
static func resolveTarget(
    bundledRunner: MyWikiRunnerBundle?,
    developmentSourceURL: URL?,
    fileManager: FileManager = .default
) -> MyWikiPipelineTarget {
    if let bundledRunner {
        return .bundledRunner(bundledRunner)
    }
    if let developmentSourceURL,
       fileManager.fileExists(atPath: developmentSourceURL.path) {
        return .developmentSource(developmentSourceURL)
    }
    return .missing
}
```

- [ ] **Step 5: Update old tests to compile**

Change existing test calls from:

```swift
MyWikiPipelineBridge.resolveTarget(
    bundledHelperAppURL: nil,
    developmentSourceURL: dev
)
```

to:

```swift
MyWikiPipelineBridge.resolveTarget(
    bundledRunner: nil,
    developmentSourceURL: dev
)
```

Change bundled-helper assertions to bundled-runner assertions. Delete tests that expect `.bundledHelperApp`.

- [ ] **Step 6: Add new source file to the Xcode project**

Modify `KnowYou.xcodeproj/project.pbxproj` to include `MyWikiRunnerBundle.swift` in the app target's MyWiki group and Sources build phase. Follow the existing pattern around `MyWikiPipelineBridge.swift`.

- [ ] **Step 7: Run target tests**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' \
  -only-testing:KnowYouTests/MyWikiPipelineBridgeTests/testResolvePipelineUsesBundledMyWikiRunnerAndIgnoresLLMWikiApp \
  -only-testing:KnowYouTests/MyWikiPipelineBridgeTests/testResolvePipelineDoesNotTreatLLMWikiAppAsValidRunner
```

Expected: PASS.

---

### Task 2: Swift JSONL LLM Bridge Reuses Diary Engine

**Files:**
- Create: `KnowYou/Services/MyWiki/MyWikiLLMBridge.swift`
- Modify: `KnowYou/Services/Summary/CloudSummarizer.swift`
- Test: `KnowYouTests/MyWikiLLMBridgeTests.swift`
- Modify project: `KnowYou.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add failing bridge tests**

Create `KnowYouTests/MyWikiLLMBridgeTests.swift`:

```swift
import XCTest
@testable import KnowYou

final class MyWikiLLMBridgeTests: XCTestCase {
    func testBridgeAnswersLLMRequestUsingInjectedDiaryEngine() async throws {
        let engine = StubMyWikiLLMEngine(result: "Ontology page draft")
        let bridge = MyWikiLLMBridge(engine: engine)

        let response = try await bridge.handle(
            MyWikiBridgeEnvelope.llmRequest(
                MyWikiLLMRequest(
                    id: "req-1",
                    messages: [
                        MyWikiLLMMessage(role: "system", content: "Extract ontology."),
                        MyWikiLLMMessage(role: "user", content: "Diary text")
                    ],
                    temperature: 0.2
                )
            )
        )

        XCTAssertEqual(response, .llmResponse(MyWikiLLMResponse(id: "req-1", content: "Ontology page draft")))
        XCTAssertEqual(engine.requests.first?.messages.map(\.role), ["system", "user"])
    }

    func testBridgeMapsDiaryEngineFailureToStructuredError() async throws {
        let engine = StubMyWikiLLMEngine(error: URLError(.userAuthenticationRequired))
        let bridge = MyWikiLLMBridge(engine: engine)

        let response = try await bridge.handle(
            .llmRequest(
                MyWikiLLMRequest(
                    id: "req-auth",
                    messages: [MyWikiLLMMessage(role: "user", content: "Diary text")],
                    temperature: nil
                )
            )
        )

        XCTAssertEqual(
            response,
            .llmError(MyWikiLLMErrorResponse(id: "req-auth", code: "auth_failed", message: "Diary Engine authentication failed."))
        )
    }
}

private final class StubMyWikiLLMEngine: MyWikiLLMCompleting {
    struct Request: Equatable {
        let messages: [MyWikiLLMMessage]
        let temperature: Double?
    }

    private let result: String?
    private let error: Error?
    private(set) var requests: [Request] = []

    init(result: String) {
        self.result = result
        self.error = nil
    }

    init(error: Error) {
        self.result = nil
        self.error = error
    }

    func complete(messages: [MyWikiLLMMessage], temperature: Double?) async throws -> String {
        requests.append(Request(messages: messages, temperature: temperature))
        if let error { throw error }
        return result ?? ""
    }
}
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MyWikiLLMBridgeTests
```

Expected: FAIL because bridge types do not exist and test file is not in the Xcode test target yet.

- [ ] **Step 3: Add bridge types**

Create `KnowYou/Services/MyWiki/MyWikiLLMBridge.swift`:

```swift
import Foundation

protocol MyWikiLLMCompleting: Sendable {
    func complete(messages: [MyWikiLLMMessage], temperature: Double?) async throws -> String
}

struct MyWikiLLMMessage: Codable, Equatable, Sendable {
    let role: String
    let content: String
}

struct MyWikiLLMRequest: Codable, Equatable, Sendable {
    let id: String
    let messages: [MyWikiLLMMessage]
    let temperature: Double?
}

struct MyWikiLLMResponse: Codable, Equatable, Sendable {
    let id: String
    let content: String
}

struct MyWikiLLMErrorResponse: Codable, Equatable, Sendable {
    let id: String
    let code: String
    let message: String
}

enum MyWikiBridgeEnvelope: Codable, Equatable, Sendable {
    case llmRequest(MyWikiLLMRequest)
    case llmResponse(MyWikiLLMResponse)
    case llmError(MyWikiLLMErrorResponse)
}

struct MyWikiLLMBridge: Sendable {
    let engine: MyWikiLLMCompleting

    func handle(_ envelope: MyWikiBridgeEnvelope) async throws -> MyWikiBridgeEnvelope {
        switch envelope {
        case .llmRequest(let request):
            do {
                let content = try await engine.complete(
                    messages: request.messages,
                    temperature: request.temperature
                )
                return .llmResponse(MyWikiLLMResponse(id: request.id, content: content))
            } catch {
                return .llmError(
                    MyWikiLLMErrorResponse(
                        id: request.id,
                        code: Self.code(for: error),
                        message: Self.message(for: error)
                    )
                )
            }
        case .llmResponse, .llmError:
            throw MyWikiPipelineBridgeError.pipelineExecutionFailed("Runner sent an unexpected MyWiki bridge response.")
        }
    }

    private static func code(for error: Error) -> String {
        if let urlError = error as? URLError,
           urlError.code == .userAuthenticationRequired || urlError.code == .userCancelledAuthentication {
            return "auth_failed"
        }
        return "engine_failed"
    }

    private static func message(for error: Error) -> String {
        if code(for: error) == "auth_failed" {
            return "Diary Engine authentication failed."
        }
        return error.localizedDescription
    }
}
```

Add custom `Codable` implementation for `MyWikiBridgeEnvelope` in the same file:

```swift
extension MyWikiBridgeEnvelope {
    private enum CodingKeys: String, CodingKey {
        case type
        case id
        case messages
        case temperature
        case content
        case code
        case message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "llm.request":
            self = .llmRequest(
                MyWikiLLMRequest(
                    id: try container.decode(String.self, forKey: .id),
                    messages: try container.decode([MyWikiLLMMessage].self, forKey: .messages),
                    temperature: try container.decodeIfPresent(Double.self, forKey: .temperature)
                )
            )
        case "llm.response":
            self = .llmResponse(
                MyWikiLLMResponse(
                    id: try container.decode(String.self, forKey: .id),
                    content: try container.decode(String.self, forKey: .content)
                )
            )
        case "llm.error":
            self = .llmError(
                MyWikiLLMErrorResponse(
                    id: try container.decode(String.self, forKey: .id),
                    code: try container.decode(String.self, forKey: .code),
                    message: try container.decode(String.self, forKey: .message)
                )
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown MyWiki bridge envelope type: \(type)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .llmRequest(let request):
            try container.encode("llm.request", forKey: .type)
            try container.encode(request.id, forKey: .id)
            try container.encode(request.messages, forKey: .messages)
            try container.encodeIfPresent(request.temperature, forKey: .temperature)
        case .llmResponse(let response):
            try container.encode("llm.response", forKey: .type)
            try container.encode(response.id, forKey: .id)
            try container.encode(response.content, forKey: .content)
        case .llmError(let response):
            try container.encode("llm.error", forKey: .type)
            try container.encode(response.id, forKey: .id)
            try container.encode(response.code, forKey: .code)
            try container.encode(response.message, forKey: .message)
        }
    }
}
```

- [ ] **Step 4: Add Diary Engine chat adapter**

In `CloudSummarizer.swift`, add:

```swift
extension CloudSummarizer: MyWikiLLMCompleting {
    func complete(messages: [MyWikiLLMMessage], temperature: Double?) async throws -> String {
        let systemPrompt = messages
            .filter { $0.role == "system" }
            .map(\.content)
            .joined(separator: "\n\n")
        let input = messages
            .filter { $0.role != "system" }
            .map { "\($0.role):\n\($0.content)" }
            .joined(separator: "\n\n")
        return try await LLMAPIClient(providerConfig: providerConfig, session: session)
            .complete(input: input, systemPrompt: systemPrompt.isEmpty ? nil : systemPrompt)
    }
}
```

In `CLISummarizer.swift`, add:

```swift
extension CLISummarizer: MyWikiLLMCompleting {
    func complete(messages: [MyWikiLLMMessage], temperature: Double?) async throws -> String {
        let prompt = messages
            .map { "\($0.role.uppercased()):\n\($0.content)" }
            .joined(separator: "\n\n")
        return try await summarize(dayKey: "mywiki", markdown: prompt, context: .automationRefresh)
    }
}
```

- [ ] **Step 5: Add files to Xcode project**

Modify `KnowYou.xcodeproj/project.pbxproj` to include:

- `MyWikiRunnerBundle.swift` in app Sources.
- `MyWikiLLMBridge.swift` in app Sources.
- `MyWikiLLMBridgeTests.swift` in test Sources.

Follow existing IDs/pattern near the MyWiki group.

- [ ] **Step 6: Run bridge tests**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MyWikiLLMBridgeTests
```

Expected: PASS.

---

### Task 3: Runner Process Uses JSONL and Never Receives API Secrets

**Files:**
- Modify: `KnowYou/Services/MyWiki/MyWikiPipelineBridge.swift`
- Test: `KnowYouTests/MyWikiPipelineBridgeTests.swift`

- [ ] **Step 1: Add failing process tests**

Append:

```swift
func testBundledRunnerInvocationUsesNodeAndScriptWithoutAPISecret() throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }

    let runnerRoot = root.appending(path: "MyWikiRunner", directoryHint: .isDirectory)
    let node = runnerRoot.appending(path: "node")
    let script = runnerRoot.appending(path: "mywiki-runner.js")
    try FileManager.default.createDirectory(at: runnerRoot, withIntermediateDirectories: true)
    try "#!/usr/bin/env bash\n".write(to: node, atomically: true, encoding: .utf8)
    try "console.log('ok')\n".write(to: script, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: node.path)

    let process = RecordingMyWikiRunnerProcess(
        events: [
            #"{"type":"runner.done","status":"succeeded","filesWritten":["wiki/sources/2026-06-04.md","wiki/entities/knowyou.md","wiki/concepts/mywiki.md"]}"#
        ],
        terminationStatus: 0
    )
    let bridge = MyWikiPipelineBridge(
        runnerProcess: process,
        llmBridge: MyWikiLLMBridge(engine: StubMyWikiLLMEngine(result: "ok"))
    )

    try bridge.runIngest(
        target: .bundledRunner(try MyWikiRunnerBundle(rootURL: runnerRoot)),
        projectRoot: root,
        manifestURL: root.appending(path: ".knowyou/ingest-manifest.json")
    )

    XCTAssertEqual(process.calls.first?.executable, node.path)
    XCTAssertTrue(process.calls.first?.arguments.contains(script.path) == true)
    XCTAssertFalse(process.calls.first?.arguments.contains("sk-secret") == true)
    XCTAssertFalse(process.calls.first?.environment.values.contains("sk-secret") == true)
}
```

- [ ] **Step 2: Run test and verify failure**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MyWikiPipelineBridgeTests/testBundledRunnerInvocationUsesNodeAndScriptWithoutAPISecret
```

Expected: FAIL because `runnerProcess` and JSONL events do not exist.

- [ ] **Step 3: Replace bundled runner failure with process execution**

In `MyWikiPipelineBridge.swift`, introduce:

```swift
protocol MyWikiRunnerProcessRunning: Sendable {
    func run(
        executable: String,
        arguments: [String],
        workingDirectory: URL,
        environment: [String: String],
        timeoutSeconds: TimeInterval,
        onEvent: @escaping @Sendable (String) async throws -> String?
    ) async throws -> MyWikiPipelineProcessResult
}
```

Add `DefaultMyWikiRunnerProcess` using `Process`, `Pipe`, `readabilityHandler`, and `standardInput`. Each stdout line is decoded as JSONL. If the line is `llm.request`, call `onEvent` and write returned JSONL response to stdin.

Change `runIngest` to be async:

```swift
func runIngest(target: MyWikiPipelineTarget, projectRoot: URL, manifestURL: URL? = nil) async throws
```

For `.bundledRunner(let bundle)`, build arguments:

```swift
var arguments = [
    bundle.scriptURL.path,
    "--project",
    projectRoot.path,
    "--provider",
    "knowyou-bridge",
    "--max-sources",
    "\(MyWikiIngestBatchPolicy.maxSourcesPerRun)"
]
if let manifestURL {
    arguments.append(contentsOf: ["--manifest", manifestURL.path])
}
```

Do not include API key, endpoint, provider model, or CLI paths in arguments/environment.

- [ ] **Step 4: Wire bridge events**

Inside `.bundledRunner` process call:

```swift
let encoder = JSONEncoder()
let decoder = JSONDecoder()
let result = try await runnerProcess.run(
    executable: bundle.nodeURL.path,
    arguments: arguments,
    workingDirectory: bundle.rootURL,
    environment: [:],
    timeoutSeconds: 30 * 60
) { line in
    guard let data = line.data(using: .utf8) else { return nil }
    let envelope = try decoder.decode(MyWikiBridgeEnvelope.self, from: data)
    let response = try await llmBridge.handle(envelope)
    return String(data: try encoder.encode(response), encoding: .utf8)
}
```

- [ ] **Step 5: Update `MyWikiDigestRunner` for async ingest**

Change:

```swift
try MyWikiPipelineBridge(llmInvocation: resolvedLLMInvocation).runIngest(...)
```

to:

```swift
try await MyWikiPipelineBridge(llmBridge: resolvedLLMBridge).runIngest(...)
```

Resolve `resolvedLLMBridge` from the active `SummaryGenerating`/Diary Engine. Keep development source fallback behind debug-only code if needed, but product `.bundledRunner` must not use `MyWikiLLMInvocation`.

- [ ] **Step 6: Run tests**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MyWikiPipelineBridgeTests -only-testing:KnowYouTests/MyWikiLLMBridgeTests
```

Expected: PASS.

---

### Task 4: TypeScript `knowyou-bridge` Provider

**Files:**
- Modify: `ThirdParty/llm_wiki/src/stores/wiki-store.ts`
- Create: `ThirdParty/llm_wiki/src/headless/knowyou-bridge-transport.ts`
- Modify: `ThirdParty/llm_wiki/src/lib/llm-client.ts`
- Modify: `ThirdParty/llm_wiki/src/headless/knowyou-ingest.ts`
- Test: `ThirdParty/llm_wiki/src/headless/knowyou-bridge-transport.test.ts`
- Test: `ThirdParty/llm_wiki/src/headless/knowyou-ingest.test.ts`

- [ ] **Step 1: Add failing transport test**

Create `ThirdParty/llm_wiki/src/headless/knowyou-bridge-transport.test.ts`:

```ts
import { describe, expect, it, vi } from "vitest"
import { streamKnowYouBridge } from "./knowyou-bridge-transport"

describe("KnowYou bridge transport", () => {
  it("sends llm.request JSONL and streams the returned content", async () => {
    const writes: string[] = []
    const transport = {
      write: vi.fn((line: string) => writes.push(line)),
      waitForResponse: vi.fn(async () => ({
        type: "llm.response",
        id: "req-1",
        content: "Generated ontology",
      })),
    }
    const tokens: string[] = []

    await streamKnowYouBridge(
      { provider: "knowyou-bridge", apiKey: "", model: "diary-engine", ollamaUrl: "", customEndpoint: "", maxContextSize: 128000 },
      [{ role: "user", content: "Diary text" }],
      {
        onToken: (token) => tokens.push(token),
        onDone: vi.fn(),
        onError: (error) => { throw error },
      },
      undefined,
      { temperature: 0.2 },
      transport,
    )

    expect(JSON.parse(writes[0])).toMatchObject({
      type: "llm.request",
      messages: [{ role: "user", content: "Diary text" }],
      temperature: 0.2,
    })
    expect(tokens.join("")).toBe("Generated ontology")
  })
})
```

- [ ] **Step 2: Run test and verify failure**

Run:

```bash
cd ThirdParty/llm_wiki
npx vitest run src/headless/knowyou-bridge-transport.test.ts
```

Expected: FAIL because the transport module and provider type do not exist.

- [ ] **Step 3: Add provider type**

Modify `ThirdParty/llm_wiki/src/stores/wiki-store.ts`:

```ts
interface LlmConfig {
  provider:
    | "openai"
    | "anthropic"
    | "google"
    | "ollama"
    | "custom"
    | "minimax"
    | "claude-code"
    | "codex-cli"
    | "knowyou-bridge"
  apiKey: string
  model: string
  ollamaUrl: string
  customEndpoint: string
  maxContextSize: number
  apiMode?: CustomApiMode
  reasoning?: ReasoningConfig
}
```

- [ ] **Step 4: Implement bridge transport**

Create `ThirdParty/llm_wiki/src/headless/knowyou-bridge-transport.ts`:

```ts
import type { LlmConfig } from "@/stores/wiki-store"
import type { ChatMessage, RequestOverrides } from "@/lib/llm-providers"
import type { StreamCallbacks } from "@/lib/llm-client"

interface BridgeResponse {
  type: "llm.response" | "llm.error"
  id: string
  content?: string
  code?: string
  message?: string
}

export interface KnowYouBridgeTransport {
  write(line: string): void
  waitForResponse(id: string, signal?: AbortSignal): Promise<BridgeResponse>
}

let sequence = 0

export async function streamKnowYouBridge(
  _config: LlmConfig,
  messages: ChatMessage[],
  callbacks: StreamCallbacks,
  signal?: AbortSignal,
  requestOverrides?: RequestOverrides,
  transport: KnowYouBridgeTransport = processBridgeTransport(),
): Promise<void> {
  const id = `req-${++sequence}`
  transport.write(`${JSON.stringify({
    type: "llm.request",
    id,
    messages,
    temperature: requestOverrides?.temperature,
  })}\n`)
  const response = await transport.waitForResponse(id, signal)
  if (response.type === "llm.error") {
    callbacks.onError(new Error(response.message ?? response.code ?? "KnowYou Diary Engine failed."))
    return
  }
  callbacks.onToken(response.content ?? "")
  callbacks.onDone()
}
```

Implement `processBridgeTransport()` in the same file using `process.stdin`, `process.stdout`, and a pending-response map keyed by `id`.

- [ ] **Step 5: Dispatch in llm-client**

In `ThirdParty/llm_wiki/src/lib/llm-client.ts`, before HTTP providers:

```ts
if (config.provider === "knowyou-bridge") {
  const mod = await import("@/headless/knowyou-bridge-transport")
  return mod.streamKnowYouBridge(config, messages, callbacks, signal, requestOverrides)
}
```

- [ ] **Step 6: Make headless runner default to bridge**

In `ThirdParty/llm_wiki/src/headless/knowyou-ingest.ts`, change:

```ts
const provider = options.provider ?? "codex-cli"
```

to:

```ts
const provider = options.provider ?? "knowyou-bridge"
```

Keep CLI args for development, but bundled Swift must pass `--provider knowyou-bridge`.

- [ ] **Step 7: Add ingest test for bridge config**

In `knowyou-ingest.test.ts`, assert `runKnowYouIngest({ projectPath })` creates `llmConfig.provider === "knowyou-bridge"` in the mocked `streamChat` configs.

- [ ] **Step 8: Run focused tests**

Run:

```bash
cd ThirdParty/llm_wiki
npx vitest run src/headless/knowyou-bridge-transport.test.ts src/headless/knowyou-ingest.test.ts
```

Expected: PASS.

---

### Task 5: Build a Bundled Runner Without `node_modules`

**Files:**
- Create: `ThirdParty/llm_wiki/vite.headless.config.ts`
- Modify: `ThirdParty/llm_wiki/package.json`
- Create: `scripts/build-mywiki-runner.sh`
- Create: `scripts/test-mywiki-runner-package.sh`

- [ ] **Step 1: Write failing package test**

Create `scripts/test-mywiki-runner-package.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
runner_dir="${KNOWYOU_MYWIKI_RUNNER_DIR:-$repo_root/build/MyWikiRunner}"

"$repo_root/scripts/build-mywiki-runner.sh"

[[ -x "$runner_dir/node" ]] || { echo "Missing executable node"; exit 1; }
[[ -f "$runner_dir/mywiki-runner.js" ]] || { echo "Missing mywiki-runner.js"; exit 1; }
[[ ! -d "$runner_dir/node_modules" ]] || { echo "Runner must not ship node_modules"; exit 1; }
[[ ! -d "$runner_dir/LLM Wiki.app" ]] || { echo "Runner must not ship LLM Wiki.app"; exit 1; }

if rg -n "npm run|npm install|node_modules" "$runner_dir/mywiki-runner.js"; then
  echo "Runner bundle contains runtime npm/node_modules dependency text"
  exit 1
fi

"$runner_dir/node" "$runner_dir/mywiki-runner.js" --help >/tmp/knowyou-mywiki-runner-help.txt 2>&1 || true
rg -n "Missing required --project|Usage|--project" /tmp/knowyou-mywiki-runner-help.txt >/dev/null
echo "mywiki runner package tests passed"
```

- [ ] **Step 2: Run and verify failure**

Run:

```bash
chmod +x scripts/test-mywiki-runner-package.sh
scripts/test-mywiki-runner-package.sh
```

Expected: FAIL because `scripts/build-mywiki-runner.sh` does not exist.

- [ ] **Step 3: Add headless Vite config**

Create `ThirdParty/llm_wiki/vite.headless.config.ts`:

```ts
import path from "node:path"
import { defineConfig } from "vite"

export default defineConfig({
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
      "@/commands/fs": path.resolve(__dirname, "src/headless/node-fs.ts"),
      "@tauri-apps/api/core": path.resolve(__dirname, "src/headless/tauri-core.ts"),
      "@tauri-apps/api/event": path.resolve(__dirname, "src/headless/tauri-event.ts"),
    },
  },
  build: {
    ssr: "src/headless/knowyou-ingest.ts",
    outDir: "dist-knowyou-runner",
    emptyOutDir: true,
    rollupOptions: {
      output: {
        entryFileNames: "mywiki-runner.js",
        format: "es",
      },
      external: [
        "node:fs/promises",
        "node:path",
        "node:process",
        "node:readline",
      ],
    },
  },
})
```

- [ ] **Step 4: Add package script**

Modify `ThirdParty/llm_wiki/package.json`:

```json
"build:knowyou-runner": "vite build --config vite.headless.config.ts"
```

- [ ] **Step 5: Add runner build script**

Create `scripts/build-mywiki-runner.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_dir="$repo_root/ThirdParty/llm_wiki"
runner_dir="${KNOWYOU_MYWIKI_RUNNER_DIR:-$repo_root/build/MyWikiRunner}"

node_bin="${KNOWYOU_BUNDLED_NODE:-$(command -v node || true)}"
if [[ -z "$node_bin" || ! -x "$node_bin" ]]; then
  echo "Missing Node binary for building MyWikiRunner. Set KNOWYOU_BUNDLED_NODE." >&2
  exit 1
fi

pushd "$source_dir" >/dev/null
npm run build:knowyou-runner
popd >/dev/null

rm -rf "$runner_dir"
mkdir -p "$runner_dir"
cp "$node_bin" "$runner_dir/node"
chmod 755 "$runner_dir/node"
cp "$source_dir/dist-knowyou-runner/mywiki-runner.js" "$runner_dir/mywiki-runner.js"

echo "MyWikiRunner: $runner_dir"
```

- [ ] **Step 6: Run package test**

Run:

```bash
chmod +x scripts/build-mywiki-runner.sh scripts/test-mywiki-runner-package.sh
scripts/test-mywiki-runner-package.sh
```

Expected: PASS.

---

### Task 6: Xcode/Release Packaging and Signing

**Files:**
- Modify: `scripts/build-release.sh`
- Modify: `scripts/release-common.sh`
- Modify: `scripts/test-release-common.sh`
- Modify: `scripts/build-dmg.sh` if the release flow expects runner before DMG

- [ ] **Step 1: Add release tests**

In `scripts/test-release-common.sh`, add assertions:

```bash
assert_contains "$release_common_script" 'sign_mywiki_runner_nested_code()' "release helper signs MyWikiRunner"
assert_contains "$release_common_script" 'Contents/Resources/MyWikiRunner/node' "release helper targets bundled MyWiki node"

build_release_script="$(cat "$repo_root/scripts/build-release.sh")"
assert_contains "$build_release_script" 'scripts/build-mywiki-runner.sh' "build release builds MyWikiRunner"
assert_contains "$build_release_script" 'Contents/Resources/MyWikiRunner' "build release copies MyWikiRunner"
assert_contains "$build_release_script" 'sign_mywiki_runner_nested_code "$app_path"' "build release signs MyWikiRunner"
```

- [ ] **Step 2: Run test and verify failure**

Run:

```bash
scripts/test-release-common.sh
```

Expected: FAIL on missing release helper/script strings.

- [ ] **Step 3: Add signing helper**

In `scripts/release-common.sh`:

```bash
sign_mywiki_runner_nested_code() {
  local target_app="${1:-$app_path}"
  local runner_node="$target_app/Contents/Resources/MyWikiRunner/node"
  if [[ ! -e "$runner_node" ]]; then
    echo "Missing bundled MyWikiRunner node: $runner_node" >&2
    exit 1
  fi
  codesign \
    --force \
    --options runtime \
    --timestamp \
    --sign "$developer_id_identity" \
    "$runner_node"
}
```

Call `sign_mywiki_runner_nested_code "$target_app"` from `sign_release_app_nested_code` before signing the main app.

- [ ] **Step 4: Copy runner during release build**

In `scripts/build-release.sh`, after `ditto "$archive_path/Products/Applications/KnowYou.app" "$app_path"`:

```bash
"$repo_root/scripts/build-mywiki-runner.sh"
rm -rf "$app_path/Contents/Resources/MyWikiRunner"
mkdir -p "$app_path/Contents/Resources"
ditto "$repo_root/build/MyWikiRunner" "$app_path/Contents/Resources/MyWikiRunner"
```

- [ ] **Step 5: Add no `LLM Wiki.app` release check**

In `scripts/verify-release.sh` or `scripts/test-release-common.sh`, add:

```bash
if [[ -d "$app_path/Contents/Resources/KnowledgeOntology/LLM Wiki.app" ]]; then
  echo "Release must not include LLM Wiki.app" >&2
  exit 1
fi
```

- [ ] **Step 6: Run release script tests**

Run:

```bash
scripts/test-release-common.sh
scripts/test-mywiki-runner-package.sh
```

Expected: PASS.

---

### Task 7: App/UI Uses Bundled Runner Only

**Files:**
- Modify: `KnowYou/App/AppState.swift`
- Modify: `KnowYou/UI/MyWiki/MyWikiPanel.swift`
- Modify: `KnowYou/UI/MainWindowView.swift`
- Test: `KnowYouTests/MainWindowViewModelTests.swift`
- Test: `KnowYouTests/MyWikiSourceLibraryPresentationTests.swift` if UI strings move

- [ ] **Step 1: Add failing AppState test**

Add a test near existing MyWiki automation tests:

```swift
func testRunMyWikiDigestResolvesBundledRunnerInsteadOfLLMWikiApp() async throws {
    let environment = try makeTestEnvironment()
    let appState = AppState(environment: environment)

    await appState.runMyWikiDigest(trigger: .manual)

    XCTAssertFalse(appState.automationJobsByKind[.wiki]?.detail.contains("LLM Wiki.app") == true)
}
```

If `makeTestEnvironment()` does not expose runner injection, add an initializer dependency:

```swift
myWikiRunnerBundle: MyWikiRunnerBundle? = MyWikiRunnerBundle.resolveDefault()
```

- [ ] **Step 2: Update AppState target resolution**

Replace:

```swift
let target = MyWikiPipelineBridge.resolveTarget(
    bundledHelperAppURL: KnowledgeOntologyLauncher.defaultBundledHelperAppURL(),
    developmentSourceURL: KnowledgeOntologyLauncher.defaultDevelopmentSourceURL()
)
```

with:

```swift
let target = MyWikiPipelineBridge.resolveTarget(
    bundledRunner: MyWikiRunnerBundle.resolveDefault(),
    developmentSourceURL: KnowledgeOntologyLauncher.defaultDevelopmentSourceURL()
)
```

If this is product code, pass `developmentSourceURL: nil` for release/runtime paths and keep source fallback only behind test/development injection.

- [ ] **Step 3: Update MyWikiPanel target resolution**

Replace `bundledHelperAppURL` stored properties with `bundledRunner: MyWikiRunnerBundle?`.

Replace:

```swift
MyWikiPipelineBridge.resolveTarget(
    bundledHelperAppURL: bundledHelperAppURL,
    developmentSourceURL: developmentSourceURL
)
```

with:

```swift
MyWikiPipelineBridge.resolveTarget(
    bundledRunner: bundledRunner,
    developmentSourceURL: developmentSourceURL
)
```

- [ ] **Step 4: Remove visible advanced workspace entry**

Search:

```bash
rg -n "Advanced|Workspace|LLM Wiki|KnowledgeOntologyLauncher|openAdvancedWorkspace" KnowYou
```

Delete or hide UI actions that open `LLM Wiki.app` as a product feature. Keep MyWiki agent connection features that do not depend on the GUI helper.

- [ ] **Step 5: Run UI/App tests**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MainWindowViewModelTests -only-testing:KnowYouTests/MyWikiSourceLibraryPresentationTests
```

Expected: PASS.

---

### Task 8: Real Diary Ontology Acceptance Test

**Files:**
- Create: `scripts/verify-mywiki-real-diary.sh`
- Create: `ThirdParty/llm_wiki/src/headless/fixtures/knowyou-real-diary/*.md` if no safe existing fixture exists
- Modify: `docs/superpowers/specs/2026-06-04-mywiki-bundled-runner-design.md` only if test details need clarification

- [ ] **Step 1: Create real diary fixture**

Create fixture files under `ThirdParty/llm_wiki/src/headless/fixtures/knowyou-real-diary/`:

`2026-06-01.md`:

```markdown
# 2026-06-01

Today I worked on KnowYou's MyWiki source library. The important thread was making Update My Wiki process only included sources. I discussed the runner packaging problem and realized ordinary users should not need npm.
```

`2026-06-02.md`:

```markdown
# 2026-06-02

I tested Diary Engine configuration with DeepSeek and OpenAI-compatible endpoints. The main product rule is that MyWiki should reuse the same Diary Engine instead of asking for a second API key.
```

`2026-06-03.md`:

```markdown
# 2026-06-03

The release packaging work focused on the DMG drag-to-Applications layout and the bundled MyWikiRunner. The extra LLM Wiki.app should be removed so KnowYou stays simpler.
```

- [ ] **Step 2: Write failing verification script**

Create `scripts/verify-mywiki-real-diary.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/knowyou-mywiki-real-diary.XXXXXX")"
trap 'rm -rf "$tmp_root"' EXIT

project="$tmp_root/KnowYouContext"
mkdir -p "$project/raw/sources"
cp "$repo_root"/ThirdParty/llm_wiki/src/headless/fixtures/knowyou-real-diary/*.md "$project/raw/sources/"

"$repo_root/scripts/build-mywiki-runner.sh"
runner="$repo_root/build/MyWikiRunner"

cat >"$tmp_root/diary-engine-harness.mjs" <<'JS'
import { spawn } from "node:child_process"
import readline from "node:readline"

const [nodePath, runnerScript, projectPath] = process.argv.slice(2)
const child = spawn(nodePath, [
  runnerScript,
  "--project",
  projectPath,
  "--provider",
  "knowyou-bridge",
  "--max-sources",
  "3",
], {
  stdio: ["pipe", "pipe", "inherit"],
})

const ontologyContent = [
  "---FILE: wiki/sources/2026-06-01.md---",
  "---",
  "title: 2026-06-01",
  "type: source",
  "---",
  "KnowYou MyWiki source library work.",
  "---FILE: wiki/entities/knowyou.md---",
  "---",
  "title: KnowYou",
  "type: entity",
  "sources: [2026-06-01.md, 2026-06-03.md]",
  "---",
  "KnowYou is the app being simplified.",
  "---FILE: wiki/concepts/bundled-mywiki-runner.md---",
  "---",
  "title: Bundled MyWikiRunner",
  "type: concept",
  "sources: [2026-06-03.md]",
  "---",
  "A bundled runner removes npm from the user path.",
].join("\n")

const rl = readline.createInterface({ input: child.stdout })
rl.on("line", (line) => {
  let msg
  try {
    msg = JSON.parse(line)
  } catch {
    process.stdout.write(`${line}\n`)
    return
  }
  if (msg.type === "llm.request") {
    child.stdin.write(`${JSON.stringify({
      type: "llm.response",
      id: msg.id,
      content: ontologyContent,
    })}\n`)
  } else {
    process.stdout.write(`${line}\n`)
  }
})

const status = await new Promise((resolve) => {
  child.on("exit", (code) => resolve(code ?? 1))
})
process.exitCode = status
JS

node "$tmp_root/diary-engine-harness.mjs" "$runner/node" "$runner/mywiki-runner.js" "$project"

test -f "$project/wiki/sources/2026-06-01.md"
test -f "$project/wiki/entities/knowyou.md"
test -f "$project/wiki/concepts/bundled-mywiki-runner.md"
rg -n "sources:" "$project/wiki/entities/knowyou.md"
rg -n '"status": "succeeded"' "$project/.llm-wiki/last-ingest-status.json"
echo "real diary MyWiki ontology verification passed"
```

- [ ] **Step 3: Run and verify failure**

Run:

```bash
chmod +x scripts/verify-mywiki-real-diary.sh
scripts/verify-mywiki-real-diary.sh
```

Expected: FAIL until bridge transport and runner build are implemented.

- [ ] **Step 4: Make acceptance test pass**

Adjust runner/bridge process wiring so the script can complete. The output must include:

- `wiki/sources/*.md`
- `wiki/entities/*.md`
- `wiki/concepts/*.md`
- source traceability in frontmatter or body
- `.llm-wiki/last-ingest-status.json` with `"status": "succeeded"`

- [ ] **Step 5: Run acceptance verification**

Run:

```bash
scripts/verify-mywiki-real-diary.sh
```

Expected: PASS.

---

### Task 9: Remove Product References to `LLM Wiki.app`

**Files:**
- Modify/delete: `KnowYou/Services/KnowledgeOntology/KnowledgeOntologyLauncher.swift`
- Modify/delete: `KnowYou/UI/KnowledgeOntology/KnowledgeOntologyPanel.swift`
- Modify: `ThirdParty/llm_wiki/KNOWYOU_INTEGRATION_CN.md`
- Modify: `docs/architecture.md`
- Modify: `docs/requirements-spec.md`
- Test: `KnowYouTests/KnowledgeOntologyLauncherTests.swift`, `KnowYouTests/KnowledgeOntologyPanelTests.swift`

- [ ] **Step 1: Search product references**

Run:

```bash
rg -n "LLM Wiki\\.app|KnowledgeOntology/LLM Wiki|bundled helper|advanced workspace|openAdvancedWorkspace" KnowYou KnowYouTests docs ThirdParty/llm_wiki/KNOWYOU_INTEGRATION_CN.md
```

Expected before changes: references exist.

- [ ] **Step 2: Update or delete tests tied only to GUI helper**

For tests whose only purpose is proving `LLM Wiki.app` resolution, replace expectations with MyWikiRunner resolution. For tests that cover unrelated project export behavior, keep them.

- [ ] **Step 3: Remove product code paths**

Delete `openAdvancedWorkspace` from `MyWikiPipelineBridge` unless another non-MyWiki feature still needs it. Remove UI buttons that call it.

If `KnowledgeOntologyLauncher.swift` becomes unused, delete it and remove it from `KnowYou.xcodeproj/project.pbxproj`.

- [ ] **Step 4: Update docs**

In `docs/architecture.md`, replace the old paragraph:

```markdown
MyWikiPipelineBridge ... runtime calls ThirdParty/llm_wiki headless ingest ...
```

with:

```markdown
MyWikiPipelineBridge launches the bundled `Contents/Resources/MyWikiRunner` runtime. The runner hosts `llm_wiki` native `autoIngest`, and all LLM calls return to KnowYou through the MyWiki Diary Engine bridge. Product builds do not include `LLM Wiki.app`, `node_modules`, or `ThirdParty/llm_wiki` as runtime dependencies.
```

In `docs/requirements-spec.md`, add:

```markdown
- Product MyWiki generation must not depend on `LLM Wiki.app`, npm, user PATH, or development source directories.
```

- [ ] **Step 5: Verify no product references remain**

Run:

```bash
rg -n "LLM Wiki\\.app|KnowledgeOntology/LLM Wiki|openAdvancedWorkspace" KnowYou docs/architecture.md docs/requirements-spec.md
```

Expected: no product-path references. References inside historical `docs/superpowers/specs/*` are acceptable and should not be edited.

---

### Task 10: Full Verification and Commit

**Files:**
- All files changed above

- [ ] **Step 1: Run focused Swift tests**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' \
  -only-testing:KnowYouTests/MyWikiPipelineBridgeTests \
  -only-testing:KnowYouTests/MyWikiLLMBridgeTests \
  -only-testing:KnowYouTests/MainWindowViewModelTests \
  -only-testing:KnowYouTests/KnowledgeOntologyLauncherTests \
  -only-testing:KnowYouTests/KnowledgeOntologyPanelTests
```

Expected: PASS. If `KnowledgeOntologyLauncherTests` or `KnowledgeOntologyPanelTests` were deleted with their product code, remove only those `-only-testing:` arguments from this command and confirm `rg -n "KnowledgeOntologyLauncherTests|KnowledgeOntologyPanelTests" KnowYou.xcodeproj/project.pbxproj` returns no matches.

- [ ] **Step 2: Run focused TypeScript tests**

Run:

```bash
cd ThirdParty/llm_wiki
npx vitest run src/headless/knowyou-bridge-transport.test.ts src/headless/knowyou-ingest.test.ts
```

Expected: PASS.

- [ ] **Step 3: Run packaging checks**

Run:

```bash
scripts/test-mywiki-runner-package.sh
scripts/test-release-common.sh
```

Expected: PASS.

- [ ] **Step 4: Run real Diary ontology acceptance**

Run:

```bash
scripts/verify-mywiki-real-diary.sh
```

Expected: PASS and output includes `real diary MyWiki ontology verification passed`.

- [ ] **Step 5: Run full app verification**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS'
xcodebuild build -scheme KnowYou -destination 'platform=macOS'
git diff --check
```

Expected: PASS. Treat recurring local `CoreSimulator is out of date` warnings as local noise only if command exit status is 0.

- [ ] **Step 6: Inspect release bundle if built**

If `scripts/build-release.sh` is run, inspect:

```bash
test -x build/release/KnowYou.app/Contents/Resources/MyWikiRunner/node
test -f build/release/KnowYou.app/Contents/Resources/MyWikiRunner/mywiki-runner.js
test ! -d "build/release/KnowYou.app/Contents/Resources/KnowledgeOntology/LLM Wiki.app"
codesign -dv --verbose=4 build/release/KnowYou.app/Contents/Resources/MyWikiRunner/node
codesign --verify --deep --strict --verbose=2 build/release/KnowYou.app
```

Expected: all commands succeed.

- [ ] **Step 7: Commit**

Run:

```bash
git status --short
git add KnowYou KnowYouTests ThirdParty/llm_wiki scripts docs KnowYou.xcodeproj/project.pbxproj
git commit -m "fix: bundle mywiki runner through diary engine"
```

Expected: one implementation commit on `codex/fix-dmg-mywiki-llm`. Do not push until user tests.
