# Full Disk Access Onboarding Guidance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Help users complete onboarding when KnowYou is not already visible in macOS Full Disk Access settings.

**Architecture:** Keep the fix in the onboarding content and view layer. Add testable guidance copy to `OnboardingContent`, render it from `OnboardingView`, and use AppKit only for the existing System Settings jump plus a new Finder reveal action.

**Tech Stack:** SwiftUI, AppKit, XCTest, macOS TCC / Full Disk Access.

---

### Task 1: Add Testable Full Disk Access Guidance

**Files:**
- Modify: `KnowYou/UI/Onboarding/OnboardingContent.swift`
- Modify: `KnowYouTests/OnboardingContentTests.swift`

- [ ] **Step 1: Write the failing test**

Add this test to `OnboardingContentTests`:

```swift
func testFullDiskAccessGuidanceExplainsHowToAddKnowYouWhenItIsNotListed() {
    let guidance = OnboardingContent.fullDiskAccessGuidance

    XCTAssertTrue(guidance.missingPermissionDetail.contains("click +"))
    XCTAssertTrue(guidance.missingPermissionDetail.contains("select KnowYou.app"))
    XCTAssertTrue(guidance.manualAddInstruction.contains("does not appear"))
    XCTAssertTrue(guidance.manualAddInstruction.contains("Show KnowYou in Finder"))
    XCTAssertEqual(guidance.openSettingsButtonTitle, "Open Full Disk Access")
    XCTAssertEqual(guidance.revealAppButtonTitle, "Show KnowYou in Finder")
    XCTAssertEqual(guidance.recheckButtonTitle, "Check Again")
}
```

- [ ] **Step 2: Run the test and verify it fails**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/OnboardingContentTests/testFullDiskAccessGuidanceExplainsHowToAddKnowYouWhenItIsNotListed
```

Expected: FAIL because `OnboardingContent.fullDiskAccessGuidance` does not exist.

- [ ] **Step 3: Add the guidance model**

Add this struct near the onboarding helper models:

```swift
struct OnboardingFullDiskAccessGuidance: Equatable {
    let missingPermissionDetail: String
    let manualAddInstruction: String
    let openSettingsButtonTitle: String
    let revealAppButtonTitle: String
    let recheckButtonTitle: String
}
```

Add this static value inside `OnboardingContent`:

```swift
static let fullDiskAccessGuidance = OnboardingFullDiskAccessGuidance(
    missingPermissionDetail: "Open Full Disk Access, click +, and select KnowYou.app. This lets KnowYou read the local Notification Center history.",
    manualAddInstruction: "If KnowYou does not appear in the list, use Show KnowYou in Finder, then add that app in System Settings.",
    openSettingsButtonTitle: "Open Full Disk Access",
    revealAppButtonTitle: "Show KnowYou in Finder",
    recheckButtonTitle: "Check Again"
)
```

- [ ] **Step 4: Run the focused test and verify it passes**

Run the same `xcodebuild test ... -only-testing:...testFullDiskAccessGuidanceExplainsHowToAddKnowYouWhenItIsNotListed` command.

Expected: PASS.

### Task 2: Render the Guidance in Onboarding

**Files:**
- Modify: `KnowYou/UI/Onboarding/OnboardingView.swift`

- [ ] **Step 1: Update the permission row detail**

Use `OnboardingContent.fullDiskAccessGuidance.missingPermissionDetail` when Full Disk Access is missing.

- [ ] **Step 2: Add the manual instruction text**

Render `OnboardingContent.fullDiskAccessGuidance.manualAddInstruction` below the Full Disk Access and notification rows in the permissions step.

- [ ] **Step 3: Add the Finder reveal action**

Add:

```swift
private func revealKnowYouInFinder() {
    NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
}
```

- [ ] **Step 4: Update permission buttons**

Use the guidance button titles and show three actions: open Full Disk Access, reveal KnowYou in Finder, and check again.

- [ ] **Step 5: Run focused onboarding tests**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/OnboardingContentTests
```

Expected: PASS.

### Task 3: Verify and Document

**Files:**
- Modify: `docs/architecture.md`
- Modify: `docs/requirements-spec.md`

- [ ] **Step 1: Update docs**

Document that onboarding must explain the manual Full Disk Access add flow and expose a way to reveal the current app bundle in Finder.

- [ ] **Step 2: Run full verification**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS'
xcodebuild build -scheme KnowYou -destination 'platform=macOS'
```

Expected: both commands exit 0.
