# Networking Account Activation Design

**Date:** 2026-07-12
**Status:** Approved for implementation planning

## 1. Goal

Give a KnowYou user a clear, secure way to enable Networking from the macOS App. The flow must verify the person's email, let them approve their public identity, authorize the current Mac, and preserve a durable session without uploading private KnowYou content.

The design replaces unrestricted client-side machine signup with a verified human account and revocable device credentials.

## 2. Product Decisions

- Networking uses a dedicated account. It does not become a general KnowYou cloud account.
- Authentication uses a six-digit email one-time password (OTP).
- A verified account may authorize at most three devices.
- The App keeps the authenticated session and device credential in macOS Keychain.
- OTP verification is required for first registration, a new device, account recovery, and security-sensitive changes. It is not required every time Networking opens.
- Cloud data includes the account identity, approved public profile, posts, replies, device records, and agent credentials.
- Diary entries, raw My Wiki pages, private reasoning, and unapproved generated content remain local.
- One human account owns one public Networking identity. Devices do not appear as separate public users.

## 3. Experience Flow

### 3.1 Networking Gate

When Networking is not enabled, the App shows a dedicated activation screen rather than a disabled feed.

The screen explains:

- what the user gains: a public profile, posting, replies, and people discovery;
- what becomes public only after approval;
- what remains private and local;
- that the current Mac will receive revocable permission to act for the user.

Primary action: **Create Networking account**.
Secondary action: **I already have an account**.

Both actions enter the same email verification flow. The service determines whether the verified email belongs to a new or existing account only after OTP verification succeeds.

### 3.2 Email Verification

The user enters an email address and requests a six-digit OTP. The verification screen displays the destination in partially masked or user-confirmed form, supports editing the email, and provides a resend countdown.

Rules:

- OTP expires after 10 minutes.
- OTP can be used once.
- Resend, verification attempts, and account creation are rate limited by email, IP, and device signals.
- Pre-verification responses do not reveal whether an account exists.
- Error copy distinguishes expired code, invalid code, temporary throttling, and network failure without leaking account existence.

After successful verification:

- a new user continues to public profile review;
- an existing user continues to device authorization, with their existing public profile available for review.

### 3.3 Public Profile Approval

KnowYou shows a generated or previously approved public profile preview containing only Networking-safe fields, such as display name, handle, avatar, short bio, interests, and goals.

The user must explicitly choose one of:

- **Approve public profile**;
- **Edit before continuing**.

No profile is published merely because an email was verified. The screen states that Diary content and raw My Wiki data are not uploaded. The user can later edit or unpublish the profile.

Existing users may skip republishing when their current profile is already approved and unchanged, but they can inspect it before authorizing a new device.

### 3.4 Device Authorization

The App proposes a human-readable device name, such as `Tianfu's MacBook Pro`, and shows device-slot usage.

On confirmation, the backend creates a device record and issues a high-entropy device credential. The App stores the credential in macOS Keychain. The backend stores only a secure hash or equivalent non-recoverable representation.

The device credential authorizes Networking operations for that account, subject to server-side policy and rate limits. It does not provide access to Diary or raw My Wiki data.

If the account already has three devices, the App displays the existing devices with last-active time and approximate location. The user must revoke one before adding the current Mac. Revocation immediately invalidates that device's credential.

### 3.5 Completion

The success screen confirms that the email, public profile, and current Mac are connected. The primary action opens Networking. A secondary action opens **Account & Devices**.

The first Networking visit should offer an actionable next step: review a suggested post or explore Friends and Career. It must not return the user to another setup dead end.

## 4. Returning And Recovery Flows

### Persistent Session

On normal launches, the App restores the authenticated session and device credential from Keychain. It silently validates the device credential before enabling write actions. Public browsing may remain available when validation is temporarily unavailable, but posting must fail closed with a clear retry state.

### New Device

A new Mac completes email OTP verification and device authorization. It does not create a second public identity.

### Lost Or Revoked Device

The user can revoke a device from **Account & Devices**. A revoked device loses write access immediately and sees a sign-in-required state on its next validation or failed write.

### Email Change

Changing the account email requires verification of the new email and a fresh security check on the current account. The exact recovery policy may be implemented using Supabase-supported authentication controls, but it must not allow an unverified email to replace the account identity.

### Logout

Logging out of the current Mac removes its local session and device secret. **Log out all devices** revokes every device credential and requires explicit confirmation plus fresh email verification.

## 5. Architecture

### Human Account

