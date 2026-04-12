# Source Logo Top 100 Implementation Plan

**Goal:** Expand the reader's branded source coverage to 100+ curated apps while keeping the resolver maintainable and preserving graceful fallback behavior.

**Architecture:** Keep source-logo rendering local to the reader UI. Convert brand resolution to a table-driven mapping, extend the bundled asset catalog with a curated top-global app set, and add focused resolver tests for the newly covered categories.

**Tech Stack:** SwiftUI, XCTest, Xcode asset catalogs, macOS app target `KnowYou`

---

## Work Items

- [x] Convert source-brand resolution from a long switch to a table-driven entry list.
- [x] Normalize aliases through one deterministic lookup table.
- [x] Add branded assets for browsers, collaboration tools, AI products, developer tools, office tools, and common macOS system apps.
- [x] Expand focused resolver tests to cover the new top-global app set.
- [x] Run targeted test verification for `DailyMarkdownViewTests`.
- [x] Run a full macOS build to confirm asset-catalog integration.

## Notes

- Prioritize global apps that frequently generate notifications or appear as clipboard sources.
- Keep unknown apps on the generic fallback path rather than forcing speculative brand mappings.
- Prefer local bundled assets over runtime app-icon discovery so behavior stays consistent across machines.
