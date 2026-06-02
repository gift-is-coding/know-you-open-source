---
name: feature-launch-pipeline
description: Use when turning a newly implemented KnowYou feature, release note, demo, screenshot, or git diff into a repeatable launch campaign: channel-native copy, image/video briefs, publishing checklist, and cross-channel status tracking for X, LinkedIn, Product Hunt, Reddit, Dev.to, Hacker News, Indie Hackers, Chinese tech communities, newsletters, and future maintained channels.
---

# Feature Launch Pipeline

Create a repeatable launch package for each KnowYou feature instead of writing one-off posts.

## Inputs

Use the richest available source, in this order:

1. User-provided feature brief, release note, screenshots, demo video, or product page.
2. Relevant git diff, merged PR notes, issue/spec docs, or local implementation plan.
3. Existing product positioning from `docs/fundraising/private/founder-company-info.md`, `docs/fundraising/private/submission-status.md`, and `docs/investor-pitch/` when the user asks for founder/investor-facing framing.

Never expose private personal data in public marketing copy. Use product links, demo links, and public founder links only when the channel needs them.

## Project Files

- Channel registry: `docs/marketing/channels.json`
- Launch packages: `docs/marketing/launches/YYYY-MM-DD-feature-slug/`
- Scaffold script: `.agents/skills/feature-launch-pipeline/scripts/scaffold_launch.py`
- Platform guidance: `.agents/skills/feature-launch-pipeline/references/channel-playbook.md`

## Workflow

1. Identify the feature's real user-facing change:
   - What is newly possible?
   - Who cares first?
   - What proof can be shown?
   - What screenshot, GIF, demo clip, or diagram would make it obvious?

2. Create or update a launch package:

```bash
python3 .agents/skills/feature-launch-pipeline/scripts/scaffold_launch.py \
  --feature "MyWiki memory from messages and logs" \
  --date "$(date +%F)"
```

3. Fill the launch package:
   - `feature-brief.md`: source facts, user value, proof, constraints.
   - `campaign-plan.md`: audience, core angle, timeline, primary CTA.
   - `channel-drafts.md`: platform-native copy for each selected channel.
   - `asset-briefs.md`: image/video/carousel briefs and required sizes.
   - `publish-status.md`: URLs, accounts, blockers, and posted status.

4. Adapt per channel. Do not paste identical copy everywhere. Load `references/channel-playbook.md` when drafting channel-specific posts.

5. Publishing:
   - If the user asks only for drafts, do not post.
   - If the user asks to publish manually through websites, use Chrome / Computer Use and update `publish-status.md`.
   - Do not use APIs unless the user explicitly asks and credentials/config are already available.
   - Record every successful URL and every blocker.

## Output Shape

For each feature launch, produce:

- one clear launch angle
- 3-5 atomic ideas that can become separate posts
- image/video brief for each major channel
- drafts for selected channels
- posting order and status table
- privacy check

## Quality Gate

Before calling a package ready:

- The feature claim is grounded in the actual implementation or visible product behavior.
- No public copy includes private phone number, birthday, home address, internal logs, investor notes, or raw personal context.
- Each platform version sounds native to that platform.
- The CTA is small and concrete.
- Visual assets show the feature, not abstract AI art.
- `publish-status.md` has a row for every selected channel.
