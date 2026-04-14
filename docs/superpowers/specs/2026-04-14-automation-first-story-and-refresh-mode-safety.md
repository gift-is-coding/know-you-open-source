# Automation First Story And Refresh Mode Safety

## Summary

This change tightens the journal refresh policy in four places:

- today automation may create the first story of the day when a verified engine exists
- missing / unverified engines surface an explicit configuration prompt instead of silently doing nothing
- refresh mode resolution no longer treats story load failures as “missing story”
- refresh log write failures stay non-fatal but become visible in the reader UI

## Product Decisions

- Automation remains today-only.
- If today already has a `model` story, automation uses incremental update.
- If today has no successful `model` story and a verified engine exists, automation runs a full recovery for today.
- If today has no successful `model` story and no verified engine exists, automation does not write fallback content; it prompts the user to configure and verify an engine.
- If an existing `.story.json` cannot be loaded, refresh fails with a visible error instead of silently switching to `fullRecovery`.
- Refresh log persistence remains best-effort, but log write failure must be surfaced as a low-key notice near the refresh affordance.
- Global diary prompt overrides must be trimmed before persistence.

## Acceptance Criteria

- A fresh day with events and a verified engine can be produced by automation without manual refresh.
- A fresh day without a verified engine leaves content unchanged and shows a configuration reminder.
- A malformed or unreadable existing `.story.json` causes refresh failure rather than a mistaken full regeneration.
- Manual full recovery without a verified engine preserves existing files and tells the user to configure and verify an engine.
- Prompt overrides drop leading and trailing whitespace before being stored.
- Refresh log write failures do not break the refresh itself, but the selected day shows a subtle “Refresh log unavailable” notice.
