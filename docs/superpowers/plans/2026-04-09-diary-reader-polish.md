# Diary Reader Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign the diary reading experience to feel like a notebook (not a list of cards), fix broken keyboard navigation, remove the status banner, move the refresh button into the diary header, and lock the detail column width.

**Architecture:** Three SwiftUI view files are modified. `DateSidebarView` and `DailyMarkdownView` lose their focus-related props. `MainWindowView` becomes the single keyboard handler using `NSEvent.addLocalMonitorForEvents` (bypasses SwiftUI focus system entirely), manages refresh loading state, and wires up the simplified child interfaces.

**Tech Stack:** SwiftUI (macOS 14+), AppKit (`NSEvent` for key monitoring), XCTest

---

## File Map

| File | What changes |
|------|-------------|
| `KnowYou/UI/Sidebar/DateSidebarView.swift` | Remove `isFocused`, `onMoveSelection`, `onEnterStoryFocus`; remove overlay border; remove `onMoveCommand` |
| `KnowYou/UI/Reader/DailyMarkdownView.swift` | New notebook layout; remove `isFocused`, `onMoveSelection`, `onExitFocus`; add `dayKey`, `isRefreshing`, `onRefresh`; add date header + refresh button |
| `KnowYou/UI/MainWindowView.swift` | Remove `StatusBannerView`; remove toolbar; remove `@FocusState` + `focusable` + `focused`; fix detail column width; update call sites; add `NSEvent` key monitor; add `@State var isRefreshing` |

---

## Task 1: Simplify DateSidebarView

**Files:**
- Modify: `KnowYou/UI/Sidebar/DateSidebarView.swift`

- [ ] **Step 1: Replace the entire file**

```swift
import SwiftUI

struct DateSidebarView: View {
    let dates: [String]
    let selectedDate: String?
    let onSelect: (String) -> Void

    var body: some View {
        List(selection: selectedDateBinding) {
            ForEach(dates, id: \.self) { date in
                Label(formattedDate(date), systemImage: "doc.plaintext")
                    .padding(.vertical, 4)
                    .fontWeight(selectedDate == date ? .semibold : .regular)
                    .tag(date)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Journals")
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var selectedDateBinding: Binding<String?> {
        Binding(
            get: { selectedDate },
            set: { newValue in
                if let newValue {
                    onSelect(newValue)
                }
            }
        )
    }

    private func formattedDate(_ dateString: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: dateString) else { return dateString }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM-dd EEE"
        return formatter.string(from: date)
    }
}
```

- [ ] **Step 2: Build to confirm no errors**

```bash
cd /Users/wutianfu/Code/know-you
xcodebuild build -scheme KnowYou -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
```

Expected: errors about `isFocused`, `onMoveSelection`, `onEnterStoryFocus` at the call site in `MainWindowView.swift` — that is correct, will be fixed in Task 3.

- [ ] **Step 3: Commit**

```bash
git add KnowYou/UI/Sidebar/DateSidebarView.swift
git commit -m "refactor: simplify DateSidebarView — remove focus props and key handlers"
```

---

## Task 2: Redesign DailyMarkdownView

**Files:**
- Modify: `KnowYou/UI/Reader/DailyMarkdownView.swift`

The new interface:
- Removes: `isFocused`, `onMoveSelection`, `onExitFocus`
- Adds: `dayKey: String?`, `isRefreshing: Bool`, `onRefresh: () -> Void`
- New layout: date header row + notebook-style paragraphs (no cards, no "linked sources" text)

- [ ] **Step 1: Replace DailyMarkdownView struct**

Replace the `DailyMarkdownView` struct (everything before `struct StorySourceDetailView`) with:

