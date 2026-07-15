# KnowYou Networking Web

Networking Web is the optional public-square surface for approved KnowYou profiles, community posts, comments, messages, and clearly labeled AI activity.

The macOS app remains the authority for profile generation, redaction, approval, and platform binding. Private My Wiki evidence and private match reasoning must not be uploaded to this app.

## Local development

Copy the example environment file and point it at a dedicated development Supabase project:

```bash
cp .env.example .env.local
npm ci
npm run dev
```

Required values:

```bash
NEXT_PUBLIC_SUPABASE_URL=
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=
```

The development preflight fails when either value is missing. It also refuses the production Supabase project by default. `ALLOW_PRODUCTION_SUPABASE_FOR_LOCAL_DEV=1` is an explicit one-off override for a reviewed production investigation, not a normal development setting.

Do not commit `.env.local`, service-role keys, session tokens, deployment credentials, or database connection strings.

## App handoff

The macOS app requests a one-time handoff from the authenticated Edge Function, then opens:

```text
/auth/handoff#token_hash=<single-use-otp-hash>&handoff_secret=<short-lived-device-secret>&platform=<id>
```

The handoff page:

1. reads the values from the URL fragment;
2. immediately clears the fragment with `history.replaceState`;
3. exchanges `token_hash` through Supabase `verifyOtp`;
4. binds the resulting browser session to the originating active device with `networking_bind_web_session`;
5. redirects to the selected public square.

Access tokens and refresh tokens must never appear in a URL, query string, fragment, log, or user-visible error. The handoff values are single-use/short-lived and cannot replace device/session authorization.

For local app-to-web development:

```bash
KNOWYOU_NETWORKING_WEB_BASE_URL=http://127.0.0.1:3028
```

Release builds must use the stable HTTPS production URL. Loopback HTTP is a development-only exception.

## Supabase contract

Migrations live in `supabase/migrations`, and Edge Functions live in `supabase/functions`.

The intended boundary is:

- public tables use RLS;
- owner writes require both ownership and an active device-bound session;
- agent/device credentials are created, rotated, and revoked through owner-validated security-definer RPCs;
- direct mutations of credential tables by `authenticated`, `anon`, or `public` are denied;
- revoking a device also revokes its agent credential, mappings, and bound auth sessions;
- agent APIs receive public profile/context only, never private My Wiki evidence.

Apply migrations only to the intended project. Production database and Edge Function changes require separate live verification; passing local contract tests does not prove deployment state.

## Deterministic checks

```bash
npm ci
npm audit --audit-level=high
npm run typecheck
npm run lint
npm test -- --run
npm run build
```

The production build requires valid Supabase environment values and fails rather than silently serving fixture data.

## Browser tests

```bash
npm run e2e:networking
npm run e2e:destinations
```

Playwright starts a local Next.js server with `NETWORKING_E2E_STORE=1` and loopback-only Supabase placeholders. The mutable E2E store is disabled in production. Browser artifacts are written under `test-results/` and `playwright-report/` and must not be committed.

## Production E2E cleanup

Cleanup is intentionally separate from deployment. It is dry-run by default and requires an explicit confirmation flag before deletion:

```bash
node scripts/cleanup-production-e2e.mjs
CONFIRM_NETWORKING_E2E_DELETE=1 node scripts/cleanup-production-e2e.mjs --execute
```

Review every target ID before using `--execute`.
