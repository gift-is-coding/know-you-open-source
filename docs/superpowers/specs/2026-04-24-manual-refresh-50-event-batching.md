# Manual Refresh 50 Event Batching

## Goal

Make manual refresh reliability match the smaller payload shape of background incremental refreshes by limiting each LLM refresh call to at most 50 fresh events.

## Requirements

- Use one shared internal refresh batch size of `50`.
- Onboarding bootstrap and forced full refresh must use the shared size: first chunk full recovery, later chunks incremental append.
- Ordinary incremental refresh must keep its existing mode decision, but if `newEvents.count > 50`, it must split the new events into chronological chunks of at most `50`.
- Each incremental chunk must persist story and Markdown immediately after success.
- If a later chunk fails, the job must be marked failed, refresh logs must identify the failed chunk, and previously persisted partial output must remain.
- UI refresh status should show chunk progress such as `Appending chunk 2/8 with 50 event(s)...`.
- The database event store, source notes, and fallback story behavior must not be altered by chunking; prompt-only event text truncation remains a separate 100-character composer budget.

## Non-Goals

- No user-facing batch-size setting.
- No prompt compression change in this pass.
- No manual retry or timeout policy change.