```swift
struct DailyMarkdownView: View {
    let story: DailyStory?
    let selectedParagraphID: String?
    let dayKey: String?
    let isRefreshing: Bool
    let onSelectParagraph: (String) -> Void
    let onFocusStory: () -> Void
    let onRefresh: () -> Void

    @State private var hoveredParagraphID: String?

    var body: some View {
        Group {
            if let story, story.sections.flatMap(\.paragraphs).isEmpty == false {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Date header row
                        HStack(alignment: .firstTextBaseline) {
                            Text(formattedDayKey)
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                onRefresh()
                            } label: {
                                if isRefreshing {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(isRefreshing)
                            .help("Regenerate this day's journal")
                        }
                        .padding(.horizontal, 28)
                        .padding(.top, 24)
                        .padding(.bottom, 16)

                        Divider()
                            .padding(.horizontal, 28)

                        // Paragraphs
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(story.sections) { section in
                                ForEach(section.paragraphs) { paragraph in
                                    paragraphRow(paragraph)
                                }
                            }
                        }
                        .padding(.horizontal, 28)
                        .padding(.top, 16)
                        .padding(.bottom, 24)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .simultaneousGesture(TapGesture().onEnded {
                    onFocusStory()
                })
            } else {
                ContentUnavailableView("No Story Yet", systemImage: "text.book.closed")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func paragraphRow(_ paragraph: DailyStoryParagraph) -> some View {
        let isSelected = paragraph.id == selectedParagraphID
        let isHovered = hoveredParagraphID == paragraph.id

        Button {
            onFocusStory()
            onSelectParagraph(paragraph.id)
        } label: {
            HStack(alignment: .top, spacing: 0) {
                // Left accent bar (only when selected)
                Rectangle()
                    .fill(isSelected ? Color.accentColor : Color.clear)
                    .frame(width: 2)
                    .padding(.vertical, 4)

                Text(.init(paragraph.text))
                    .font(.body)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.07)
                    : (isHovered ? Color.primary.opacity(0.04) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredParagraphID = hovering ? paragraph.id : nil
        }
    }

    private var formattedDayKey: String {
        guard let dayKey else { return "" }
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        parser.locale = Locale(identifier: "en_US_POSIX")
        guard let date = parser.date(from: dayKey) else { return dayKey }

        let monthDay = DateFormatter()
        monthDay.dateFormat = "M月d日"
        let weekday = DateFormatter()
        weekday.dateFormat = "EEEE"
        weekday.locale = Locale(identifier: "en_US")
        return "\(monthDay.string(from: date)) · \(weekday.string(from: date))"
    }
}
```

- [ ] **Step 2: Build (expect call-site errors in MainWindowView, not in this file)**

```bash
xcodebuild build -scheme KnowYou -destination 'platform=macOS' 2>&1 | grep "error:" | grep -v "MainWindowView"
```

Expected: no errors originating from `DailyMarkdownView.swift` itself.

- [ ] **Step 3: Commit**

```bash
git add KnowYou/UI/Reader/DailyMarkdownView.swift
git commit -m "feat: notebook-style diary layout with date header and refresh button"
```

---

## Task 3: Update MainWindowView

**Files:**
- Modify: `KnowYou/UI/MainWindowView.swift`

Changes in this task:
1. Remove `StatusBannerView`
2. Remove toolbar button
3. Remove `@FocusState`, `.focusable()`, `.focused()`
4. Fix detail column width (lock divider)
5. Update `DateSidebarView` call site (remove 3 props)
6. Update `DailyMarkdownView` call site (new props)
7. Add `@State var isRefreshing`
8. Add `NSEvent` key monitor

- [ ] **Step 1: Replace the entire MainWindowView struct**

```swift
import SwiftUI
import AppKit

struct MainWindowView: View {
    @Environment(AppState.self) private var appState
    @State private var isRefreshing = false
    @State private var keyMonitor: Any?

    var body: some View {
        NavigationSplitView {
            DateSidebarView(
                dates: appState.availableDates,
                selectedDate: appState.selectedDate,
                onSelect: appState.selectDate
            )
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } content: {
            DailyMarkdownView(
                story: appState.selectedStory,
                selectedParagraphID: appState.selectedStoryParagraphID,
                dayKey: appState.selectedDate,
                isRefreshing: isRefreshing,
                onSelectParagraph: { paragraphID in
                    appState.focusStoryParagraphs()
                    appState.selectStoryParagraph(paragraphID)
                },
                onFocusStory: {
                    appState.focusStoryParagraphs()
                },
                onRefresh: {
                    guard !isRefreshing else { return }
                    isRefreshing = true
                    Task { @MainActor in
                        await appState.refreshSelectedDay()
                        isRefreshing = false
                    }
                }
            )
        } detail: {
            StorySourceDetailView(
                selectedParagraph: appState.selectedStoryParagraph,
                selectedEvents: appState.selectedStorySourceEvents,
                allEvents: appState.selectedDayEvents
            )
        }
        .navigationSplitViewColumnWidth(min: 320, ideal: 360, max: 420)
        .frame(minWidth: 1240, minHeight: 720)
        .onAppear {
            startKeyMonitor()
        }
        .onDisappear {
            stopKeyMonitor()
        }
    }

    private func startKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak appState] event in
            guard let appState else { return event }
            let handled = handleKeyEvent(event, appState: appState)
            return handled ? nil : event
        }
    }

    private func stopKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    @MainActor
    private func handleKeyEvent(_ event: NSEvent, appState: AppState) -> Bool {
        switch appState.readerFocus {
        case .dateList:
            switch event.keyCode {
            case 126: appState.handleReaderMove(.up);    return true  // ↑
            case 125: appState.handleReaderMove(.down);  return true  // ↓
            case 124: appState.handleReaderMove(.right); return true  // →
            case 36:  appState.handleReaderMove(.right); return true  // Return
            default:  return false
            }
        case .storyParagraphs:
            switch event.keyCode {
            case 126: appState.handleReaderMove(.up);   return true  // ↑
            case 125: appState.handleReaderMove(.down); return true  // ↓
            case 123: appState.handleReaderMove(.left); return true  // ←
            case 53:  appState.handleReaderExit();      return true  // Escape
            default:  return false
            }
        }
    }
}
```

