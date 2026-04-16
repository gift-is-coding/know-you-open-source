# Diary Engine Selector Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a top-right diary engine selector that shows the current default engine, lists five supported engines with gray/yellow/green status lights, supports OpenAI-compatible API configuration, and only allows green engines to become the default.

**Architecture:** Keep the existing `SummaryGenerating` pipeline, but split engine concerns into three layers: persisted engine configuration, runtime verification state, and reader-facing selector UI. Add a small probe service for CLI/API smoke tests, extend the existing config model to support Openclaw and OpenAI-compatible API settings, and surface the resulting state in `AppState` so the reader header can host the new selector without coupling the UI directly to process/network code.

**Tech Stack:** SwiftUI, Observation, Foundation `Process`, `URLSession`, Keychain-backed secret storage, XCTest, `xcodebuild`

---

## File Structure

### Existing files to modify

- `KnowYou/Services/Summary/SummarizerConfig.swift`
  Current home of engine type selection, CLI path resolution, and Keychain-backed OpenAI key storage. Extend it into the canonical persisted engine configuration model.
- `KnowYou/Services/Summary/CloudSummarizer.swift`
  Current OpenAI-only summarizer. Expand it to accept a configurable OpenAI-compatible `baseURL` and `model`.
- `KnowYou/Services/Summary/CLISummarizer.swift`
  Current CLI wrapper for Claude/Codex/Gemini. Extend it to support Openclaw and to expose a reusable smoke-test path.
- `KnowYou/App/AppState.swift`
  Current app orchestration and summarizer runtime status holder. Replace the single summarizer status with per-engine runtime state plus selected default engine state.
- `KnowYou/UI/Reader/DailyMarkdownView.swift`
  Current header row already owns the top-right refresh control. Add the new engine entry point here.
- `KnowYou/UI/MainWindowView.swift`
  Pass selector actions and engine state from `AppState` into `DailyMarkdownView`.
- `KnowYou/UI/Settings/SettingsView.swift`
  Keep Settings as a secondary configuration surface, but align text and any residual controls with the new engine terminology.
- `docs/architecture.md`
  Update runtime/UI description after implementation lands.
- `docs/requirements-spec.md`
  Update product requirements after implementation lands.

### New files to create

- `KnowYou/Services/Summary/DiaryEngine.swift`
  Shared engine enums, display labels, status-light state, and reusable row/action metadata.
- `KnowYou/Services/Summary/EngineProbe.swift`
  Isolated discovery + smoke-test service for CLI/API engines.
- `KnowYou/UI/Reader/DiaryEngineSelectorButton.swift`
  Compact top-right button that shows current engine name, disclosure affordance, and status light.
- `KnowYou/UI/Reader/DiaryEnginePanel.swift`
  First-level panel listing all five engines, status text, `Test`/`Retest`, and default selection affordances.
- `KnowYou/UI/Reader/APIDetailSheet.swift`
  Second-level API configuration surface with `baseURL`, `token`, `model`, help links, and `Test Connection`.
- `KnowYouTests/EngineProbeTests.swift`
  Dedicated tests for discovery and smoke-test state mapping.

### Existing tests to modify

- `KnowYouTests/SummarizerConfigTests.swift`
  Extend for Openclaw, API `baseURL`, API `model`, and Keychain token behavior.
- `KnowYouTests/CLISummarizerTests.swift`
  Extend for Openclaw argument handling and smoke-test helper behavior.
- `KnowYouTests/MainWindowViewModelTests.swift`
  Cover `AppState` engine state transitions, retained default engine behavior, and refresh behavior.

---

### Task 1: Expand The Engine Domain And Persistence Model

**Files:**
- Create: `KnowYou/Services/Summary/DiaryEngine.swift`
- Modify: `KnowYou/Services/Summary/SummarizerConfig.swift`
- Modify: `KnowYou/Services/Summary/CloudSummarizer.swift`
- Test: `KnowYouTests/SummarizerConfigTests.swift`

