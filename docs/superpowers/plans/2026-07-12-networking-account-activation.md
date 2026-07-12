# Networking Account Activation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace automatic machine-user signup with verified email OTP activation, explicit public-profile approval, and at most three revocable Mac device credentials.

**Architecture:** Supabase Auth owns the verified human session. A new `networking_devices` table and owner-validated RPCs issue and revoke hashed device credentials; the existing `people`, `profiles`, and `agent_tokens` pipeline remains the public-content backend. The macOS App presents a state-driven activation flow and persists refresh/device secrets only in Keychain.

**Tech Stack:** Swift 6, SwiftUI, XCTest, Supabase Auth REST, PostgreSQL migrations/RLS/RPC, Vitest.

## Global Constraints

- Authentication uses a six-digit email OTP with a 10-minute product expiry expectation.
- One account may have at most three active devices.
- Returning users with valid Keychain state must not be asked for OTP again.
- Diary entries, raw My Wiki pages, private reasoning, and unapproved generated content remain local.
- The Supabase publishable key is public; service-role credentials must never enter App or Web bundles.
- Public profiles and posts remain attributed to one human identity, not separate machine users.
- Existing production test data must not be deleted.

---

### Task 1: Device Authorization Database Contract

**Files:**
- Create: `NetworkingWeb/supabase/migrations/<generated_timestamp>_networking_verified_devices.sql`
- Create: `NetworkingWeb/tests/networking-verified-devices-migration.test.ts`

**Interfaces:**
- Consumes: authenticated `auth.uid()`, existing `public.people`, and `extensions.digest`.
- Produces: `public.networking_devices`, `networking_register_device(p_device_id, p_display_name, p_token_hash)`, `networking_revoke_device(p_device_id)`, and `networking_list_devices()`.

- [ ] **Step 1: Write migration contract tests**

Assert the migration defines RLS, owner predicates, unique active device IDs, a transactional three-device check, explicit grants, token hashing input validation, and revoked-device filtering.

- [ ] **Step 2: Run the contract test and verify RED**

Run: `cd NetworkingWeb && npm test -- tests/networking-verified-devices-migration.test.ts`

Expected: FAIL because the migration does not exist.

- [ ] **Step 3: Generate and implement the migration**

Run: `cd NetworkingWeb && supabase migration new networking_verified_devices`

Implement the table and RPCs so every owner operation derives ownership from `(select auth.uid())`; revoke execute from `public` and `anon`; grant only to `authenticated`; reject blank IDs/names, malformed SHA-256 hashes, duplicate active devices, and a fourth active device.

- [ ] **Step 4: Run migration tests and local database verification**

Run: `cd NetworkingWeb && npm test -- tests/networking-verified-devices-migration.test.ts`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add NetworkingWeb/supabase/migrations NetworkingWeb/tests/networking-verified-devices-migration.test.ts
git commit -m "feat: add verified networking devices"
```

### Task 2: Email OTP And Device Client

**Files:**
- Modify: `KnowYou/Services/Networking/NetworkingPlatformClient.swift`
- Modify: `KnowYouTests/NetworkingPlatformClientTests.swift`

**Interfaces:**
- Produces: `requestEmailOTP(email:)`, `verifyEmailOTP(email:token:) -> NetworkingPlatformSession`, `registerDevice(session:deviceID:displayName:tokenHash:)`, `listDevices(session:)`, and `revokeDevice(session:deviceID:)`.
- Produces: `NetworkingDeviceRecord` and typed OTP/device errors suitable for UI recovery states.

- [ ] **Step 1: Add failing request-shape tests**

Test `/auth/v1/otp` email requests, `/auth/v1/verify` with `type=email`, authenticated device RPC calls, decoding device records, and HTTP errors for invalid, expired, throttled, and capacity responses.

- [ ] **Step 2: Run focused tests and verify RED**

Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/NetworkingPlatformClientTests`

Expected: FAIL because the OTP and device APIs are absent.

- [ ] **Step 3: Implement the minimal client APIs**

Use the existing transport and JSON decoding path. Never log OTPs, access tokens, refresh tokens, or device plaintext tokens. Keep password signup methods only long enough to decode legacy persisted state; do not invoke them from new activation.

- [ ] **Step 4: Run focused tests and verify GREEN**

Run the same `xcodebuild test` command.

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add KnowYou/Services/Networking/NetworkingPlatformClient.swift KnowYouTests/NetworkingPlatformClientTests.swift
git commit -m "feat: add networking email otp client"
```

### Task 3: Stateful Activation And Keychain Migration

**Files:**
- Modify: `KnowYou/Services/Networking/NetworkingActivationService.swift`
- Modify: `KnowYou/Services/Networking/NetworkingActivationRunner.swift`
- Modify: `KnowYouTests/NetworkingCockpitPresentationTests.swift`
- Modify: `KnowYouTests/NetworkingPlatformClientTests.swift`

**Interfaces:**
- Produces: `NetworkingAccountActivationPhase` state machine for email entry, OTP pending, profile approval, device capacity, device authorization, and ready.
- Produces: activation input accepting a verified `NetworkingPlatformSession` and device metadata instead of generated email/password credentials.
- Persists: email and non-secret device metadata in activation JSON; refresh token, agent token, and device token in Keychain only.

- [ ] **Step 1: Add failing state and persistence tests**

Cover phase transitions, resumable verified sessions, refresh-token restoration, absence of password in new state, device token Keychain isolation, migration of legacy machine credentials without automatic signup, and fail-closed behavior when secrets are missing.

- [ ] **Step 2: Run focused tests and verify RED**

Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/NetworkingCockpitPresentationTests -only-testing:KnowYouTests/NetworkingPlatformClientTests`

