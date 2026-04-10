# Spec: Reader Scroll And Source Logos

**Date:** 2026-04-10  
**Branch:** dev  
**Status:** Draft

---

## Problem

There are two related reader issues in the current app:

1. **Keyboard paragraph navigation loses visibility once content exceeds the viewport.** The app intercepts up/down arrow keys at the window level and updates the selected story paragraph, but the center reading column does not scroll to keep the newly selected paragraph visible. Once the user keeps pressing down past the visible region, selection continues to move while the viewport stays fixed.
2. **Reference-heavy source lists are visually flat.** The right-side source detail panel currently shows only time, app name text, and source type. When many source items come from different apps, the list is harder to scan than it needs to be.

The user wants:

- keyboard navigation in the diary reader to keep the selected paragraph on screen
- app logos added only in the source panel, not in the diary body

---

## Goals

1. Keep the selected story paragraph visible while navigating with arrow keys.
2. Improve source-panel scanability by showing app logos before source app names.
3. Keep the current diary content model and source-link behavior intact.
4. Make unknown or unmapped app names degrade gracefully to a generic icon.

## Non-Goals

- changing diary markdown generation
- inserting logos into the diary body
- changing the `EventRecord` schema
- implementing dynamic runtime lookup of installed-app icons

---

## Approaches Considered

### Approach A: Let `ScrollView` manage visibility implicitly

Rely on SwiftUI focus or default button behavior and hope the selected row stays visible.

Trade-offs:

- lowest implementation effort
- does not address the actual current bug because selection already changes without scrolling
- fragile inside the current `NavigationSplitView` + window-level keyboard handling setup

### Approach B: Explicit scroll synchronization + local brand logo assets

Keep the current selection model, but add explicit `ScrollViewReader` synchronization in the reader and a local app-brand resolver for source cards.

Trade-offs:

- directly addresses the current bug
- keeps responsibilities local to the reader and source-card UI
- easy to test by extracting pure presentation logic
- requires maintaining a small logo asset catalog and app-name mapping table

### Approach C: Rebuild reader selection around AppKit focus and live app-icon lookup

Move deeper into AppKit for scroll/focus behavior and resolve source icons from installed applications or bundle metadata at runtime.

Trade-offs:

- potentially more dynamic long term
- unnecessary complexity for the current product need
- less reliable because historical `sourceApp` values do not guarantee a resolvable installed app

### Recommendation

Choose **Approach B**.

It fixes the visible bug without reworking the reader architecture, and it delivers the requested source visualization with controlled scope. The app can support a curated set of common channels now and still fall back safely for everything else.

---

## Design

### 1. Reader Scroll Synchronization

**Primary file:** `KnowYou/UI/Reader/DailyMarkdownView.swift`

The reading column should keep using the existing `selectedParagraphID` state as the source of truth. The change is to make the `ScrollView` follow that state.

Implementation shape:

- wrap the existing story `ScrollView` in `ScrollViewReader`
- assign each paragraph row a stable scroll target using the paragraph ID
- observe `selectedParagraphID` changes and scroll to the matching row
- also trigger an initial scroll when a day loads and the selected paragraph is set

Expected behavior:

- arrowing down moves selection and scrolls the viewport when the next paragraph would otherwise fall below the visible area
- arrowing up does the same in reverse
- clicking a paragraph still selects it and can reuse the same scroll-sync path if needed

Scroll positioning rule:

- use a stable anchor that keeps reading comfortable, biased toward `.center`
- avoid trying to preserve pixel-perfect prior offset; the goal is visibility and reading continuity, not inertial scrolling fidelity

This change should stay inside the reader view layer. `AppState.handleReaderMove()` remains the navigation state machine and does not need to know about scroll geometry.

### 2. Source Logo Rendering

**Primary file:** `KnowYou/UI/Reader/DailyMarkdownView.swift`

