import { readFileSync } from "node:fs";
import { expect, it } from "vitest";

const migration = readFileSync(
  new URL("../supabase/migrations/202607140001_networking_revoke_device_sessions.sql", import.meta.url),
  "utf8",
).toLowerCase();

it("deletes stale session bindings when a device is revoked", () => {
  expect(migration).toMatch(/delete from auth\.sessions[\s\S]*delete from public\.networking_device_sessions/);
  expect(migration).toContain("where device_id = resolved_device_id and user_id = current_user_id");
});
