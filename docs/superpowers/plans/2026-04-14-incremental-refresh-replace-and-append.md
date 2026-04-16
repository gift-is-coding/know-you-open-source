# Incremental Refresh Replace-And-Append Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix incremental refresh so CLI engines validate and repair against an incremental schema, then apply replacement-and-append semantics using `existingStory + newEvents` without reloading `allEvents` into the model.

**Architecture:** Split the work into three bounded layers. First, teach `CLISummarizer` to handle an incremental structured contract distinct from full-story generation. Second, update `DailyMarkdownComposer` to parse the new payload and merge it as `encouragement/summary/todo replace + details append` while preserving canonical detail paragraphs. Third, update AppState integration tests and run targeted plus full verification.

**Tech Stack:** Swift, XCTest, Xcode build/test tooling, local CLI summarizer adapters

---

### Task 1: Lock Down The Incremental CLI Contract With Failing Tests

**Files:**
- Modify: `KnowYouTests/CLISummarizerTests.swift`
- Modify: `KnowYou/Services/Summary/CLISummarizer.swift`
- Test: `KnowYouTests/CLISummarizerTests.swift`

- [ ] **Step 1: Write failing tests for incremental structured output and repair**

Add tests that prove incremental refresh needs its own schema and repair path.

```swift
func testCodexIncrementalRefreshReadsIncrementalSchemaOutputFile() async throws {
    let json = """
    {
      "encouragementToReplace": {
        "text": "Closed the day with steady follow-through.",
        "sourceEventIDs": ["A3F2C1D4-E5B6-7890-ABCD-EF1234567890"]
      },
      "summaryBulletsToReplace": [
        { "text": "- Closed the follow-up loop", "sourceEventIDs": ["A3F2C1D4-E5B6-7890-ABCD-EF1234567890"] }
      ],
      "detailBlocksToAppend": [
        { "text": "## Follow-up\\n\\nHandled the customer response.", "sourceEventIDs": ["A3F2C1D4-E5B6-7890-ABCD-EF1234567890"] }
      ],
      "todoItemsToReplace": [
        { "text": "- [ ] Send the handoff", "sourceEventIDs": ["A3F2C1D4-E5B6-7890-ABCD-EF1234567890"] }
      ]
    }
    """
    let stub = StubProcessRunner(
        behaviors: [.success(ProcessExecutionResult(stdout: "", stderr: "", terminationStatus: 0, duration: 0))],
        onInvocation: { _, arguments, _, _ in
            guard let outputIndex = arguments.firstIndex(of: "-o") else { return }
            try? json.write(toFile: arguments[outputIndex + 1], atomically: true, encoding: .utf8)
        }
    )
    let summarizer = CLISummarizer(tool: .codex, executablePath: "/usr/local/bin/codex", runner: stub)

    let result = try await summarizer.summarizeIncremental(dayKey: "2026-04-14", markdown: "prompt")
    let object = try decodedJSONObject(from: result)

    XCTAssertNotNil(object["encouragementToReplace"])
    XCTAssertNotNil(object["summaryBulletsToReplace"])
    XCTAssertNotNil(object["detailBlocksToAppend"])
    XCTAssertNotNil(object["todoItemsToReplace"])
}

func testCodexIncrementalRefreshRepairsInvalidPrimaryOutputUsingIncrementalSchema() async throws {
    let repaired = """
    {
      "encouragementToReplace": {
        "text": "Recovered encouragement.",
        "sourceEventIDs": ["A3F2C1D4-E5B6-7890-ABCD-EF1234567890"]
      },
      "summaryBulletsToReplace": [],
      "detailBlocksToAppend": [],
      "todoItemsToReplace": []
    }
    """
    let stub = StubProcessRunner(
        behaviors: [
            .success(ProcessExecutionResult(stdout: "", stderr: "", terminationStatus: 0, duration: 0)),
            .success(ProcessExecutionResult(stdout: "", stderr: "", terminationStatus: 0, duration: 0)),
        ],
        onInvocation: { _, arguments, invocationIndex, _ in
            guard let outputIndex = arguments.firstIndex(of: "-o"), arguments.indices.contains(outputIndex + 1) else {
                return
            }
            let outputPath = arguments[outputIndex + 1]
            let contents = invocationIndex == 0 ? "not json" : repaired
            try? contents.write(toFile: outputPath, atomically: true, encoding: .utf8)
        }
    )
    let summarizer = CLISummarizer(tool: .codex, executablePath: "/usr/local/bin/codex", runner: stub)

    let result = try await summarizer.summarizeIncremental(dayKey: "2026-04-14", markdown: "prompt")
    let object = try decodedJSONObject(from: result)

    XCTAssertNotNil(object["encouragementToReplace"])
    XCTAssertEqual(stub.invocations.count, 2)
}

func testCodexIncrementalRefreshRejectsMissingRequiredField() async {
    let invalid = """
    {
      "summaryBulletsToReplace": [],
      "detailBlocksToAppend": [],
      "todoItemsToReplace": []
    }
    """
    let stub = StubProcessRunner(
        behaviors: [.success(ProcessExecutionResult(stdout: "", stderr: "", terminationStatus: 0, duration: 0))],
        onInvocation: { _, arguments, _, _ in
            guard let outputIndex = arguments.firstIndex(of: "-o"), arguments.indices.contains(outputIndex + 1) else {
                return
            }
            try? invalid.write(toFile: arguments[outputIndex + 1], atomically: true, encoding: .utf8)
        }
    )
    let summarizer = CLISummarizer(tool: .codex, executablePath: "/usr/local/bin/codex", runner: stub)

    await XCTAssertThrowsErrorAsync(
        try await summarizer.summarizeIncremental(dayKey: "2026-04-14", markdown: "prompt")
    )
}
```

