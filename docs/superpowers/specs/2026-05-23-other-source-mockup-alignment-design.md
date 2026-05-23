# Other Source Mockup Alignment Design

## Problem

The current `Other Source` entry opens the old mixed `Connectors` page. That page is functionally connected, but it does not match the product model in the approved mockup: it leads with Daily Memory Export, uses the generic `Connectors` title, and does not explain the local Markdown library or sync rules clearly enough.

## User-Facing Goal

`Other Source` must feel like a first-level source library parallel to `My Diary`, not a settings panel. It is the place to connect external knowledge sources, import them into local storage, and then browse each connected source from the left sidebar.

## Required Interaction

- Sidebar keeps `My Diary` and `Other Source` as first-level peers.
- `Other Source` row keeps a visible `+` action.
- Clicking `Other Source` opens a page titled `Other Source`.
- The page subtitle states that connected sources are synced into a local Markdown library.
- Knowledge-source import controls are the primary content:
  - `Add Folder`
  - `Add Obsidian`
  - `Add API`
  - `Import Now`
  - Daily import toggle and import time.
- Empty state must explain that no sources are connected yet and that added connectors become first-level sidebar entries.
- Daily Memory Export must not be the leading content on the `Other Source` page. It may remain in the legacy gear-menu `Connectors` sheet for compatibility.
- The right detail pane for `Other Source` must explain:
  - local Markdown storage,
  - source files are not modified,
  - daily sync,
  - deduplication by source identity and content hash,
  - exported KnowYou diary files are skipped to avoid Obsidian export/import loops.

## Non-Goals

- No new connector backend in this pass.
- No redesign of the diary reader.
- No dynamic remote-link mode; imports remain local-first.

## Acceptance

- The main `Other Source` page visually matches the mockup structure: `Other Source` header, knowledge source rows/actions first, local storage and sync rules visible in the detail pane.
- The gear-menu `Connectors` sheet can still show Daily Memory Export and Knowledge Imports together.
- Focused tests cover the new presentation mode and copy.
