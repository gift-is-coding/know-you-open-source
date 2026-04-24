# Today Full Refresh Dropdown

## Goal

Add a small dropdown next to the formal reader refresh button so users can explicitly force a full refresh for the currently selected real day, even when a successful story already exists.

## Requirements

- The reader header must keep the existing refresh button and add a small triangle dropdown beside it.
- The dropdown must render with only one visible triangle indicator.
- The dropdown must contain one English action:
  - `Full Refresh Today (Overwriting)` when today is selected
- The dropdown action must be available for any selected real day, including historical dates.
- The dropdown action must stay unavailable for `Demo Day`.
- Triggering the action must ignore the normal incremental/full-recovery auto decision and force a full refresh for the selected day.
- If the selected day's event count exceeds `50`, the forced full refresh must reuse the same chunking strategy as onboarding bootstrap:
  - first `50` events use full recovery
  - later batches append incrementally in batches of at most `50`
- Partial chunk progress must still persist after each successful chunk.
- Ordinary manual incremental refresh must also split more than `50` new events into sequential incremental chunks.

## Notes

- This is intentionally a light UI addition, not a new refresh mode picker.
- Today keeps the more explicit label, while historical days may show a generic full refresh label.
