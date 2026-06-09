# KnowYou Release Signing

This document is the canonical release path for outside-the-App-Store macOS builds.

For version bump rules, see [KnowYou Versioning](release-versioning.md).

## One-Time Machine Setup

Store Apple notarization credentials in the login keychain:

```bash
xcrun notarytool store-credentials "know-you-notary" \
  --apple-id "danhua_ouyang@outlook.com" \
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

It will build the Release archive, notarize it, verify the stapled app, package a drag-to-Applications DMG, upload the DMG plus `.sha256` to `gift-is-coding/know-you-downloads`, update that repo's download landing page metadata, and publish both `update-feed/latest.json` and `update-feed/appcast.xml` for in-app update checks.

Sparkle releases require two extra inputs on the release machine:

- `KNOWYOU_SPARKLE_PUBLIC_ED_KEY`: optional override for the public EdDSA key injected into the Release Info.plist. The checked-in default public key is `DPaKuqvU48UAoI0rOvKtWaStpzMsX9fwypStdx4md/M=`.
- `KNOWYOU_SPARKLE_SIGN_UPDATE`: optional path to Sparkle `sign_update`; if omitted, `sign_update` must be on `PATH`.

The matching private key must remain in the release user's macOS Keychain. Do not commit or share the private key; `sign_update` reads it from Keychain when publishing.

Release notes are shared across the GitHub release, the legacy `latest.json` update sheet, and the Sparkle appcast. By default the script emits a structured install and verification note. For a real product release, set `KNOWYOU_RELEASE_NOTES_FILE=/path/to/release-notes.md` or `KNOWYOU_RELEASE_NOTES='...'` before `./scripts/publish-release.sh` so both update UIs show the actual changes.

The first Sparkle-enabled release still requires one manual DMG install by existing users. After that version is installed, later direct-channel updates can use Sparkle's progress, install, quit, replace, and relaunch flow.

## Local Update Testing

Debug builds read the local update metadata from:

- `http://127.0.0.1:8765/Support/update-feed/debug-update.json`
- `http://127.0.0.1:8765/Support/update-feed/appcast.xml`

To fake a newer version for the KnowYou update pill and update sheet, generate the local fixture and serve the repo root:

```bash
./scripts/prepare-local-update-fixture.sh
/usr/bin/python3 -m http.server 8765 --bind 127.0.0.1
```

The default fixture uses version `9.9.0`, so it should be newer than normal development builds. This UI-only fixture is enough to test that the title-bar update pill appears, the update sheet shows the release notes every time a new offer is detected, and the direct button hands off to Sparkle. Because no real DMG is present, Sparkle will not complete a download/install cycle from this placeholder appcast.

To test a real Sparkle download/install/relaunch cycle, first build a notarized DMG with a newer bundle version, then pass that DMG to the fixture script:

```bash
KNOWYOU_LOCAL_UPDATE_VERSION=9.9.1 \
KNOWYOU_LOCAL_UPDATE_BUILD=9991 \
KNOWYOU_LOCAL_UPDATE_DMG=/path/to/KnowYou-9.9.1-9991.dmg \
KNOWYOU_SPARKLE_SIGN_UPDATE=/path/to/Sparkle/bin/sign_update \
  ./scripts/prepare-local-update-fixture.sh

/usr/bin/python3 -m http.server 8765 --bind 127.0.0.1
```

When `KNOWYOU_LOCAL_UPDATE_DMG` is set, the script copies the DMG into `Support/update-feed/` and writes Sparkle `edSignature` plus `length` attributes into the appcast using the private key in Keychain. That signed fixture can exercise Sparkle's progress, verification, install, quit, replace, and relaunch path.

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
