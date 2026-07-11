# Networking Stateful Falcon — Fix Round Spec

Date: 2026-07-09
Branch: codex/networking-community-bootstrap (continue on this branch)
Source: Claude code review of the staged Stateful Falcon diff + live UX walkthrough on the fresh dev server.
Scope: 2 Critical + 5 Suggestions from review, plus UX findings. Grouped by priority. P0 blocks merge.

---

## P0 — must fix before merge

### C1 Stale activation.json permanently wedges the cockpit (App)

Problem: `ensureActivationState()` (KnowYou/UI/Networking/NetworkingCockpitView.swift, ~line 403) early-returns
`ready` for ANY stored state with `isEnabled == true` — including last round's `localSandbox` states
(supabaseURL `local.knowyou.invalid`) and platform states without `authEmail`. Those users can never
Open Square and the inbox polls a fake host, with no recovery path in the UI.

Design:
- Tighten the early-return condition to:
  `state.isEnabled && state.isPlatformConnected && state.authEmail != nil && state.authPassword != nil`.
- Anything else is stale: fall through to re-activation. On success overwrite activation.json; on failure
  keep the old file and show a retryable error.
- Apply the same acceptance check in `NetworkingMCPCommand.connectedContext` (reject sandbox states).

Acceptance:
- Unit: (a) seeded localSandbox state file → ensure triggers activation (inject mock runner, assert called);
  (b) seeded full platform state with authEmail → ready immediately, no re-activation.
- Manual: drop an old sandbox activation.json into `.knowyou/networking/` → open cockpit → status goes
  Preparing → ready; file now has `mode=platform` + `authEmail`; Open Square is enabled.

### C2 Square shows a random member's identity as "yours" (Web)

Problem: `getAgentHomePreview()` (NetworkingWeb/src/lib/networking/supabase-data.ts, ~line 380) picks an
ARBITRARY active membership (`.eq("status","active").limit(1)`) with no viewer filter. The right rail then
renders "PROFILE IN THIS COMMUNITY: <someone else>" and "IN YOUR KNOWYOU APP: N needs reply / N matches"
to every visitor, including anonymous ones. Verified live: signed-out visitor sees Mina Park's queue.

Design:
- Make it viewer-scoped: `supabase.auth.getUser()` first; no user → return null (AgentHomePanel already has
  the correct signed-out empty state). With a user → resolve own person row by `user_id`, then membership
  filtered by `person_id` + `community_id`.
- Same treatment for the top profile strip and the right-rail "Profile in this community" card: show the
  signed-in viewer's own published profiles; signed-out → onboarding empty card.

Acceptance:
- Incognito visit `/`: no other person's name anywhere in the rail, no "IN YOUR KNOWYOU APP" counts,
  onboarding empty card visible.
- After App handoff sign-in: rail shows own handle and own queue counts.
- New contract test: `getAgentHomePreview` source must contain `auth.getUser` and a `person_id` filter on
  the membership query; must NOT contain the unfiltered `.eq("status", "active")` + `.limit(1)` pattern.

### UX1 Signed-out composer is a silent trap (Web)

Problem: anonymous visitors get a fully enabled composer; submitting runs
`redirect("/auth?status=signin-required")` — typed content is lost and neither `/` nor `/auth` renders
any `?status=` feedback. Same for `/?status=profile-required`.

