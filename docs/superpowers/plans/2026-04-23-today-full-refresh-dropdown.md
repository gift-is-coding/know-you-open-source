# Plan: Today Full Refresh Dropdown

1. Add a selected-day full refresh entry point in `AppState`.
2. Generalize the onboarding-only chunked full refresh helper so it can also serve forced reader full refresh.
3. Add the dropdown chevron beside the formal refresh button and wire it to the new `AppState` action.
4. Add focused tests covering:
   - forced full refresh despite an existing model story
   - `50`-event chunking for full refresh
   - `50`-event chunking for large ordinary manual incremental refreshes
   - historical selected-day behavior
5. Update requirements, architecture, and verify with targeted tests plus a fresh macOS build.
