# Manual Refresh Parallel Fallback And Read-Path Safety

## Overview

The refresh system already distinguishes `fullRecovery` from `incrementalUpdate`, but two behaviors remain unacceptable:

- opening the app or selecting a date can still rewrite existing journal artifacts through legacy migration logic
- manual refresh retries can fail too early or wait unnecessarily because fallback engines are tried one by one

This pass removes read-path writes and tightens manual refresh behavior without changing the automation policy.

## Product Decisions

- Loading an existing story must never rewrite `.story.json` or `.md`
- Legacy single-paragraph `# Details` content remains readable as-is
- New successful `fullRecovery` output must still be normalized before writing so fresh artifacts use paragraph-level Details workstreams
- Manual refresh must try the default engine first
- If the default engine fails, the app must race the remaining green engines in parallel
- The first successful structured result wins; all other in-flight manual fallback attempts should be cancelled
- Automation remains today-only and single-engine

## Acceptance Criteria

- App launch does not migrate legacy stories across the vault
- Selecting a historical day does not rewrite existing files
- `fullRecovery` uses the global prompt override when present
- `fullRecovery` normalizes parsed story structure before persisting
- Manual refresh tries the default engine first
- After a default-engine failure, remaining green engines run in parallel
- When one fallback engine succeeds, losing engines are cancelled
- Failed manual refreshes do not overwrite existing `.md` or `.story.json`
