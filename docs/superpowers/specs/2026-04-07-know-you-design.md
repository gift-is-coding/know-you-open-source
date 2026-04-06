# Know You V1 Design

## Overview

Know You is a macOS product that automatically captures a user's daily computer context, filters sensitive information before persistence, and produces one Markdown memory document per day.

V1 is a local-first macOS desktop product with:

- A background capture layer
- A minimal desktop reader
- One canonical Markdown file per day
- Cloud-based AI summarization
- Automatic backfill when a day was missed

The product is not an Obsidian plugin. Its UI style may borrow from Obsidian's calm, Markdown-centric reading experience, but the product remains a standalone macOS app.

## Product Goal

Help a user reconstruct what happened on their computer each day by turning passive signals into readable daily memory documents.

## V1 Scope

### In Scope

- macOS-only
- Non-App-Store distribution
- Background clipboard monitoring
- Notification history collection
- Sensitive data filtering before durable storage
- SQLite-based raw event storage
- Daily Markdown composition
- Cloud LLM summary generation
- Missed-day backfill and idempotent regeneration
- Minimal two-pane reader UI

### Out of Scope

- Cross-device sync
- Story push or weekly push notifications
- One-click Claude Code or OpenClaw export workflow
- Advanced search and analytics
- Rich knowledge graph UI
- Plugin-dependent architecture

## Core Product Shape

Know You V1 has two runtime surfaces:

1. A background service that captures events, filters them, stores them, and composes daily outputs
2. A desktop reader that lets the user browse dates and read the resulting Markdown

The core user-facing artifact is Markdown on disk. SQLite exists to support reliable capture, deduplication, replay, and backfill.

## UX Principles

- Minimal UI over feature density
- Markdown is the main reading surface
- Daily records are the primary navigation unit
- Trust comes from visible source structure plus privacy protection
- Failure states should be explicit, not hidden

## Primary User Experience

The main app window is intentionally simple:

- Left pane: date list
- Right pane: rendered Markdown for the selected day

The right pane shows four sections in the Markdown document:

- `Summary`
- `Timeline`
- `Clipboard`
- `Notifications`

The UI is intentionally quiet and document-like. V1 does not introduce dashboards, heavy metadata panes, or visual analytics.

## High-Level Architecture

### 1. Clipboard Watcher

Responsibilities:

- Observe clipboard changes from the macOS pasteboard in the background
- Normalize clipboard captures into event records
- Optionally import history from existing clipboard tools later, but do not depend on them for core functionality

Notes:

- Core clipboard history belongs to Know You itself
- Maccy or similar tools are examples, not platform dependencies

### 2. Notification Collector

Responsibilities:

- Read macOS notification history from the local notification store
- Attribute notifications with timestamp, source app, title, and body when available
- Support scheduled collection and replay for missed intervals

### 3. Normalization and Deduplication Layer

Responsibilities:

- Convert raw clipboard and notification captures into a common event schema
- Attach source type, source app, timestamps, and stable content hashes
- Prevent duplicate persistence during repeated runs or backfills

### 4. Privacy Filter

Responsibilities:

- Classify event payloads before any durable storage
- Decide whether to drop, redact, or keep content
- Emit a minimal audit marker when sensitive content is skipped

Important boundary:

No unfiltered raw secret should be written to SQLite or Markdown.

### 5. Event Store

Responsibilities:

- Persist filtered raw events
- Track run history
- Track per-day composition status
- Track backfill state
- Support idempotent regeneration of a day's output

Recommended implementation:

- Local SQLite database

### 6. Daily Composer

Responsibilities:

- Group one day's filtered events
- Build one canonical Markdown document for that date
- Preserve deterministic section structure
- Replace the prior version of the same day rather than append duplicates

### 7. Cloud Summary Job

Responsibilities:

- Send the composed daily context to a cloud LLM
- Generate a readable daily summary
- Insert or update the `Summary` section in the day's Markdown

This is cloud-first in V1. Summary quality is prioritized over local-model-only behavior.

### 8. Desktop Reader

Responsibilities:

- Show available dates
- Let the user switch between daily documents
- Render the Markdown content cleanly
- Surface system state clearly when capture or summarization failed

## Data Model

### Canonical Event Record

Each captured item should normalize into a common record with fields such as:

- `id`
- `source_type` such as `clipboard` or `notification`
- `source_app`
- `captured_at`
- `observed_at`
- `content_raw_filtered`
- `content_redacted`
- `privacy_action`
- `content_hash`
- `day_key`
- `run_id`

The exact table layout can evolve, but the system must preserve:

- source attribution
- time attribution
- privacy outcome
- dedupe capability
- day-level grouping

### Daily Output Record

Each day should have:

- one Markdown file on disk
- one database status record tracking composition and summary state

### Run History

