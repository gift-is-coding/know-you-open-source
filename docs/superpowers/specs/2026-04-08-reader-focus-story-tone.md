# KnowYou Reader Focus and Story Tone Spec

## Overview

The current reader has three product gaps:

- keyboard navigation does not respect a stable focus model between the date list and the story content
- generated story text is too compressed and mechanical on many days
- notification import failure is hard to diagnose from inside the app

This pass keeps the existing three-column layout and source-linked story model, but makes the reading experience feel intentional and understandable.

## Goals

- make keyboard navigation predictable between the left date list and the middle story column
- make generated daily stories read more like a human diary and less like an event dump
- improve Markdown readability without turning the story into a rigid report
- explain notification import behavior clearly, including why notifications may be missing on a given Mac

## Requirements

### 1. Explicit reader focus

The reader must track keyboard focus as product state, not just inherit whatever `NavigationSplitView` or `List` happens to do.

There are exactly two focus zones in this pass:

- `dateList`
- `storyParagraphs`

Behavior:

- In `storyParagraphs`, `Up` and `Down` move between paragraphs.
- In `storyParagraphs`, `Left` or `Escape` returns focus to `dateList`.
- In `dateList`, `Up` and `Down` change the selected day.
- In `dateList`, `Right` enters `storyParagraphs` for the selected day.

### 2. Paragraph memory per day

Each day should remember its last selected paragraph.

- Re-entering a day’s story restores that paragraph when it still exists.
- If the saved paragraph no longer exists, the first available paragraph is selected.

### 3. Visible focus indication

The active keyboard zone must be visually obvious.

- The focused column should have a stronger accent treatment than the unfocused column.
- Existing selection styling should remain, but focus should be distinguishable from item selection.

### 4. Warmer story generation

Story generation should shift toward a gentle diary voice.

- do not force a fixed paragraph count
- let quiet days stay short and busy days breathe naturally
- prefer narrative transitions, reflection, and grouped context over bullet-like compression
- keep structured source linkage unchanged

### 5. Light Markdown richness

Story output should remain readable Markdown with modest hierarchy.

- preserve the top-level day heading
- preserve a story section and a source-notes section
- improve rhythm with spacing and light separators or emphasis where helpful
- avoid heavy list formatting inside the story body

### 6. Notification diagnostics

The app must explain the collection model clearly.

- clipboard capture is native macOS pasteboard polling and does not depend on Maccy
- notification import comes from the local macOS Notification Center database
- the UI should distinguish between missing database, permission denied, and machine-dependent notification non-persistence

## Acceptance Criteria

- While reading a day, `Left` or `Escape` always returns the user to the date list.
- From the date list, `Right` always re-enters the story view for the selected day.
- Each day restores its own last-selected paragraph.
- Story prompt guidance no longer enforces a fixed paragraph range.
- Composed Markdown reads with clearer spacing and lightweight structure.
- Service/status text explains both clipboard provenance and notification-import limitations.
