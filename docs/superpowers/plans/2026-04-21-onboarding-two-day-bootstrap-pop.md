# Plan: Onboarding Two-Day Bootstrap Pop

## Summary

Reduce onboarding bootstrap from 7 days to 2 days, run those two refreshes serially during onboarding, keep sidebar placeholders, and add a lightweight non-blocking pop in the main window.

## Implementation

1. Update `AppState` onboarding bootstrap behavior.
   - Return only today and yesterday from the bootstrap day helper.
   - Launch missing bootstrap days serially in day order.
   - Keep going to yesterday even if today fails.
   - Preserve placeholder dates in the sidebar until bootstrap completes.
   - Add a tiny onboarding bootstrap notice state plus dismiss helpers.

2. Update UI entry points.
   - Render the lightweight pop from `MainWindowView` as a top overlay.
   - Keep the pop dismissible and auto-hide after a short delay.
   - Refresh onboarding copy so it no longer references “last 7 days” or a single first diary.

3. Add regression coverage.
   - Assert onboarding queues only two days.
   - Assert the notice message is exposed after onboarding completion.
   - Assert bootstrap starts today first and only starts yesterday after today finishes.
   - Assert a failed today refresh still allows yesterday to run.
   - Assert an already-existing day is skipped.

4. Sync docs.
   - Update `docs/requirements-spec.md`
   - Update `docs/architecture.md`

## Verification

- Focused XCTest slices for onboarding copy, onboarding progress, bootstrap serialization, and pop presentation
- `xcodebuild test -scheme KnowYou -destination 'platform=macOS'`
- `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`
