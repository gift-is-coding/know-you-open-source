# Onboarding Rebuild from `ea0ae05`

## Summary

Use `ea0ae05` as the clean recovery baseline and reintroduce onboarding with the smallest possible surface area. Preserve the dev-era product shell and only add the onboarding-specific hooks needed for Demo Day, coachmarks, progress restoration, Demo Day post-onboarding placement, and one-time 7-day bootstrap generation.

## Steps

1. Restore the clean baseline shape
   - Keep `Settings`, support/community docs, update UI, sync memory, refresh surfaces, and engine selector behavior from `ea0ae05`.
   - Confirm the rebuild branch does not inherit the reduced settings/support layout from the prior merge result.

2. Port onboarding content and presentation
   - Bring over the current approved onboarding copy and Demo Day dataset.
   - Rebuild `OnboardingView` so it overlays the real `MainWindowView` and uses anchor-based coachmarks.
   - Keep the approved progression: story read -> story click -> references -> privacy -> permissions -> engine prompt -> engine setup -> generating.

3. Add minimal product hooks
   - Add only the onboarding callbacks/anchors needed in `MainWindowView`, `DailyMarkdownView`, and `DateSidebarView`.
   - Keep the existing shell, toolbar placement, settings access, sync memory access, update pill placement, and refresh UI intact.

4. Rebuild onboarding state in `AppState`
   - Persist onboarding progress separately from normal automation.
   - Keep Demo Day visible during onboarding and pinned to the bottom after completion.
   - Add one-time 7-day bootstrap generation after onboarding finishes.
   - Avoid rewriting unrelated steady-state automation behavior beyond what is needed for the onboarding bootstrap separation.

5. Fold in probe/review fixes cleanly
   - Re-add omitted test files to the Xcode project.
   - Add common executable directory fallbacks for CLI tool lookup.
   - Collapse probe logic to a single implementation.
   - Make API probe success mean `2xx + non-empty text`.

## Tests

- Add/update tests for:
  - onboarding step progression and restoration
  - Demo Day bottom ordering after onboarding
  - one-time 7-day bootstrap behavior
  - engine probe non-empty text success
  - executable fallback directory resolution
  - settings/community/support metadata still present

- Run:
  - targeted onboarding/probe/settings slices during implementation
  - `xcodebuild test -scheme KnowYou -destination 'platform=macOS'`
  - `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`

- Finish with a manual smoke pass covering:
  - Settings -> About & Community -> Community Guide -> #feedback
  - update pill
  - sync memory
  - refresh flow
  - engine selector / API configuration
  - onboarding end-to-end

## Assumptions

- `ea0ae05` is the correct recovery baseline.
- Current approved onboarding behavior is the desired end state, not the older pre-demo onboarding.
- Demo Day remains in the product after onboarding and is not deleted.