The right-side `StorySourceDetailView` should keep the same structure, but each `SourceEventCard` header gains a logo view before the source app name.

Visual behavior:

- show a compact, fixed-size logo at the start of the card header
- keep the existing app name text visible next to the logo
- preserve the current time label and source-type label layout
- apply the same card component to both linked sources and "View All Sources"

The center diary column remains unchanged. No logos are added to `DailyMarkdownView` paragraph content.

### 3. Brand Resolution Strategy

**New supporting type:** a small source-brand resolver in the reader UI layer or a nearby focused file if extraction improves testability

Resolver responsibilities:

- normalize `sourceApp` values
- map known aliases to a stable brand key
- provide a rendering description:
  - branded asset name when known
  - fallback SF Symbol when unknown

Normalization expectations:

- case-insensitive matching
- tolerant of whitespace and common naming variations
- supports aliases such as product + vendor naming differences where useful

Initial branded coverage should focus on common reference-style channels already likely to appear in this app, such as:

- ChatGPT
- Claude
- Perplexity
- Notion
- GitHub
- Slack
- Feishu
- WeChat
- X
- Google-family apps that are common sources in this app context

Unknown sources:

- do not fail
- do not leave an empty space
- fall back to a generic symbol derived from the source category or a neutral app symbol

### 4. Asset Strategy

**Primary location:** app asset catalog

Store a curated set of local brand images with stable names. Keep the asset list intentionally small and extend it only when a new source appears often enough to justify maintenance.

Benefits of this approach:

- no runtime dependency on installed applications
- predictable appearance across machines
- easy future extension by adding one asset and one mapping entry

### 5. Error Handling

For scroll behavior:

- if the selected paragraph ID is missing from the current rendered paragraph list, do nothing instead of forcing an invalid scroll
- if a day reload changes paragraph IDs, rely on the refreshed selection state already owned by `AppState`

For logo behavior:

- if a brand asset is missing or the source app is unmapped, render the fallback symbol
- no source card should render without a leading visual marker
- the logo resolver should be deterministic and side-effect free

---

## Components

### `KnowYou/UI/Reader/DailyMarkdownView.swift`

Primary change area for both requested items.

Responsibilities after change:

- keep paragraph selection behavior unchanged
- synchronize the visible scroll position with `selectedParagraphID`
- add source-logo rendering to `SourceEventCard`
- continue rendering the same source text content and disclosure sections

### `KnowYouTests/DailyMarkdownViewTests.swift`

Add focused tests for extracted presentation/resolution logic related to:

- selected paragraph scroll target behavior
- known source-app brand resolution
- alias normalization
- fallback icon behavior for unknown apps

If the current file becomes awkward for these tests, a small new test file for source-brand resolution is acceptable.

---

## Testing

Follow TDD during implementation:

1. Add or extend focused tests for the new reader presentation logic before production changes.
2. Verify the new tests fail for the intended reason.
3. Implement the minimal reader scroll synchronization and logo-resolution code.
4. Re-run the targeted test slice until green.
5. Run full verification before claiming success:
   - `xcodebuild test -scheme KnowYou -destination 'platform=macOS'`
   - `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`

Manual verification should also confirm:

- holding the down arrow in a long diary keeps the selected paragraph visible
- holding the up arrow does the same in reverse
- known source apps display branded logos
- unknown source apps display the fallback icon cleanly

---

## Documentation Impact

If implementation changes behavior as designed, update these docs before closing the work:

- `docs/architecture.md`
- `docs/requirements-spec.md`

The update should record:

- explicit scroll-follow behavior for keyboard paragraph navigation
- source-panel logo rendering for recognized apps with fallback behavior for unknown channels

---

## Open Decisions Resolved

- The fix should live in the reader view layer, not in `AppState`.
- Logos should appear only in the source panel.
- The implementation should use local brand assets, not runtime app-icon lookup.
- Unknown channels should fall back gracefully instead of requiring complete logo coverage.
