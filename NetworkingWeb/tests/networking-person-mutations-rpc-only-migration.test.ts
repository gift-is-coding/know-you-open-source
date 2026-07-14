import { readFileSync } from "node:fs";
import { expect, it } from "vitest";

const migration = readFileSync(
  new URL("../supabase/migrations/202607130011_networking_person_mutations_rpc_only.sql", import.meta.url),
  "utf8",
).toLowerCase();

it("retires direct person mutations after atomic activation becomes the owner write path", () => {
  expect(migration).toContain("revoke insert, update on table public.people");
  expect(migration).toContain("from authenticated");
  expect(migration).not.toContain("grant insert");
  expect(migration).not.toContain("grant update");
});
