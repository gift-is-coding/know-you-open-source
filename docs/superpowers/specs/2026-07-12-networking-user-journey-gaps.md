# Networking User Journey Gaps — Spec

Date: 2026-07-12
Branch: continue on codex/networking-community-bootstrap
Source: Claude user-journey review of HEAD bd226b4 (all Stateful Falcon fix-round items verified landed).
Scope: journey-level design gaps, not code defects. The supply-side journey (App user: generate →
approve → open square → post) is complete; these items fix where the journey leaks value.

Scope by owner decision: ONLY J2 (reply notifications) and J3 (thin-context expectation management).
Everything else from the journey review — permalinks/visitor exits, identity portability disclosures,
trust/verification signals, delete/revoke controls — is explicitly out of scope. Do not build them.

---

## In scope

### J2 The "someone replied to you" moment has no delivery path (App)

Problem: the core activation moment of the whole product — an inbound reply on your post — is only
discoverable if the user happens to open the App, open Networking, and keep the cockpit visible
(60s poll). There are no system notifications for Networking, while the App already has notification
infrastructure for other modules. Conversations die because replies are seen days late.

Design:
- Move inbound polling out of the cockpit-visible-only loop: add a background poll (reuse
  `NetworkingInboxService`) orchestrated from `AppState` alongside the existing background tasks
  (clipboard/notifications/daily sync). Cadence: on app launch + every 15 minutes while the app runs.
  Only when activation state `isReadyForPlatformHandoff`.
- Diff against the persisted inbox cursor; for each NEW `inbound` item post a user notification
  (UNUserNotificationCenter, same pattern as the diary notifications): title = community display name,
  body = public summary, click → open the App at the Networking cockpit with that community selected.
- Never include private reasoning in the notification body (public summary only).

Acceptance:
- Unit: given a stored cursor and a fetched inbox containing one new inbound item, the notification
  scheduler is invoked exactly once; re-running with the same data schedules nothing (dedupe by item id).
- Manual: user B replies to user A's post on the web → within one poll cycle A gets a macOS notification;
  clicking it lands in the cockpit with the right community selected.

### J3 First profile generation happens before My Wiki has anything to say (App)

Problem: the 3-step guidance pushes a fresh user straight to "Generate profile", but a fresh install has
a near-empty My Wiki. The LLM generates a hollow profile from thin context, and the journey's intended
"wow" moment becomes a disappointment. No expectation management exists.

Design:
- Before generation, compute a cheap sufficiency signal from `MyWikiContextPackService` (e.g. number of
  entities/concepts returned for the scenario, or total context bytes vs the 8KB budget).
- Below threshold (e.g. < 3 entities or < 1KB context): keep Generate enabled, but show an inline notice
  on the step-1 card: "Your My Wiki is still thin — profiles get much better after a few days of use.
  You can generate now and refresh later." After generation from thin context, tag the draft with a
  "regenerate later" hint instead of presenting it as final.
- Threshold and copy live next to the existing guidance state (`NetworkingCockpitGuidanceState`) so the
  presentation tests cover it.

Acceptance:
- Unit (presentation tests): sufficiency below threshold → notice visible, above → hidden.
- Manual: brand-new My Wiki root → step 1 shows the thin-context notice; a root with weeks of data does not.

---

## Definition of Done

1. Build/tests green (Swift targeted networking tests) with the new unit and presentation tests
   listed above.
2. Journey walkthrough (activation loop): B replies on web → A gets a macOS notification within one
   poll cycle → clicking it lands in the cockpit with the right community selected.
3. Journey walkthrough (fresh user): brand-new My Wiki root → thin-context notice on the generate step;
   a data-rich root shows no notice.
4. No private reasoning ever appears in notification bodies (public summary only; grep + spot check).
