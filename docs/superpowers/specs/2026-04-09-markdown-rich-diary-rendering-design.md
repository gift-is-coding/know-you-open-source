# Spec: Markdown-Rich Diary Rendering

**Date:** 2026-04-09  
**Branch:** dev  
**Status:** Draft

---

## Problem

The diary reader currently feels like plain text even though the app stores daily notes as Markdown files. Users expect visible Markdown formatting in the reading experience, including headings, paragraph spacing, bold emphasis, quotes, and other common rich-text markers.

The current implementation does not render the saved Markdown document directly. Instead, the main reading column renders `DailyStoryParagraph.text` as separate SwiftUI paragraph rows. That preserves paragraph-level source linking, but it drops most block-level Markdown presentation and makes the reader feel flatter than the underlying `.md` artifact.

The desired outcome is:

- Keep daily notes stored as Markdown on disk
- Render Markdown formatting in the app reading experience
- Preserve paragraph-level source linking as the higher-priority interaction
- Render both `Story` and `Source Notes` with Markdown-aware presentation

---

## Goals

1. Upgrade the diary reader from plain-text-feeling paragraphs to Markdown-rich reading.
2. Keep the existing paragraph selection model that powers the source detail panel.
3. Preserve the current file format and note-generation pipeline: Markdown remains the canonical export artifact on disk.
4. Ensure `Story` and `Source Notes` both display as Markdown in the main reading column.

## Non-Goals

- Replacing the source-link model with freeform document editing
- Turning the reader into a full Notion-style editor
- Reworking the right-side source detail panel
- Changing vault storage away from `.md`

---

## Approaches Considered

### Approach A: Render the entire `.md` file as one Markdown document

This would make the reader most closely match the saved file and would produce the most literal Markdown reading experience.

Trade-offs:

- Best fidelity to the saved document
- Weak fit for current source-link behavior because the UI loses a clean mapping from clicked paragraph to `sourceEventIDs`
- More work to rebuild selection, hit-testing, and paragraph-to-source mapping after render

### Approach B: Keep paragraph units, but render each paragraph as Markdown and render `Source Notes` as a Markdown block

This keeps the current interaction model for the story while improving typography and Markdown richness where users feel it most.

Trade-offs:

- Preserves paragraph click -> source detail mapping
- Fits the current structured story model cleanly
- Supports inline Markdown and constrained block Markdown inside each story paragraph
- `Source Notes` can render from the saved Markdown section or a generated Markdown fragment without requiring per-item source linking

### Approach C: Replace source-linked paragraphs with a single Markdown document plus separate outline metadata

This would attempt to regain source mapping by building a second metadata layer over a full Markdown renderer.

Trade-offs:

- Potentially flexible long term
- Highest complexity
- Creates more architecture than the feature needs right now

### Recommendation

Choose **Approach B**.

It keeps the most important behavior, paragraph-level source linking, while solving the actual user complaint: the reader feels like plain text instead of Markdown-rich content. It also works with the current app architecture because `AppState` already tracks both `selectedStory` and `selectedMarkdownURL`, and the story model already provides the paragraph boundaries needed for source selection.

---

## Design

### 1. Story Rendering

The `Story` section remains paragraph-based for interaction purposes.

Each `DailyStoryParagraph` row is still a selectable unit with its existing stable paragraph ID. The change is that the paragraph body stops rendering as plain body text and instead renders as Markdown-rich content.

Expected supported formatting inside story paragraphs:

- Bold and emphasis
- Inline code
- Links
- Block quotes when present inside a paragraph unit
- Soft and hard line breaks
- Small headings if the generated text includes them

The paragraph container remains the selection surface. Clicking anywhere in the rendered Markdown block selects that paragraph and updates the source detail panel.

This means the reader becomes visually richer without giving up the current source-tracing behavior.

### 2. Source Notes Rendering

`Source Notes` should also render as Markdown in the main reading column.