- [ ] **Step 1: Write the failing persistence tests for the new engine model**

Add the following cases to `KnowYouTests/SummarizerConfigTests.swift`:

```swift
func testSaveAndLoadRoundTripsOpenclawCLIPath() {
    var config = SummarizerConfig.load(from: defaults, keychain: keychain, keychainService: "tests")
    config.defaultEngine = .openclawCLI
    config.openclawCLIPath = "/opt/homebrew/bin/openclaw"
    config.save(to: defaults, keychain: keychain, keychainService: "tests")

    let loaded = SummarizerConfig.load(from: defaults, keychain: keychain, keychainService: "tests")
    XCTAssertEqual(loaded.defaultEngine, .openclawCLI)
    XCTAssertEqual(loaded.openclawCLIPath, "/opt/homebrew/bin/openclaw")
}

func testSaveAndLoadRoundTripsOpenAICompatibleAPISettings() {
    var config = SummarizerConfig.load(from: defaults, keychain: keychain, keychainService: "tests")
    config.defaultEngine = .api
    config.apiBaseURL = "https://openrouter.ai/api/v1/responses"
    config.apiModel = "openai/gpt-5"
    config.apiToken = "sk-router"
    config.save(to: defaults, keychain: keychain, keychainService: "tests")

    let loaded = SummarizerConfig.load(from: defaults, keychain: keychain, keychainService: "tests")
    XCTAssertEqual(loaded.apiBaseURL, "https://openrouter.ai/api/v1/responses")
    XCTAssertEqual(loaded.apiModel, "openai/gpt-5")
    XCTAssertEqual(loaded.apiToken, "sk-router")
}

func testAPIIsIncompleteWithoutBaseURLTokenAndModel() {
    var config = SummarizerConfig.load(from: defaults, keychain: keychain, keychainService: "tests")
    config.defaultEngine = .api
    config.apiBaseURL = "https://api.openai.com/v1/responses"
    config.apiModel = ""
    config.apiToken = "sk-test"

    XCTAssertFalse(config.apiConfigurationIsComplete)
}
```

- [ ] **Step 2: Run the config test slice and verify it fails**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/SummarizerConfigTests
```

Expected:

```text
Test suite 'SummarizerConfigTests' failed
```

- [ ] **Step 3: Add the shared engine domain types**

Create `KnowYou/Services/Summary/DiaryEngine.swift` with the minimal shared types:

```swift
import Foundation

enum DiaryEngine: String, CaseIterable, Codable {
    case claudeCode
    case codexCLI
    case geminiCLI
    case openclawCLI
    case api

    var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codexCLI: return "Codex CLI"
        case .geminiCLI: return "Gemini CLI"
        case .openclawCLI: return "Openclaw CLI"
        case .api: return "API"
        }
    }

    var shortDescription: String {
        switch self {
        case .claudeCode: return "Use the local Claude Code CLI."
        case .codexCLI: return "Use the local Codex CLI."
        case .geminiCLI: return "Use the local Gemini CLI."
        case .openclawCLI: return "Use the local Openclaw CLI."
        case .api: return "Use an OpenAI-compatible API endpoint."
        }
    }
}

enum EngineIndicatorState: Equatable {
    case gray
    case yellow
    case green
}
```

- [ ] **Step 4: Refactor `SummarizerConfig` into the new persisted configuration shape**

Update `KnowYou/Services/Summary/SummarizerConfig.swift` so it holds:

```swift
struct SummarizerConfig {
    var defaultEngine: DiaryEngine
    var claudeCLIPath: String
    var codexCLIPath: String
    var geminiCLIPath: String
    var openclawCLIPath: String
    var apiBaseURL: String
    var apiModel: String
    var apiToken: String

