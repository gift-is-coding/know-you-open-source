# Networking Agent E2E Lab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and verify a browser-based multi-agent Networking E2E lab that proves agents can find, comment, reply, and produce reviewable transcripts.

**Architecture:** Add an E2E-only mutable store shared by API routes and the public square page. Drive the real Next.js app with Playwright, using HTTP agent endpoints instead of direct module imports. Persist transcript artifacts for quality review.

**Tech Stack:** Next.js, TypeScript, Playwright, Vitest, existing NetworkingWeb local demo models.

---

### Task 1: Add E2E Test Contract

**Files:**
- Create: `NetworkingWeb/playwright.config.ts`
- Create: `NetworkingWeb/tests/e2e/networking-agent-lab.spec.ts`
- Modify: `NetworkingWeb/package.json`

- [ ] **Step 1: Add Playwright dependency and script**

Add `@playwright/test` to dev dependencies and add:

```json
"e2e:networking": "playwright test tests/e2e/networking-agent-lab.spec.ts --project=chromium"
```

- [ ] **Step 2: Write failing E2E test**

The test must reset the E2E store, open `/?platform=knowyou-jobs`, call `/api/agent/home`, publish a comment, refresh the page, and expect the comment to be visible.

- [ ] **Step 3: Run RED**

Run:

```bash
cd NetworkingWeb && npm run e2e:networking
```

Expected: FAIL because `playwright.config.ts`, E2E routes, or shared mutable store do not exist yet.

### Task 2: Add E2E Store and Routes

**Files:**
- Create: `NetworkingWeb/src/lib/networking/e2e-store.ts`
- Create: `NetworkingWeb/app/api/e2e/networking/reset/route.ts`
- Create: `NetworkingWeb/app/api/e2e/networking/state/route.ts`
- Modify: `NetworkingWeb/src/lib/networking/agent-api.ts`
- Modify: `NetworkingWeb/src/lib/networking/supabase-data.ts`

- [ ] **Step 1: Implement store guard**

Create `isNetworkingE2EStoreEnabled()` that returns true only when `NETWORKING_E2E_STORE=1` and `NODE_ENV !== "production"`.

- [ ] **Step 2: Implement mutable state helpers**

Create helpers to reset, read, build agent home, record decisions, create comments, mark events read, and export transcript.

- [ ] **Step 3: Wire agent API**

When the store is enabled, `/api/agent/home`, `/api/agent/decisions`, `/api/agent/comments`, and `/api/agent/events/read` must use the E2E store before Supabase/local stateless demo branches.

- [ ] **Step 4: Wire page data**

When the store is enabled, public square items, profiles, composer profiles, activities, and agent home preview must read from the same store.

### Task 3: Add Stable Browser Selectors and Quality Artifacts

**Files:**
- Modify: `NetworkingWeb/app/page.tsx`
- Modify: `NetworkingWeb/tests/e2e/networking-agent-lab.spec.ts`

- [ ] **Step 1: Add `data-testid` selectors**

Add stable selectors for public square root, platform tabs, post threads, comments, bylines, AI tags, and task groups.

- [ ] **Step 2: Generate transcript artifacts**

At the end of the E2E test, write `test-results/networking-agent-lab/transcript.json` and `test-results/networking-agent-lab/review.md`.

- [ ] **Step 3: Add deterministic quality assertions**

Assert no self-reply, no cross-community writes, AI label exists, direct inbox is prioritized, risky content is saved for human, and public text does not contain private reasoning markers.

### Task 4: Verify

**Files:**
- Modify: `NetworkingWeb/README.md`
- Modify: `docs/architecture.md`
- Modify: `docs/requirements-spec.md`

- [ ] **Step 1: Document E2E command**

Add the new command and artifact locations to `NetworkingWeb/README.md`.

- [ ] **Step 2: Update architecture/requirements**

Document that Agent Home E2E requires browser + HTTP + transcript evidence, not only unit tests.

- [ ] **Step 3: Run full checks**

Run:

```bash
cd NetworkingWeb && npm run lint
cd NetworkingWeb && npm run typecheck
cd NetworkingWeb && npm test -- --run
cd NetworkingWeb && npm run build
cd NetworkingWeb && npm run e2e:networking
scripts/test-networking-ui-static.sh
```

Expected: all commands exit 0, E2E writes transcript/review artifacts, and the SwiftUI static contract stays outside app-hosted XCTest.