- [ ] **Step 2: Run the CLI summarizer slice and verify the new tests fail**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/CLISummarizerTests
```

Expected:

```text
Test Case '-[KnowYouTests.CLISummarizerTests testCodexIncrementalRefreshReadsIncrementalSchemaOutputFile]' failed
```

- [ ] **Step 3: Commit the failing-test checkpoint**

```bash
git add KnowYouTests/CLISummarizerTests.swift
git commit -m "test: cover incremental cli structured contract"
```

### Task 2: Implement Incremental Schema, Validation, And Repair In CLISummarizer

**Files:**
- Modify: `KnowYou/Services/Summary/CLISummarizer.swift`
- Test: `KnowYouTests/CLISummarizerTests.swift`

- [ ] **Step 1: Add a dedicated incremental summarize entry point and expectation**

Refactor the current `.story`-only path into a shared structured helper.

```swift
private enum Expectation {
    case story
    case incrementalUpdate
    case acknowledgement
}

func summarize(dayKey: String, markdown: String, context: SummaryInvocationContext = .defaultBehavior) async throws -> String {
    try await summarizeStructured(
        prompt: markdown,
        expectation: .story,
        context: context
    )
}

func summarizeIncremental(dayKey: String, markdown: String, context: SummaryInvocationContext) async throws -> String {
    try await summarizeStructured(
        prompt: markdown,
        expectation: .incrementalUpdate,
        context: context
    )
}
```

- [ ] **Step 2: Add the incremental schema and expectation-aware repair prompt**

Keep the full-story schema untouched and add a second schema for replacement-and-append payloads.

```swift
private static let incrementalUpdateSchema = """
{"type":"object","additionalProperties":false,"required":["encouragementToReplace","summaryBulletsToReplace","detailBlocksToAppend","todoItemsToReplace"],"properties":{"encouragementToReplace":{"type":"object","additionalProperties":false,"required":["text","sourceEventIDs"],"properties":{"text":{"type":"string"},"sourceEventIDs":{"type":"array","minItems":1,"items":{"type":"string","pattern":"^[0-9A-Fa-f-]{36}$"}}}},"summaryBulletsToReplace":{"type":"array","items":{"type":"object","additionalProperties":false,"required":["text","sourceEventIDs"],"properties":{"text":{"type":"string"},"sourceEventIDs":{"type":"array","minItems":1,"items":{"type":"string","pattern":"^[0-9A-Fa-f-]{36}$"}}}}},"detailBlocksToAppend":{"type":"array","items":{"type":"object","additionalProperties":false,"required":["text","sourceEventIDs"],"properties":{"text":{"type":"string"},"sourceEventIDs":{"type":"array","minItems":1,"items":{"type":"string","pattern":"^[0-9A-Fa-f-]{36}$"}}}}},"todoItemsToReplace":{"type":"array","items":{"type":"object","additionalProperties":false,"required":["text","sourceEventIDs"],"properties":{"text":{"type":"string"},"sourceEventIDs":{"type":"array","minItems":1,"items":{"type":"string","pattern":"^[0-9A-Fa-f-]{36}$"}}}}}}}
"""