Design:
- `SquarePanel` resolves viewer auth state server-side. Signed out: do not render the composer form or
  Reply inputs; render a guidance card instead ("Profiles are generated in the KnowYou App. Open a square
  from the App to sign this browser in." + link to `/auth`).
- Signed in but no profile bound to this platform: hint to approve the matching scenario profile in the App.
- Add a small status banner on `/` and `/auth` for `?status=signin-required` and `?status=profile-required`.

Acceptance:
- Signed out: no interactive Post/Reply controls on the page; guidance card present.
- Signed in: composer enabled, profile select lists only own profiles bound to that platform; a submitted
  post appears in the feed.
- Opening `/?status=profile-required` shows the banner text.

---

## P1 — fix in this round

### S1 Signup-failure fallback can never succeed (App)

Problem: `NetworkingActivationRunner.activate()` generates fresh random credentials, and on signUp failure
falls back to signIn with those same never-registered credentials — dead code that buries the real error.

Design:
- Before generating credentials, read the previous state's `authEmail`/`authPassword`; if present, signIn
  directly (idempotent re-activation — this is also the migration path for C1).
- Only generate + signUp when no stored credentials exist. Remove the signup→signin fallback; surface the
  signup error as-is.

Acceptance:
- Unit: stored credentials present → signUp never called; signUp failure → error message is the single
  signup error (no "sign-in failed" concatenation).

### S2 Handoff URL falls back to localhost (App, security)

Problem: `webBaseURL` defaults to `http://127.0.0.1:3028` in `NetworkingBackendConfiguration.resolved()`
AND a second hardcoded fallback inside cockpit `openSquare`. A packaged app would open a URL carrying
access/refresh tokens against whatever listens on localhost:3028.

Design:
- Single source of truth in `NetworkingBackendConfiguration`; wrap the localhost default in `#if DEBUG`.
- Release builds with no configured web URL: `openSquare` shows an explicit "web base URL not configured"
  error and never builds a token-bearing URL. Delete the second fallback in the cockpit.

Acceptance:
- `grep -rn "127.0.0.1:3028" KnowYou/` hits only the DEBUG default (one place) or nothing.
- Unit: resolved() behavior without env/config matches the above.

### UX2 Cockpit 3-step guidance (App — original problem 1a, missed last round)

Problem: the approved plan's onboarding checklist was not implemented; the cockpit still gives no
"what do I do next" guidance.

Design:
- Add a 3-step strip at the top of the cockpit: "1 Generate profile → 2 Approve & sync → 3 Open your square".
- Step state sources: (1) selected profile has a draft; (2) `syncRecordsByProfileID` has an entry;
  (3) `canOpenSquare` is true. Highlight the current step with a one-line action hint; empty inbox copy
  points at the current incomplete step; collapse to a single done row when all three complete.

Acceptance:
- Presentation unit tests (NetworkingCockpitPresentationTests style): each state combination highlights the
  correct step.
- Manual: fresh My Wiki root → step 1 highlighted on first entry.

### S4 Open Square failure overwrites global agent status (App)

Design: dedicated `openSquareError: String?` state shown next to the button; stop writing
`activationStatus = .failed(...)` from `openSquare`.

Acceptance: click Open Square while offline → agent status pill stays "ready", inline error appears.

---

## P2 — may defer

- S3 SquareTabs: replace `router.replace` with `window.history.replaceState(null, "", url)` to kill the
  background RSC refetch (8 Supabase queries) per tab switch. Update the web-copy-contract test that
  currently asserts `router.replace`. Acceptance: zero network requests on tab switch; URL still syncs;
  deep link `/?platform=knowyou-jobs` selects the right tab.
- S5 Inbox dedupe: server items win over same-id local copies; local-only highlights are kept.
  Acceptance: unit test with a same-id conflict.
- UX3 Language policy (zh vs en) for web copy + seed data is a product decision; settle it before rewriting
  copy. Not blocking.

---

## Ops (not code, do it anyway)

- Kill the wedged Jul 7 dev server on port 3028 (serves stale HTML, CSS chunk 500s) and restart from the
  worktree, or standardize on the fresh instance (was on 60790).
- Verification scripts must assert the first CSS chunk returns 200, not just the HTML — "curl 200 OK" was a
  false positive this round.

## Definition of Done

1. Build/tests green: Swift networking tests + `xcodebuild build`; NetworkingWeb `npm test -- --run`,
   `lint`, `build`. New regression tests for C2/UX1/UX2 present.
2. Two-viewer walkthrough: incognito signed-out (no foreign identity, no composer, guidance card, instant
   tab switch) → App "Open Square" handoff sign-in (correct identity chip, composer lists own profiles only,
   post lands in feed).
3. Migration scenario: seeded old sandbox activation.json → App re-activates automatically, Open Square
   works (joint C1+S1 acceptance).
4. Security greps: localhost fallback only under DEBUG; MCP responses contain no plaintext token (fixed
   last round — keep it that way).
5. Production hosting: deploy the Next.js App Router application through the Cloudflare OpenNext adapter
   to `networking.giiift.site`; desktop/mobile HTML and the first CSS chunk return 200, while
   `/api/e2e/networking/state` and `/api/e2e/networking/reset` return 404 in production.
6. Machine signup: the dedicated Networking Supabase project has password-signup email confirmation
   disabled so non-inbox machine identities receive an immediate session. A signup response containing a
   user but no access token throws `machineEmailConfirmationRequired` with an actionable configuration
   message. Production verification covers App activation, authenticated Web handoff, a real MCP post, and
   reading the same post back from the live public square.
