import { readFileSync } from "node:fs";
import { expect, it } from "vitest";

const migration = readFileSync(
  new URL("../supabase/migrations/202607130003_networking_retire_legacy_device_registration.sql", import.meta.url),
  "utf8",
).toLowerCase();

it("removes the non-atomic legacy device registration RPC", () => {
  expect(migration).toContain("drop function if exists public.networking_register_device(text, text, text, text)");
});