private func repairPrompt(for raw: String, expectation: Expectation) -> String {
    switch expectation {
    case .story:
        return storyRepairPrompt(for: raw)
    case .incrementalUpdate:
        return incrementalRepairPrompt(for: raw)
    case .acknowledgement:
        return #"{"ok":"OK"}"#
    }
}
```

- [ ] **Step 3: Add expectation-aware validation and invocation planning**

Make Codex choose the correct schema file and make every engine validate against the matching payload.

```swift
private func validatedOutput(from raw: String, expectation: Expectation) -> String? {
    switch expectation {
    case .story:
        return validatedStoryOutput(from: raw)
    case .incrementalUpdate:
        return validatedIncrementalOutput(from: raw)
    case .acknowledgement:
        return normalizedAcknowledgement(from: raw) == nil ? nil : #"{"ok":"OK"}"#
    }
}

private func schemaText(for expectation: Expectation) -> String {
    switch expectation {
    case .story:
        return Self.dailyStorySchema
    case .incrementalUpdate:
        return Self.incrementalUpdateSchema
    case .acknowledgement:
        return Self.acknowledgementSchema
    }
}
```

- [ ] **Step 4: Re-run the CLI summarizer slice and verify it passes**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/CLISummarizerTests
```

Expected:

```text
** TEST SUCCEEDED **
```

- [ ] **Step 5: Commit the CLI layer**

```bash
git add KnowYou/Services/Summary/CLISummarizer.swift KnowYouTests/CLISummarizerTests.swift
git commit -m "feat: add incremental structured cli contract"
```

### Task 3: Replace-Or-Append Merge Semantics In DailyMarkdownComposer

**Files:**
- Modify: `KnowYou/Services/Composer/DailyMarkdownComposer.swift`
- Modify: `KnowYouTests/DailyMarkdownComposerTests.swift`
- Test: `KnowYouTests/DailyMarkdownComposerTests.swift`

- [ ] **Step 1: Write failing composer tests for the new payload shape and merge semantics**

Add tests that enforce:

- required top-level fields
- `encouragement` replacement
- `summary` replacement
- `details` append as a new paragraph
- `todo` replacement
- no `allEvents` dependency for language selection

```swift
func testParseIncrementalUpdateRequiresAllReplacementFields() {
    let composer = DailyMarkdownComposer()

    XCTAssertNil(
        composer.parseIncrementalUpdate(
            raw: """
            {
              "summaryBulletsToReplace": [],
              "detailBlocksToAppend": [],
              "todoItemsToReplace": []
            }
            """
        )
    )
}

func testMergeIncrementalUpdateReplacesEncouragementSummaryAndTodoButAppendsDetails() {
    let composer = DailyMarkdownComposer()
    let update = composer.parseIncrementalUpdate(raw: """
    {
      "encouragementToReplace": { "text": "Closed the day with steady follow-through.", "sourceEventIDs": ["\(newEncouragementID.uuidString)"] },
      "summaryBulletsToReplace": [{ "text": "- Closed the follow-up loop", "sourceEventIDs": ["\(newSummaryID.uuidString)"] }],
      "detailBlocksToAppend": [{ "text": "## Follow-up\\n\\nHandled the customer response.", "sourceEventIDs": ["\(newDetailID.uuidString)"] }],
      "todoItemsToReplace": []
    }
    """)

    let merged = composer.mergeIncrementalUpdate(
        dayKey: "2026-04-12",
        existingStory: existingStory,
        update: try XCTUnwrap(update),
        provenance: provenance
    )

    let paragraphs = merged.sections.flatMap(\.paragraphs)
    XCTAssertEqual(paragraphs.count, 5)
    XCTAssertEqual(paragraphs[0].text, "# You did a good job today\n\nClosed the day with steady follow-through.")
    XCTAssertTrue(paragraphs[1].text.contains("- Closed the follow-up loop"))
    XCTAssertEqual(paragraphs[3].text, "## Follow-up\n\nHandled the customer response.")
    XCTAssertEqual(paragraphs[4].text, "# To-do")
}
```

