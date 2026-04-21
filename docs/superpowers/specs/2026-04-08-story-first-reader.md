# KnowYou Story-First Reader Spec

## Overview

The existing daily note reader is too close to the raw capture stream. A noisy day, especially one with many notifications and clipboard records, turns into a long Markdown dump instead of a readable story.

This feature changes the app from a Markdown-first reader to a story-first daily reader:

- Left sidebar stays date-based, but uses a compact date format
- Center pane renders a fixed daily story structure
- Right pane shows the raw source records behind the currently selected story paragraph
- The toolbar refresh action regenerates the currently selected day

Markdown remains on disk as an export artifact, but the app UI should render from a structured story model instead of parsing Markdown as the primary view format.

## Product Goal

Help the user understand what happened during a day as a compact story, while still preserving direct visibility into the original clipboard and notification evidence.

## User Problems

### 1. Daily output is too noisy

The current generated note often looks like a log file instead of a narrative. Users cannot quickly reconstruct the main thread of the day.

### 2. Raw source inspection is disconnected

The user wants to see the original source material, including time and app, but not as tiny citation markers or hidden metadata.

### 3. Sidebar wastes space

Long labels like `Wednesday, Apr 8` are visually heavy and reduce scan efficiency.

### 4. Regeneration should match selection

The top-right refresh control must regenerate the selected day, not just implicitly act on today.

## Experience Shape

The main app window uses three columns:

- Sidebar: available dates
- Reader: structured story sections and selectable paragraphs
- Detail pane: raw evidence for the selected paragraph, plus full-day sources on demand

## Story Model

Each day now has a structured story artifact:

- `DailyStory`
- `DailyStorySection`
- `DailyStoryParagraph`

Each paragraph links back to concrete `EventRecord.id` values.

The system persists:

- `YYYY-MM-DD.md`
- `YYYY-MM-DD.story.json`

The `.story.json` file is the canonical UI artifact. The Markdown file is kept for portability and human-readable export.

## Story Template

The story uses four fixed sections:

- `Main Thread`
- `Key Progress`
- `Communication / External Events`
- `Loose Fragments`

Generation rules:

- Output should be short paragraphs, not bullets
- Source linking is paragraph-level
- Section ids must remain stable
- Empty sections are allowed

## Fallback Behavior

If no summarizer is configured, or structured output cannot be parsed, the app must still create a deterministic local story from the stored events.

This fallback must:

- preserve the four-section structure
- create at least one readable paragraph when events exist
- keep paragraph-to-source links intact

## UI Requirements

### Sidebar

- Show dates as `MM-dd EEE`
- Example: `04-08 Wed`
- Keep date navigation lightweight and scannable

### Story Reader

- Render section title plus paragraph cards
- Clicking a paragraph selects it
- Selected paragraph is visually highlighted
- Up/down keyboard movement changes paragraph selection

### Source Detail Pane

- Show raw source events for the selected paragraph
- Each source record shows:
  - time
  - app
  - source type
  - original kept or audit text
- Include a collapsed `View All Sources` affordance for the whole day

### Toolbar Regeneration

- The circular refresh button regenerates the selected day
- If no day is selected, it falls back to today

## State Requirements

App state must track:

- selected story
- selected story paragraph id
- source events linked to the selected paragraph
- all source events for the selected day

When a date is selected:

- load `.story.json` if it exists
- otherwise build a fallback story from the database
- auto-select the first paragraph when present

## Non-Goals

- No sentence-level citation model
- No separate raw-Markdown reading mode in the main reader
- No badge system in the sidebar for this iteration
- No browser extension or external note-view integration

## Acceptance Criteria

- A noisy day opens as a readable four-section story
- The user can click a paragraph and immediately inspect its raw sources
- The date list uses compact labels like `04-08 Wed`
- The toolbar refresh regenerates the selected day
- Historical days without `.story.json` still render through fallback generation
