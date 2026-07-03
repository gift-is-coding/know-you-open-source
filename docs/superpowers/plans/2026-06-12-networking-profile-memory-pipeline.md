# Networking Profile Memory Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 Networking 能基于用户本地 My Wiki 记忆层生成高质量、可审核的职业和个人 profile 原文 draft。

**Architecture:** 在现有 `NetworkingProfileGenerationService` 内替换默认 context provider 行为：从 `wiki/` 记忆页做 scenario-aware selection，不再默认读取 `raw/sources`。继续复用现有 LLM summarizer 和 approval 模型。

**Tech Stack:** Swift, XCTest, SwiftUI app services, local My Wiki markdown project.

---

### Task 1: My Wiki-only context provider tests

**Files:**
- Modify: `KnowYouTests/NetworkingCockpitPresentationTests.swift`
- Modify: `KnowYou/Services/Networking/NetworkingProfileGenerationService.swift`

- [ ] **Step 1: Write failing tests**

Add tests that create a temporary My Wiki with both `wiki/` pages and `raw/sources` pages, then assert `MyWikiNetworkingContextProvider` returns only wiki citations and ranks career/friends pages by scenario.

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/NetworkingCockpitPresentationTests
```

Expected: the new raw-source exclusion test fails because the current provider delegates to `MyWikiContextPackService`, which scans both `wiki/` and `raw/sources`.

- [ ] **Step 3: Implement the provider**

Update `MyWikiNetworkingContextProvider` to enumerate only `wiki/` markdown files, parse title/frontmatter/body, score pages with scenario lens terms, and emit a bounded `NetworkingProfileContext`.

- [ ] **Step 4: Run targeted tests**

Run the same `xcodebuild test` target and confirm the new tests pass.

### Task 2: Profile prompt quality and privacy

**Files:**
- Modify: `KnowYouTests/NetworkingCockpitPresentationTests.swift`
- Modify: `KnowYou/Services/Networking/NetworkingProfileGenerationService.swift`

- [ ] **Step 1: Write failing tests**

Add tests that capture the prompt passed to the summarizer and assert it asks for public profile output, redaction, citations, and separate career/social section intent.

- [ ] **Step 2: Implement prompt update**

Revise `NetworkingPromptProfileGenerator` prompt to target 2,000-3,000 words across 6-10 titled sections, with public-safe redaction and no raw evidence. Summary 只作为 UI 预览，sections 才是用户审批前要看的 profile 原文。

- [ ] **Step 3: Run targeted tests**

Run the Networking test slice again.

### Task 3: Real local My Wiki generation smoke

**Files:**
- Modify only if needed: `KnowYou/KnowYouApp.swift`
- Modify only if needed: `KnowYou/Services/Networking/NetworkingProfileGenerationService.swift`

- [ ] **Step 1: Build current app**

Run:

```bash
xcodebuild build -scheme KnowYou -destination 'platform=macOS'
```

- [ ] **Step 2: Generate two profiles from real local data**

Use a freshly built app or a focused helper command to run `NetworkingProfileGenerationService` against:

```text
/Users/wutianfu/Library/Application Support/KnowYou/KnowledgeOntology/KnowYouContext
```

Generate `Career / Hiring` and `Friends / Social` drafts.

- [ ] **Step 3: Inspect output**

Confirm both drafts are grounded in My Wiki citations, avoid raw source paths, avoid private evidence, and are useful from a user-facing profile perspective.

### Task 4: App draft visibility

**Files:**
- Modify: `KnowYou/UI/Networking/NetworkingCockpitView.swift`
- Modify: `KnowYouTests/NetworkingCockpitPresentationTests.swift`

- [ ] **Step 1: Write failing presentation assertion**

Assert that the generated-result preview includes both `Draft summary` and `Full profile draft`, and renders `draft.body`.

- [ ] **Step 2: Implement full-body display**

Update the SwiftUI preview so summary is a short overview and the full generated draft body is visible and selectable before approval.

- [ ] **Step 3: Fix status copy**

When a draft exists but is not approved, profile cards should show `Generated draft` / `Needs approval`, not `Draft not generated`.