- [ ] **Step 2: Run the composer slice and verify the new tests fail**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/DailyMarkdownComposerTests
```

Expected:

```text
Test Case '-[KnowYouTests.DailyMarkdownComposerTests testMergeIncrementalUpdateReplacesEncouragementSummaryAndTodoButAppendsDetails]' failed
```

- [ ] **Step 3: Implement the new payload types, prompt, and merge behavior**

Reshape the payload and stop passing `allEvents` into the prompt/merge path.

```swift
private struct GeneratedIncrementalPayload: Decodable {
    let encouragementToReplace: GeneratedStoryParagraph
    let summaryBulletsToReplace: [GeneratedStoryParagraph]
    let detailBlocksToAppend: [GeneratedStoryParagraph]
    let todoItemsToReplace: [GeneratedStoryParagraph]
}

struct JournalIncrementalUpdate {
    let encouragementToReplace: JournalIncrementalItem
    let summaryBulletsToReplace: [JournalIncrementalItem]
    let detailBlocksToAppend: [JournalIncrementalItem]
    let todoItemsToReplace: [JournalIncrementalItem]
}

func incrementalPrompt(dayKey: String, existingStory: DailyStory, newEvents: [EventRecord]) -> String {
    let language = narrativeLanguage(for: existingStory, fallbackEvents: newEvents)
    let headings = journalHeadings(for: language)
    let blocks = journalBlocks(from: existingStory, language: language)
    return """
    Return strict JSON only.
    Required JSON shape:
    {
      "encouragementToReplace": { "text": "Closed the day with steady follow-through.", "sourceEventIDs": ["A3F2C1D4-E5B6-7890-ABCD-EF1234567890"] },
      "summaryBulletsToReplace": [{ "text": "- Closed the follow-up loop", "sourceEventIDs": ["A3F2C1D4-E5B6-7890-ABCD-EF1234567890"] }],
      "detailBlocksToAppend": [{ "text": "## Follow-up\n\nHandled the customer response.", "sourceEventIDs": ["A3F2C1D4-E5B6-7890-ABCD-EF1234567890"] }],
      "todoItemsToReplace": [{ "text": "- [ ] Send the handoff", "sourceEventIDs": ["A3F2C1D4-E5B6-7890-ABCD-EF1234567890"] }]
    }

    Existing encouragement:
    \(blockBodyText(blocks.encouragement, heading: headings.encouragement))
    Existing summary:
    \(blockBodyText(blocks.summary, heading: headings.summary))
    Existing details:
    \(blockBodyText(blocks.details, heading: headings.details))
    Existing to-do:
    \(blockBodyText(blocks.todo, heading: headings.todo))
    """
}
```

- [ ] **Step 4: Build replacement helpers and preserve detail paragraphs**

Do not collapse detail threads back into one markdown blob.

```swift
private func replaceBulletBlock(_ items: [JournalIncrementalItem], heading: String) -> JournalMarkdownBlock {
    let body = items.map { $0.text.hasPrefix("- ") ? $0.text : "- \($0.text)" }.joined(separator: "\n")
    let sourceIDs = Array(Set(items.flatMap(\.sourceEventIDs))).sorted { $0.uuidString < $1.uuidString }
    return JournalMarkdownBlock(heading: heading, body: body, sourceEventIDs: sourceIDs)
}

private func makeDetailParagraphs(existing: [DailyStoryParagraph], appended: [JournalIncrementalItem], heading: String) -> [DailyStoryParagraph] {
    let preserved = existing.filter { !$0.text.contains("# To-do") && !$0.text.contains("# Summary") }
    let newParagraphs = appended.enumerated().map { index, item in
        DailyStoryParagraph(
            id: "daily-journal-details-appended-\(index)",
            text: item.text,
            sourceEventIDs: item.sourceEventIDs
        )
    }
    return preserved + newParagraphs
}
```

- [ ] **Step 5: Re-run the composer slice and verify it passes**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/DailyMarkdownComposerTests
```

Expected:

```text
** TEST SUCCEEDED **
```

- [ ] **Step 6: Commit the composer layer**

```bash
git add KnowYou/Services/Composer/DailyMarkdownComposer.swift KnowYouTests/DailyMarkdownComposerTests.swift
git commit -m "feat: replace and append incremental story sections"
```

### Task 4: Wire AppState To The Incremental Summarizer Path And Update Integration Tests

**Files:**
- Modify: `KnowYou/App/AppState.swift`
- Modify: `KnowYouTests/MainWindowViewModelTests.swift`
- Test: `KnowYouTests/MainWindowViewModelTests.swift`

- [ ] **Step 1: Write failing integration assertions against the new payload and merge behavior**

