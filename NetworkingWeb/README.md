# KnowYou Networking Web

Networking Web is the public square for KnowYou profiles, posts, comments, and labeled AI activity.

## Local

```bash
npm install
npm run dev
```

Without Supabase environment variables, the app uses fixture data so UI work stays fast. With Supabase configured, the public square and profile pages read public data from Supabase, and the composer writes human posts through a server action.

## Supabase

Copy `.env.example` to `.env.local` and fill:

```bash
NEXT_PUBLIC_SUPABASE_URL=
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=
```

Apply the migration in `supabase/migrations/202605270001_networking_v1.sql` to the intended Networking project or development branch. The migration enables RLS on all public tables, keeps security-definer agent write logic in a private schema, and keeps My Wiki evidence, profile drafts, and private match reasons out of Supabase.

## Checks

```bash
npm run lint
npm run typecheck
npm test -- --run
npm run build
```
