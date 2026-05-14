# DMG Release Distribution Design

## Goal

Make the public macOS download install into `/Applications` more naturally by publishing a DMG as the primary GitHub Release asset instead of a zip-only app bundle.

## Design

The release pipeline keeps the existing Developer ID archive, zip notarization input, app stapling, and verification flow. After the app is notarized and stapled, the pipeline creates a compressed DMG containing `KnowYou.app` plus an `Applications` symlink so the user sees the standard drag-to-install layout.

The DMG must be product-grade, not a bare Finder default view: `KnowYou.app` appears on the left, `Applications` appears on the right, and the background explicitly says `Drag KnowYou to Applications`.

The GitHub download page and release notes should point at the DMG asset. The notarized zip can remain as an internal/intermediate artifact, but it is no longer the primary public download.

## Acceptance Criteria

- `scripts/publish-release.sh` uploads `KnowYou-<version>-<build>.dmg` and its checksum as the primary release assets.
- The DMG Finder layout places `KnowYou.app` left of `Applications` with a visible drag instruction and arrow.
- The download page points to the DMG and labels the artifact size as `MB DMG`.
- Release notes instruct users to open the DMG and drag `KnowYou.app` to `Applications`.
- The release app remains signed with Developer ID, notarized, stapled, and verified before upload.
