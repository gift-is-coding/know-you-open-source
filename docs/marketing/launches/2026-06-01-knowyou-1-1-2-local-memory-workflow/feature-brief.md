# KnowYou 1.1.2 Local Memory Workflow Feature Brief

Date: 2026-06-01
Slug: `knowyou-1-1-2-local-memory-workflow`

## Source

- Recent repo changes: onboarding history bootstrap, Applications install gate before Full Disk Access, Diary Engine recovery nudge, release regression assets, update feed alignment.
- Product docs: `README.md`, `docs/architecture.md`, `docs/requirements-spec.md`.
- Download URL: `https://giiift.site/know-you/`
- Demo URL: `https://www.youtube.com/watch?v=UiaAVBtqBx0`

## What Shipped

- A real first-run experience on top of the actual three-pane reader, not a disconnected welcome screen.
- Demo Day onboarding: users can click a story paragraph and immediately see the source evidence on the right.
- First 3 days bootstrap: after setup, KnowYou generates recent daily memory from available local history on the Mac.
- Local privacy promise is now explicit in setup: local Markdown, no KnowYou backend server.
- Applications install gate before Full Disk Access: users are guided to run KnowYou from `/Applications` before macOS privacy permissions are granted.
- Diary Engine recovery nudge: if no engine is selected or the selected engine is unhealthy, the toolbar asks the user to add/fix the engine instead of silently failing.
- Usable daily workflow surface: diary, source-linked evidence, Todo inbox, Other Source, My Wiki, update entry, and engine status.

## User Pain

People who use AI coding agents every day still repeat themselves constantly:

- "Here is what I worked on yesterday."
- "This is why I made that product decision."
- "This bug came from that Slack thread / terminal log / note."
- "Use this project context before touching the code."

The context exists, but it is scattered across notifications, clipboard snippets, Markdown files, terminal logs, notes, and app activity. The user has to manually reconstruct it.

## User Value

After this release, the first useful moment arrives much earlier:

- A new user can understand the product by reading a real source-linked diary.
- They can verify every memory through the source panel instead of trusting a black-box summary.
- They can start from their recent 3 days rather than an empty app.
- They get a visible nudge when the AI diary engine needs setup or repair.
- Their memory stays local and portable as Markdown.
- Their future AI agents get better context without the user retyping the same background.

## Proof

- Onboarding flow and content exist in `KnowYou/UI/Onboarding/OnboardingContent.swift`.
- Architecture documents describe Demo Day, source-linked reader, local Markdown, 3-day bootstrap, Full Disk Access guidance, and engine setup.
- `DiaryEngineRecoveryNudgePresentation` was added under reader/engine UI.
- Regression assets now cover onboarding, diary reader refresh, Todo, Other Source, My Wiki, engine settings, reminders, and release gate.
- Generated launch images saved under `assets/`.

## Constraints

- Do not claim full autonomous agent memory for every external tool yet.
- Do not imply cloud sync or server processing; the public claim should be local-first and Mac-local.
- Do not publish real diary/source screenshots unless redacted.
- Do not expose private founder info, investor application status, or local file paths in public copy.

## Core Launch Angle

KnowYou turns the scattered context on your Mac into a local, source-linked memory that you can read at night and hand to AI agents later.
