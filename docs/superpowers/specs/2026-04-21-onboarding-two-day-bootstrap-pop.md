# Onboarding Two-Day Bootstrap Pop

## Goal

After onboarding completes, Know You should automatically start generating only today and yesterday, immediately show both dates in the sidebar as placeholders, and surface a light non-blocking reminder that the first entries are still generating.

## Requirements

- The onboarding bootstrap window must shrink from 7 days to 2 days: today and yesterday.
- The bootstrap must still run once per user onboarding completion and must not repeat on later launches after success.
- Today should refresh before yesterday during onboarding bootstrap, and yesterday should still be attempted even if today fails.
- The sidebar must show today and yesterday immediately, even before the Markdown/story files finish writing.
- The product must show a non-blocking pop in the real main window after onboarding completes.
- The pop must explain that today and yesterday are generating now and suggest coming back in about 2 minutes.
- Existing successful content for either day must be skipped instead of regenerated.

## Non-Goals

- No blocking modal
- No detailed progress tracker for bootstrap
- No new global toast system
