# KnowYou Regression Test Cases

This folder is the long-lived home for KnowYou user-journey regression coverage.
It describes what must be checked before a PR or remote push, and it should be
updated whenever the product's user-visible workflow changes.

## Maintenance Rule

Update this folder when a change touches any of these areas:

- onboarding, Full Disk Access guidance, notification permission, or first generation
- My Diary, date navigation, story reading, source detail, refresh, or full refresh
- Todo inbox, daily todo candidates, manual add, completion, or evidence sweep
- My Wiki, Source Library, duplicate review, or agent setup
- Other Source, Local Folder, Obsidian, Feishu/Lark, Notion, Google Drive, source scan, or prompt generation
- diary engine selector, LLM API providers, CLI engines, Codex Auth, or engine status
- Settings, Sync Memory, LaunchAgent-backed automation, evening reminder, or update sheet
- clipboard, notification import, privacy filtering, SQLite, Markdown output, or release verification

Every test case should keep these fields current:

- **Goal**: the user-visible risk this case protects.
- **Environment**: app-clean, permission-clean, true-clean, or real-machine.
- **Steps**: concrete user actions, written from the user's point of view.
- **Assertions**: observable outcomes and persisted artifacts to verify.
- **Automation**: whether it belongs in pre-push, nightly, manual-release, or later coverage.
- **Update Triggers**: product changes that require revisiting the case.

## Environment Types

- `app-clean`: isolates app data only. The runner creates a temporary profile root such as `build/regression/<run-id>/profile`, points KnowYou at isolated Application Support, UserDefaults suite, Keychain service, Vault, and SQLite locations, and uses deterministic fixtures. This is the default pre-push environment for seeded UI journeys. It does not open Full Disk Access and does not prove macOS permissions are fresh.
- `permission-clean`: isolates permission state with the installed New User app at `/Applications/KnowYou New User.app`. Build it from the current worktree with `scripts/install-new-user-app.sh --no-launch`; the app uses bundle id `dev.knowyou.newuser` and is not a DerivedData app. Reset TCC only for `dev.knowyou.newuser` when a missing-permission pass is required, and never reset, delete, or modify the daily-use `dev.knowyou.app` bundle id. This environment verifies missing-permission onboarding and blocked/degraded states.
- `true-clean`: uses an independent macOS user or VM/snapshot with a freshly installed signed app. It is the only environment that represents a real first-time user across app data, Keychain, TCC permissions, login items, and system prompts.
- `real-machine`: uses this Mac's real clipboard or Notification Center behavior to verify signal ingestion. It validates the data pipeline, not first-user permission freshness.

## Codex Regression Skill

KnowYou UI regression is intentionally Codex-driven. Do not introduce Xcode UI
test targets or third-party UI automation libraries for these journeys.

The maintained execution entrypoint is the project skill:

- `.agents/skills/knowyou-regression-runner/SKILL.md`

Invoke it from Codex when you want to run or maintain the suite:

- `Use $knowyou-regression-runner to run the app-clean pre-push user journey.`
- `Use $knowyou-regression-runner to run the permission-clean first-run check.`
- `Use $knowyou-regression-runner to walk the true-clean release checklist.`

The skill must use Codex GUI / ComputerUser for the native macOS app. It may use
ChromeUser or Browser only when a test step intentionally involves a browser
surface. Shell commands are only for deterministic setup and evidence.

## Expected Setup Modes

Future setup helpers may expose these modes, but they must remain setup helpers
for the Codex Skill rather than the UI automation mechanism itself:

- `scripts/regression/run-user-journey.sh --app-clean`
- `scripts/install-new-user-app.sh --no-launch`
- `scripts/regression/run-user-journey.sh --permission-clean`
- `scripts/regression/run-user-journey.sh --true-clean-checklist`

The app-clean setup helper should set `KNOWYOU_PROFILE_ROOT`, `KNOWYOU_USER_DEFAULTS_SUITE`, `KNOWYOU_KEYCHAIN_SERVICE`, a fixed clock, a deterministic summarizer, and regression-safe flags that disable real LaunchAgent registration, update-network effects, and external agent config writes.

The permission-clean setup helper installs the current worktree over `/Applications/KnowYou New User.app`. Multiple worktrees must not run this New User permission test in parallel because the last install intentionally wins. If `dev.knowyou.newuser` already has Full Disk Access and its TCC state is not reset, launching from `/Applications/KnowYou New User.app` should verify the authorized-through path. The Codex Skill verifies the product's no-permission guidance through GUI / ComputerUser. The helper and skill must never reset the daily app's `dev.knowyou.app` permissions.

## Regression Levels

- `pre-push`: must be stable enough to run before pushing.
- `nightly`: useful for broader coverage that may be slower or more environment-sensitive.
- `manual-release`: run before signing/notarizing or publishing a release; true-clean checks belong here because they are intentionally heavier than pre-push.

See [coverage-matrix.md](coverage-matrix.md) for the current mapping.
