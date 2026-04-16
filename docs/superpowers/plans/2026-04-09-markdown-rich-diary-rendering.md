# Markdown-Rich Diary Rendering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve paragraph-to-source linking while upgrading the diary reader so both `Story` and `Source Notes` render as Markdown-rich content instead of plain text.

**Architecture:** Keep the existing `DailyStory` paragraph model as the interaction layer for story selection, but swap each paragraph body to a Markdown-aware renderer. Add a small markdown-loading/extraction path so the reader can load the saved `.md` file and display the `## Source Notes` section as a Markdown block, with a fallback generated from `selectedDayEvents` when the file is missing.

**Tech Stack:** Swift, SwiftUI, Foundation, XCTest, `xcodebuild`

---

## File Map

| File | Responsibility |
|------|----------------|
| `KnowYou/App/AppEnvironment.swift` | Add a helper to load saved markdown text from a note URL |
| `KnowYou/App/AppState.swift` | Track selected day markdown text and extracted source-notes markdown |
| `KnowYou/UI/Reader/DailyMarkdownView.swift` | Replace plain-text paragraph rendering with Markdown-aware blocks and render `Source Notes` in the main reading column |
| `KnowYouTests/MainWindowViewModelTests.swift` | Cover loading markdown-backed source notes and fallback behavior |
| `KnowYouTests/DailyMarkdownComposerTests.swift` | Keep current markdown contract assertions intact if helper behavior depends on section headings |

---

### Task 1: Add failing tests for markdown-backed source notes

**Files:**
- Modify: `KnowYouTests/MainWindowViewModelTests.swift`
- Reference: `KnowYou/App/AppState.swift`
- Reference: `KnowYou/App/AppEnvironment.swift`

- [ ] **Step 1: Add a test that loads `Source Notes` from the saved markdown file**

```swift
    func testSelectingDateLoadsSourceNotesMarkdownFromSavedFile() throws {
        let environment = try makeStoryEnvironment()
        let appState = AppState(environment: environment)

        appState.selectDate("2026-04-08")

        XCTAssertEqual(
            appState.selectedSourceNotesMarkdown,
            """
            ## Source Notes

            - [09:00] Notes (clipboard): Important note
            - [09:15] Mail (notification): Investor replied
            """
        )
    }
```

- [ ] **Step 2: Add a test that falls back to generated source notes when the markdown file is missing**

```swift
    func testSelectingDateFallsBackToGeneratedSourceNotesWhenMarkdownFileIsMissing() throws {
        let environment = try makeStoryEnvironment()
        let appState = AppState(environment: environment)
        let fileURL = environment.vaultURL.appending(path: "2026-04-08.md")
        try FileManager.default.removeItem(at: fileURL)

        appState.selectDate("2026-04-08")

        XCTAssertEqual(
            appState.selectedSourceNotesMarkdown,
            """
            ## Source Notes

            - [09:00] Notes (clipboard): Important note
            - [09:15] Mail (notification): Investor replied
            """
        )
    }
```

- [ ] **Step 3: Update `makeStoryEnvironment()` fixture markdown and events so the tests assert real section content**

```swift
        try writeStoryDay(
            dayKey: "2026-04-08",
            markdown: """
            # 2026-04-08

            ## Story

            First paragraph with **bold** emphasis.

            Second paragraph with a [link](https://example.com).

            ---

            ## Source Notes

            - [09:00] Notes (clipboard): Important note
            - [09:15] Mail (notification): Investor replied
            """,
            story: DailyStory(
                dayKey: "2026-04-08",
                generatedAt: Date(timeIntervalSince1970: 1_775_000_000),
                sections: [
                    DailyStorySection(
                        id: "daily-journal",
                        title: "",
                        paragraphs: [
                            DailyStoryParagraph(id: "daily-journal-0", text: "First paragraph with **bold** emphasis.", sourceEventIDs: [firstID]),
                            DailyStoryParagraph(id: "daily-journal-1", text: "Second paragraph with a [link](https://example.com).", sourceEventIDs: [secondID]),
                        ]
                    )
                ]
            ),
            environment: environment
        )
```

- [ ] **Step 4: Run the targeted test slice and verify failure**

Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MainWindowViewModelTests`

Expected: FAIL with compiler errors because `selectedSourceNotesMarkdown` does not exist yet.

- [ ] **Step 5: Commit the failing tests**

```bash
git add KnowYouTests/MainWindowViewModelTests.swift
git commit -m "test: cover markdown-backed source notes loading"
```

---

### Task 2: Load saved markdown and expose extracted source-notes markdown in AppState

**Files:**
- Modify: `KnowYou/App/AppEnvironment.swift`
- Modify: `KnowYou/App/AppState.swift`
- Test: `KnowYouTests/MainWindowViewModelTests.swift`

- [ ] **Step 1: Add a markdown file loader helper to `AppEnvironment`**

```swift
    func loadDailyNoteMarkdown(from fileURL: URL) throws -> String {
        try String(contentsOf: fileURL, encoding: .utf8)
    }
