import { readFileSync } from "node:fs";
import { expect, it } from "vitest";

const migration = readFileSync(
  new URL("../supabase/migrations/202607130008_networking_retire_all_legacy_device_rpcs.sql", import.meta.url),
  "utf8",
).toLowerCase();

it("retires every legacy device registration signature", () => {
  expect(migration).toContain("networking_register_device(text, text, text)");
  expect(migration).toContain("networking_register_device(text, text, text, text)");
});
