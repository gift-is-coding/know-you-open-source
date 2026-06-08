# Codex Regression Runner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a durable regression runner entrypoint that prepares isolated KnowYou environments and hands native UI execution to Codex GUI / Computer Use.

**Architecture:** Add regression environment support in the app runtime profile, then add a shell runner that creates run directories, seeds safe state, launches the right app, and writes Computer Use prompts plus evidence metadata. Keep native UI interaction out of shell scripts and out of XCUITest.

**Tech Stack:** Swift XCTest, Bash, Xcode macOS build, Codex regression skill docs.

---

### Task 1: Runtime Profile Isolation

**Files:**
- Modify: `KnowYou/App/AppSupportMetadata.swift`
- Modify: `KnowYou/App/AppState.swift`
- Test: `KnowYouTests/SettingsMetadataTests.swift`
- Test: `KnowYouTests/AppStateDefaultUserDefaultsTests.swift`

- [ ] Add tests for `KNOWYOU_PROFILE_ROOT`, `KNOWYOU_KEYCHAIN_SERVICE`, and `KNOWYOU_USER_DEFAULTS_SUITE`.
- [ ] Make `AppRuntimeProfile` resolve regression support directories from `KNOWYOU_PROFILE_ROOT`.
- [ ] Make default `AppState` UserDefaults use `KNOWYOU_USER_DEFAULTS_SUITE` when present.
- [ ] Make vault path loading use the same resolved defaults instead of unconditional `.standard`.

### Task 2: Regression Runner Script

**Files:**
- Create: `scripts/regression/run-user-journey.sh`
- Create: `scripts/test-regression-runner.sh`

- [ ] Write a shell test that runs `--app-clean --dry-run` and asserts run metadata, env file, and Computer Use prompt are generated.
- [ ] Implement `--app-clean`, `--permission-clean`, `--true-clean-checklist`, `--run-id`, `--dry-run`, and `--no-launch`.
- [ ] Generate `computer-use-prompt.md`, `run-metadata.json`, `env.sh`, and `assertions.md` in every run directory.
- [ ] Ensure permission-clean only targets `dev.knowyou.newuser` and `/Applications/KnowYou New User.app`.

### Task 3: Documentation And Verification

**Files:**
- Modify: `docs/regression/README.md`
- Modify: `.agents/skills/knowyou-regression-runner/SKILL.md`

- [ ] Replace “future setup helpers” wording with the concrete runner contract.
- [ ] Document that scripts prepare and launch, while Codex GUI / Computer Use performs native clicks.
- [ ] Run focused shell and Swift tests, then full macOS test/build and `git diff --check`.
