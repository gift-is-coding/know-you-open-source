# KnowYou Versioning

This document defines when to change KnowYou's project version numbers.

## Version Fields

- `MARKETING_VERSION` is the user-facing app version, shown as `v<version>` in the app and release metadata.
- `CURRENT_PROJECT_VERSION` stays as the Xcode project fallback. The actual built app's `CFBundleVersion` is overwritten during the Xcode build phase with the repository commit count.
- Release scripts use `MARKETING_VERSION` plus the release repository build number to name artifacts and publish update metadata.

## Bump Rules

Use semantic-version style increments:

- Patch, for normal user-visible improvements, UI refinements, bug fixes, and small workflow changes. Example: `1.0.4` to `1.0.5`.
- Minor, for a new meaningful product surface or workflow that changes how users use KnowYou. Example: `1.0.x` to `1.1.0`.
- Major, only for breaking data, compatibility, or release-channel changes. Example: `1.x.y` to `2.0.0`.

## Default Rule

After merging any user-visible feature into `main`, bump `MARKETING_VERSION` before the final build/UAT pass.

If the change is internal-only, test-only, docs-only, or unreleased cleanup, do not bump `MARKETING_VERSION`.

## Release Checklist

1. Decide the bump size using the rules above.
2. Update every `MARKETING_VERSION` entry in `KnowYou.xcodeproj/project.pbxproj`.
3. Do not manually update `CURRENT_PROJECT_VERSION` unless the build phase changes.
4. Run the final verification on `main`:
   - `xcodebuild test -scheme KnowYou -destination 'platform=macOS'`
   - `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`
5. Launch the freshly built DerivedData app and run the functional UAT smoke test.
