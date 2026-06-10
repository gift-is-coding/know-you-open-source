# My Wiki Search Index V1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a lightweight Obsidian-style local keyword search in My Wiki that searches diary/raw source Markdown and generated wiki pages without BM25, embedding, model downloads, or a server.

**Architecture:** Reuse the existing My Wiki markdown scan/query-plan logic as a dedicated search service, then add a small SwiftUI presentation path in `MyWikiPanel` that switches from category browsing to search results when the query is non-empty. Keep ranking lexical and in-memory for V1.

**Tech Stack:** Swift 6, SwiftUI, XCTest, existing My Wiki project folder layout.

---

## Task 1: Local Keyword Search Service

**Files:**
- Create: `KnowYou/Services/MyWiki/MyWikiSearchService.swift`
- Create: `KnowYouTests/MyWikiSearchServiceTests.swift`
- Modify if needed: `KnowYou.xcodeproj/project.pbxproj`

- [ ] Write failing tests for diary/raw source/wiki page search, Chinese phrase matching, wiki-before-raw ranking, and empty project behavior.
- [ ] Implement `MyWikiSearchRequest`, `MyWikiSearchResult`, `MyWikiSearchGroup`, and `MyWikiSearchService.search`.
- [ ] Reuse or mirror the existing `MyWikiContextPackService` tokenization/scoring style, keeping the V1 implementation lexical only.
- [ ] Run `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MyWikiSearchServiceTests`.

## Task 2: My Wiki Search Presentation

**Files:**
- Modify: `KnowYou/UI/MyWiki/MyWikiModels.swift`
- Test: `KnowYouTests/MyWikiSearchPresentationTests.swift`

- [ ] Write failing presentation tests for query-empty browse mode, query-nonempty search mode, result count text, and group labels.
- [ ] Add lightweight presentation structs/policies for grouped search results.
- [ ] Keep existing category section filtering behavior unchanged when the search service is not used.
- [ ] Run the new presentation tests.

## Task 3: Wire Search Into MyWikiPanel

**Files:**
- Modify: `KnowYou/UI/MyWiki/MyWikiPanel.swift`
- Modify tests if needed: `KnowYouTests/KnowledgeOntologyPanelTests.swift` or targeted My Wiki panel/presentation tests

- [ ] Add `@State` search results and search status.
- [ ] Trigger local search when `query` changes and `projectRoot` exists.
- [ ] Show grouped search results instead of category sections when query is non-empty.
- [ ] Selecting a wiki result opens the matching `MyWikiEntry`; selecting a raw source result uses existing source opening behavior.
- [ ] Keep query-empty My Wiki dashboard unchanged.

## Task 4: Verification

**Files:**
- Modify: `docs/architecture.md`
- Modify: `docs/requirements-spec.md`

- [ ] Add short architecture/requirements notes saying V1 search is local lexical search over `wiki/` and `raw/sources/`.
- [ ] Run targeted My Wiki tests:
  `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/MyWikiSearchServiceTests -only-testing:KnowYouTests/MyWikiSearchPresentationTests -only-testing:KnowYouTests/MyWikiContextPackServiceTests -only-testing:KnowYouTests/MyWikiMarkdownStoreTests`
- [ ] Run `git diff --check`.
- [ ] If time allows, run full `xcodebuild test -scheme KnowYou -destination 'platform=macOS'`; otherwise report that only targeted verification was run.