Update the existing incremental tests to send the new payload and assert replacement behavior.

```swift
return StaticSummarizer(
    response: """
    {
      "encouragementToReplace": { "text": "Closed the day with steady follow-through.", "sourceEventIDs": ["\(newID.uuidString)"] },
      "summaryBulletsToReplace": [{ "text": "- Customer approved the follow-up", "sourceEventIDs": ["\(newID.uuidString)"] }],
      "detailBlocksToAppend": [{ "text": "## Follow-up\\n\\nHandled the approval loop.", "sourceEventIDs": ["\(newID.uuidString)"] }],
      "todoItemsToReplace": [{ "text": "- [ ] Queue the final handoff", "sourceEventIDs": ["\(newID.uuidString)"] }]
    }
    """
)

XCTAssertFalse(refreshedMarkdown.contains("Keep the pace."))
XCTAssertTrue(refreshedMarkdown.contains("Closed the day with steady follow-through."))
XCTAssertFalse(refreshedMarkdown.contains("- Wrapped the first pass"))
XCTAssertTrue(refreshedMarkdown.contains("- Customer approved the follow-up"))
```

- [ ] **Step 2: Run the AppState integration slice and verify it fails**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MainWindowViewModelTests
```

Expected:

```text
Test Suite 'MainWindowViewModelTests' failed
```

- [ ] **Step 3: Route incremental refresh through the incremental summarizer API**

Change AppState to call the new incremental entry point instead of full-story summarize.

```swift
private func runAttempt(
    _ attempt: RefreshSummarizerAttempt,
    dayKey: String,
    prompt: String,
    context: SummaryInvocationContext,
    mode: RefreshMode
) async -> RefreshAttemptRunResult {
    do {
        let raw: String
        switch mode {
        case .incrementalUpdate:
            raw = try await attempt.summarizer.summarizeIncremental(dayKey: dayKey, markdown: prompt, context: context)
        case .fullRecovery:
            raw = try await attempt.summarizer.summarize(dayKey: dayKey, markdown: prompt, context: context)
        }
        return .succeeded(attempt, raw, startedAt, Date())
    } catch {
        return .failed(attempt, error, startedAt, Date())
    }
}
```

- [ ] **Step 4: Re-run the AppState integration slice and verify it passes**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MainWindowViewModelTests
```

Expected:

```text
** TEST SUCCEEDED **
```

- [ ] **Step 5: Commit the integration wiring**

```bash
git add KnowYou/App/AppState.swift KnowYouTests/MainWindowViewModelTests.swift
git commit -m "fix: route incremental refresh through incremental schema"
```

### Task 5: Full Verification And Documentation Sync

**Files:**
- Review: `docs/superpowers/specs/2026-04-14-incremental-refresh-replace-and-append-design.md`
- Review: `docs/architecture.md`
- Review: `docs/requirements-spec.md`
- Verify: repository root

- [ ] **Step 1: Check whether architecture or requirements docs need a matching note**

If either document mentions incremental append-only semantics, update it.

```md
Incremental refresh now uses a replacement-and-append contract:
- Encouragement, Summary, and To-do are regenerated from existing story context plus new events
- Details append only new workstream paragraphs
- CLI engines validate incremental refresh against a dedicated incremental schema
```

- [ ] **Step 2: Run the focused regression slices**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/CLISummarizerTests
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/DailyMarkdownComposerTests
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MainWindowViewModelTests
```

Expected:

```text
** TEST SUCCEEDED **
```

- [ ] **Step 3: Run full repository verification required by AGENTS.md**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS'
xcodebuild build -scheme KnowYou -destination 'platform=macOS'
```

Expected:

```text
** TEST SUCCEEDED **
** BUILD SUCCEEDED **
```

- [ ] **Step 4: Inspect the fresh build artifact before claiming success**

Run:

```bash
find ~/Library/Developer/Xcode/DerivedData -name KnowYou.app -print
```

Expected:

```text
Only the latest session's KnowYou.app path is used for any launch check.
```

- [ ] **Step 5: Commit the final verified state**

```bash
git add KnowYou docs/architecture.md docs/requirements-spec.md docs/superpowers/specs/2026-04-14-incremental-refresh-replace-and-append-design.md docs/superpowers/plans/2026-04-14-incremental-refresh-replace-and-append.md
git commit -m "fix: stabilize incremental refresh structured contract"
```