    var apiConfigurationIsComplete: Bool {
        !apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !apiModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
```

Keep these implementation rules:

- Store `defaultEngine`, CLI paths, `apiBaseURL`, and `apiModel` in `UserDefaults`
- Store `apiToken` in Keychain
- Preserve executable resolution fallback through `PATH`
- Add default path `/usr/local/bin/openclaw`

- [ ] **Step 5: Make the API summarizer OpenAI-compatible instead of OpenAI-only**

Update `KnowYou/Services/Summary/CloudSummarizer.swift` so the initializer becomes:

```swift
init(
    apiKey: String,
    apiURL: URL = URL(string: "https://api.openai.com/v1/responses")!,
    session: URLSession = .shared,
    model: String = "gpt-5"
) {
    self.apiKey = apiKey
    self.apiURL = apiURL
    self.session = session
    self.model = model
}
```

and the request uses `apiURL` instead of a fixed static URL.

- [ ] **Step 6: Run the config test slice and verify it passes**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/SummarizerConfigTests
```

Expected:

```text
** TEST SUCCEEDED **
```

- [ ] **Step 7: Commit the persistence/domain changes**

```bash
git add KnowYou/Services/Summary/DiaryEngine.swift KnowYou/Services/Summary/SummarizerConfig.swift KnowYou/Services/Summary/CloudSummarizer.swift KnowYouTests/SummarizerConfigTests.swift
git commit -m "feat: add diary engine configuration model"
```

### Task 2: Add Engine Discovery And Smoke-Test Probing

**Files:**
- Create: `KnowYou/Services/Summary/EngineProbe.swift`
- Modify: `KnowYou/Services/Summary/CLISummarizer.swift`
- Test: `KnowYouTests/EngineProbeTests.swift`
- Test: `KnowYouTests/CLISummarizerTests.swift`

- [ ] **Step 1: Write failing probe tests for CLI and API state mapping**

Create `KnowYouTests/EngineProbeTests.swift` with cases like:

```swift
func testCLIProbeReturnsGrayWhenExecutableIsMissing() async throws
func testCLIProbeReturnsYellowWhenExecutableExistsButSmokeTestFails() async throws
func testCLIProbeReturnsGreenWhenSmokeTestReturnsNonEmptyOutput() async throws
func testAPIProbeReturnsGrayWhenConfigurationIsIncomplete() async throws
func testAPIProbeReturnsYellowWhenHTTPRequestFails() async throws
func testAPIProbeReturnsGreenWhenResponseContainsOutputText() async throws
```

Use a stub process runner and a stub URL protocol/session so the tests never hit the real network.

- [ ] **Step 2: Run the probe-related tests and verify they fail**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/EngineProbeTests -only-testing:KnowYouTests/CLISummarizerTests
```

Expected:

```text
Test suite 'EngineProbeTests' failed
```

- [ ] **Step 3: Extend `CLISummarizer.Tool` and add a reusable smoke-test helper**

Update `KnowYou/Services/Summary/CLISummarizer.swift` so `Tool` adds:

```swift
case openclaw
```

and add a helper that can be reused by the probe service:

```swift
func smokeTest(prompt: String = "Reply with OK.") async throws -> String {
    let result = try await runner.run(executable: executablePath, arguments: arguments(for: prompt))
    let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        throw CocoaError(.executableLoad, userInfo: [NSLocalizedDescriptionKey: "Smoke test returned empty output"])
    }
    return trimmed
}
```

Factor the existing argument construction into:

```swift
func arguments(for prompt: String) -> [String]
```

so both `summarize` and `smokeTest` share the same logic.

- [ ] **Step 4: Implement `EngineProbe`**

Create `KnowYou/Services/Summary/EngineProbe.swift` with a focused API like:

```swift
import Foundation

struct EngineProbeResult: Equatable {
    let engine: DiaryEngine
    let state: EngineIndicatorState
    let detail: String
    let verifiedAt: Date?
}

struct EngineProbe {
    let session: URLSession
    let processRunner: ProcessRunning