This section does not need paragraph-level source selection, because the source inspection workflow is already handled by the right-side panel. The main reading column only needs to display the source section with proper Markdown formatting, such as:

- Section heading
- Bullet list spacing
- Inline emphasis and code formatting
- Readable typography for long lines

Implementation-wise, this section can be rendered as a single Markdown block rather than as individually selectable rows.

### 3. Reader Composition

The main reader becomes a hybrid Markdown view:

- Header with date and refresh button remains
- `Story` is rendered as a sequence of selectable Markdown paragraph blocks
- `Source Notes` is rendered below as a Markdown section block

This preserves the notebook-style layout introduced in the current diary reader polish work while making the content itself look like Markdown instead of plain text.

### 4. Data Source Strategy

The app should continue using the structured `DailyStory` model for paragraph-linked story rendering.

For the source section, the app can use one of two equivalent sources:

- Parse the `## Source Notes` tail from the saved `.md` file
- Regenerate the same Markdown list from `selectedDayEvents`

Recommendation:

Use the saved `.md` file as the source for the rendered `Source Notes` block whenever `selectedMarkdownURL` is available. This keeps the UI aligned with the exact exported artifact the user asked to preserve.

If the file cannot be loaded, fall back to a generated source-notes Markdown fragment so the reader stays functional.

### 5. Markdown Constraints

To protect source linking, the `Story` section should still be treated as a list of paragraph units. That means the app supports Markdown-rich rendering inside a paragraph unit, but it does not promise arbitrary full-document block composition across paragraph boundaries.

This is an intentional constraint and not a bug:

- Source linking remains reliable
- Rendering stays predictable
- The model remains compatible with the current `DailyStoryParagraph` structure

The saved `.md` file can still contain normal section headings and the `Source Notes` list exactly as it does now.

---

## Components

### `KnowYou/UI/Reader/DailyMarkdownView.swift`

Primary change area.

Responsibilities after change:

- Continue rendering the date header and refresh control
- Render each story paragraph using Markdown-aware content instead of plain body text
- Keep paragraph selection visuals and callbacks
- Render `Source Notes` as a Markdown block below the story content

### `KnowYou/App/AppState.swift`

May need a small read-path addition so the selected day can expose the saved Markdown contents, or at minimum the extracted `Source Notes` section, to the reader view.

The selection model for story paragraphs should stay intact.

### `KnowYou/App/AppEnvironment.swift`

May need a helper for loading a saved `.md` file by `dayKey` or by URL.

### `KnowYou/Services/Composer/DailyMarkdownComposer.swift`

No required format change for this feature. The current Markdown output shape already contains separate `Story` and `Source Notes` sections and can remain the saved-file contract.

Prompt changes to encourage richer inline Markdown are optional follow-up work, not required to unlock frontend Markdown rendering.

---

## Error Handling

- If the saved Markdown file is missing, the story still renders from `DailyStory` and the source notes fall back to a generated Markdown list.
- If the Markdown renderer cannot interpret a specific fragment, the app should fail soft by showing the raw text for that fragment instead of blank content.
- If a story paragraph contains unsupported Markdown structure, the paragraph should still remain clickable and source-linked.

---

## Testing

1. Add focused tests for any markdown-loading helper introduced in `AppEnvironment` or `AppState`.
2. Add reader-facing tests that verify:
   - story paragraphs still preserve selection IDs
   - source notes are available from the saved markdown file when present
   - fallback source-notes generation works when the file is missing
3. Run the targeted test slice during implementation.
4. Run full verification before claiming completion:
   - `xcodebuild test -scheme KnowYou -destination 'platform=macOS'`
   - `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`

---

## Open Decisions Resolved

- Source linking is higher priority than freeform full-document rendering.
- Both `Story` and `Source Notes` should render as Markdown in the reader.
- The `.md` file remains the on-disk artifact.
- The recommended implementation is hybrid: paragraph-level Markdown rendering for story, section-level Markdown rendering for source notes.
