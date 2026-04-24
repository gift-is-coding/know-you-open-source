# Onboarding Bootstrap Chunking Plan

1. Update `AppState` bootstrap completion accounting so onboarding completion only counts genuinely successful bootstrap days.
2. Add an onboarding-only refresh entry point that can opt into chunked full-recovery fallback while still reusing the shared refresh attempts, validation, persistence, and logging machinery.
3. When a bootstrap day exceeds `50` events, split it into chronological chunks:
   - first chunk via full recovery
   - remaining chunks via incremental append against the accumulated story
4. Persist each successful chunk immediately and preserve partial output on later failure.
5. Extend refresh log stage details to record chunk planning and per-chunk load/write progress.
6. Add focused tests for:
   - chunking above `50`
   - no chunking at `50`
   - partial-story preservation plus continuation to yesterday after a later chunk failure
7. Run focused verification, then rerun the isolated onboarding smoke flow against `/tmp/know-you-onboarding-smoke`.
