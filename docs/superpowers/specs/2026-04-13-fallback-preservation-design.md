# Preserve Successful Stories During Fallback Refresh

## Summary

Current refresh behavior can overwrite an existing successful `generationMode == model` daily story with a newly generated fallback story when the summarizer fails or returns invalid output.

This design changes only one rule:

- if a day already has a persisted model-backed story, and a later refresh attempt produces only fallback output, the app must preserve the existing `.story.json` and `.md` files instead of overwriting them

## Current Problem

The current daily generation path always writes the newly produced story artifacts after `generateStory(...)` returns. Because `generateStory(...)` returns fallback output on summarizer failure, both manual refresh and automation can downgrade a previously successful day into fallback content.

That creates a data-loss style regression:

- the user had a better model-generated journal
- a later failing refresh replaces it with lower-quality fallback prose
- the user sees the day become "乱了" even though no better output was produced

## Design

The change is intentionally narrow:

1. Keep fallback generation available when there is no prior successful story.
2. Before writing new artifacts, load the currently persisted story for that day.
3. If the persisted story exists and `provenance.generationMode == .model`, and the newly generated story is not model-backed, abort persistence.
4. Mark the refresh as failed, preserve the existing files, and keep the existing story selected in the UI.

## Invariants

- Fallback remains valid for first-time generation and for days without an existing successful story.
- Fallback must never overwrite an existing successful model story.
- The protection applies regardless of whether the refresh was triggered manually or by automation, because both paths share the same write pipeline.

## Acceptance Criteria

- A day with no prior successful story still persists fallback output when summarization fails.
- A day with an existing persisted model story does not change its `.story.json` or `.md` when a later refresh falls back.
- The blocked refresh is reported as failed rather than silently claiming success.
