# Month Grouped Date Sidebar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Group the journal date sidebar by English month headers, with the current month open and older months collapsed by default.

**Architecture:** Keep `AppState` and `MainWindowView` unchanged. Add a testable `DateSidebarPresentation` model in `DateSidebarView.swift`, then render its sections with `DisclosureGroup` rows in the existing sidebar `List`.

**Tech Stack:** Swift, SwiftUI, XCTest, macOS app target.

---

## File Structure

- Modify: `KnowYou/UI/Sidebar/DateSidebarView.swift`
  - Add `DateSidebarPresentation`, `DateSidebarSection`, and `DateSidebarItem`.
  - Render month sections with `DisclosureGroup`.
  - Keep special non-date rows visible.
- Modify: `KnowYouTests/DailyMarkdownViewTests.swift`
  - Add focused tests for the new presentation model because this file is already included in the test target.

## Task 1: Add Failing Presentation Tests

**Files:**
- Modify: `KnowYouTests/DailyMarkdownViewTests.swift`

- [x] **Step 1: Add tests near the top of `DailyMarkdownViewTests`**

```swift
    func testDateSidebarPresentationGroupsDatesByEnglishMonth() {
        let presentation = DateSidebarPresentation(
            dates: ["2026-04-24", "2026-04-23", "2026-03-31", "demo-day"],
            selectedDate: nil,
            today: makeDate(year: 2026, month: 4, day: 24),
            calendar: gregorianCalendar
        )

        XCTAssertEqual(presentation.sections.map(\.title), ["April 2026", "March 2026", nil])
        XCTAssertEqual(presentation.sections[0].items.map(\.id), ["2026-04-24", "2026-04-23"])
        XCTAssertEqual(presentation.sections[1].items.map(\.id), ["2026-03-31"])
        XCTAssertEqual(presentation.sections[2].items.map(\.id), ["demo-day"])
    }

    func testDateSidebarPresentationOpensCurrentMonthAndCollapsesOlderMonths() {
        let presentation = DateSidebarPresentation(
            dates: ["2026-04-24", "2026-03-31"],
            selectedDate: nil,
            today: makeDate(year: 2026, month: 4, day: 24),
            calendar: gregorianCalendar
        )

        XCTAssertTrue(presentation.sections[0].isExpandedByDefault)
        XCTAssertFalse(presentation.sections[1].isExpandedByDefault)
    }

    func testDateSidebarPresentationOpensSelectedOlderMonth() {
        let presentation = DateSidebarPresentation(
            dates: ["2026-04-24", "2026-03-31"],
            selectedDate: "2026-03-31",
            today: makeDate(year: 2026, month: 4, day: 24),
            calendar: gregorianCalendar
        )

        XCTAssertTrue(presentation.sections[0].isExpandedByDefault)
        XCTAssertTrue(presentation.sections[1].isExpandedByDefault)
    }

    private var gregorianCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        DateComponents(calendar: gregorianCalendar, timeZone: TimeZone(secondsFromGMT: 0), year: year, month: month, day: day).date!
    }
```

- [x] **Step 2: Run the failing test slice**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/DailyMarkdownViewTests/testDateSidebarPresentationGroupsDatesByEnglishMonth -only-testing:KnowYouTests/DailyMarkdownViewTests/testDateSidebarPresentationOpensCurrentMonthAndCollapsesOlderMonths -only-testing:KnowYouTests/DailyMarkdownViewTests/testDateSidebarPresentationOpensSelectedOlderMonth
```

Expected: FAIL because `DateSidebarPresentation` does not exist.

## Task 2: Implement Presentation Model And Sidebar Rendering

**Files:**
- Modify: `KnowYou/UI/Sidebar/DateSidebarView.swift`

- [x] **Step 1: Add presentation model types below `DateSidebarView`**

```swift
struct DateSidebarPresentation {
    let sections: [DateSidebarSection]

