# Reader Scroll And Source Logos Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep the selected diary paragraph visible during keyboard navigation and add branded app logos to source cards in the right-side source panel with graceful fallback behavior.

**Architecture:** The reader keeps `AppState` as the selection source of truth while `DailyMarkdownView` adds local scroll-follow behavior with `ScrollViewReader`. Source-card visuals stay in the reader UI layer, using a deterministic brand resolver plus local asset-catalog images for known apps and SF Symbol fallback for unknown channels.

**Tech Stack:** SwiftUI, XCTest, Xcode asset catalogs, macOS app target `KnowYou`

---

## File Structure

- Modify: `KnowYou/UI/Reader/DailyMarkdownView.swift`
  - Add reader scroll-follow wiring
  - Add source-brand resolver and source-logo rendering
  - Keep paragraph selection and source-card layout responsibilities local
- Modify: `KnowYouTests/DailyMarkdownViewTests.swift`
  - Add failing tests for scroll-target presentation and source-brand resolution
- Create: `KnowYou/Assets.xcassets/SourceLogos/`
  - Container for branded source logos
- Create: `KnowYou/Assets.xcassets/<Brand>.imageset/` for each included source logo
  - Local asset-catalog entries referenced by the brand resolver
- Modify: `docs/architecture.md`
  - Record keyboard scroll-follow behavior and source logo rendering
- Modify: `docs/requirements-spec.md`
  - Record user-visible behavior for scroll-follow and source branding

### Task 1: Add Failing Tests For Reader Scroll Presentation

**Files:**
- Modify: `KnowYouTests/DailyMarkdownViewTests.swift`
- Test: `KnowYouTests/DailyMarkdownViewTests.swift`

- [ ] **Step 1: Write the failing test for selected paragraph scroll target derivation**

```swift
func testPresentationUsesSelectedParagraphAsScrollTarget() {
    let first = DailyStoryParagraph(
        id: "daily-journal-0",
        text: "First paragraph",
        sourceEventIDs: [UUID()]
    )
    let second = DailyStoryParagraph(
        id: "daily-journal-1",
        text: "Second paragraph",
        sourceEventIDs: [UUID()]
    )
    let story = DailyStory(
        dayKey: "2026-04-10",
        generatedAt: Date(timeIntervalSince1970: 0),
        sections: [
            DailyStorySection(id: "daily-journal", title: "", paragraphs: [first, second])
        ]
    )

    let presentation = DailyMarkdownPresentation(
        story: story,
        selectedParagraphID: "daily-journal-1"
    )

    XCTAssertEqual(presentation.initialScrollParagraphID, "daily-journal-1")
}
```

- [ ] **Step 2: Write the failing test for missing selection fallback**

```swift
func testPresentationFallsBackToFirstParagraphWhenSelectionMissing() {
    let first = DailyStoryParagraph(
        id: "daily-journal-0",
        text: "First paragraph",
        sourceEventIDs: [UUID()]
    )
    let second = DailyStoryParagraph(
        id: "daily-journal-1",
        text: "Second paragraph",
        sourceEventIDs: [UUID()]
    )
    let story = DailyStory(
        dayKey: "2026-04-10",
        generatedAt: Date(timeIntervalSince1970: 0),
        sections: [
            DailyStorySection(id: "daily-journal", title: "", paragraphs: [first, second])
        ]
    )

    let presentation = DailyMarkdownPresentation(
        story: story,
        selectedParagraphID: "missing-id"
    )

    XCTAssertEqual(presentation.initialScrollParagraphID, "daily-journal-0")
}
```