Each scheduled or launch-triggered run should record:

- run type
- start time
- end time
- success or failure by subsystem
- missing days discovered
- days regenerated

## Privacy Model

The privacy model is explicit for `drop` and `redact`. All content not matched by those rules is implicitly kept.

### Drop

Content in this class is never durably stored in raw form. The system may store only a minimal audit line such as "sensitive clipboard item skipped."

Examples:

- passwords
- one-time passcodes
- API keys
- access tokens
- session cookies
- seed phrases
- private keys
- full payment card numbers

### Redact

Content in this class may be stored only in masked or summarized form.

Examples:

- bank account details
- transaction identifiers
- exact financial credentials
- partially sensitive identifiers that still carry timeline value

Everything not matched by `drop` or `redact` remains eligible for normal storage, including people names, company names, ordinary work notes, messages, drafts, and general life context.

## Capture and Persistence Lifecycle

### During the Day

- The clipboard watcher runs lightly in the background
- The notification collector performs scheduled reads
- Incoming items are normalized
- The privacy filter runs before durable persistence
- Filtered events are written into SQLite

### End-of-Day Generation

- The composer loads the filtered events for the date
- It generates the canonical Markdown structure
- The cloud summary job generates the summary section
- The final Markdown file is written or updated

### Backfill

If a day was missed because the app was closed, a job failed, or summarization was incomplete:

- the next launch or next scheduled run detects the missing or incomplete day
- Know You regenerates the day from available stored events
- the same Markdown file path is updated instead of creating duplicates

### Idempotency

The same day may be recomposed multiple times. The result must converge on one canonical file and one canonical day state.

## Daily Markdown Structure

Each day produces a single Markdown file with a predictable structure:

```md
# 2026-04-07

## Summary

[AI-generated summary for the day]

## Timeline

- [time] [short event line]
- [time] [short event line]

## Clipboard

- [clipboard item or redacted marker]

## Notifications

- [notification item or redacted marker]
```

Notes:

- The right pane in the UI should show this Markdown directly
- The structure is fixed for V1 to preserve trust and consistency
- If summary generation fails, the rest of the document still exists

## Onboarding

V1 onboarding should be short and operational:

1. Choose or confirm the local vault directory
2. Explain what clipboard and notification capture means
3. Request the required macOS permissions
4. Configure cloud LLM credentials

The onboarding should not pretend the product works when permissions are missing.

## System Status and Failure Handling

Failure states must be explicit in the UI.

### Capture Failures

Examples:

- notification store cannot be read
- clipboard watcher is not active

Handling:

- keep the app running
- mark the missing source clearly
- retry on next scheduled or launch-triggered run

### Summary Failures

Examples:

- invalid API key
- network timeout
- provider failure

Handling:

- still generate the Markdown file for the day
- leave the summary section empty or marked as pending
- allow later retry without rebuilding unrelated data

### Privacy Events

Handling:

- dropped items produce only minimal audit traces when needed
- redacted items enter storage only in masked form

## Distribution and Platform Constraints

V1 targets direct distribution outside the Mac App Store.

Reason:

- the product needs more flexible access to background execution, notification history, and local file control than an App Store-first approach comfortably allows

## Suggested Technical Direction

The exact framework choices can be finalized in implementation planning, but the design assumes:

- native macOS background capabilities
- local SQLite storage
- a desktop UI that can render Markdown cleanly
- a scheduler for daily generation and retry

Acceptable implementation shapes include:

- a native Swift or SwiftUI app with a helper/background component
- a desktop shell plus native helper for macOS-only capture

The architecture decision should favor macOS reliability over cross-platform convenience.

## Testing Strategy

V1 needs targeted tests in four areas:

### Privacy Filter Tests

Use fixtures covering:

- passwords
- OTP codes
- API keys
- payment card patterns
- financial transaction strings

Expected outcomes:

- drop or redact decisions are deterministic

### Composer Tests

Use fixed daily event fixtures to verify:

- Markdown structure is stable
- sections are ordered correctly
- rerunning the same day produces the same output shape

### Backfill Tests

Use missing-day fixtures to verify:

- incomplete days are discovered
- reruns repair the canonical file
- duplicates are not created

### Reader UI Tests

Verify:

- date selection updates the rendered Markdown
- missing summary or missing source states are surfaced clearly

## Open Follow-On Work After MVP

These are intentionally deferred:

- push notifications for weekly or recent-story recaps
- direct handoff into Claude Code or OpenClaw
- advanced search
- cross-device sync
- richer context visualizations

## Summary

Know You V1 is a standalone macOS memory product, not a plugin. It captures clipboard and notification context, filters sensitive information before persistence, stores reliable daily event history locally, and produces one canonical Markdown memory document per day. The desktop UI is intentionally minimal: dates on the left, Markdown on the right.
