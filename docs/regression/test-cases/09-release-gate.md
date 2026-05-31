# 09 - Release Gate

## Goal

Protect the final publishing path: a build that reaches users should have passed unit tests, Codex-driven GUI regression, real-machine smoke, signing, notarization, DMG packaging, and a human or Codex-guided launch check from the shipped artifact.

## Environment

- Type: `true-clean` plus `real-machine`
- Data: current checkout, current release credentials, fresh release artifact
- True-clean requirement: independent macOS user or VM/snapshot, fresh DMG install, no reused Application Support, Keychain, UserDefaults, TCC grants, or login-item state

## Steps

1. Confirm the working tree contains only intended release changes.
2. Run full macOS tests with `xcodebuild test -scheme KnowYou -destination 'platform=macOS'`.
3. Run full macOS build with `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`.
4. Run `git diff --check`.
5. Run `plutil -lint KnowYou.xcodeproj/project.pbxproj`.
6. Run the pre-push Codex GUI regression suite through `$knowyou-regression-runner`.
7. Run the real-machine clipboard/notification smoke.
8. Build the release app with `scripts/build-release.sh`.
9. Notarize with `scripts/notarize-release.sh`.
10. Build the DMG with the release packaging script.
11. Verify with `scripts/verify-release.sh`.
12. Launch the shipped `KnowYou.app` from the fresh release artifact on the normal release machine for smoke coverage.
13. Install and launch the shipped DMG in a true-clean macOS user or VM/snapshot.
14. Complete Full Disk Access, notification permission, first engine setup, and first generation from scratch.
15. Run a short manual click pass: open My Diary, click a paragraph, open My Wiki, open Other Source, open Settings.

## Assertions

- Tests and build complete successfully in the current session.
- No stale DerivedData app is used for verification.
- Build metadata git SHA matches the current release commit.
- Code signing, hardened runtime, notarization, stapling, and Gatekeeper checks pass.
- The shipped artifact opens without onboarding/auth/engine state being accidentally reset.
- True-clean validation does not reuse the developer machine's `dev.knowyou.app` permissions, Keychain, UserDefaults, Application Support, or login-item state.
- Release verification does not push remote changes automatically.

## Automation

- Level: `manual-release`
- Recommended command sequence should be printed by the release checklist or release script.
- Codex Skill case id: `release-gate`
- True-clean setup helper mode: `scripts/regression/run-user-journey.sh --true-clean-checklist`

## Update Triggers

- Release scripts change
- Signing identity, team id, notary profile, or artifact naming changes
- Update feed or download repo changes
- Build metadata generation changes
- DMG packaging layout changes
