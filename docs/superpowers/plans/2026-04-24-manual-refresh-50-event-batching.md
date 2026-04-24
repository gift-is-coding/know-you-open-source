# Plan: Manual Refresh 50 Event Batching

1. Change the shared AppState refresh batch constant from `100` to `50`.
2. Route large ordinary incremental refreshes through a chunked helper that reuses the existing incremental composer, summarizer validation, persistence, and refresh log structures.
3. Keep forced full refresh overwrite semantics while applying the smaller `50` event chunk size.
4. Keep onboarding bootstrap serial by day and serial by chunk, now using the same `50` event size.
5. Add focused tests for `205 -> 50 + 50 + 50 + 50 + 5`, ordinary incremental `133 -> 50 + 50 + 33`, and partial persistence when a later incremental chunk fails.
6. Update requirements and architecture docs, then verify with focused XCTest slices and a fresh macOS build.
