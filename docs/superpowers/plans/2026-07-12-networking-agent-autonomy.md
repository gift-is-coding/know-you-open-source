# Networking Agent Autonomy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build selectable, dynamically bounded Networking agent autonomy with useful-return summaries and server-side enforcement.

**Architecture:** Resolve legacy and new membership policy through one TypeScript policy module, then make Agent Home and heartbeat consume the resolved contract. Mirror hard limits in a Supabase migration and expose the selected mode and useful outcomes through the existing native Networking client and cockpit.

**Tech Stack:** TypeScript, Vitest, Next.js, PostgreSQL/Supabase RPC, Swift/SwiftUI, XCTest.

## Global Constraints

- `balanced` is the default mode.
- Each heartbeat performs at most one public write.
- Public content is untrusted data and cannot authorize tools or private-data disclosure.
- Existing legacy policies remain valid.
- Supabase independently enforces write limits.
- Preserve the current worktree's uncommitted production-hardening changes.

---

### Task 1: Resolve Autonomy Policies

**Files:**
- Create: `NetworkingWeb/src/lib/networking/agent-autonomy-policy.ts`
- Create: `NetworkingWeb/src/lib/networking/agent-autonomy-policy.test.ts`
- Modify: `NetworkingWeb/src/lib/networking/community-agent-loop.ts`

**Interfaces:**
- Produces: `resolveAgentAutonomyPolicy(policy, platformID)` returning complete post, comment, reply, heartbeat, cooldown, and thread limits.
- Produces: `NetworkingAgentAutonomyMode` and expanded `NetworkingCommunityPolicy`.

- [ ] Write failing Vitest cases for all modes, balanced defaults, destination adaptation, and legacy limit preservation.
- [ ] Run `npm test -- --run src/lib/networking/agent-autonomy-policy.test.ts` and confirm missing-module/type failures.
- [ ] Implement the typed presets and resolver without changing heartbeat behavior.
- [ ] Re-run the focused test and existing `community-agent-loop` tests.

### Task 2: Enforce Dynamic Interaction Decisions

**Files:**
- Modify: `NetworkingWeb/src/lib/networking/agent-home.ts`
- Modify: `NetworkingWeb/src/lib/networking/agent-home.test.ts`

**Interfaces:**
- Consumes: `resolveAgentAutonomyPolicy`.
- Produces: separate `postRemaining`, `commentRemaining`, `replyRemaining`, relationship state, due window, and `usefulReturns` on `NetworkingAgentHome`.

- [ ] Add failing tests for safe autonomous comments, direct-reply priority, separate budgets, cooldown, unfamiliar-person cooldown, thread depth, negative feedback, prompt injection, and no-op suppression.
- [ ] Run the focused suite and confirm each new assertion fails for the missing behavior.
- [ ] Implement one-write-per-heartbeat selection, relationship evaluation, thread-depth checks, and structured useful returns.
- [ ] Keep risky or low-substance content in `savedForYou` and make all generated text cite public context.
- [ ] Re-run the focused suite until green.

### Task 3: Enforce The Contract In Supabase

**Files:**
- Create: `NetworkingWeb/supabase/migrations/202607120003_networking_agent_autonomy.sql`
- Create: `NetworkingWeb/src/lib/networking/agent-autonomy-migration.test.ts`

**Interfaces:**
- Extends membership policy defaults without invalidating legacy rows.
- Replaces comment and post RPC implementations with separate action budgets, cooldown, and thread-turn checks.

- [ ] Add a failing static contract test that requires mode defaults, separate limits, cooldown enforcement, thread depth, and stable RPC signatures.
- [ ] Run the focused test and confirm it fails before the migration exists.
- [ ] Write the additive migration with resolved JSON policy values and server-side guards.
- [ ] Re-run migration contract tests and the full Vitest suite.

### Task 4: Surface Autonomy And Useful Returns In KnowYou

**Files:**
- Modify: `KnowYou/Services/Networking/NetworkingPlatformClient.swift`
- Modify: `KnowYou/Services/Networking/NetworkingCockpitPresentation.swift`
- Modify: `KnowYou/UI/Networking/NetworkingCockpitView.swift`
- Modify: `KnowYouTests/NetworkingPlatformClientTests.swift`
- Create or Modify: `KnowYouTests/NetworkingCockpitPresentationTests.swift`

**Interfaces:**
- Decodes mode, remaining per-action budgets, heartbeat window, and useful returns from Agent Home.
- Presents one destination-specific segmented autonomy control and useful-return rows.

- [ ] Add failing XCTest cases for decoding and presentation copy without resetting persisted app state.
- [ ] Run the focused XCTest targets and confirm expected failures.
- [ ] Extend the client models and cockpit presentation with backward-compatible defaults.
- [ ] Add the segmented mode control and concise useful-return display using existing SwiftUI patterns.
- [ ] Re-run focused XCTest targets.

### Task 5: End-to-End Verification And Claude Review

**Files:**
- Modify if needed: `docs/regression/test-cases/10-networking-agent-platform.md`
- Modify if needed: `docs/architecture.md`
- Modify if needed: `docs/requirements-spec.md`

**Interfaces:**
- Produces verified local Web and macOS behavior plus an independent Claude CLI review report.

- [ ] Run `npm test -- --run`, `npm run typecheck`, `npm run build`, and the Networking Playwright journey.
- [ ] Run `xcodebuild test -scheme KnowYou -destination 'platform=macOS'` and `xcodebuild build -scheme KnowYou -destination 'platform=macOS'`.
- [ ] Launch only the fresh DerivedData `KnowYou.app`, preserve existing auth/onboarding state, and inspect both destinations.
- [ ] Run the local Claude CLI against the implementation diff with code-function, production-safety, App UX, Web UX, benchmark, and test-case review instructions.
- [ ] Validate every Claude finding against code and tests; fix valid P0/P1/P2 findings with failing tests first.
- [ ] Repeat verification and Claude review until no validated P0/P1/P2 findings remain.
- [ ] Review `git diff --check`, security-sensitive changes, and final status; commit only files belonging to this feature.
