# Month Grouped Date Sidebar Design

## Goal

Group the left journal date sidebar by month so long histories are easier to scan. The current month should be open by default, while previous months should start collapsed.

## Requirements

- Keep `DateSidebarView`'s public inputs unchanged: it still receives flat `yyyy-MM-dd` day keys from `AppState`.
- Render valid day keys under month headers formatted in English, for example `April 2026`.
- Keep the day row labels in the existing compact format, for example `04-24 Fri`.
- Open the current month by default.
- Collapse months before the current month by default.
- If the selected day belongs to a previous month, open that month as well so the selected row remains visible.
- Keep invalid or special day keys, including `OnboardingDemoStory.demoDayKey`, visible outside month grouping instead of dropping them.
- Preserve the existing bottom sidebar menus for settings, sync memory, and feedback.

## Approach

Add a small presentation model next to `DateSidebarView` that converts `[String]` into ordered sidebar sections. `DateSidebarView` will render those sections with SwiftUI `DisclosureGroup`s and seed expansion state from the presentation model.

The model will accept a `Calendar` and `today` date so tests can verify current-month behavior without depending on wall-clock time. The production view will use `.current` calendar and `Date()`.

## Testing

- Add focused unit coverage for grouping, English month titles, current-month default expansion, previous-month default collapse, and selected previous-month expansion.
- Run the targeted test slice before implementation to verify the test fails.
- Run the same targeted tests after implementation.
- Run the repository-required macOS test and build commands before completion.