Expected: FAIL on the new phase and persistence assertions.

- [ ] **Step 3: Implement the activation state machine and runner**

Remove generated machine credentials from the new path. After OTP verification and profile approval, generate one high-entropy device token, register its SHA-256 hash, create or update the existing person/profile rows, register the existing agent token, and save the resulting state atomically.

- [ ] **Step 4: Run focused tests and verify GREEN**

Run the same focused `xcodebuild test` command.

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add KnowYou/Services/Networking/NetworkingActivationService.swift KnowYou/Services/Networking/NetworkingActivationRunner.swift KnowYouTests/NetworkingCockpitPresentationTests.swift KnowYouTests/NetworkingPlatformClientTests.swift
git commit -m "feat: activate networking with verified accounts"
```

### Task 4: macOS Activation Experience

**Files:**
- Create: `KnowYou/UI/Networking/NetworkingAccountActivationView.swift`
- Modify: `KnowYou/UI/Networking/NetworkingCockpitView.swift`
- Modify: `KnowYouTests/NetworkingCockpitPresentationTests.swift`

**Interfaces:**
- Consumes: `NetworkingAccountActivationPhase` and client/runner closures injected by the cockpit.
- Produces: entry, email, six-digit OTP, profile review, device authorization/capacity, completion, retry, and recovery UI states.

- [ ] **Step 1: Add failing presentation tests**

Test exact primary actions and privacy copy for every phase, OTP validation/paste behavior, device-slot copy, recoverable error actions, and that an unverified account cannot enter the active cockpit.

- [ ] **Step 2: Run focused tests and verify RED**

Run: `xcodebuild test -scheme KnowYou -destination 'platform=macOS' -only-testing:KnowYouTests/NetworkingCockpitPresentationTests`

Expected: FAIL because the activation presentation is absent.

- [ ] **Step 3: Implement the SwiftUI flow**

Match the approved five-screen visual design. Use native controls, keyboard focus, paste/autofill-friendly OTP input, VoiceOver labels, visible progress, clear retry actions, and explicit local-versus-public privacy copy. Do not reset existing onboarding, login, or My Wiki state.

- [ ] **Step 4: Run focused tests and verify GREEN**

Run the same focused test command.

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add KnowYou/UI/Networking/NetworkingAccountActivationView.swift KnowYou/UI/Networking/NetworkingCockpitView.swift KnowYouTests/NetworkingCockpitPresentationTests.swift
git commit -m "feat: add networking account onboarding"
```

### Task 5: Production Closure And Independent Review

**Files:**
- Modify if required: `NetworkingWeb/README.md`
- Modify if required: `docs/architecture.md`
- Modify if required: `docs/requirements-spec.md`
- Create: `docs/superpowers/specs/2026-07-12-networking-account-activation-review.md`

**Interfaces:**
- Verifies the complete App-to-Supabase-to-Web journey and records review evidence.

- [ ] **Step 1: Run full local verification**

```bash
xcodebuild test -scheme KnowYou -destination 'platform=macOS'
xcodebuild build -scheme KnowYou -destination 'platform=macOS'
cd NetworkingWeb && npm test
cd NetworkingWeb && npm run build
```

Expected: all commands exit 0.

- [ ] **Step 2: Verify the production contract without deleting data**

Apply the reviewed migration, verify OTP delivery with a user-controlled test email, authorize one device, publish a test post through the App, confirm it appears on `networking.giiift.site`, revoke the device, and confirm another write is rejected. Preserve existing E2E rows.

- [ ] **Step 3: Perform GUI verification**

Launch only the freshly built `KnowYou.app`; verify all activation screens at desktop and compact window sizes, keyboard/VoiceOver basics, persistent relaunch, Friends/Career entry, and Web handoff. Preserve existing user onboarding and login state.

- [ ] **Step 4: Run the local Claude review skill loop**

Review code functionality, security, App UX, Web UX, benchmarks, and test evidence. Validate each finding before modification. Repeat focused tests and review until no P0, P1, or P2 findings remain; record accepted fixes and final evidence in the review document.

- [ ] **Step 5: Commit closure evidence**

```bash
git add NetworkingWeb/README.md docs/architecture.md docs/requirements-spec.md docs/superpowers/specs/2026-07-12-networking-account-activation-review.md
git commit -m "docs: verify networking account activation"
```
