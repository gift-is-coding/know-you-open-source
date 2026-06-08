---
name: knowyou-regression-runner
description: Use when running or maintaining KnowYou user-journey regression tests with Codex ComputerUser, GUI, Browser, or ChromeUser. This is the required route for KnowYou UI regression and must use Codex's own interaction capabilities instead of framework-based UI automation.
---

# KnowYou Regression Runner

Use this skill to run or maintain KnowYou user-journey regression coverage from `docs/regression/`.
The runner is Codex-driven: native macOS app flows must be inspected through Codex GUI / ComputerUser capabilities, and browser flows must use Browser or ChromeUser when a browser is actually part of the product surface.

## Hard Boundaries

- Do not create or rely on Xcode UI test targets or third-party UI automation libraries.
- Do not reset, delete, or modify the daily `dev.knowyou.app` permissions, Keychain service, UserDefaults, app container, or login items.
- Do not treat `app-clean` as proof of fresh macOS permissions. Only `permission-clean` or `true-clean` can cover first-permission behavior.
- Do not grant Full Disk Access automatically in pre-push automation. Verify the product guidance and blocked/degraded path instead.
- Do not modify real Codex, Claude Code, Cursor, Gemini, OpenClaw, browser, OAuth, or external account config during automated regression.

## Required Inputs

Before operating the app, read:

1. `docs/regression/README.md`
2. `docs/regression/coverage-matrix.md`
3. The specific files under `docs/regression/test-cases/` that match the requested regression level

If the user gives no level, default to `app-clean` pre-push coverage plus the `permission-clean` first-run check.

## Tooling Policy

- Use Codex GUI / ComputerUser for the native KnowYou macOS app: launch the freshly built app, click visible controls, inspect text, and capture screenshots or observations.
- Use ChromeUser only for browser surfaces, remote pages, OAuth-like web pages, docs links, or local web pages that the product intentionally opens in a browser.
- Use Browser only for local web targets when the request explicitly involves a local browser page or the current in-app browser tab.
- Use shell commands only for deterministic setup and evidence: building, launching, profile setup, fixture checks, SQLite queries, grep/rg, git status, and release scripts.

## Environment Selection

- `app-clean`: create an isolated run directory under `build/regression/<run-id>/`, set isolated profile-related environment variables when supported, use deterministic fixtures, and verify My Diary, Todo, Other Source, My Wiki, and Settings without touching daily app data.
- `permission-clean`: run `scripts/install-new-user-app.sh --no-launch` from the current worktree, then launch `/Applications/KnowYou New User.app`. This installed app uses bundle id `dev.knowyou.newuser` and is not a DerivedData app. Reset TCC only for `dev.knowyou.newuser` when the case needs the missing-permission path. If the user has already authorized this app and TCC is preserved, use it to verify the authorized-through path. Never operate on `dev.knowyou.app`.
- `true-clean`: guide a manual pass in an independent macOS user or VM/snapshot using a fresh signed app or DMG. Treat this as release acceptance, not routine pre-push automation.
- `real-machine`: run only when validating this Mac's real clipboard or Notification Center ingestion. Do not describe it as first-user proof.

## Workflow

1. Confirm the requested level and environment from the user's prompt or `coverage-matrix.md`.
2. Check `git status --short --branch` and note whether the workspace is already dirty.
3. Build or launch the current app using the repo's existing macOS workflow. Prefer `./scripts/run-dev-app.sh` for a development launch when no regression runner script exists yet.
   - If `scripts/regression/run-user-journey.sh` exists, prefer it for regression setup because it writes the run directory, isolated environment, Computer Use prompt, and evidence paths.
   - Use `scripts/regression/run-user-journey.sh --app-clean` for My Diary, Todo, Other Source, My Wiki, and Settings pre-push coverage.
   - Use `scripts/regression/run-user-journey.sh --permission-clean --reset-new-user-state` when explicitly validating the missing Full Disk Access first-run path for `dev.knowyou.newuser`.
4. Prepare the selected environment without touching daily `dev.knowyou.app` state.
   - For `permission-clean`, do not run multiple worktrees in parallel because the last install intentionally overwrites `/Applications/KnowYou New User.app`.
   - For ordinary feature regression, use app-clean/dev-bypass or an already configured profile instead of stopping on the Full Disk Access gate.
5. Use Codex GUI / ComputerUser to execute each test case step from the user's point of view. Click only visible, user-reachable controls.
   - Do not claim shell execution alone completed native GUI regression. The script is setup/evidence plumbing; Codex GUI / ComputerUser is the execution mechanism for native clicks and visual assertions.
6. Use shell evidence for persisted artifacts, such as files under the regression profile, SQLite rows, build logs, and release logs.
7. Record each case as `pass`, `fail`, `blocked`, or `manual-only`, with the failing step and visible evidence.
8. Before reporting success, verify that no forbidden automation path or real user state was touched.

## Reporting Format

Return a concise Chinese report:

- Environment and exact command or launch path used
- Cases executed and status
- Screenshots or file/database evidence when available
- Any blockers, especially missing regression runner support
- Whether daily `dev.knowyou.app` state was left untouched

If only documentation was updated, say that no UI regression was actually run.