**Note on `.navigationSplitViewColumnWidth` placement:** The `.navigationSplitViewColumnWidth(min: 320, ideal: 360, max: 420)` must be placed on the `detail` trailing closure, not on the `NavigationSplitView` itself. The fix above attaches it to the `NavigationSplitView` which applies to the whole view — if the build rejects this, move it inside the detail closure:

```swift
} detail: {
    StorySourceDetailView(...)
        .navigationSplitViewColumnWidth(min: 320, ideal: 360, max: 420)
}
// and remove it from the NavigationSplitView modifier chain
```

- [ ] **Step 2: Remove the duplicate frame constraint from StorySourceDetailView**

In `DailyMarkdownView.swift`, find `StorySourceDetailView.body` and remove:

```swift
.frame(minWidth: 320, idealWidth: 360, maxWidth: 420, maxHeight: .infinity)
```

The column width is now controlled at the `NavigationSplitView` level.

- [ ] **Step 3: Build — must be clean**

```bash
xcodebuild build -scheme KnowYou -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
```

Expected: `** BUILD SUCCEEDED **` with no errors.

- [ ] **Step 4: Commit**

```bash
git add KnowYou/UI/MainWindowView.swift KnowYou/UI/Reader/DailyMarkdownView.swift
git commit -m "feat: update MainWindowView — remove banner/toolbar, fix divider, add key monitor, wire refresh"
```

---

## Task 4: Run Full Test Suite

- [ ] **Step 1: Run all tests**

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)|passed|failed" | tail -20
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 2: If any tests fail, check which ones**

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' 2>&1 | grep "FAIL\|error:" | head -20
```

The only tests likely to fail are ones that instantiate `DateSidebarView` or `DailyMarkdownView` with the old interface. Fix the call sites in test files to match the new parameter lists.

- [ ] **Step 3: Commit if test fixes were needed**

```bash
git add KnowYouTests/
git commit -m "fix: update tests for new DateSidebarView and DailyMarkdownView interfaces"
```

---

## Task 5: Manual Smoke Test

Launch the app and verify:

- [ ] Status banner is gone — diary content fills to the top of the content column
- [ ] Diary shows date header (`4月8日 · Wednesday`) above the divider line
- [ ] Refresh button (↻) appears top-right of diary; clicking it shows spinner then reloads content
- [ ] Paragraphs render as flowing text with no card borders and no "linked sources" text
- [ ] Hovering a paragraph shows faint background
- [ ] Clicking a paragraph highlights it with left blue bar + faint blue background, detail panel updates
- [ ] ↑/↓ in date list moves selection
- [ ] → or Return enters the diary (focuses first paragraph)
- [ ] ↑/↓ in diary moves between paragraphs
- [ ] ← or Escape returns focus to date list
- [ ] Detail column cannot be dragged / blue divider line is gone

```bash
APP=/Users/wutianfu/Library/Developer/Xcode/DerivedData/KnowYou-cpkyzkjnjvsdheazyqdtmemzuvbv/Build/Products/Debug/KnowYou.app
pkill -x KnowYou 2>/dev/null; sleep 1; open "$APP"
```

- [ ] **Commit any fixes found during smoke test**

```bash
git add -p
git commit -m "fix: smoke test corrections"
```

---

## Key Code References

- `AppState.readerFocus: ReaderFocusZone` — current focus zone (`.dateList` or `.storyParagraphs`)
- `AppState.handleReaderMove(_ direction: ReaderMoveDirection)` — moves selection
- `AppState.handleReaderExit()` — returns to date list
- `AppState.refreshSelectedDay()` — async, imports notifications + calls LLM + reloads
- `AppState.focusStoryParagraphs()` — sets readerFocus to .storyParagraphs

## NSEvent Key Codes (macOS)

| Key | Code |
|-----|------|
| ↑ Up | 126 |
| ↓ Down | 125 |
| ← Left | 123 |
| → Right | 124 |
| Return | 36 |
| Escape | 53 |
