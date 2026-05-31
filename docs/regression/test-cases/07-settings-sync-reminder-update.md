# 07 - Settings, Sync Memory, Reminder, And Updates

## Goal

Protect secondary but release-critical workflows: users should configure Daily Memory Export, understand LaunchAgent-backed automation, enable evening reminders, and act on update prompts without surprising side effects.

## Environment

- Type: `app-clean` for UI reachability and dry-run filesystem checks
- Type: `true-clean` for real LaunchAgent, notification permission, first-user system prompts, and update URL behavior before release
- Isolation: automated runs use fixture paths and dry-run registration; real LaunchAgent and notification permission checks belong in a separate macOS user or VM/snapshot

## Steps

1. Launch KnowYou with completed onboarding.
2. Open Settings.
3. Verify Daily Memory Export / Connectors entry is reachable.
4. Open the Connectors or Sync Memory panel.
5. Verify Obsidian and OpenClaw destination rows are visible.
6. Set fixture paths in regression mode and run `Sync Now`.
7. Verify generated daily Markdown files are copied to the expected fixture destinations.
8. Toggle Auto Sync Daily in a dry-run or regression-safe mode.
9. Verify the UI explains whether LaunchAgent registration succeeded or failed.
10. Open reminder settings.
11. Verify Evening review reminder toggle, notification authorization state, and test entry are visible.
12. In true-clean manual-release mode, enable notification permission and send a test reminder.
13. If an update offer fixture is injected, click the update pill and verify the update sheet explains current version, available version, and action.

## Assertions

- Sync Memory copies KnowYou-owned daily Markdown only.
- OpenClaw native daily memory files are not overwritten.
- Auto Sync and reminder toggles do not install real LaunchAgents in automated pre-push unless explicitly running a sandboxed dry-run.
- Reminder does not generate diary in the background; it only routes to review or generate.
- Update sheet never appears without a valid update offer.
- Update actions open the configured direct download or App Store path only in manual-release mode.

## Automation

- Level: `nightly` for fixture path Sync Now and dry-run LaunchAgent status
- Level: `manual-release` for real notification permission, real LaunchAgent, and real update feed checks
- Codex Skill case id: `settings-sync-reminder-update`
- Use Codex GUI / ComputerUser for Settings navigation, Sync Now, reminder controls, and update sheet inspection.

## Update Triggers

- Sync Memory config changes
- LaunchAgent labels or scheduling changes
- Evening reminder copy, authorization, payload, or routing changes
- Update service metadata or release channel changes
- Settings navigation changes