```

- [ ] **Step 2: Add selected markdown state and helpers to `AppState`**

```swift
    var selectedMarkdownText: String?
    var selectedSourceNotesMarkdown: String?

    private func loadSelectedMarkdownText() -> String? {
        guard let environment, let selectedMarkdownURL else { return nil }
        return try? environment.loadDailyNoteMarkdown(from: selectedMarkdownURL)
    }

    private func extractSourceNotesMarkdown(from markdown: String) -> String? {
        guard let markerRange = markdown.range(of: "\n## Source Notes") ?? markdown.range(of: "## Source Notes") else {
            return nil
        }

        return markdown[markerRange.lowerBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func generatedSourceNotesMarkdown(from events: [EventRecord]) -> String {
        let lines = events.map { event in
            "- [\\(Self.timeFormatter.string(from: event.capturedAt))] \\(event.sourceApp) (\\(event.sourceType.rawValue)): \\(event.displayText)"
        }

        let body = lines.isEmpty ? "_No entries_" : lines.joined(separator: "\\n")
        return "## Source Notes\\n\\n\\(body)"
    }
```

- [ ] **Step 3: Add a shared formatter and update `loadDayPresentation` / `updateSelectedPresentation` to populate markdown state**

```swift
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
```

```swift
        let markdown = loadSelectedMarkdownText()
        selectedMarkdownText = markdown
        selectedSourceNotesMarkdown =
            markdown.flatMap(extractSourceNotesMarkdown(from:))
            ?? generatedSourceNotesMarkdown(from: events)
```

- [ ] **Step 4: Clear markdown state when no environment is available**

```swift
        guard let environment else {
            selectedStory = nil
            selectedStoryParagraphID = nil
            selectedStorySourceEvents = []
            selectedDayEvents = []
            selectedMarkdownText = nil
            selectedSourceNotesMarkdown = nil
            return
        }
```

- [ ] **Step 5: Run the targeted test slice and verify it passes**

Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MainWindowViewModelTests`

Expected: PASS for the new source-notes tests and existing `MainWindowViewModelTests`.

- [ ] **Step 6: Commit the state-loading implementation**

```bash
git add KnowYou/App/AppEnvironment.swift KnowYou/App/AppState.swift KnowYouTests/MainWindowViewModelTests.swift
git commit -m "feat: load markdown-backed source notes for reader"
```

---

### Task 3: Add failing view tests for markdown-rich reader content

**Files:**
- Create or Modify: `KnowYouTests/DailyMarkdownViewTests.swift`
- Reference: `KnowYou/UI/Reader/DailyMarkdownView.swift`

- [ ] **Step 1: Add a focused view test file if it does not exist**

```swift
import XCTest
@testable import KnowYou

final class DailyMarkdownViewTests: XCTestCase {
}
```

- [ ] **Step 2: Add a test for story paragraph markdown preservation in the view model surface**

```swift
    func testStoryParagraphRetainsMarkdownTextForRenderer() {
        let paragraph = DailyStoryParagraph(
            id: "daily-journal-0",
            text: "A paragraph with **bold** and `code`.",
            sourceEventIDs: [UUID()]
        )

        XCTAssertEqual(paragraph.text, "A paragraph with **bold** and `code`.")
    }
```

- [ ] **Step 3: Add a test for source-notes markdown block presence**

```swift
    func testSourceNotesMarkdownIncludesHeadingAndBullets() {
        let markdown = """
        ## Source Notes

        - [09:00] Notes (clipboard): Important note
        - [09:15] Mail (notification): Investor replied
        """

        XCTAssertTrue(markdown.hasPrefix("## Source Notes"))
        XCTAssertTrue(markdown.contains("- [09:00] Notes"))
        XCTAssertTrue(markdown.contains("- [09:15] Mail"))
    }
```

- [ ] **Step 4: Run the new test file**

Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/DailyMarkdownViewTests`

Expected: PASS. These tests are intentionally lightweight and lock in the text contract that the renderer will consume.

- [ ] **Step 5: Commit the test scaffold**

```bash
git add KnowYouTests/DailyMarkdownViewTests.swift
git commit -m "test: add diary markdown reader coverage scaffold"
```

---

### Task 4: Replace plain-text story paragraphs with markdown-aware rendering and show source notes in the reader

**Files:**
- Modify: `KnowYou/UI/Reader/DailyMarkdownView.swift`
- Modify: `KnowYou/UI/MainWindowView.swift`
- Reference: `KnowYou/App/AppState.swift`

- [ ] **Step 1: Extend `DailyMarkdownView` inputs so the reader can receive source-notes markdown**

```swift
struct DailyMarkdownView: View {
    let story: DailyStory?
    let selectedParagraphID: String?
    let sourceNotesMarkdown: String?
    let dayKey: String?
    let isRefreshing: Bool
    let isActive: Bool
    let onSelectParagraph: (String) -> Void
    let onFocusStory: () -> Void
    let onRefresh: () -> Void
```

- [ ] **Step 2: Add markdown-aware subviews inside `DailyMarkdownView.swift`**

```swift
private struct MarkdownParagraphContent: View {
    let markdown: String

    var body: some View {
        Group {
            if let attributed = try? AttributedString(
                markdown: markdown,
                options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
            ) {
                Text(attributed)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(markdown)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.body)
        .multilineTextAlignment(.leading)
        .lineSpacing(4)
    }
}

private struct MarkdownSectionBlock: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let attributed = try? AttributedString(
                markdown: markdown,
                options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
            ) {
                Text(attributed)
                    .textSelection(.enabled)
            } else {
                Text(markdown)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
```

- [ ] **Step 3: Replace the plain paragraph `Text(.init(paragraph.text))` with the markdown-aware renderer**

```swift
                MarkdownParagraphContent(markdown: paragraph.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
```

- [ ] **Step 4: Render source notes below the story paragraphs**

```swift
                        if let sourceNotesMarkdown, !sourceNotesMarkdown.isEmpty {
                            Divider()
                                .padding(.top, 12)
                                .padding(.bottom, 20)

                            MarkdownSectionBlock(markdown: sourceNotesMarkdown)
                                .padding(.horizontal, 14)
                        }
```

- [ ] **Step 5: Pass the new property from `MainWindowView`**

```swift
            DailyMarkdownView(
                story: appState.selectedStory,
                selectedParagraphID: appState.selectedStoryParagraphID,
                sourceNotesMarkdown: appState.selectedSourceNotesMarkdown,
                dayKey: appState.selectedDate,
                isRefreshing: isRefreshing,
                isActive: appState.readerFocus == .storyParagraphs,
                onSelectParagraph: { paragraphID in
                    appState.focusStoryParagraphs()
                    appState.selectStoryParagraph(paragraphID)
                },
                onFocusStory: {
                    appState.focusStoryParagraphs()
                },
                onRefresh: {
                    guard !isRefreshing else { return }
                    isRefreshing = true
                    Task { @MainActor in
                        await appState.refreshSelectedDay()
                        isRefreshing = false
                    }
                }
            )
```

- [ ] **Step 6: Run the focused tests and verify the reader compiles**

Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MainWindowViewModelTests -only-testing:KnowYouTests/DailyMarkdownViewTests`

Expected: PASS.

- [ ] **Step 7: Commit the reader rendering changes**

```bash
git add KnowYou/UI/Reader/DailyMarkdownView.swift KnowYou/UI/MainWindowView.swift KnowYou/App/AppState.swift
git commit -m "feat: render diary story and source notes as markdown"
```

---

### Task 5: Tighten markdown contract tests and run full verification

**Files:**
- Modify: `KnowYouTests/DailyMarkdownComposerTests.swift`
- Reference: `KnowYou/Services/Composer/DailyMarkdownComposer.swift`

- [ ] **Step 1: Add a contract test that source-notes extraction still matches current composer output**

```swift
    func testComposerOutputContainsSourceNotesHeadingForReaderExtraction() {
        let composer = DailyMarkdownComposer()
        let event = EventRecord(
            id: UUID(),
            sourceType: .clipboard,
            sourceApp: "Notes",
            capturedAt: Date(timeIntervalSince1970: 1_775_000_000),
            dayKey: "2026-04-08",
            text: "Important note",
            auditText: nil,
            privacyAction: .keep,
            contentHash: "reader-extraction"
        )
        let story = composer.fallbackStory(dayKey: "2026-04-08", events: [event])

        let markdown = composer.compose(dayKey: "2026-04-08", events: [event], story: story)

        XCTAssertTrue(markdown.contains("## Source Notes"))
        XCTAssertTrue(markdown.contains("- ["))
    }
```

- [ ] **Step 2: Run the focused composer and view-model tests**

Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/DailyMarkdownComposerTests -only-testing:KnowYouTests/MainWindowViewModelTests -only-testing:KnowYouTests/DailyMarkdownViewTests`

Expected: PASS.

- [ ] **Step 3: Run full test verification**

Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS'`

Expected: PASS for the full `KnowYouTests` suite.

- [ ] **Step 4: Run full build verification**

Run: `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit the final verification-safe state**

```bash
git add KnowYouTests/DailyMarkdownComposerTests.swift KnowYouTests/DailyMarkdownViewTests.swift
git commit -m "test: verify markdown-rich diary reader behavior"
```

---

## Self-Review

### Spec coverage

- Story paragraphs render as Markdown: Task 4
- Source Notes render as Markdown: Tasks 2 and 4
- Source linking remains higher priority: Task 4 keeps paragraph IDs and selection callbacks unchanged
- Saved `.md` remains the artifact: Task 2 reads it instead of replacing it
- Fallback when file is missing: Task 2

### Placeholder scan

No `TODO`, `TBD`, or deferred implementation markers remain.

### Type consistency

- `selectedSourceNotesMarkdown` is introduced once and reused consistently
- `loadDailyNoteMarkdown(from:)` is the only environment loader helper
- `DailyMarkdownView` receives `sourceNotesMarkdown` as the added input

