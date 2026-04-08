# Spec: Diary Reader Polish

**Date:** 2026-04-09  
**Branch:** dev  
**Status:** Approved

---

## Problem

Four user-facing issues identified during hands-on testing:

1. **Diary reading experience is fragmented** — paragraphs render as isolated cards with visible borders, background fills, and "N linked sources" text. Reads like a list of UI elements, not a journal entry.
2. **Keyboard navigation is fully broken** — arrow keys, Enter, and Escape have no effect. The `onMoveCommand` approach breaks inside `NavigationSplitView` because `List` consumes arrow key events and focus propagation is unreliable.
3. **Blue vertical divider line** between the diary column and the source detail column is draggable, produces a blue highlight on drag, and behaves incorrectly. Needs to be locked.
4. **Refresh button is buried in the window toolbar** — contextually disconnected from the diary being viewed. Users cannot tell it operates on the selected day.
5. **Status banner wastes prominent screen space** — the blue `StatusBannerView` at the top of the content area displays diagnostic text (clipboard status, notification errors, summarizer info) that has no value during normal reading.

---

## Design

### 1. Notebook-Style Diary Layout

**File:** `KnowYou/UI/Reader/DailyMarkdownView.swift`

#### Date header
Add a date header above the paragraphs:
- Format: `4月8日 · Wednesday` (localized, derived from `dayKey`)
- Style: large, semibold, secondary color — acts as the reading anchor, not a navigation element

#### Paragraph rendering
Remove all card-style visuals from each paragraph:
- **Remove:** background fill, rounded rect border stroke, `"N linked sources"` caption text
- **Keep:** paragraph `text`, click handler, `onSelectParagraph` callback

Paragraph spacing: reduce from `28pt` gap to `8pt` gap. Paragraphs feel like lines of a continuous entry, not separate items.

#### Selection state
Selected paragraph:
- Left-edge accent bar: `2pt` wide, `Color.accentColor`, vertically inset `4pt` from top/bottom
- Background: `Color.accentColor.opacity(0.07)`
- No border stroke

Hover state (`.onHover`):
- Background: `Color.primary.opacity(0.04)`
- No border stroke

#### Focus overlay removed
Remove the `isFocused`-driven `RoundedRectangle` stroke overlay from `DailyMarkdownView`. The blue section border is replaced by the paragraph-level selection indicator.

#### Source panel unchanged
The right-side `StorySourceDetailView` and its behavior are not modified. Source linking works identically — clicking a paragraph populates the detail panel.

---

### 2. Keyboard Navigation

**File:** `KnowYou/UI/MainWindowView.swift` (primary), with cleanup in `DateSidebarView.swift` and `DailyMarkdownView.swift`

#### Root cause
`onMoveCommand` in child views requires SwiftUI focus to be explicitly on that view. Inside `NavigationSplitView`, `List` claims key focus and does not forward arrow key events to parent `onMoveCommand` handlers. Result: all keyboard input is silently consumed.

#### Fix: window-level `onKeyPress`
Move all keyboard handling to `MainWindowView` using `onKeyPress` (macOS 14+). The main window observes `appState.readerFocus` to dispatch each key to the correct handler.

Key map:

| `readerFocus` | Key | Action |
|---------------|-----|--------|
| `.dateList` | `.upArrow` | `appState.handleReaderMove(.up)` |
| `.dateList` | `.downArrow` | `appState.handleReaderMove(.down)` |
| `.dateList` | `.rightArrow` | `appState.handleReaderMove(.right)` |
| `.dateList` | `.return` | `appState.handleReaderMove(.right)` |
| `.storyParagraphs` | `.upArrow` | `appState.handleReaderMove(.up)` |
| `.storyParagraphs` | `.downArrow` | `appState.handleReaderMove(.down)` |
| `.storyParagraphs` | `.leftArrow` | `appState.handleReaderMove(.left)` |
| `.storyParagraphs` | `.escape` | `appState.handleReaderExit()` |

#### Cleanup
- Remove `.focusable()` + `.focused()` + `.onMoveCommand` + `.onExitCommand` from `DateSidebarView` and `DailyMarkdownView` — these are superseded by window-level handling.
- Remove the `isFocused`-driven border overlay from `DateSidebarView`.
- Keep `appState.readerFocus` state and `AppState.handleReaderMove()` logic unchanged — only the input capture layer changes.

#### `onKeyPress` attachment point
Attach `.onKeyPress` to the outermost `NavigationSplitView` in `MainWindowView`, with `.all` phase and a `@FocusState` anchor so the modifier receives key events when the window is key.

---

### 3. Fix Column Divider

**File:** `KnowYou/UI/MainWindowView.swift`

Add `.navigationSplitViewColumnWidth(min: 320, ideal: 360, max: 420)` to the `detail` column closure in `NavigationSplitView`. When `min == max`, the column is non-resizable and the drag handle disappears.

Remove the duplicate `.frame(minWidth: 320, idealWidth: 360, maxWidth: 420, maxHeight: .infinity)` from `StorySourceDetailView` — column width is now controlled at the split view level.

---

### 4. Refresh Button — Moved Into Diary Header

**Files:** `KnowYou/UI/Reader/DailyMarkdownView.swift`, `KnowYou/UI/MainWindowView.swift`

#### Position
The refresh button moves from the window toolbar into the diary content area header, right-aligned on the same row as the date title:

```
[ 4月8日 · Wednesday ]                    [ ↻ ]
────────────────────────────────────────────────
凌晨两点多，开始处理 KnowYou 的...
```

The toolbar button in `MainWindowView` is removed entirely.

#### Appearance
- Icon: `arrow.clockwise` (SF Symbol), no label
- Style: `.plain` button, secondary foreground color
- Loading state: show `ProgressView()` (spinning indicator) in place of the icon while regeneration is in progress — driven by a `@State var isRefreshing: Bool`

#### Backend — what the refresh does
`appState.refreshSelectedDay()` already exists and handles both today and historical dates. The fix applied earlier ensures historical-day refresh imports notifications with `since = startOfDay(targetDate)` before generating the story.

Full pipeline on button tap:
1. **Import notifications** for the selected day (since midnight of that day)
2. **Import clipboard events** (already in the database from the continuous watcher)
3. **Call LLM** (`CLISummarizer`) with the full `storyPrompt` built from all events
4. **Parse response** and write `story.json` + regenerate the markdown file
5. **Reload** the UI

This pipeline is already implemented. The only code change needed is wiring the button into `DailyMarkdownView`'s header and removing it from the toolbar.

---

## Files Changed

| File | Change |
|------|--------|
| `KnowYou/UI/Reader/DailyMarkdownView.swift` | Notebook layout, remove card styles, remove isFocused border, add header with date + refresh button |
| `KnowYou/UI/MainWindowView.swift` | Add `onKeyPress`, fix detail column width, remove focusable/focused, remove toolbar button, remove StatusBannerView |
| `KnowYou/UI/Sidebar/DateSidebarView.swift` | Remove onMoveCommand, remove isFocused border overlay |

---

### 5. Remove Status Banner

**File:** `KnowYou/UI/MainWindowView.swift`

Remove `StatusBannerView` and the `VStack` wrapping it from the `content` column. The `DailyMarkdownView` fills the full column height directly.

The `AppState.statusMessage` and `AppState.statusDetails` properties are left in place — they may still be useful for the menu bar extra or future diagnostics — but nothing in the main window reads or displays them.

---

## Out of Scope

- Content quality / LLM prompt changes (separate concern)
- Source detail panel UI changes
- Sidebar date formatting changes
