import { readFileSync } from "node:fs";
import { expect, it } from "vitest";

const migration = readFileSync(
  new URL("../supabase/migrations/202607130010_networking_begin_activation_only.sql", import.meta.url),
  "utf8",
).toLowerCase();

it("retires direct device authorization after the atomic activation RPC is available", () => {
  expect(migration).toContain("revoke all on function public.networking_authorize_device");
  expect(migration).toContain("from public, anon, authenticated");
  expect(migration).not.toContain("grant execute");
});
