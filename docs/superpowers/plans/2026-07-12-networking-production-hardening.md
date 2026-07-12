# Networking Production Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Isolate production data, replace open signup with a rate-limited machine activation function, fail closed on missing deployment configuration, and safely remove existing E2E production rows.

**Architecture:** Keep Supabase Auth and RLS as the identity/data plane. Add one narrowly scoped Edge Function backed by a security-definer rate-limit function, add Node preflight/cleanup scripts, and change the Swift signup path to function-create then password sign-in.

**Tech Stack:** Swift, Supabase Auth/Postgres/Edge Functions, Next.js, Node.js, Vitest, XCTest, Cloudflare OpenNext.

---

### Task 1: Deployment and local-environment gates

**Files:** `NetworkingWeb/scripts/require-supabase-env.mjs`, `NetworkingWeb/tests/deployment-config.test.ts`, `NetworkingWeb/package.json`, `NetworkingWeb/playwright.config.ts`, `NetworkingWeb/src/lib/supabase/env.ts`, `NetworkingWeb/README.md`, `NetworkingWeb/.env.example`.

- [ ] Add failing tests for deploy preflight, production fail-closed behavior, and local rejection of the production project.
- [ ] Implement the preflight script and wire it into `dev`, `build:production`, and `deploy:cloudflare`.
- [ ] Give Playwright explicit local-only Supabase values.
- [ ] Run deployment tests, typecheck, and lint.

### Task 2: Rate-limited machine signup

**Files:** `NetworkingWeb/supabase/migrations/202607120001_networking_machine_signup_rate_limit.sql`, `NetworkingWeb/supabase/functions/networking-machine-signup/index.ts`, `NetworkingWeb/supabase/functions/networking-machine-signup/deno.json`, `KnowYou/Services/Networking/NetworkingPlatformClient.swift`, `KnowYouTests/NetworkingPlatformClientTests.swift`.

- [ ] Add failing Swift tests requiring function invocation followed by password sign-in.
- [ ] Add SQL contract tests for restricted grants, advisory locking, hourly limit, and cleanup.
- [ ] Implement migration and Edge Function validation/admin creation.
- [ ] Implement Swift function-create/sign-in flow and run targeted tests.

### Task 3: Production E2E cleanup tool

**Files:** `NetworkingWeb/scripts/cleanup-production-e2e.mjs`, `NetworkingWeb/tests/production-cleanup-script.test.ts`, `NetworkingWeb/README.md`.

- [ ] Add failing source-contract tests for dry-run default, exact markers, smoke exclusion, service-role requirement, and explicit execute confirmation.
- [ ] Implement deterministic candidate reporting and dependency-ordered deletion.
- [ ] Run dry-run against production and present exact candidates for confirmation.
- [ ] After explicit confirmation, execute once and verify production counts/public feed.

### Task 4: Production rollout and review loop

- [ ] Apply the migration and deploy the Edge Function.
- [ ] Disable public signup only after the function is live and a fresh activation succeeds.
- [ ] Run the project production-review skill and local Claude CLI review.
- [ ] Fix verified P0/P1/P2 findings and repeat until none remain.
- [ ] Deploy Web, verify HTML/CSS 200, production E2E endpoints 404, App activation/handoff, and clean public feed.
