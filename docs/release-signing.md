# KnowYou Release Signing

This document is the canonical release path for outside-the-App-Store macOS builds.

For version bump rules, see [KnowYou Versioning](release-versioning.md).

## One-Time Machine Setup

Store Apple notarization credentials in the login keychain:

```bash
xcrun notarytool store-credentials "know-you-notary" \
  --apple-id "ouyang_danhua@outlook.com" \
  --team-id "3DY726RPHL" \
  --password "<app-specific-password>"
```

After that, validate the profile exists:

```bash
xcrun notarytool history --keychain-profile "know-you-notary"
```

## Release Flow

For the normal public release path, run the single publish script:

```bash
./scripts/publish-release.sh
```

It will build the Release archive, notarize it, verify the stapled app, package a drag-to-Applications DMG, upload the DMG plus `.sha256` to `gift-is-coding/know-you-downloads`, and update that repo's download landing page metadata.

If you need to run the steps manually, use the lower-level scripts below:

1. Build the release archive and the first distributable zip:

```bash
./scripts/build-release.sh
```

2. Submit the zip to Apple notarization, staple the ticket, and emit the final notarized zip plus public DMG:

```bash
./scripts/notarize-release.sh
```

3. Verify the stapled app:

```bash
./scripts/verify-release.sh
```

## Artifacts

Everything lands under `build/release/`:

- `KnowYou.xcarchive`
- `KnowYou.app`
- `KnowYou-<version>-<build>.zip`
- `KnowYou-<version>-<build>-notarized.zip`
- `KnowYou-<version>-<build>.dmg`
- `notary-result.json`

## Expected Success Signals

- `codesign --verify --deep --strict --verbose=2` exits 0
- `xcrun notarytool submit --wait` returns `Accepted`
- `xcrun stapler validate` exits 0
- `spctl --assess --type execute -vv` reports acceptance

## Notes

- Debug and day-to-day development stay on the existing local signing flow.
- Release packaging intentionally forces `Developer ID Application: danhu ouyang (3DY726RPHL)`.
- The release app uses hardened runtime because notarization requires it.
