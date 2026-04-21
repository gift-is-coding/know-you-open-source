# Developer ID Release Signing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a repeatable Developer ID release pipeline for KnowYou, bind Apple notarization credentials on this Mac, and produce one notarized distributable build.

**Architecture:** Keep debug signing untouched, move release packaging into shell scripts, and make the app target's Release configuration notarization-ready with hardened runtime. The final path is `archive -> zip -> notarize -> staple -> verify`.

**Tech Stack:** Xcode / `xcodebuild`, shell scripts, `notarytool`, `stapler`, `codesign`, `spctl`

---

### Task 1: Make Release Build Notarization-Ready

**Files:**
- Modify: `KnowYou.xcodeproj/project.pbxproj`
- Modify: `docs/architecture.md`
- Modify: `docs/requirements-spec.md`

- [ ] Add `ENABLE_HARDENED_RUNTIME = YES` to the app target Release config.
- [ ] Keep debug signing unchanged so local development does not regress.
- [ ] Document the new release/distribution behavior in architecture and requirements docs.

### Task 2: Add Reusable Release Scripts

**Files:**
- Create: `scripts/release-common.sh`
- Create: `scripts/test-release-common.sh`
- Create: `scripts/build-release.sh`
- Create: `scripts/notarize-release.sh`
- Create: `scripts/verify-release.sh`
- Modify: `.gitignore`

- [ ] Write a small shared shell library for version lookup, artifact naming, and path validation.
- [ ] Write a failing shell test first for the shared helpers, then implement the helpers until the test passes.
- [ ] Add a build script that archives the app, copies the release `.app`, and creates the distributable `.zip`.
- [ ] Add a notarize script that submits the zip, staples the app, and emits a final notarized zip.
- [ ] Add a verify script that runs `codesign`, `stapler`, and `spctl` against the built app.
- [ ] Ignore local release artifacts under `build/`.

### Task 3: Add Human-Facing Release Docs

**Files:**
- Create: `docs/release-signing.md`
- Modify: `README.md`
- Modify: `LAUNCH-CHECKLIST.md`

- [ ] Document the one-time Apple credential binding step with `notarytool store-credentials`.
- [ ] Document the release command sequence and artifact locations.
- [ ] Update the launch checklist so release-signing items map to the new scripts and can be checked with evidence.

### Task 4: Bind Notary Credentials And Produce A Real Artifact

**Files:**
- No repo file changes required for the credential store step.

- [ ] Store `know-you-notary` in the macOS keychain using the provided Apple ID, team, and app-specific password.
- [ ] Run the new release build script.
- [ ] Run the notarize script and wait for Apple acceptance.
- [ ] Run the verify script against the stapled app.

### Task 5: Full Verification And Final Cleanup

**Files:**
- Modify: `LAUNCH-CHECKLIST.md`
- Modify: docs or scripts if live verification exposes gaps

- [ ] Run `scripts/test-release-common.sh`.
- [ ] Run `xcodebuild test -scheme KnowYou -destination 'platform=macOS'`.
- [ ] Run `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`.
- [ ] Update checklist items that are now complete.
- [ ] Review `git diff`, commit the release pipeline, and report the produced artifact path plus notarization status.