    func probe(engine: DiaryEngine, config: SummarizerConfig, environment: [String: String]) async -> EngineProbeResult
}
```

Rules to implement:

- CLI missing executable => `.gray`
- CLI found but test throws/returns invalid => `.yellow`
- CLI smoke test success => `.green`
- API incomplete => `.gray`
- API configured but HTTP/test fails => `.yellow`
- API output text extracted => `.green`

- [ ] **Step 5: Extend CLI tests for Openclaw and shared argument behavior**

Add this case to `KnowYouTests/CLISummarizerTests.swift`:

```swift
func testOpenclawPassesPromptAsFirstArgument() async throws {
    let stub = StubProcessRunner(output: "OK")
    let summarizer = CLISummarizer(tool: .openclaw, executablePath: "/usr/local/bin/openclaw", runner: stub)

    _ = try await summarizer.smokeTest(prompt: "Reply with OK.")

    XCTAssertEqual(stub.lastArguments, ["Reply with OK."])
}
```

- [ ] **Step 6: Run the probe-related tests and verify they pass**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/EngineProbeTests -only-testing:KnowYouTests/CLISummarizerTests
```

Expected:

```text
** TEST SUCCEEDED **
```

- [ ] **Step 7: Commit the probe layer**

```bash
git add KnowYou/Services/Summary/EngineProbe.swift KnowYou/Services/Summary/CLISummarizer.swift KnowYouTests/EngineProbeTests.swift KnowYouTests/CLISummarizerTests.swift
git commit -m "feat: add diary engine probing"
```

### Task 3: Replace Single Summarizer Status With Per-Engine Runtime State In `AppState`

**Files:**
- Modify: `KnowYou/App/AppState.swift`
- Modify: `KnowYou/App/AppEnvironment.swift`
- Test: `KnowYouTests/MainWindowViewModelTests.swift`

- [ ] **Step 1: Write failing `AppState` tests for per-engine status behavior**

Add tests to `KnowYouTests/MainWindowViewModelTests.swift` for:

```swift
func testRefreshEngineStatusesPreservesLastVerifiedStateForUnchangedEngine() async throws
func testApplyEngineConfigDoesNotAutoSwitchDefaultWhenProbeFails() async throws
func testOnlyGreenEngineCanBecomeDefault() async throws
func testEditingAPIConfigReturnsAPIRowToYellowUntilRetested() async throws
```

At minimum, assert that:

- the saved default engine remains selected after a failed probe
- non-green engines are rejected by the default-selection method
- existing verification timestamps are not cleared during a passive refresh

- [ ] **Step 2: Run the `AppState` test slice and verify it fails**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MainWindowViewModelTests
```

Expected:

```text
Test suite 'MainWindowViewModelTests' failed
```

- [ ] **Step 3: Add per-engine runtime types and selector state to `AppState`**

Replace the single `SummarizerRuntimeStatus` usage with a per-engine model such as:

```swift
struct EngineRuntimeStatus: Equatable {
    var state: EngineIndicatorState = .gray
    var detail: String = "Not configured"
    var lastVerifiedAt: Date?
}
```

and store:

```swift
var engineStatuses: [DiaryEngine: EngineRuntimeStatus] = [:]
var defaultEngine: DiaryEngine = SummarizerConfig.load().defaultEngine
var isRetestingEngines = false
```

- [ ] **Step 4: Add `AppState` methods for engine refresh, retest, API update, and default selection**

Add focused methods with these signatures:

```swift
func refreshEngineStatuses()
func retestAllEngines() async
func retestEngine(_ engine: DiaryEngine) async
func selectDefaultEngine(_ engine: DiaryEngine)
func applyEngineConfig(_ config: SummarizerConfig)
```

Required behavior:

- `selectDefaultEngine` persists only when the target engine is green
- `applyEngineConfig` updates the persisted config and rebuilds `environment?.summarizer`
- `applyEngineConfig` does not auto-promote another engine
- API field edits can reset only the API state to yellow/gray without touching the other engines

- [ ] **Step 5: Keep summarizer instantiation aligned with the selected default engine**

Update `AppState.makeSummarizer()` and `applyEngineConfig(_:)` so the active summarizer is derived from `defaultEngine`:

```swift
let config = SummarizerConfig.load()
environment?.summarizer = config.makeSummarizer(for: config.defaultEngine)
```

Add a helper in `SummarizerConfig` if needed:

```swift
func makeSummarizer(for engine: DiaryEngine, environment: [String: String] = ProcessInfo.processInfo.environment) -> SummaryGenerating?
```

- [ ] **Step 6: Run the `AppState` test slice and verify it passes**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MainWindowViewModelTests
```

Expected:

```text
** TEST SUCCEEDED **
```

- [ ] **Step 7: Commit the runtime-state integration**

```bash
git add KnowYou/App/AppState.swift KnowYou/App/AppEnvironment.swift KnowYouTests/MainWindowViewModelTests.swift KnowYou/Services/Summary/SummarizerConfig.swift
git commit -m "feat: track diary engine runtime status"
```

### Task 4: Build The Top-Right Selector UI And API Detail Flow

**Files:**
- Create: `KnowYou/UI/Reader/DiaryEngineSelectorButton.swift`
- Create: `KnowYou/UI/Reader/DiaryEnginePanel.swift`
- Create: `KnowYou/UI/Reader/APIDetailSheet.swift`
- Modify: `KnowYou/UI/Reader/DailyMarkdownView.swift`
- Modify: `KnowYou/UI/MainWindowView.swift`
- Modify: `KnowYou/UI/Settings/SettingsView.swift`
- Test: `KnowYouTests/MainWindowViewModelTests.swift`

- [ ] **Step 1: Add failing UI-facing tests for selector state rendering**

Add focused tests in `KnowYouTests/MainWindowViewModelTests.swift` or a new UI-level view test file that assert the view model exposes enough state for:

```swift
XCTAssertEqual(appState.defaultEngine.displayName, "Codex CLI")
XCTAssertEqual(appState.engineStatuses[.codexCLI]?.state, .green)
XCTAssertEqual(appState.engineStatuses[.api]?.state, .yellow)
```

The test goal is not snapshot rendering; it is making sure the reader can render the outer badge, first-level rows, and API detail state from `AppState`.

- [ ] **Step 2: Run the relevant UI/view-model tests and verify they fail**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MainWindowViewModelTests
```

Expected:

```text
Test suite 'MainWindowViewModelTests' failed
```

- [ ] **Step 3: Build the compact top-right selector button**

Create `KnowYou/UI/Reader/DiaryEngineSelectorButton.swift` with a focused view like:

```swift
import SwiftUI

struct DiaryEngineSelectorButton: View {
    let title: String
    let state: EngineIndicatorState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.subheadline.weight(.medium))
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private var color: Color {
        switch state {
        case .gray: return .gray
        case .yellow: return .yellow
        case .green: return .green
        }
    }
}
```

- [ ] **Step 4: Build the first-level panel and API detail screen**

Create `KnowYou/UI/Reader/DiaryEnginePanel.swift` and `KnowYou/UI/Reader/APIDetailSheet.swift` with these behaviors:

- panel lists all five engines
- green rows show a selectable default action
- yellow/gray rows show disabled selection treatment
- CLI rows expose `Test`/`Retest`
- API row opens the detail sheet
- API sheet binds to `baseURL`, `token`, `model`, exposes help links, and calls `Test Connection`

Keep the API detail screen focused. Do not move vault or notification settings into it.

- [ ] **Step 5: Wire the selector into the reader header**

Update `KnowYou/UI/Reader/DailyMarkdownView.swift` header row so the current refresh button stays present and the selector sits beside it:

```swift
HStack(spacing: 10) {
    DiaryEngineSelectorButton(
        title: engineTitle,
        state: engineState,
        action: onOpenEnginePanel
    )
    Button { onRefresh() } label: { ... }
}
```

Update `KnowYou/UI/MainWindowView.swift` to pass:

- current default engine label
- current default engine state
- row data for all engines
- closures for `selectDefaultEngine`, `retestEngine`, `retestAllEngines`, and API config save/test

- [ ] **Step 6: Align the Settings copy with the new engine system**

Reduce `SettingsView` from being the primary summarizer control surface to being a secondary location. Replace old "Summarizer" copy with "Diary Engine" terminology and remove any UI that conflicts with the new selector-first flow.

- [ ] **Step 7: Run the view-model/UI test slice and verify it passes**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MainWindowViewModelTests
```

