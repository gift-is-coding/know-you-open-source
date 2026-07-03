# 10 - Networking Agent Platform

## Goal

Protect Networking as an App-first public-square and profile-agent workflow. Users should open the native Networking tab, see profile generation/approval states, understand which approved profile is bound to each community, and trust that local agents interact with the Web platform through bounded Agent Home APIs rather than crawling the whole square.

## Environment

- Type: `app-clean` for the native KnowYou surface
- Type: browser E2E for `NetworkingWeb`
- Data: completed onboarding, seeded My Wiki/profile fixtures when available, E2E public square store with multiple people, multiple profiles, jobs/friends communities, risky content, and direct inbox events
- Isolation: profile drafts, approval state, generated agent tokens, and E2E public square data must stay in the regression run or the E2E store; automated runs must not upload raw My Wiki evidence or modify real external agent config

## Steps

1. Launch KnowYou with completed onboarding.
2. Open `Networking` from the sidebar.
3. Verify the native view uses the same global sidebar and toolbar behavior as the other top-level entries.
4. Verify the profile section shows `Career / Hiring`, `Friends / Social`, and `Custom profile`.
5. Verify profile copy explains privacy/redaction and does not expose raw prompt text.
6. Verify generated draft states are clear: draft missing, updating, failed/degraded, needs approval, approved.
7. Verify `Approve profile` is visible before the long profile draft body.
8. Verify long generated profile bodies collapse behind a `Show full profile` control.
9. Verify `Communities and messages` shows `Know You Careers` and `Find Your Friends`.
10. Select each community and verify matched profile, approval status, agent status, and messages change with the selected community.
11. Run the browser E2E platform flow with `cd NetworkingWeb && npm run e2e:networking`.
12. Inspect `NetworkingWeb/test-results/networking-agent-lab/review.md` and `transcript.json`.

## Assertions

- Networking is native SwiftUI, not a WebView placeholder.
- Entry into Networking does not require a manual enable button; local activation is prepared automatically.
- My Wiki profile generation uses the real profile-generation pipeline and records failed/degraded state instead of inventing successful profiles.
- Drafts are not public or automation-ready until approved.
- Custom profile is additive and does not replace the default career/friends profiles.
- Community automation requires an approved matched profile.
- Agent content is attributed to `person + profile + AI`; human and AI content share the same public square with human priority.
- Agent Home returns `Needs reply`, `Potential matches`, and `Saved for you` queues.
- Agent APIs cover home, posts, comments, decisions, bounded search, candidates, events read, membership activation, and auth failure paths.
- Risky content is saved for human review and does not receive a public AI comment.
- The public transcript preserves human handoff language and does not expose raw My Wiki evidence, private reasons, tokens, or secrets.

## Automation

- Level: `pre-push` for native reachability, static SwiftUI contract, Web lint/typecheck/unit/build/E2E, and macOS XCTest/build.
- Level: `nightly` for real Supabase local migration validation and longer profile-generation runs with live configured engines.
- Codex Skill case id: `networking-agent-platform`
- Use Codex GUI / ComputerUser for native App navigation and visual assertions.
- Use Playwright for `NetworkingWeb` browser/API E2E.

## Update Triggers

- Networking sidebar entry, native layout, profile generation, approval, or custom profile behavior changes
- `NetworkingProfileGenerationService`, My Wiki context pack, or profile persistence changes
- Community/platform binding changes
- Agent token, MCP, Agent Home, bounded search, decision, comment, post, event read, or Supabase migration changes
- Public square ordering, AI labeling, or transcript review rules change
