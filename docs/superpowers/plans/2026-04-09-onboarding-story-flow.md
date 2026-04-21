# Onboarding Story Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current utility-style onboarding with a five-step story-driven flow that explains local Markdown storage, automatic capture, filtering, optional sync, a final diary preview, and permission value before completion.

**Architecture:** Introduce a small onboarding content model that owns step order, CTA copy, and static narrative text, then rebuild `OnboardingView` around that model with dedicated scene subviews. Keep persistence in `AppState`, defer summarizer setup out of the first-run critical path, and back the story flow with focused XCTest coverage plus full macOS build/test verification.

**Tech Stack:** SwiftUI, XCTest, AppKit, xcodebuild, existing `AppState` and Settings flow

---

### Task 1: Add a Testable Onboarding Step Model

**Files:**
- Create: `KnowYou/UI/Onboarding/OnboardingContent.swift`
- Create: `KnowYouTests/OnboardingContentTests.swift`
- Modify: `KnowYou.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write the failing tests for the new onboarding narrative contract**

```swift
import XCTest
@testable import KnowYou

final class OnboardingContentTests: XCTestCase {
    func testStoryFlowContainsFiveStepsInNarrativeOrder() {
        XCTAssertEqual(
            OnboardingStep.allCases,
            [.intro, .capture, .safety, .preview, .permissions]
        )
    }

    func testIntroStepStatesLocalMarkdownStorage() {
        let content = OnboardingContent.content(for: .intro)

        XCTAssertTrue(content.caption.contains("Markdown"), content.caption)
        XCTAssertTrue(content.caption.localizedCaseInsensitiveContains("your own Mac"), content.caption)
    }

    func testSafetyStepExplainsOptionalSyncAndFiltering() {
        let content = OnboardingContent.content(for: .safety)
        let joined = ([content.title, content.body] + content.bullets).joined(separator: "\n")

        XCTAssertTrue(joined.localizedCaseInsensitiveContains("filtered"), joined)
        XCTAssertTrue(joined.localizedCaseInsensitiveContains("Claude"), joined)
        XCTAssertTrue(joined.localizedCaseInsensitiveContains("Openclaw"), joined)
        XCTAssertTrue(joined.localizedCaseInsensitiveContains("optional"), joined)
    }

    func testPermissionsStepUsesStorySpecificPrimaryAction() {
        XCTAssertEqual(
            OnboardingContent.content(for: .permissions).primaryCTA,
            "Start remembering my days"
        )
    }
}
```

- [ ] **Step 2: Run the new test file and verify it fails because the onboarding model does not exist yet**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/OnboardingContentTests
```

Expected: FAIL with errors such as `cannot find 'OnboardingStep' in scope` and `cannot find 'OnboardingContent' in scope`.

- [ ] **Step 3: Create the minimal onboarding content model**

```swift
import Foundation

enum OnboardingStep: Int, CaseIterable {
    case intro
    case capture
    case safety
    case preview
    case permissions
}

struct OnboardingStepContent: Equatable {
    var title: String
    var body: String
    var caption: String
    var bullets: [String]
    var primaryCTA: String
}

enum OnboardingContent {
    static func content(for step: OnboardingStep) -> OnboardingStepContent {
        switch step {
        case .intro:
            return OnboardingStepContent(
                title: "From the moment your day begins, KnowYou helps you remember it.",
                body: "It turns scattered context into a readable diary you can revisit at night.",
                caption: "Your information stays in Markdown files stored on your own Mac.",
                bullets: [],
                primaryCTA: "See how your day comes together"
            )
        case .capture:
            return OnboardingStepContent(
                title: "During the day, it quietly gathers the clues you leave behind.",
                body: "KnowYou works automatically so you do not need to write a manual log.",
                caption: "",
                bullets: [
                    "Message notifications help reconstruct who reached you and when.",
                    "Clipboard activity gives context about what you were reading, writing, and comparing.",
                    "Voice-input tools that land text in the clipboard give KnowYou richer context."
                ],
                primaryCTA: "Show me the safety boundary"
            )
        case .safety:
            return OnboardingStepContent(
                title: "Before anything becomes memory, KnowYou filters it.",
                body: "Even local files are filtered so sensitive details are not retained blindly.",
                caption: "",
                bullets: [
                    "Sensitive items like bank-card numbers, OTPs, passwords, and tokens should not be saved locally.",
                    "You can now or later sync your Markdown files to Openclaw or Claude.",
                    "That sync is optional and helps agents remember you better."
                ],
                primaryCTA: "Show me what my day could look like"
            )
        case .preview:
            return OnboardingStepContent(
                title: "By evening, your day becomes a story you can actually read.",
                body: "KnowYou turns the signals into a diary from morning to night, with source context nearby when you need it.",
                caption: "",
                bullets: [],
                primaryCTA: "What do you need from me?"
            )
        case .permissions:
            return OnboardingStepContent(
                title: "Turn on the signals that let KnowYou rebuild your day.",
                body: "Each permission exists to fill in a specific piece of the story, not to create a generic data grab.",
                caption: "",
                bullets: [],
                primaryCTA: "Start remembering my days"
            )
        }
    }
}
```