Expected:

```text
** TEST SUCCEEDED **
```

- [ ] **Step 8: Commit the UI integration**

```bash
git add KnowYou/UI/Reader/DiaryEngineSelectorButton.swift KnowYou/UI/Reader/DiaryEnginePanel.swift KnowYou/UI/Reader/APIDetailSheet.swift KnowYou/UI/Reader/DailyMarkdownView.swift KnowYou/UI/MainWindowView.swift KnowYou/UI/Settings/SettingsView.swift KnowYouTests/MainWindowViewModelTests.swift
git commit -m "feat: add diary engine selector UI"
```

### Task 5: Update Docs And Run Full Verification

**Files:**
- Modify: `docs/architecture.md`
- Modify: `docs/requirements-spec.md`
- Modify: `docs/real-machine-verification.md` (if manual real-machine notes are produced)

- [ ] **Step 1: Update the architecture doc**

Add the final implementation details to `docs/architecture.md`, covering:

- top-right engine entry in the reader
- five-engine model
- per-engine status lights
- OpenAI-compatible API configuration
- Openclaw support

- [ ] **Step 2: Update the requirements spec**

Add or revise requirements for:

- outer top-right engine label + status light
- first-level engine panel
- green-only default selection
- API `baseURL + token + model`
- gray/yellow/green detection semantics

