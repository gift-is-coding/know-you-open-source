# Conservative Incremental Refresh Spec

## Context

Current daily generation could overwrite a previously good note for today because automation always reconsidered today as a regeneration candidate. Manual refresh also used a single-attempt full regeneration path, which made recovery fragile when one engine attempt failed.

## Goals

- Stop automatic full rewrites of today when a successful model story already exists.
- Add a conservative incremental path that only appends new material.
- Preserve existing files on any incremental or recovery failure.
- Improve manual refresh success rate with bounded cross-engine retries.

## Product Rules

### Success Baseline

A day counts as a successful generated baseline only when:

- `<day>.story.json` exists
- `story.provenance.generationMode == .model`

`fallback` and `legacy` artifacts do not count as a successful baseline.

### Automation

- Background automation still backfills truly missing days.
- Background automation no longer forces today into the full-regeneration queue.
- If today already has a successful model story, automation may only run incremental append for today.
- Historical dates do not get automatic incremental append.

### Incremental Update

- Incremental candidate events are the events whose IDs are not present in the existing story's `sourceEventIDs`.
- The model input for incremental updates must include only those new events as generation material.
- Existing content may be supplied only as compressed anchors:
  - encouragement text
  - summary bullets
  - detail headings/summaries
  - to-do items
  - already-used source IDs
- Incremental output may only append to:
  - `Summary`
  - `Details`
  - `To-do`
- `Encouragement` must remain unchanged.

### Manual Refresh

- If the selected day has a successful baseline, manual refresh uses incremental update.
- Otherwise manual refresh uses full recovery generation for that day only.
- Manual refresh tries the currently selected engine first, then other green engines, up to 5 total attempts.
- A successful attempt stops the retry loop immediately.
- If every attempt fails, existing files remain untouched.

## Non-Goals

- No automatic historical incremental refresh.
- No rewriting of previous sections during incremental updates.
- No change to the external `.md` or `.story.json` formats.
