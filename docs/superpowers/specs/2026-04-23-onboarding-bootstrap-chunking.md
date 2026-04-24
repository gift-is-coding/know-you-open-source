# Onboarding Bootstrap Chunking

## Goal

Keep the first-run onboarding bootstrap lightweight enough to finish on heavy event days without changing steady-state manual or automation refresh behavior.

## Requirements

- The onboarding bootstrap scope remains exactly two days: today and yesterday.
- Day order remains serial: today first, then yesterday.
- Chunking applies to onboarding bootstrap, forced full refresh, and large incremental refreshes through the shared AppState refresh batching constant.
- If a bootstrap day has more than `50` events after notification sync, the app must:
  - generate the first `50` events with full recovery
  - append the remaining events in chronological chunks of at most `50` using incremental updates
- Days at `50` events or fewer must continue to use a single full recovery call.
- Chunk execution inside a day must remain serial.
- A failed later chunk must keep already-persisted partial story/markdown output.
- A partially generated day must not count as a fully successful bootstrap day for the completion notification.
- Refresh logs must include chunk progress details without changing the log schema.

## Non-Goals

- No event-count cap beyond the per-call batch size; all events should still be processed in order.
- No new user setting for chunk size.
