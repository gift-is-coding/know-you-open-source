# 01 - First-Run Onboarding

## Goal

Protect the first user journey from a fresh install: users should understand the product by interacting with the real reader, pass required permission guidance, configure an engine, and reach the main app without dead ends.

## Environment

- Type: `permission-clean` for automation, plus `true-clean` before release
- Data: no persisted onboarding state, no saved vault path, no saved engine config
- Test environment: `/Applications/KnowYou New User.app`, installed from the current worktree by `scripts/install-new-user-app.sh --no-launch`, bundle id `dev.knowyou.newuser`, deterministic regression summarizer, and TCC reset only for `dev.knowyou.newuser` when the case needs the missing-permission path
- Path rule: the launched app must be `/Applications/KnowYou New User.app`, not a DerivedData app
- True-clean release pass: independent macOS user or VM/snapshot with the signed app installed fresh

## Steps

1. Run `scripts/install-new-user-app.sh --no-launch`.
2. Verify `/Applications/KnowYou New User.app` exists, its bundle id is `dev.knowyou.newuser`, and the launch path is not a DerivedData app.
3. Launch `/Applications/KnowYou New User.app` from the permission-clean environment.
4. Verify the app opens the real three-pane reader with onboarding coachmarks, not a separate marketing screen.
5. Read the demo day and click the primary continue action.
6. Click a highlighted story paragraph.
7. Verify the right source detail panel shows source evidence for that paragraph.
8. Continue to the privacy step and verify local Markdown/privacy messaging is visible.
9. Continue to the permissions step.
10. Verify Full Disk Access is explained as the hard requirement and notification permission is explained as the 8:30 PM review reminder.
11. Verify the page says to click `+` in Full Disk Access, choose the app from Applications, and use `Show App to Add` if KnowYou is not listed.
12. Verify the Full Disk Access visual guide is visible.
13. Verify the app starts with Full Disk Access missing even if the daily `dev.knowyou.app` is already authorized on this Mac.
14. Stop before grant in the missing-permission quick pass, use the test-safe Debug bypass for ordinary feature coverage, or launch the already-authorized `/Applications/KnowYou New User.app` to verify the authorized-through path.
15. Click the highlighted engine selector when using a bypass or authorized path.
16. Verify the engine setup sheet opens and allows the deterministic regression engine path.
17. Start first generation when using the bypass or authorized path.
18. Wait until onboarding exits and the normal My Diary surface is visible.

## Assertions

- The main window is visible and active throughout the journey.
- The story panel, source panel, and engine selector are reachable by user-visible controls.
- The permission step does not require real Notification permission to continue.
- Full Disk Access remains the only hard permission gate.
- The page includes `+`, `Applications`, `Full Disk Access`, `Show App to Add`, and the `FullDiskAccessAddGuide` asset.
- First generation writes onboarding completion state only inside the regression profile.
- The permission-clean run does not read, reset, or modify `dev.knowyou.app` permissions.
- The permission-clean run uses `dev.knowyou.newuser` from `/Applications/KnowYou New User.app`, not a DerivedData app.
- A daily machine where `dev.knowyou.app` is already authorized cannot be treated as a true first-user proof.
- No external browser, System Settings, Finder, or agent app becomes mandatory in automated pre-push mode.

## Automation

- Level: `pre-push`
- Codex Skill case id: `first-run-onboarding`
- Use Codex GUI / ComputerUser to click the visible onboarding card, story paragraph, source detail, permission bypass, engine selector, engine sheet, and main content.
- Setup helper mode: `scripts/install-new-user-app.sh --no-launch`, then `scripts/regression/run-user-journey.sh --permission-clean` when that runner exists
- Release validation: repeat the user journey manually in `--true-clean-checklist` on an independent macOS user or VM/snapshot.

## Update Triggers

- Onboarding step order changes
- Permission copy or gate behavior changes
- Engine setup becomes optional, moves, or gains new providers
- First generation behavior changes
- Main window routing changes
