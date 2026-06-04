# Global Search V1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a top-level `Search` entry below `Home` that searches diary Markdown, My Wiki entities/concepts, imported sources, and unified Todo with local keyword matching only.

**Architecture:** Add a small `GlobalSearchService` over current in-memory app indexes, My Wiki dashboard primary entries, and source file paths. Keep My Wiki file-level search separate as an in-panel search. Route the new global search through `MainWindowMode.search` and `DateSidebarPresentation.searchRootItem`.

**Tech Stack:** Swift 6, SwiftUI, XCTest.

---

## Task 1: RED Tests

**Files:**
- Create: `KnowYouTests/GlobalSearchServiceTests.swift`
- Modify: `KnowYouTests/DailyMarkdownViewTests.swift`

- [x] Add a service test that searches one diary file, one imported source document, and one Todo item with the same keyword.
- [x] Add a blank-query test.
- [x] Add sidebar presentation tests for `Search` below `Home`, selected state, and `.search` action.
- [x] Run targeted tests and confirm the initial failure is missing global search production code.

## Task 2: Search Service

**Files:**
- Create: `KnowYou/Services/Search/GlobalSearchService.swift`
- Modify: `KnowYou.xcodeproj/project.pbxproj`

- [x] Add `GlobalSearchRequest`, `GlobalSearchResponse`, `GlobalSearchGroup`, and `GlobalSearchResult`.
- [x] Search Todo titles/status, diary Markdown files, and imported source local content paths.
- [x] Filter diary notes to `YYYY-MM-DD` day keys so utility Markdown such as `Todo.md` is not treated as diary.
- [x] Return grouped results in `Todo`, `Diary`, `Sources` order.

## Task 3: Navigation and UI

**Files:**
- Modify: `KnowYou/UI/Sidebar/DateSidebarView.swift`
- Modify: `KnowYou/UI/MainWindowView.swift`

- [x] Add `SidebarSelectionAction.search`.
- [x] Add `DateSidebarPresentation.searchRootItem` and insert it after `Home`.
- [x] Add `MainWindowMode.search`.
- [x] Show a global search page in the main content pane.
- [x] Route result clicks to Todo inbox, diary date, or source document.

## Task 4: Documentation and Verification

**Files:**
- Modify: `docs/architecture.md`
- Modify: `docs/requirements-spec.md`

- [x] Document the top-level global search entry and V1 lexical-only scope.
- [x] Run targeted global search/sidebar tests.
- [x] Run `git diff --check`.
- [x] Run full `xcodebuild test -scheme KnowYou -destination 'platform=macOS'`.
- [x] Run full `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`.
- [x] Reopen the freshly built app from the current checkout.

## Task 5: Result Click Targeting

**Files:**
- Modify: `KnowYou/Services/Search/GlobalSearchService.swift`
- Modify: `KnowYou/UI/MainWindowView.swift`
- Modify: `KnowYou/UI/Reader/DailyMarkdownView.swift`
- Modify: `KnowYou/UI/Todo/TodoInboxView.swift`
- Modify: `KnowYou/UI/Knowledge/KnowledgeSourceContentView.swift`
- Modify: `KnowYouTests/GlobalSearchServiceTests.swift`
- Modify: `KnowYouTests/DailyMarkdownViewTests.swift`
- Modify: `KnowYouTests/KnowledgeSourceContentViewTests.swift`

- [x] Add tests that search results expose target IDs for Todo, Diary, and Sources.
- [x] Add tests for diary search-query scroll targeting and Markdown block highlighting rules.
- [x] Add tests for Todo row highlight target matching and source presentation query normalization.
- [x] Store a one-shot global search navigation target in `MainWindowView`.
- [x] Route clicked search results to the existing Todo, Diary, and Source screens while passing target/query context.
- [x] Highlight and scroll Todo rows, Diary paragraphs, and Source Markdown blocks.
- [x] Highlight matched keywords inside search result title/snippet, Todo row titles, and rendered Markdown text.

## Task 6: My Wiki Entity and Concept Coverage

**Files:**
- Modify: `KnowYou/Services/Search/GlobalSearchService.swift`
- Modify: `KnowYou/UI/MainWindowView.swift`
- Modify: `KnowYouTests/GlobalSearchServiceTests.swift`

- [x] Add a failing service test proving global search can find generated My Wiki entity and concept entries.
- [x] Extend `GlobalSearchRequest` and `GlobalSearchResult` with My Wiki entry data.
- [x] Rank and group My Wiki results between `Diary` and `Sources`.
- [x] Load `MyWikiMarkdownStore` dashboard primary entries for global search.
- [x] Route My Wiki result clicks to the My Wiki panel and select the matching entity or concept.

## Task 7: Explicit Search Submission

**Files:**
- Modify: `KnowYou/UI/MainWindowView.swift`
- Modify: `KnowYouTests/KnowledgeOntologyPanelTests.swift`

- [x] Add a failing policy test proving draft input does not execute global search.
- [x] Split global search text entry into draft query and submitted query.
- [x] Trigger search only from TextField submit / Enter.
- [x] Keep result highlighting and result navigation tied to the submitted query.
- [x] Clear both draft and submitted query when the user clears the search field.
