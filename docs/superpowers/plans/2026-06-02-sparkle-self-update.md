# Sparkle Self Update Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship Sparkle-backed direct-channel self update plus stronger update content UI and post-update What's New.

**Architecture:** Keep KnowYou's custom update detection and sheet for product consistency, but route direct install actions through Sparkle. Publish both legacy JSON metadata and Sparkle appcast so old versions can migrate and new versions can self-update.

**Tech Stack:** SwiftUI, AppKit, Sparkle 2.9.x, Xcode Swift Package Manager, bash release scripts.

---

### Task 1: Update UI And State Tests

**Files:**
- Modify: `KnowYouTests/UpdatePresentationTests.swift`
- Modify: `KnowYouTests/MainWindowViewModelTests.swift`
- Modify: `scripts/test-publish-release-common.sh`

- [x] Change presentation tests so direct update copy expects `Update <version>` and `Update Now`.
- [x] Add AppState tests for Sparkle default updater and post-update What's New version memory.
- [x] Add release helper test for Sparkle appcast XML.
- [x] Verify the tests fail before implementation.

### Task 2: Implement App Update Runtime

**Files:**
- Modify: `KnowYou/Domain/AppUpdate.swift`
- Modify: `KnowYou/Services/Updates/UpdateService.swift`
- Modify: `KnowYou/App/AppEnvironment.swift`
- Modify: `KnowYou/App/AppState.swift`
- Modify: `KnowYou/UI/MainWindowView.swift`
- Modify: `KnowYou/UI/Updates/UpdatePillView.swift`
- Modify: `KnowYou/UI/Updates/UpdateSheet.swift`

- [x] Change direct copy and pill title to the new version-forward language.
- [x] Add `SparkleDirectAppUpdater` and make it the default direct updater.
- [x] Add `lastSeenAppVersion` / `lastDismissedWhatsNewVersion` state and post-update sheet behavior.
- [x] Make the update pill more visible and update sheets content-first.
- [x] Verify targeted Swift tests pass.

### Task 3: Implement Sparkle Packaging

**Files:**
- Modify: `KnowYou.xcodeproj/project.pbxproj`
- Modify: `KnowYou.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
- Add: `Support/update-feed/appcast.xml`
- Modify: `scripts/release-common.sh`
- Modify: `scripts/build-release.sh`
- Modify: `scripts/publish-release.sh`

- [x] Add Sparkle 2.9.2 SPM dependency and Info.plist Sparkle keys.
- [x] Add debug appcast for local preview.
- [x] Require Sparkle public key for Release builds.
- [x] Generate appcast XML with signed DMG enclosure and publish it beside `latest.json`.
- [x] Verify release helper tests pass.

### Task 4: Documentation And Verification

**Files:**
- Add: `docs/superpowers/specs/2026-06-02-sparkle-self-update-design.md`
- Add: `docs/superpowers/plans/2026-06-02-sparkle-self-update.md`
- Modify: `docs/requirements-spec.md`
- Modify: `docs/architecture.md`
- Modify: `docs/release-signing.md`

- [x] Update architecture, requirements, release docs, spec, and plan.
- [x] Run targeted tests, release helper tests, full macOS build, Info.plist inspection, and `git diff --check`.
- [x] Note that live Sparkle install verification requires a real signed release with matching public/private EdDSA keys.

Verification note: one full `xcodebuild test -scheme KnowYou -destination 'platform=macOS'` run completed successfully before the explicit Info.plist template correction. After the correction, a rerun of the full suite hung in an existing app-driven diary generation path and was terminated; the Sparkle/update-specific test slice, release helper tests, final macOS build, bundle Info.plist inspection, and `git diff --check` passed afterward.