- [ ] **Step 4: Add the new source files to the Xcode project**

```pbxproj
/* Begin PBXFileReference section */
		ABCD0001 /* OnboardingContent.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = OnboardingContent.swift; sourceTree = "<group>"; };
		ABCD0002 /* OnboardingContentTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = OnboardingContentTests.swift; sourceTree = "<group>"; };
/* End PBXFileReference section */

/* Begin PBXSourcesBuildPhase section */
				ABCD1001 /* OnboardingContent.swift in Sources */,
				ABCD1002 /* OnboardingContentTests.swift in Sources */,
/* End PBXSourcesBuildPhase section */
```

- [ ] **Step 5: Run the targeted test again and verify it passes**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/OnboardingContentTests
```

Expected: PASS with `Executed 4 tests, with 0 failures`.

- [ ] **Step 6: Commit the model foundation**

```bash
git add KnowYou/UI/Onboarding/OnboardingContent.swift KnowYouTests/OnboardingContentTests.swift KnowYou.xcodeproj/project.pbxproj
git commit -m "test: add onboarding story content model"
```

### Task 2: Rebuild OnboardingView Around the Story Flow

**Files:**
- Modify: `KnowYou/UI/Onboarding/OnboardingView.swift`
- Create: `KnowYouTests/OnboardingContentTests.swift`

- [ ] **Step 1: Extend the tests to lock in step-specific CTA labels and preview copy**

```swift
func testPreviewStepUsesReaderStyleValueLanguage() {
    let content = OnboardingContent.content(for: .preview)
    let joined = [content.title, content.body].joined(separator: "\n")

    XCTAssertTrue(joined.localizedCaseInsensitiveContains("story"), joined)
    XCTAssertTrue(joined.localizedCaseInsensitiveContains("morning to night"), joined)
}

func testCaptureStepStatesAutomationClearly() {
    let content = OnboardingContent.content(for: .capture)
    XCTAssertTrue(content.body.localizedCaseInsensitiveContains("automatically"), content.body)
}
```

- [ ] **Step 2: Run the focused tests and verify they fail on missing content details**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/OnboardingContentTests
```

Expected: FAIL on the new assertions until the content and view wiring are updated.

- [ ] **Step 3: Replace the integer step index with a dedicated story-step enum**

```swift
@State private var step: OnboardingStep = .intro
@State private var vaultPath: String = (try? AppState.defaultVaultURL().path) ?? ""

private var allSteps: [OnboardingStep] { OnboardingStep.allCases }
private var stepIndex: Int { allSteps.firstIndex(of: step) ?? 0 }
private var isLastStep: Bool { step == allSteps.last }

private func advance() {
    guard let currentIndex = allSteps.firstIndex(of: step), currentIndex + 1 < allSteps.count else { return }
    step = allSteps[currentIndex + 1]
}

private func goBack() {
    guard let currentIndex = allSteps.firstIndex(of: step), currentIndex > 0 else { return }
    step = allSteps[currentIndex - 1]
}
```

- [ ] **Step 4: Replace the three old utility pages with five dedicated story scenes**

```swift
switch step {
case .intro:
    IntroOnboardingStep(content: OnboardingContent.content(for: .intro))
case .capture:
    CaptureOnboardingStep(content: OnboardingContent.content(for: .capture))
case .safety:
    SafetyOnboardingStep(content: OnboardingContent.content(for: .safety))
case .preview:
    PreviewOnboardingStep(story: previewStory)
case .permissions:
    PermissionsOnboardingStep(
        content: OnboardingContent.content(for: .permissions),
        notificationAvailable: appState.environment?.notificationReader.isAvailable == true
    )
}
```

- [ ] **Step 5: Add a believable diary preview component instead of a generic placeholder**

