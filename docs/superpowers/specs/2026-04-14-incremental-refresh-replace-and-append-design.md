# Incremental Refresh Replace-And-Append Design

## Overview

The current incremental refresh contract is internally inconsistent:

- the incremental prompt asks the model for an append payload
- the CLI summarizer validates and repairs only the full `.story` schema
- the incremental decode path expects the append payload again

That mismatch makes valid incremental responses fail after structured validation or repair.

This pass separates the incremental structured contract from the full-story contract and updates the product semantics so incremental refresh behaves like a state update rather than a blind append.

## Problem

The first incremental design was intentionally conservative, but two issues now matter:

- protocol mismatch: incremental refresh asks for one JSON shape and validates another
- content drift: append-only `Summary` and `To-do` accumulate stale or repetitive items over time

Passing `allEvents` back into the model is not an acceptable fix because the token cost grows with the day and defeats the purpose of incremental refresh.

## Product Decision

Incremental refresh input must use:

- newly captured events that are not yet referenced by the current story
- the existing generated diary content as the prior state snapshot

Incremental refresh must not pass `allEvents` back to the model.

Section behavior changes to:

- `Encouragement`: replace from model output
- `Summary`: replace from model output
- `Details`: append only new blocks from model output
- `To-do`: replace from model output

The existing story remains the source of prior context. New events are the only fresh evidence introduced during the incremental run.

## Structured Contract

Incremental refresh gets its own schema and must not reuse the full-story `.story` schema.

Canonical incremental JSON:

```json
{
  "encouragementToReplace": {
    "text": "...",
    "sourceEventIDs": ["uuid"]
  },
  "summaryBulletsToReplace": [
    { "text": "...", "sourceEventIDs": ["uuid"] }
  ],
  "detailBlocksToAppend": [
    { "text": "...", "sourceEventIDs": ["uuid"] }
  ],
  "todoItemsToReplace": [
    { "text": "...", "sourceEventIDs": ["uuid"] }
  ]
}
```

Contract rules:

- all four top-level fields are required in the incremental schema
- `null` is never valid for any field
- `encouragementToReplace` is a single replacement block
- `encouragementToReplace.sourceEventIDs` is the full evidence set for the replacement block, not just newly added IDs
- `summaryBulletsToReplace` may be empty but, when present, represents the full new summary state
- `summaryBulletsToReplace[*].sourceEventIDs` is the full evidence set for that bullet, drawn from allowed historical IDs plus new event IDs
- `detailBlocksToAppend` contains only newly appended details material
- `todoItemsToReplace` may be empty but, when present, represents the full new to-do state
- `todoItemsToReplace[*].sourceEventIDs` is the full evidence set for that item, drawn from allowed historical IDs plus new event IDs
- an empty replacement array means the section is intentionally cleared, not preserved
- a missing field is invalid structured output and must trigger repair or attempt failure
- incremental repair must target this schema only
- full refresh repair must continue targeting the `.story` schema only

## Prompt Semantics

The incremental prompt should provide:

- existing encouragement text
- existing encouragement source IDs
- existing summary text
- existing summary source IDs
- existing details text
- existing to-do text
- existing to-do source IDs
- the already used source IDs
- the new events to integrate

The prompt should explicitly tell the model:

- re-evaluate `Encouragement` as the current end-of-day tone using the existing diary plus the new events
- rewrite `Summary` as the current full summary state
- append only the new `Details` material needed to cover the new events
- rewrite `To-do` as the current full to-do state
- avoid repeating detail threads that are already covered by the existing details anchor
- keep the story language aligned with the existing diary unless the existing diary is empty or malformed

## Source Evidence Rules

Incremental refresh still only introduces fresh evidence from `newEvents`, but replacement sections may continue to depend on old context that already existed in the story.

Blindly unioning old section IDs into replacement sections is not acceptable because replacement content may intentionally drop older facts or completed tasks. That would leave stale citations attached to newer text.

Instead, the prompt should expose compact allowed historical evidence for replacement sections:

- existing encouragement source IDs
- existing summary source IDs
- existing to-do source IDs

Replacement sections must return their full evidence sets explicitly, choosing from:

- the section's allowed historical source IDs
- the current incremental `newEvents`

Append-only `Details` blocks must reference only `newEvents`.

Merge behavior:

- replacement `Encouragement` uses exactly the IDs returned for the replacement block
- replacement `Summary` uses exactly the IDs returned for the replacement bullets
- appended `Details` use exactly the IDs returned for each new block
- replacement `To-do` uses exactly the IDs returned for the replacement items

## Failure Handling

Incremental payload application stays atomic.

If any required top-level field is missing, malformed, or semantically invalid after repair:

- the entire incremental payload is rejected
- no partial section updates are applied
- the existing story remains unchanged

Partial acceptance is intentionally out of scope for this pass because it would make section state transitions harder to reason about and test.

## Implementation Notes

- add a third CLI expectation for incremental structured output
- add an incremental schema for Codex structured output
- add engine-appropriate incremental validation and incremental repair entry points
- update `DailyMarkdownComposer.parseIncrementalUpdate` to decode the replacement-and-append payload
- update incremental merge logic to replace or append by section according to the new semantics
- preserve canonical paragraph structure by appending `Details` as new detail paragraphs rather than collapsing all detail content back into one paragraph blob
- derive incremental narrative language from `existingStory` first and use `newEvents` only as a fallback heuristic
- keep full recovery generation unchanged

## Acceptance Criteria

- a valid incremental payload is accepted by the CLI path without being forced through full-story repair
- incremental refresh succeeds for CLI engines that return the new contract
- `Encouragement`, `Summary`, and `To-do` are replaced on incremental refresh
- `Details` only gains newly appended blocks on incremental refresh
- replacement sections use only the explicit evidence IDs returned for their replacement content
- incremental refresh preserves the canonical one-paragraph-per-detail-workstream structure
- incremental refresh does not pass `allEvents` back into the model
- full recovery behavior and `.story` validation remain unchanged

## Non-Goals

- no redesign of the persisted `.story.json` top-level format
- no historical backfill strategy changes
- no token-heavy re-summarization of all raw events during incremental refresh