Supabase Auth represents the verified person. Public profile ownership, moderation state, and account-level policy attach to this identity.

### Device Record

`networking_devices` represents each authorized installation and contains:

- account owner ID;
- stable device ID;
- user-editable display name;
- credential hash and rotation metadata;
- creation, last-active, and revoked timestamps;
- coarse security metadata required for abuse investigation.

A database constraint or transactionally enforced service rule limits active devices to three per account.

### Public Actions

Posts and replies are attributed publicly to the person's approved profile. The originating device ID is retained as private audit metadata. Device credentials are accepted only through server-controlled functions that validate revocation, account status, profile state, and rate limits.

### Trust Boundary

The Supabase publishable key remains public by design and is not treated as a secret. Security comes from verified user sessions, server-side authorization, RLS, device credential validation, and rate limiting. Privileged service-role credentials never ship in the App or Web bundle.

## 6. Abuse Controls

- Disable unrestricted client-created machine accounts once the verified account flow is deployed.
- Apply OTP send and verification limits per email, IP, and device signal.
- Apply account creation limits and anomaly monitoring.
- Apply post, reply, and agent-action quotas per account and device.
- Keep RLS ownership checks for all user-controlled rows.
- Require an approved, non-suspended public profile before public writes.
- Support device and account revocation without requiring an App update.
- Emit auditable security events without storing private KnowYou source content.

Dogfood may use relaxed numerical thresholds, but it must use the same authorization architecture as production.

## 7. UI States And Accessibility

The flow must include explicit states for loading, offline, invalid OTP, expired OTP, resend throttling, service unavailable, profile validation failure, three-device capacity, device revocation, and credential expiration.

All controls must support keyboard navigation, VoiceOver labels, visible focus, Dynamic Type-compatible sizing where applicable, and sufficient contrast. OTP entry supports paste and autofill while remaining a single logical accessibility field.

Closing the flow preserves safe progress after email verification but never treats an unapproved profile or unconnected device as fully activated.

## 8. Privacy Copy Requirements

The UI must communicate these facts in plain language:

- The email identifies the Networking account and is not shown publicly by default.
- Only the reviewed profile and explicitly approved posts or replies become public.
- Diary entries and raw My Wiki pages stay on the Mac.
- The device credential is stored in Keychain and can be revoked.
- Removing a device blocks future actions from that device but does not delete already published content.

## 9. Verification And Benchmarks

### Functional Test Cases

1. A new user verifies an email, approves a profile, connects the first Mac, and reaches Networking.
2. An existing user verifies the same email on a second Mac and retains one public identity.
3. A fourth device cannot connect until an existing device is revoked.
4. A revoked device cannot post or reply, including with a previously issued credential.
5. Invalid, expired, reused, and rate-limited OTP attempts produce the correct state without account enumeration.
6. Relaunch restores a valid session without another OTP.
7. Missing or corrupted Keychain credentials fail closed for writes and offer recovery.
8. No activation request contains Diary entries, raw My Wiki pages, or private reasoning.

### Security Benchmarks

- No P0, P1, or P2 findings in the release review loop.
- No service-role secret or reusable plaintext device credential in client bundles, logs, or database rows.
- Revocation prevents authenticated device writes within one validation cycle and no later than 60 seconds.
- Automated signup and OTP abuse receives deterministic throttling without exposing account existence.
- RLS and server functions reject cross-account profile, device, post, and reply mutations.

### UX Benchmarks

- A first-time user can explain what is public and what stays local before approving the profile.
- The happy path contains no more than three decisions after entering the OTP: approve profile, connect device, open Networking.
- Returning users with a valid session enter Networking without authentication prompts.
- Every error state offers one clear recovery action and preserves already completed safe steps.
- In moderated usability testing, at least 4 of 5 participants complete activation without assistance and correctly identify the three-device limit.

## 10. Out Of Scope

- A general KnowYou cloud account for Diary or My Wiki synchronization.
- Password authentication.
- Social login.
- Organization or team accounts.
- More than three active devices.
- A separate public identity for each local agent or device.
- Automatic publication of generated profiles or posts without user approval.

## 11. Definition Of Done

- The macOS activation and recovery flows match this design.
- Unrestricted machine signup is no longer reachable from public clients.
- Email verification, profile approval, device issuance, revocation, and persistent session behavior are covered by focused tests.
- Production RLS, rate limits, and server functions pass adversarial tests.
- App and Web behavior are verified against the same production authorization contract.
- The release pipeline completes implementation verification and independent Claude review with no unresolved P0, P1, or P2 findings.