```swift
private let previewStory = [
    "9:10 AM  You started the morning by outlining the work ahead and pulling together the documents you needed.",
    "11:40 AM  Notifications and copied snippets captured the back-and-forth that shaped the middle of the day.",
    "3:20 PM  As the afternoon narrowed into execution, the day gained a clear thread instead of scattered fragments.",
    "9:05 PM  By the evening, KnowYou turned the raw context into a diary you could revisit and trace."
]

private struct PreviewOnboardingStep: View {
    let story: [String]

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Today")
                Text("Morning")
                Text("Afternoon")
                Text("Evening")
            }
            .frame(width: 90, alignment: .leading)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(story, id: \.self) { paragraph in
                    Text(paragraph)
                        .padding(12)
                        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Sources")
                    .font(.headline)
                Text("Messages")
                Text("Clipboard")
                Text("Readable, traceable, local")
            }
            .frame(width: 120, alignment: .leading)
        }
    }
}
```

- [ ] **Step 6: Update the progress dots and CTA labels to reflect story progression**

```swift
ForEach(allSteps, id: \.self) { item in
    Circle()
        .fill(item == step ? Color.accentColor : Color.secondary.opacity(0.3))
        .frame(width: 8, height: 8)
}

Button(OnboardingContent.content(for: step).primaryCTA) {
    isLastStep ? finish() : advance()
}
.buttonStyle(.borderedProminent)
```

- [ ] **Step 7: Remove summarizer setup from the first-run finish path**

```swift
private func finish() {
    let vaultURL = URL(fileURLWithPath: vaultPath, isDirectory: true)
    appState.applyVaultURL(vaultURL)
    UserDefaults.standard.set(true, forKey: AppState.UserDefaultsKeys.hasCompletedOnboarding)
    onComplete()
}
```

- [ ] **Step 8: Re-run the focused onboarding tests and verify they pass**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/OnboardingContentTests
```

Expected: PASS with the new preview and CTA expectations satisfied.

- [ ] **Step 9: Commit the story-flow view rewrite**

```bash
git add KnowYou/UI/Onboarding/OnboardingView.swift KnowYou/UI/Onboarding/OnboardingContent.swift KnowYouTests/OnboardingContentTests.swift
git commit -m "feat: rebuild onboarding as story flow"
```

### Task 3: Add Permission Details, Voice-Input Links, and Settings Handoff

**Files:**
- Modify: `KnowYou/UI/Onboarding/OnboardingView.swift`
- Modify: `KnowYou/UI/Settings/SettingsView.swift`
- Modify: `KnowYou/App/AppState.swift`
- Create: `KnowYouTests/OnboardingContentTests.swift`

- [ ] **Step 1: Write failing tests for the permission/value copy and post-onboarding configuration handoff**

```swift
func testPermissionsStepExplainsWhyAccessIsNeeded() {
    let content = OnboardingContent.content(for: .permissions)
    let joined = ([content.title, content.body] + content.bullets).joined(separator: "\n")

    XCTAssertTrue(joined.localizedCaseInsensitiveContains("permission"), joined)
    XCTAssertTrue(joined.localizedCaseInsensitiveContains("story"), joined)
}

func testCaptureStepRecommendsVoiceInputHelpers() {
    let content = OnboardingContent.content(for: .capture)
    let joined = content.bullets.joined(separator: "\n")

    XCTAssertTrue(joined.localizedCaseInsensitiveContains("voice"), joined)
    XCTAssertTrue(joined.localizedCaseInsensitiveContains("clipboard"), joined)
}
```

- [ ] **Step 2: Run the focused tests and verify they fail until the permission and helper copy is expanded**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/OnboardingContentTests
```

Expected: FAIL on the new permission/helper assertions.

- [ ] **Step 3: Expand the content model and permissions scene with plain-language value rows**

```swift
case .permissions:
    return OnboardingStepContent(
        title: "Turn on the signals that let KnowYou rebuild your day.",
        body: "These permissions help KnowYou recover the moments that would otherwise disappear from the story.",
        caption: "You can skip this for now and come back from Settings later.",
        bullets: [
            "Clipboard helps capture the context you actively touched during the day.",
            "Notification access helps recover conversations, reminders, and important interruptions.",
            "Local access keeps the journal automatic instead of making you rebuild the day by hand."
        ],
        primaryCTA: "Start remembering my days"
    )
```

- [ ] **Step 4: Add outbound links for voice-input helpers and a direct system-settings link for permission recovery**

