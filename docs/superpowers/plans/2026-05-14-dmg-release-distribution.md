# DMG Release Distribution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish KnowYou as a drag-to-Applications DMG from the existing release pipeline.

**Architecture:** Keep the current archive -> zip notarization -> staple -> verify pipeline, then create a compressed DMG from the stapled app. Use the DMG as the primary GitHub Release asset and keep shell helper tests around artifact naming, download URL, release notes, and download page metadata.

**Tech Stack:** Bash, `xcodebuild`, `notarytool`, `stapler`, `hdiutil`, `gh`

---

### Task 1: Lock DMG artifact expectations

**Files:**
- Modify: `scripts/test-release-common.sh`
- Modify: `scripts/test-publish-release-common.sh`

- [x] Add assertions for `release_dmg_path`, DMG checksum naming, DMG download URLs, DMG install copy, and `MB DMG` download page labels.
- [x] Run `./scripts/test-release-common.sh` and `./scripts/test-publish-release-common.sh` and confirm they fail against the zip-only implementation.

### Task 2: Add DMG packaging and publishing

**Files:**
- Create: `scripts/build-dmg.sh`
- Modify: `scripts/release-common.sh`
- Modify: `scripts/notarize-release.sh`
- Modify: `scripts/publish-release.sh`

- [x] Add `release_dmg_path` and point public release helpers at the DMG.
- [x] Create a compressed DMG containing `KnowYou.app` and an `Applications` symlink.
- [x] Generate the DMG after the app is notarized and stapled.
- [x] Upload the DMG and DMG checksum from `publish-release.sh`.
- [x] Re-run focused shell tests and confirm they pass.

### Task 3: Update release docs and verify

**Files:**
- Modify: `docs/release-signing.md`
- Modify: `docs/architecture.md`
- Modify: `docs/requirements-spec.md`
- Modify: `docs/product-hunt-launch.md`

- [x] Update docs so the public artifact is described as a DMG.
- [x] Run shell helper tests, full macOS tests, and release build verification.
- [x] Upload the latest verified main release DMG to GitHub Release `v1.0.4-build139`.

### Task 4: Add Custom Finder Installer Layout

**Files:**
- Modify: `scripts/build-dmg.sh`
- Create: `scripts/test-build-dmg-layout.sh`

- [x] Add a failing shell test that requires the DMG script to generate a custom background, place `KnowYou.app` on the left, place `Applications` on the right, and use large icons.
- [x] Generate a background PNG during packaging with the instruction `Drag KnowYou to Applications`.
- [x] Render the background at 2x pixel density and reserve a light label area so Finder-rendered item names stay legible.
- [x] Create a read-write DMG, use Finder AppleScript to write `.DS_Store` icon positions and background settings, then convert to compressed read-only DMG.
- [x] Mount the generated DMG and verify it contains `KnowYou.app`, `Applications`, `.background/background.png`, and no temporary generator source.