- [ ] **Step 3: Run the targeted tests and verify they fail for missing API**

Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/DailyMarkdownViewTests`

Expected: FAIL with compile errors or assertion failures because `DailyMarkdownPresentation` does not yet accept `selectedParagraphID` and does not expose `initialScrollParagraphID`.

- [ ] **Step 4: Commit the failing-test checkpoint**

```bash
git add KnowYouTests/DailyMarkdownViewTests.swift
git commit -m "test: cover reader scroll target presentation"
```

### Task 2: Add Failing Tests For Source Brand Resolution

**Files:**
- Modify: `KnowYouTests/DailyMarkdownViewTests.swift`
- Test: `KnowYouTests/DailyMarkdownViewTests.swift`

- [ ] **Step 1: Write the failing test for known brand mapping**

```swift
func testSourceBrandResolvesKnownBrandAsset() {
    let brand = SourceBrandResolver.resolve(appName: "ChatGPT")

    XCTAssertEqual(brand.assetName, "SourceLogoChatGPT")
    XCTAssertEqual(brand.fallbackSymbolName, "app.fill")
}
```

- [ ] **Step 2: Write the failing test for alias normalization**

```swift
func testSourceBrandNormalizesAliases() {
    let brand = SourceBrandResolver.resolve(appName: "OpenAI ChatGPT")

    XCTAssertEqual(brand.assetName, "SourceLogoChatGPT")
}
```

- [ ] **Step 3: Write the failing test for unknown-app fallback**

```swift
func testSourceBrandFallsBackForUnknownApp() {
    let brand = SourceBrandResolver.resolve(appName: "Completely Unknown App")

    XCTAssertNil(brand.assetName)
    XCTAssertEqual(brand.fallbackSymbolName, "app.fill")
}
```

- [ ] **Step 4: Run the targeted tests and verify they fail for missing resolver types**

Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/DailyMarkdownViewTests`

Expected: FAIL with compile errors because `SourceBrandResolver` and its return type do not exist yet.

- [ ] **Step 5: Commit the failing-test checkpoint**

```bash
git add KnowYouTests/DailyMarkdownViewTests.swift
git commit -m "test: cover source brand resolution"
```

### Task 3: Implement Reader Scroll Synchronization

**Files:**
- Modify: `KnowYou/UI/Reader/DailyMarkdownView.swift`
- Test: `KnowYouTests/DailyMarkdownViewTests.swift`

- [ ] **Step 1: Extend `DailyMarkdownPresentation` with scroll-target derivation**

```swift
struct DailyMarkdownPresentation: Equatable {
    let paragraphs: [DailyStoryParagraph]
    let storyHeading: String
    let initialScrollParagraphID: String?

    init(story: DailyStory?, selectedParagraphID: String? = nil) {
        paragraphs = story?.sections.flatMap(\.paragraphs) ?? []
        storyHeading = Self.resolvedStoryHeading(for: story, paragraphs: paragraphs)
        initialScrollParagraphID = Self.resolvedInitialScrollParagraphID(
            paragraphs: paragraphs,
            selectedParagraphID: selectedParagraphID
        )
    }

    private static func resolvedInitialScrollParagraphID(
        paragraphs: [DailyStoryParagraph],
        selectedParagraphID: String?
    ) -> String? {
        if let selectedParagraphID,
           paragraphs.contains(where: { $0.id == selectedParagraphID }) {
            return selectedParagraphID
        }

        return paragraphs.first?.id
    }
}
```

- [ ] **Step 2: Wrap the reader body in `ScrollViewReader` and tag paragraph rows**

```swift
var body: some View {
    let presentation = DailyMarkdownPresentation(
        story: story,
        selectedParagraphID: selectedParagraphID
    )

    Group {
        if presentation.showsEmptyState == false {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // existing header + story content
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .onAppear {
                    scrollToSelectedParagraph(using: proxy, paragraphID: presentation.initialScrollParagraphID)
                }
                .onChange(of: selectedParagraphID) { _, newValue in
                    scrollToSelectedParagraph(using: proxy, paragraphID: newValue)
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
        } else {
            ContentUnavailableView("No Story Yet", systemImage: "text.book.closed")
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}
```

