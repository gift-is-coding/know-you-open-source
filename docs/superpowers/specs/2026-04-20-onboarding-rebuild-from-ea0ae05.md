# Rebuild Onboarding from `ea0ae05`

## Summary

Rebuild the in-app onboarding flow on top of commit `ea0ae05`, preserving the product shell and settings/community structure that existed before the onboarding/main merge. Reintroduce only the onboarding-specific behavior from the later feature work: Demo Day inside the real reader, coachmark overlays, state restoration, Demo Day persistence at the bottom of the list, and one-time 7-day bootstrap generation after onboarding completes.

The rebuild must preserve existing dev-era behavior already present in `ea0ae05`, especially:

- `Settings -> About & Community -> Community Guide -> #feedback`
- update pill and update sheet
- sync memory menu/panel
- existing engine selector and API configuration flow
- refresh progress and refresh log behavior

It must also keep the PR review fixes:

- missing tests re-added to `KnowYouTests`
- CLI executable detection searches common install directories
- API probe accepts `2xx + non-empty text`
- only one active `EngineProbe` implementation remains in the target

## Product Decisions

- `Feedback` remains part of the existing community/settings structure and is not added as a new first-level menu item.
- Onboarding stays fully inside the real product shell rather than a standalone welcome flow.
- Demo data remains available after onboarding as `Demo Day`, always sorted at the bottom of the left journal list.
- Onboarding completion auto-starts a one-time bootstrap for the last 7 calendar days including today.
- API probe success means the endpoint is reachable and returns non-empty text. It does not require `OK/Okay`.

## Implementation Boundaries

### Keep from `ea0ae05`

- current main window shell and toolbar layout
- settings content, including About & Community
- update surfaces
- sync memory surfaces
- refresh behavior and diagnostics
- existing engine selector and API settings flow

### Port from later onboarding work

- `OnboardingContent`
- `OnboardingDemoStory`
- `OnboardingView`
- coachmark anchor preferences / overlay flow
- onboarding progress persistence and restoration
- Demo Day injection and bottom ordering
- onboarding-only 7-day bootstrap state and generation flow

### Do not carry over wholesale

- reduced/reframed `SettingsView`
- onboarding-specific toolbar/shell rewrites
- unrelated `AppState` automation rewrites
- duplicated probe implementations
- any emergency cleanup specific to the prior incorrect merge result

## Validation Requirements

- `Settings` still exposes `About & Community`
- `Community Guide` still includes `#feedback`
- update pill still appears when an update offer exists
- sync memory entry still opens from the sidebar gear/menu
- engine selector and API configuration still work
- Demo Day appears inside the real reader during onboarding
- coachmark sequence matches the approved flow
- Demo Day stays at the bottom after onboarding
- onboarding completion seeds and generates the past 7 days once
- all restored and newly added tests run inside `KnowYouTests`
