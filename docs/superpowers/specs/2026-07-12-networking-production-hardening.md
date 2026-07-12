# Networking Production Hardening

## Goal

Separate production from local/test traffic, close unrestricted machine-user signup, make Cloudflare deployment fail closed when Supabase configuration is missing, and provide an auditable cleanup path for existing E2E production data.

## Environment isolation

- Local development must refuse the production Supabase project unless `ALLOW_PRODUCTION_SUPABASE_FOR_LOCAL_DEV=1` is explicitly set.
- Playwright must receive explicit local-only Supabase values and must never inherit `.env.local` production credentials.
- A tracked `.env.example` documents local/dev variables without secrets.
- A separate Supabase development project remains an operator-owned cloud resource; its creation and billing choice are not hidden inside a build script.

## Machine signup

- Public Supabase email/password signup is disabled in production.
- The App calls `networking-machine-signup` only when it has no stored machine identity.
- The Edge Function accepts only KnowYou machine email/password formats, applies a server-side per-source hourly limit, creates an email-confirmed user with the service role, and returns no service credential.
- The App signs in with password after the function succeeds. Existing identities continue to use password sign-in and are unaffected.
- No static shared secret is embedded in the App. A distributable shared secret would be extractable and would not provide a trustworthy security boundary.

## Deployment fail-closed

- `deploy:cloudflare` runs a preflight that requires a valid Supabase URL and publishable key before OpenNext build.
- Production rendering throws a configuration error instead of falling back to demo data when Supabase variables are absent.
- Local demo mode remains available only outside production.

## Production cleanup

- A one-time script defaults to dry-run and prints exact candidate IDs/counts.
- It selects only known E2E markers: machine emails/handles with `e2e-knowyou-` or `ky_e2e_`, and the fixed `eeeeeeee-...` fixture identities/content.
- `--execute` requires the production project URL, a service-role key, and explicit `CONFIRM_NETWORKING_E2E_DELETE=1`.
- The operator must review the dry-run output immediately before execution. Real Tianfu Wu rows and the verified smoke post are excluded.

## Acceptance

- Dev preflight rejects `jevgtiamxlkucjqpbekn.supabase.co` by default.
- Deploy preflight exits non-zero when either Supabase variable is absent.
- Production `hasSupabaseEnv()` absence cannot enable demo data.
- Machine signup function rejects malformed identities and rate-limited sources.
- Swift tests prove activation calls the function and then password sign-in.
- Cleanup dry-run is deterministic; production deletion is separately confirmed and verified by post-delete counts.
- Production review and Claude review report no P0/P1/P2.

