# Spec: Day Refresh And Background Sync

**Date:** 2026-04-11  
**Branch:** llm-channel-validation-and-connectivity  
**Status:** Draft

---

## Problem

The current "refresh selected day" behavior is doing too much work under one UI action.

Today-refresh currently reuses the automation pipeline, which means one click can:

- import notifications
- compute pending backfill days
- regenerate more than one date
- spend token and time on work the user did not ask for

This creates two product failures:

1. The refresh button feels unreliable because it can spin for a long time without making it clear whether it is refreshing the selected day, importing sources, or backfilling historical dates.
2. The refresh scope is inconsistent with user intent. When the user refreshes one day, they expect only that day to be refreshed.

There is a second issue in the engine experience:

- onboarding still exposes a default engine picker
- the main-window selector reads the same persisted config
- but when the active default is `None`, the app does not automatically choose a verified green engine

The product needs a cleaner model:

- background capture is responsible for lightweight source ingestion
- manual refresh is responsible for regenerating only the selected day
- notification backfill should be bounded to the selected day, never previous days
- default engine selection should honor explicit user choice, but avoid staying on `None` when a verified engine exists

---

## Goals

1. Make the refresh button act only on the currently selected day.
2. Remove historical backfill from the manual refresh path.
3. Allow notification import to be refreshed for the selected day before generation, because notification data can be recovered from the local macOS database.
4. Keep clipboard capture as a background-only source and avoid implying that historical clipboard data can be reconstructed on demand.
5. Make background notification ingestion frequent enough that "today" stays close to current without requiring manual automation runs.
6. Auto-select the highest-priority verified engine when the current default is `None`, while preserving any explicit non-`None` user choice.

## Non-Goals

- Building a new multi-source sync center UI
- Reconstructing historical clipboard contents after the app was not running
- Backfilling multiple historical days from a single refresh click
- Changing the five-step onboarding flow itself
- Replacing the existing fallback story generation path

---

## Approaches Considered

### Approach A: Keep refresh tied to the automation pipeline

The selected-day refresh button continues to call the same path used by startup and periodic automation.

Trade-offs:

- Lowest implementation cost
- Keeps source import and generation in one place
- Wrong product semantics because refreshing one day can still trigger unrelated work
- Preserves the current "long spinner, unclear progress" failure mode

### Approach B: Separate manual day refresh from background automation

Manual refresh becomes a day-scoped flow. Background automation continues to ingest sources on its own schedule.

Trade-offs:

- Matches user intent and creates stable button semantics
- Makes performance more predictable
- Requires a clearer split between "ingest source data" and "generate day note"
- Needs day-window notification sync logic instead of reusing global automation

### Approach C: Keep refresh mixed, but only limit backfill count

This would still allow refresh to import sources and possibly touch automation behavior, but with tighter limits.

Trade-offs:

- Smaller change than a true separation
- Still mixes responsibilities in one UI action
- Leaves product semantics fuzzy and harder to reason about

### Recommendation

Choose **Approach B**.

The user action should be explicit and narrow:

- refresh one selected day
- optionally pull recoverable notifications for that same day
- regenerate only that same day

Background source ingestion should remain active independently and should not be smuggled inside a manual refresh for unrelated dates.

---

## Design

### 1. Manual Refresh Scope

The main-window refresh button and menu bar "Refresh Selected Day" action must always target only the currently selected day.

Hard rules:

- Never backfill earlier dates from a manual refresh action
- Never regenerate more than the selected day
- Never reuse the multi-day automation planner during manual refresh

Selected-day semantics:

- If the selected day is today, refresh only today
- If the selected day is historical, refresh only that historical day
- If no day is selected, default to today and refresh only today

### 2. Source Sync Behavior During Manual Refresh

Manual refresh should not attempt to perform a full source ingestion pass.

Instead, it should use source-specific rules.

#### Notification

Notification data is recoverable from the local macOS Notification Center database, so manual refresh may sync notifications for the selected day before generation.

Rules:

- For the selected day, read notifications only within that day's time window
- Today uses `todayStart ... now`
- Historical days use `dayStart ... nextDayStart`
- Do not sync notifications outside the selected day's window
- Do not backfill adjacent or earlier days as part of this action

This keeps refresh semantics consistent:

"Refresh this day" means "bring in recoverable notifications for this day, then regenerate this day."

#### Clipboard

Clipboard capture should remain background-only.

Rules:

- Manual refresh must not claim to recover clipboard entries that were missed while the app was not running
- Manual refresh should use whatever clipboard events for that day already exist in the local database
- The product should treat clipboard as real-time capture, not replayable historical sync

This is an intentional asymmetry:

- notification is queryable from a persistent system database
- clipboard is not reliably reconstructable after the fact

### 3. Refresh Execution Order

The selected-day refresh flow should run in this order:

1. resolve selected day
2. import notification records for that day window
3. read events for that day from the app database
4. generate the day story and markdown
5. update UI state and status messaging