- [ ] **Step 3: Add a local scroll helper with a stable anchor**

```swift
private func scrollToSelectedParagraph(
    using proxy: ScrollViewProxy,
    paragraphID: String?
) {
    guard let paragraphID else { return }

    withAnimation(.easeInOut(duration: 0.18)) {
        proxy.scrollTo(paragraphID, anchor: .center)
    }
}
```

- [ ] **Step 4: Attach paragraph IDs to the rendered rows**

```swift
ForEach(presentation.paragraphs) { paragraph in
    paragraphRow(paragraph)
        .id(paragraph.id)
}
```

- [ ] **Step 5: Run the targeted test slice and verify it passes**

Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/DailyMarkdownViewTests`

Expected: PASS with the new scroll-target tests green and the pre-existing markdown tests still green.

- [ ] **Step 6: Commit the scroll implementation**

```bash
git add KnowYou/UI/Reader/DailyMarkdownView.swift KnowYouTests/DailyMarkdownViewTests.swift
git commit -m "fix: keep selected diary paragraph in view"
```

### Task 4: Add Local Source Logo Assets

**Files:**
- Create: `KnowYou/Assets.xcassets/SourceLogoChatGPT.imageset/Contents.json`
- Create: `KnowYou/Assets.xcassets/SourceLogoClaude.imageset/Contents.json`
- Create: `KnowYou/Assets.xcassets/SourceLogoPerplexity.imageset/Contents.json`
- Create: `KnowYou/Assets.xcassets/SourceLogoNotion.imageset/Contents.json`
- Create: `KnowYou/Assets.xcassets/SourceLogoGitHub.imageset/Contents.json`
- Create: `KnowYou/Assets.xcassets/SourceLogoSlack.imageset/Contents.json`
- Create: `KnowYou/Assets.xcassets/SourceLogoFeishu.imageset/Contents.json`
- Create: `KnowYou/Assets.xcassets/SourceLogoWeChat.imageset/Contents.json`
- Create: `KnowYou/Assets.xcassets/SourceLogoX.imageset/Contents.json`
- Create: `KnowYou/Assets.xcassets/SourceLogoGoogle.imageset/Contents.json`

- [ ] **Step 1: Add the selected logo image files to the asset catalog**

```text
Place one square PNG per brand into its matching `.imageset` directory and reference it from `Contents.json`.
Use stable names:
- SourceLogoChatGPT
- SourceLogoClaude
- SourceLogoPerplexity
- SourceLogoNotion
- SourceLogoGitHub
- SourceLogoSlack
- SourceLogoFeishu
- SourceLogoWeChat
- SourceLogoX
- SourceLogoGoogle
```

- [ ] **Step 2: Define each asset catalog entry**

```json
{
  "images" : [
    {
      "filename" : "logo.png",
      "idiom" : "universal",
      "scale" : "1x"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

- [ ] **Step 3: Build once to confirm the asset catalog is valid**

Run: `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`

Expected: PASS with no asset-catalog validation errors.

- [ ] **Step 4: Commit the asset additions**

```bash
git add KnowYou/Assets.xcassets
git commit -m "chore: add source logo assets"
```

### Task 5: Implement Source Brand Resolver And Source Card Logo Rendering

**Files:**
- Modify: `KnowYou/UI/Reader/DailyMarkdownView.swift`
- Test: `KnowYouTests/DailyMarkdownViewTests.swift`

- [ ] **Step 1: Add a deterministic source-brand model and resolver**

```swift
private struct SourceBrand: Equatable {
    let assetName: String?
    let fallbackSymbolName: String
}

private enum SourceBrandResolver {
    static func resolve(appName: String) -> SourceBrand {
        let normalized = appName
            .lowercased()
            .replacingOccurrences(of: " ", with: "")

        switch normalized {
        case "chatgpt", "openaichatgpt":
            return SourceBrand(assetName: "SourceLogoChatGPT", fallbackSymbolName: "app.fill")
        case "claude", "anthropicclaude":
            return SourceBrand(assetName: "SourceLogoClaude", fallbackSymbolName: "app.fill")
        case "perplexity":
            return SourceBrand(assetName: "SourceLogoPerplexity", fallbackSymbolName: "app.fill")
        case "notion":
            return SourceBrand(assetName: "SourceLogoNotion", fallbackSymbolName: "doc.text.fill")
        case "github":
            return SourceBrand(assetName: "SourceLogoGitHub", fallbackSymbolName: "chevron.left.slash.chevron.right")
        case "slack":
            return SourceBrand(assetName: "SourceLogoSlack", fallbackSymbolName: "message.fill")
        case "feishu":
            return SourceBrand(assetName: "SourceLogoFeishu", fallbackSymbolName: "message.fill")
        case "wechat", "weixin":
            return SourceBrand(assetName: "SourceLogoWeChat", fallbackSymbolName: "message.fill")
        case "x", "twitter":
            return SourceBrand(assetName: "SourceLogoX", fallbackSymbolName: "bubble.left.and.bubble.right.fill")
        case "googledrive", "googledocs", "gmail", "googlecalendar":
            return SourceBrand(assetName: "SourceLogoGoogle", fallbackSymbolName: "app.fill")
        default:
            return SourceBrand(assetName: nil, fallbackSymbolName: "app.fill")
        }
    }
}
```

- [ ] **Step 2: Add a small logo view to `SourceEventCard`**

```swift
private struct SourceBrandLogoView: View {
    let appName: String

    var body: some View {
        let brand = SourceBrandResolver.resolve(appName: appName)

        Group {
            if let assetName = brand.assetName {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: brand.fallbackSymbolName)
                    .resizable()
                    .scaledToFit()
                    .padding(5)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 18, height: 18)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}
```

- [ ] **Step 3: Insert the logo ahead of the app name in source cards**

```swift
HStack(alignment: .firstTextBaseline, spacing: 10) {
    Text(timeText)
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)

    SourceBrandLogoView(appName: event.sourceApp)

    Text(event.sourceApp)
        .font(.callout.weight(.semibold))

    Spacer(minLength: 8)

    Text(event.sourceType.rawValue.capitalized)
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
}
```

- [ ] **Step 4: Run the targeted tests and verify they pass**

Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/DailyMarkdownViewTests`

Expected: PASS with brand-resolution tests green and existing tests unchanged.

- [ ] **Step 5: Commit the resolver and UI changes**

```bash
git add KnowYou/UI/Reader/DailyMarkdownView.swift KnowYouTests/DailyMarkdownViewTests.swift
git commit -m "feat: add branded source logos"
```

### Task 6: Update Documentation And Run Full Verification

**Files:**
- Modify: `docs/architecture.md`
- Modify: `docs/requirements-spec.md`
- Test: full project verification commands

- [ ] **Step 1: Update architecture documentation**

```markdown
- The reader keeps keyboard paragraph navigation in `AppState`, while `DailyMarkdownView` uses `ScrollViewReader` to keep the selected paragraph visible.
- Source cards in the right-side detail panel render local brand logos for recognized apps and a fallback symbol for unknown apps.
```

- [ ] **Step 2: Update requirements documentation**

```markdown
- When navigating diary paragraphs with the keyboard, the selected paragraph must remain visible in the reader viewport.
- Source detail cards should display a channel logo before the source app name when the app is recognized, with a generic fallback icon otherwise.
```

- [ ] **Step 3: Run full test verification**

Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS'`

Expected: PASS with all tests green.

- [ ] **Step 4: Run full build verification**

Run: `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`

Expected: PASS with a successful macOS build.

- [ ] **Step 5: Commit docs and verification-backed completion**

```bash
git add docs/architecture.md docs/requirements-spec.md
git commit -m "docs: document reader scroll follow and source logos"
```
