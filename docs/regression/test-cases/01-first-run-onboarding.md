# 01 - First-Run Onboarding

## Goal

Protect the first user journey from a fresh install: users should understand the product by interacting with the real reader, pass required permission guidance, configure an engine, and reach the main app without dead ends.

## Environment

- Type: `permission-clean` for automation, plus `true-clean` before release
- Data: no persisted onboarding state, no saved vault path, no saved engine config
- Test environment: a regression-only bundle id such as `dev.knowyou.regression`, deterministic regression summarizer, and TCC reset only for that regression bundle id
- True-clean release pass: independent macOS user or VM/snapshot with the signed app installed fresh

## Steps

1. Launch the regression-bundle KnowYou from a permission-clean environment.
2. Verify the app opens the real three-pane reader with onboarding coachmarks, not a separate marketing screen.
3. Read the demo day and click the primary continue action.
4. Click a highlighted story paragraph.
5. Verify the right source detail panel shows source evidence for that paragraph.
6. Continue to the privacy step and verify local Markdown/privacy messaging is visible.
7. Continue to the permissions step.
8. Verify Full Disk Access is explained as the hard requirement and notification permission is explained as the 8:30 PM review reminder.
9. Verify the app starts with Full Disk Access missing even if the daily `dev.knowyou.app` is already authorized on this Mac.
10. Use the test-safe Full Disk Access bypass in Debug regression mode, or stop before grant in the permission-clean quick pass.
11. Click the highlighted engine selector.
12. Verify the engine setup sheet opens and allows the deterministic regression engine path.
13. Start first generation when using the bypass path.
14. Wait until onboarding exits and the normal My Diary surface is visible.

## Assertions

- The main window is visible and active throughout the journey.
- The story panel, source panel, and engine selector are reachable by user-visible controls.
- The permission step does not require real Notification permission to continue.
- Full Disk Access remains the only hard permission gate.
- First generation writes onboarding completion state only inside the regression profile.
- The permission-clean run does not read, reset, or modify `dev.knowyou.app` permissions.
- A daily machine where `dev.knowyou.app` is already authorized cannot be treated as a true first-user proof.
- No external browser, System Settings, Finder, or agent app becomes mandatory in automated pre-push mode.

## Automation

- Level: `pre-push`
- Codex Skill case id: `first-run-onboarding`
- Use Codex GUI / ComputerUser to click the visible onboarding card, story paragraph, source detail, permission bypass, engine selector, engine sheet, and main content.
- Setup helper mode: `scripts/regression/run-user-journey.sh --permission-clean`
- Release validation: repeat the user journey manually in `--true-clean-checklist` on an independent macOS user or VM/snapshot.

## Update Triggers

- Onboarding step order changes
- Permission copy or gate behavior changes
- Engine setup becomes optional, moves, or gains new providers
- First generation behavior changes
- Main window routing changes