This order avoids conflict between source sync and generation while keeping the work bounded to one date.

### 4. Background Ingestion Model

Manual refresh should no longer be the main way source data enters the system.

#### Clipboard Background Capture

Keep the existing clipboard watcher behavior:

- active while the app is running
- lightweight polling
- immediate database writes
- duplicate resistance through existing content hashing

#### Notification Background Capture

Notification capture should become a higher-frequency incremental background process.

Rules:

- run every 30 seconds while the app is active
- use incremental import windows rather than full rescans
- retain a small overlap buffer to avoid missing late-written records
- rely on strong deduplication so overlap does not create duplicates

This creates "eventual consistency" for today without requiring the user to run a heavy refresh action.

### 5. Notification Cold-Start Recovery

When the app launches after being closed for part of the day, today's earlier notifications may be missing from the local event store.

The app should recover those notifications on startup.

Rules:

- on cold start, import notifications from today's start until now
- once that import succeeds, persist the last successful notification import timestamp
- subsequent 30-second background imports should use an incremental window bounded by `max(todayStart, lastSuccessfulImportAt - overlapBuffer)`
- if the selected day is historical and the user explicitly refreshes it, import notifications for that historical day window before generation

This gives the product two recovery modes:

- automatic recovery for today during startup
- explicit day-window recovery for a historical day when the user refreshes that day

### 6. Deduplication Requirements

Higher-frequency notification scanning is only acceptable if duplicate insertion is strongly prevented.

The system should treat notification ingestion as idempotent.

Requirements:

- overlapping notification scans must not create duplicate event rows
- repeated manual refresh of the same historical day must not create duplicate notification events
- startup recovery plus background scanning must not create duplicate notification events

Implementation may use any combination of:

- unique database constraint
- insert-or-ignore behavior
- stable content hash and day-window matching

The final design requirement is behavioral, not tool-specific:

"Repeated scans over the same notification should converge to one stored event."

### 7. Refresh UI And Status Messaging

The refresh UI should reflect one bounded day refresh rather than an unbounded automation run.

Requirements:

- spinner lifetime should cover only the selected-day refresh flow
- completion message should mention the selected day
- failure message should identify whether refresh failed during notification sync or generation
- fallback generation should remain visible in status text when the model path is unavailable or invalid

Examples:

- `Refreshed 2026-04-11 with story view`
- `Refreshed 2026-04-11 with local story fallback`
- `Refreshed 2026-04-08 after syncing notifications`
- `Refresh failed for 2026-04-08: Notification Center database not readable`

### 8. Default Engine Auto-Selection

Onboarding and the main-window selector should continue to use the same persisted `defaultEngine`.

The app should preserve explicit user choice, but should not stay on `None` if a verified engine is available.

Rules:

- If `defaultEngine != .none`, never auto-replace it just because another green engine exists
- If `defaultEngine == .none`, automatically choose the highest-priority green engine
- Persist that selected engine to the shared summarizer config
- Use the same persisted value across onboarding, app restart, and main-window selector

Recommended priority order:

1. Claude CLI
2. Codex CLI
3. Gemini CLI
4. Openclaw CLI
5. OpenAI

This order can be implemented as a static product preference and should not depend on scan completion order.

### 9. Onboarding Relationship

The onboarding "Default engine" picker remains valid.

Behavior rules:

- If onboarding finishes with a concrete non-`None` engine, preserve that choice
- If onboarding finishes with `None`, the main app may later auto-select a green engine using the rule above
- The product must not maintain separate onboarding-only and main-window-only engine defaults

This keeps the mental model simple:

there is one default engine setting, shared across the app

---

## Testing

### Unit Tests

Add or update tests for:

- manual refresh of today only touching today
- manual refresh of a historical day only touching that historical day
- manual refresh no longer invoking multi-day automation behavior
- day-window notification import for both today and historical dates
- startup recovery importing today's earlier notifications
- 30-second notification incremental scans remaining idempotent
- `defaultEngine == .none` auto-selecting the highest-priority green engine
- explicit non-`None` engine choice never being auto-overridden

### Integration Tests

Verify:

- refresh spinner ends when the selected-day pipeline finishes
- repeated historical refresh does not duplicate notification events
- app relaunch preserves engine selection and notification import bookkeeping

### Manual Verification

Verify on a real macOS environment:

- startup after a closed morning session pulls today's earlier notifications
- refreshing a historical day imports only that day's notifications
- refreshing one day does not regenerate neighboring days
- clipboard captures continue arriving without using the refresh button
- when default engine is `None` and multiple engines are green, the highest-priority green engine is chosen automatically

---

## Open Questions Resolved

- Manual refresh should never backfill earlier dates: resolved
- Historical dates may sync notifications for that selected day only: resolved
- Clipboard should not promise historical recovery: resolved
- Notification background sync frequency should be 30 seconds: resolved
- Cold start should recover today's earlier notifications: resolved
- Auto-selection should only happen when the current default is `None`: resolved

