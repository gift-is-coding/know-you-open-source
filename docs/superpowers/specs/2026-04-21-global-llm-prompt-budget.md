# Global LLM Prompt Budget

## Goal

Keep diary generation responsive on high-noise days by adding a shared prompt-budget rule before any summarizer call, without changing stored event data or user-visible raw event views.

## Requirements

- The product must apply the same prompt event-text limit to all LLM diary jobs:
  - full-story generation
  - incremental update generation
- Prompt budgeting must live in the shared prompt assembly layer, not in engine-specific adapters.
- The product must preserve event order and include every event; v1 does not add an event-count cap.
- Each event's `text` / `auditText` must be truncated to at most 100 Swift characters when rendered into the summarizer prompt.
- Prompt truncation must not mutate database rows, `.story.json`, Markdown output, source notes, or UI event display.
- Prompt lines must continue to include the existing structured fields:
  - `id`
  - `time`
  - `app`
  - `source`
  - `text`

## Non-Goals

- No token estimation
- No event-count limiting
- No app-specific filtering
- No summarization or rewriting of long source events
- No new settings surface for prompt-budget tuning
