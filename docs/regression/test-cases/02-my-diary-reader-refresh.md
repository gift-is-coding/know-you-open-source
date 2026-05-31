# 02 - My Diary Reader And Refresh

## Goal

Protect the core daily reading experience: users should switch dates, read story paragraphs, inspect source evidence, and refresh the selected day without corrupting another day.

## Environment

- Type: `app-clean`
- Data: at least three seeded days with events, `.story.json`, Markdown, and mixed clipboard/notification source events
- Suggested seed: existing April 04-06 demo data, extended with current Todo and source fixture data
- Isolation: temporary profile root, UserDefaults suite, Keychain service, Vault, and SQLite; this case does not validate first-user macOS permission state

## Steps

1. Launch KnowYou with completed onboarding.
2. Verify sidebar root entries show `My Wiki`, `Other Source`, and `My Diary` as same-level entries.
3. Open `My Diary`.
4. Select the newest seeded day.
5. Verify the center pane shows the formatted day, story heading, and multiple paragraphs.
6. Click the first paragraph.
7. Verify the right pane shows the linked raw source event.
8. Switch to another seeded day.
9. Verify the story and source detail update to the selected day.
10. Trigger the normal refresh button for the selected day.
11. Verify refresh state appears and then resolves.
12. Open the full-refresh menu and verify the title reflects the selected date context.
13. Trigger full refresh only in a deterministic regression mode, or assert the action is available without running it in quick mode.

## Assertions

- Date selection changes only the selected day.
- Paragraph selection persists a visible selected state and source detail.
- Source detail shows event app, type, timestamp, and text/audit content when available.
- Normal refresh does not import or rewrite unrelated historical days.
- Existing model-generated story must not be overwritten by degraded fallback output.
- Refresh failure, if injected, appears as an explainable status and does not leave a permanent spinner.

## Automation

- Level: `pre-push`
- Codex Skill case id: `my-diary-reader-refresh`
- Use Codex GUI / ComputerUser for date selection, paragraph clicks, source detail inspection, refresh, and full-refresh menu reachability.
- Add a focused non-UI assertion around file timestamps or story day keys if the UI test triggers real refresh.

## Update Triggers

- Sidebar navigation changes
- Date grouping or selection changes
- Story paragraph rendering changes
- Source detail presentation changes
- Refresh, full refresh, incremental refresh, or fallback preservation behavior changes
