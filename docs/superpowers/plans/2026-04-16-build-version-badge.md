# Build Version Badge And Source App Alias Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a tiny build identifier in the main window so every local build is visibly tied to a version/build number and git short SHA, and make source-app logo resolution robust to Chinese, English, and bundle-id style names.

**Architecture:** Read marketing/build versions from the app bundle, write an auto build number plus git short SHA into build outputs during Xcode build, render a non-interactive badge in the main window corner, and enhance the source-brand alias resolver with normalization plus fuzzy matching.

**Tech Stack:** SwiftUI, Foundation, Xcode project build phases, XCTest

---

### Task 1: Add metadata formatting tests

**Files:**
- Modify: `KnowYouTests/SettingsMetadataTests.swift`

- [ ] Add failing tests for badge text formatting with and without git SHA.
- [ ] Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/SettingsMetadataTests`
- [ ] Verify the new tests fail for the expected missing symbol/behavior reason.

### Task 2: Implement build metadata reader

**Files:**
- Modify: `KnowYou/App/AppSupportMetadata.swift`

- [ ] Add minimal app build metadata types that:
  - read bundle version/build values
  - decode optional `BuildMetadata.json`
  - expose one `badgeText`
- [ ] Re-run the `SettingsMetadataTests` slice and make it pass.

### Task 3: Show badge in main window

**Files:**
- Modify: `KnowYou/UI/MainWindowView.swift`

- [ ] Add a tiny bottom-right overlay badge using the formatted metadata text.
- [ ] Keep it non-interactive and visually quiet.

### Task 4: Generate bundle build metadata at build time

**Files:**
- Modify: `KnowYou.xcodeproj/project.pbxproj`

- [ ] Add an Xcode shell script build phase that writes `BuildMetadata.json` into the built app resources.
- [ ] Populate `buildNumber` from `git rev-list --count HEAD`.
- [ ] Populate `gitShortSHA`; fall back safely when git is unavailable.
- [ ] Patch the built `Info.plist` so `CFBundleVersion` matches the generated build number.

### Task 5: Expand source app alias coverage

**Files:**
- Modify: `KnowYou/UI/Reader/DailyMarkdownView.swift`
- Modify: `KnowYouTests/DailyMarkdownViewTests.swift`

- [ ] Add a failing test for bundle-id style source names such as `com.tencent.xinWeChat`.
- [ ] Keep the existing alias catalog, but improve normalization and fallback matching.
- [ ] Make the resolver cover known app assets across Chinese names, English names, and bundle-id style names without changing the unknown-app fallback.

### Task 6: Verify app behavior

**Files:**
- Verify only

- [ ] Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/SettingsMetadataTests -only-testing:KnowYouTests/DailyMarkdownViewTests`
- [ ] Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS'`
- [ ] Run: `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`
- [ ] Inspect the freshly built app bundle and confirm `CFBundleVersion` matches the generated build number.
- [ ] Open the freshly built app and visually confirm the badge is visible in the main window corner.