    init(dates: [String], selectedDate: String?, today: Date = Date(), calendar: Calendar = .current) {
        let parser = Self.dateParser
        let currentMonth = Self.monthStart(for: today, calendar: calendar)
        let selectedMonth = selectedDate.flatMap(parser.date(from:)).map { Self.monthStart(for: $0, calendar: calendar) }
        var monthBuckets: [Date: [DateSidebarItem]] = [:]
        var specialItems: [DateSidebarItem] = []

        for dayKey in dates {
            guard let date = parser.date(from: dayKey) else {
                specialItems.append(DateSidebarItem(id: dayKey, title: Self.formattedDay(dayKey)))
                continue
            }

            let month = Self.monthStart(for: date, calendar: calendar)
            monthBuckets[month, default: []].append(
                DateSidebarItem(id: dayKey, title: Self.formattedDay(dayKey))
            )
        }

        let monthSections = monthBuckets.keys.sorted(by: >).map { month in
            DateSidebarSection(
                id: Self.monthID(for: month),
                title: Self.monthDisplay.string(from: month),
                isExpandedByDefault: month == currentMonth || month == selectedMonth,
                items: monthBuckets[month, default: []]
            )
        }

        if specialItems.isEmpty {
            sections = monthSections
        } else {
            sections = monthSections + [
                DateSidebarSection(
                    id: "special",
                    title: nil,
                    isExpandedByDefault: true,
                    items: specialItems
                )
            ]
        }
    }

    private static let dateParser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let monthDisplay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    private static let dayDisplay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM-dd EEE"
        return formatter
    }()

    private static func monthStart(for date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }

    private static func monthID(for date: Date) -> String {
        dateParser.string(from: date)
    }

    private static func formattedDay(_ dateString: String) -> String {
        if dateString == OnboardingDemoStory.demoDayKey {
            return "Demo Day"
        }
        guard let date = Self.dateParser.date(from: dateString) else { return dateString }
        return Self.dayDisplay.string(from: date)
    }
}

struct DateSidebarSection: Identifiable, Equatable {
    let id: String
    let title: String?
    let isExpandedByDefault: Bool
    let items: [DateSidebarItem]
}

struct DateSidebarItem: Identifiable, Equatable {
    let id: String
    let title: String
}
```

- [x] **Step 2: Update `DateSidebarView` to render sections**

Replace the flat `ForEach(dates, id: \.self)` list body with a presentation-driven list:

```swift
                ForEach(presentation.sections) { section in
                    if let title = section.title {
                        DisclosureGroup(isExpanded: expansionBinding(for: section)) {
                            ForEach(section.items) { item in
                                dateRow(item)
                            }
                        } label: {
                            Text(title)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(section.items) { item in
                            dateRow(item)
                        }
                    }
                }
```

Add `@State private var expandedSectionIDs: Set<String> = []`, `private var presentation: DateSidebarPresentation`, `private func dateRow(_ item: DateSidebarItem) -> some View`, and `private func expansionBinding(for section: DateSidebarSection) -> Binding<Bool>`. Seed expansion in `.onAppear` and `.onChange(of: dates)` / `.onChange(of: selectedDate)` using section defaults.

- [x] **Step 3: Run the targeted tests**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/DailyMarkdownViewTests/testDateSidebarPresentationGroupsDatesByEnglishMonth -only-testing:KnowYouTests/DailyMarkdownViewTests/testDateSidebarPresentationOpensCurrentMonthAndCollapsesOlderMonths -only-testing:KnowYouTests/DailyMarkdownViewTests/testDateSidebarPresentationOpensSelectedOlderMonth
```

Expected: PASS.

## Task 3: Full Verification

**Files:**
- Review: `KnowYou/UI/Sidebar/DateSidebarView.swift`
- Review: `KnowYouTests/DailyMarkdownViewTests.swift`

- [x] **Step 1: Run repository-required tests**

Run:

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS'
```

Expected: PASS.

- [x] **Step 2: Run repository-required build**

Run:

```bash
xcodebuild build -scheme KnowYou -destination 'platform=macOS'
```

Expected: PASS.

- [x] **Step 3: Review final diff**

Run:

```bash
git diff -- KnowYou/UI/Sidebar/DateSidebarView.swift KnowYouTests/DailyMarkdownViewTests.swift docs/superpowers/specs/2026-04-24-month-grouped-date-sidebar-design.md docs/superpowers/plans/2026-04-24-month-grouped-date-sidebar.md
```

Expected: diff only contains the month-grouped sidebar feature, focused tests, and Superpower docs.
