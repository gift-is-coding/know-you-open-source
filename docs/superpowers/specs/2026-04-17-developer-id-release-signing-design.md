# KnowYou Developer ID Release Signing Design

## Goal

Fix the unfinished Apple ID verification and release-signing gap so KnowYou can be exported as a real outside-the-App-Store macOS build: signed with Developer ID, notarized by Apple, stapled, and locally verifiable before upload to the download channel.

## Current Problem

The current project can build and run locally, but the release chain is incomplete:

- the app target still points at an Apple Development identity and a different team for Release
- Release does not enable the hardened runtime required for notarization
- this Mac has a valid `Developer ID Application` certificate, but `notarytool` credentials are not stored
- the repo has no reusable release scripts, so signing/notarization depends on ad hoc terminal steps
- the launch checklist still marks Developer ID signing, notarization, and release package verification as unfinished

## Recommended Approach

Keep local development signing unchanged and add a dedicated release pipeline.

That pipeline should:

1. archive the app in `Release`
2. force Developer ID team + identity for the release artifact
3. package the archived `.app` as a distributable `.zip`
4. submit the `.zip` with `notarytool`
5. staple the notarization ticket back onto the `.app`
6. repackage and verify the final artifact with `codesign`, `spctl`, and `stapler`

This keeps day-to-day debug/test work stable while making production release deterministic.

## Scope

In scope:

- release-specific signing configuration for the app target
- hardened runtime for release builds
- reusable shell scripts for archive, package, notarize, staple, and verify
- keychain profile setup for Apple notarization on this Mac
- release docs, README updates, checklist updates, architecture/requirements updates
- one live notarized build artifact produced on this machine

Out of scope:

- App Store packaging
- DMG installer authoring
- CI notarization secrets in GitHub Actions
- changing the debug workflow

## Artifact Layout

Release work will live under `build/release/` and stay out of git:

- `build/release/KnowYou.xcarchive`
- `build/release/KnowYou.app`
- `build/release/KnowYou-<version>-<build>.zip`
- `build/release/KnowYou-<version>-<build>-notarized.zip`

Scripts will live in `scripts/` with a small shared library so we can test the argument/metadata logic without having to notarize every run.

## Credential Model

The machine will store a keychain-backed `notarytool` profile instead of persisting the Apple app-specific password in repo files or shell history.

Expected profile:

- profile name: `know-you-notary`
- Apple ID: stored only on the release machine and supplied to `notarytool`; never committed
- Team ID: supplied only through the release machine environment; never committed

## Verification

Success means we can show all of the following from the current session:

- `xcodebuild archive` succeeds for the release path
- `codesign --verify --deep --strict --verbose=2` succeeds on the release app
- `xcrun notarytool submit --wait` returns `Accepted`
- `xcrun stapler validate` succeeds
- `spctl --assess --type execute -vv` accepts the app

## Risks And Mitigations

- Team mismatch between old development signing and Developer ID signing
  Mitigation: keep debug unchanged; isolate release settings and override explicitly in scripts
- Missing hardened runtime causing notarization rejection
  Mitigation: enable it in Release and verify via a live notarization attempt
- Future manual releases drifting from the documented path
  Mitigation: put the exact commands in scripts and link them from README/docs
