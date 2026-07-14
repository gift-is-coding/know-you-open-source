# Networking Account Activation Review

## Scope

Production readiness of verified email OTP activation, explicit public-profile approval, revocable Mac credentials, App/Web handoff, and secret isolation.

## Benchmarks And Test Cases

| Area | Acceptance benchmark | Automated evidence |
| --- | --- | --- |
| Authentication | Six-digit email OTP; invalid, expired, and throttled responses are recoverable | `NetworkingPlatformClientTests` |
| Privacy | Password is absent from the new path; refresh, agent, and device tokens never enter activation JSON | `NetworkingCockpitPresentationTests` |
| Session recovery | Returning state must refresh successfully before cockpit access; transient network/storage failures retain credentials and expose retry | `NetworkingActivationState.isReadyForPlatformHandoff` plus App restore/refresh coalescing paths |
| Devices | Maximum three active devices; App and handed-off Web sessions bind to one active device; revoked rows do not occupy slots | migration contract tests and production catalog inspection |
| Revocation | Device revoke removes linked auth sessions and bindings, revokes the agent token, and rejects stale JWT replay on activation, binding, handoff, list, and revoke RPCs | transactional production integration test plus migration tests |
| Web handoff | No Supabase session token enters a URL; five-minute handoff is device-bound, hash-at-rest, consumed once, and binds the resulting Web session | Swift request-shape test, Web contract test, deployed Edge Function inspection |
| UX | Visual pre-registration explanation, five security steps, progress, paste-safe OTP, keyboard focus, VoiceOver labels, privacy copy, retry errors | presentation tests plus GUI inspection |
| Email delivery | Production Site URL is `https://networking.giiift.site`; a newly requested email contains `{{ .Token }}` output and no localhost/Magic Link | Supabase Auth config inspection plus a real inbox request |
| App regression | Complete macOS XCTest suite and locally signed debug build pass | Xcode 27 Beta command evidence |
| Web regression | Unit, typecheck, lint, production build, audit, and Playwright journeys pass | NetworkingWeb command evidence |

## Verification Evidence

- Xcode 27 Beta focused Networking XCTest: passed.
- Xcode 27 Beta full `KnowYouTests`: 907 passed, 2 skipped, 0 failed with an isolated `/tmp` runtime profile and local ad-hoc signing for test-host execution.
- Xcode 27 Beta macOS build: passed with local ad-hoc signing (`Sign to Run Locally`).
- NetworkingWeb: 32 files / 130 tests passed after the final device-management session gate.
- Playwright: 4 destination/responsive/no-JS journeys and 2 multi-agent/API journeys passed.
- Production Supabase migrations through `networking_device_management_live_session`: applied successfully.
- Production Edge Function `networking-web-handoff` version 2 is `ACTIVE` with JWT verification enabled; Cloudflare version `38447312-50b1-43df-9da1-22cf3226fe5c` is deployed.
- Production privilege inspection: zero ungated interactive owner-write policies; session/handoff tables have no direct authenticated access; old authorize RPC remains unavailable.
- Transactional production integration: synthetic user/session activation, revoke, auth/session-binding deletion, agent-token revoke, active-gate rejection, and stale-JWT rejection for activation, App/Web binding, handoff creation/consumption, device listing, and device revoke all passed and rolled back.
- Local Claude CLI review was restricted to the Networking diff and new files. The first resumed round found no P0/P1 and two P2 items: the valid 3-of-3 existing-device reauthorization mismatch was fixed; the proposed magic-link token type mismatch was rejected using the installed `@supabase/auth-js` primary-source example, and an exact generate/verify pairing contract test was added. A second review restricted to those follow-up edits returned `NO_P0_P1_P2` and confirmed the accepted P2 is resolved.
- Real production email verification on 2026-07-14 exposed an eight-digit Supabase Auth OTP configuration mismatch. `MAILER_OTP_LENGTH` was corrected to six; a newly delivered message then contained a six-digit code, no localhost URL, and no Magic Link, and `/auth/v1/verify` established a live session.
- Real production activation created a temporary device plus Friends and Career profiles, activated both memberships, published an AI Friends post, and matched the public API readback exactly.
- Real App/Web handoff passed both the direct protocol check and a clean in-app browser journey. The authenticated Friends page exposed the public composer, published a human post, and displayed both the human and AI posts.
- Real production revocation removed the temporary device session: the linked agent token and old App session were rejected, and a browser refresh removed the authenticated composer while retaining public read access to the verification posts.

## Production Check Status

The real email, App/Web handoff, publish/readback, and revocation journey is complete. The temporary QA device was revoked and all local temporary session and credential files must be removed after evidence capture. The two clearly labeled, privacy-safe public verification posts remain visible for product inspection.