- [ ] **Step 3: Run the full test suite**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS'
```

Expected:

```text
** TEST SUCCEEDED **
```

- [ ] **Step 4: Run the full build**

Run:

```bash
xcodebuild build -scheme KnowYou -destination 'platform=macOS'
```

Expected:

```text
** BUILD SUCCEEDED **
```

- [ ] **Step 5: Record any real-machine verification notes if needed**

If manual verification is performed for local CLI discovery or API test flows, append a brief dated note to `docs/real-machine-verification.md` with the exact engines exercised and their observed states.

- [ ] **Step 6: Commit docs and verification updates**

```bash
git add docs/architecture.md docs/requirements-spec.md docs/real-machine-verification.md
git commit -m "docs: update engine selector architecture and requirements"
```

---

## Self-Review

### Spec coverage

- Top-right entry control: covered in Task 4
- First-level panel with five engines: covered in Task 4
- Openclaw support: covered in Tasks 1 and 2
- OpenAI-compatible API fields: covered in Tasks 1 and 4
- Gray/yellow/green semantics: covered in Tasks 2, 3, and 4
- Green-only default selection: covered in Task 3 and surfaced in Task 4
- Secret handling through Keychain: covered in Task 1
- Architecture and requirements sync: covered in Task 5

### Placeholder scan

- No `TODO` / `TBD`
- Every task includes exact files
- Every test/run step includes explicit commands
- Every code-bearing task includes concrete code or signatures

### Type consistency

- `DiaryEngine` is the canonical engine enum across config, probe, runtime state, and UI
- `EngineIndicatorState` is the canonical three-color state across probe, runtime state, and UI
- `SummarizerConfig` remains the persisted config entry point, but now stores engine-specific fields
- `AppState` remains the source of truth for UI-facing engine status