```swift
private func openVoiceInputHelper(_ urlString: String) {
    guard let url = URL(string: urlString) else { return }
    NSWorkspace.shared.open(url)
}

Button("Try voice input with Maccy") {
    openVoiceInputHelper("https://maccy.app")
}

Button("Open Full Disk Access") {
    openFullDiskAccess()
}
```

- [ ] **Step 5: Add a post-onboarding settings nudge so summarizer setup still has a clear home**

```swift
Section("Summarizer") {
    Text("Optional enhancement. Your local Markdown diary works without this.")
        .font(.caption)
        .foregroundStyle(.secondary)

    Picker("Type", selection: $summarizerConfig.type) {
        ForEach(SummarizerType.allCases, id: \.self) { type in
            Text(type.displayName).tag(type)
        }
    }
    .pickerStyle(.menu)
}
```

- [ ] **Step 6: Keep `AppState` persistence behavior narrow and explicit**

```swift
func applyVaultURL(_ url: URL) {
    UserDefaults.standard.set(url.path, forKey: UserDefaultsKeys.vaultPath)
    guard let environment else { return }
    environment.vaultURL = url
    refreshNotesIndex()
    statusMessage = "Vault set to \(url.lastPathComponent)"
}
```

- [ ] **Step 7: Re-run the targeted tests and verify they pass**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/OnboardingContentTests
```

Expected: PASS with all helper, filtering, sync, and permission assertions green.

- [ ] **Step 8: Commit the permission and settings handoff work**

```bash
git add KnowYou/UI/Onboarding/OnboardingView.swift KnowYou/UI/Settings/SettingsView.swift KnowYou/App/AppState.swift KnowYouTests/OnboardingContentTests.swift
git commit -m "feat: connect onboarding story to permissions and settings"
```

### Task 4: Update Product Docs and Run Full Verification

**Files:**
- Modify: `docs/requirements-spec.md`
- Modify: `docs/architecture.md`
- Modify: `docs/superpowers/specs/2026-04-09-onboarding-story-design.md`
- Modify: `docs/superpowers/plans/2026-04-09-onboarding-story-flow.md`

- [ ] **Step 1: Write the documentation updates that reflect the new onboarding responsibilities**

```markdown
## 6.7 配置需求

首次 onboarding 必须优先完成故事化引导、隐私边界解释、结果预览和权限说明。

- vault 位置必须在 onboarding 中明确说明为本地 Markdown 存储
- summarizer 配置不再阻塞首次完成
- 权限请求之前必须先展示结果页预览
```

```markdown
## 2. 系统总览

界面层中的 onboarding 现在是五步叙事流：

1. 开场与本地 Markdown 承诺
2. 自动化采集说明
3. 过滤与可选同步边界
4. 日记结果预览
5. 权限价值说明与完成
```

- [ ] **Step 2: Run a focused test pass for onboarding and existing app-state regression coverage**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' \
  -only-testing:KnowYouTests/OnboardingContentTests \
  -only-testing:KnowYouTests/MainWindowViewModelTests
```

Expected: PASS with `0 failures`.

- [ ] **Step 3: Run the full macOS test suite required by the repository**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS'
```

Expected: PASS for the full `KnowYouTests` suite with `0 failures`.

- [ ] **Step 4: Run the full macOS build verification required by the repository**

Run:

```bash
xcodebuild build -scheme KnowYou -destination 'platform=macOS'
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit the docs and final verification-ready state**

```bash
git add docs/requirements-spec.md docs/architecture.md docs/superpowers/specs/2026-04-09-onboarding-story-design.md docs/superpowers/plans/2026-04-09-onboarding-story-flow.md
git commit -m "docs: align onboarding story flow documentation"
```

## Self-Review

- Spec coverage:
  - Intro/local Markdown statement: Task 1 and Task 2
  - Automatic notifications/clipboard/voice input: Task 1 and Task 3
  - Filtering and optional sync to Openclaw/Claude: Task 1 and Task 3
  - Preview before permissions: Task 2
  - Permission-value explanation: Task 3
  - Summarizer moved out of first-run path: Task 2 and Task 3
  - Architecture/requirements updates: Task 4

- Placeholder scan:
  - No unfinished markers or placeholder steps remain.

- Type consistency:
  - `OnboardingStep`, `OnboardingStepContent`, and `OnboardingContent.content(for:)` are used consistently across tests and production tasks.

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-04-09-onboarding-story-flow.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**
