import { readFileSync } from "node:fs";
import { expect, it } from "vitest";

const migration = readFileSync(
  new URL("../supabase/migrations/202607140004_networking_device_management_live_session.sql", import.meta.url),
  "utf8",
).toLowerCase();

it("requires a server-live session for device listing and revocation", () => {
  for (const functionName of ["networking_list_devices", "networking_revoke_device"]) {
    const start = migration.indexOf(`create or replace function public.${functionName}`);
    expect(start).toBeGreaterThan(-1);
    const definition = migration.slice(start, migration.indexOf("$$;", start) + 3);
    expect(definition).toContain("networking_current_session_is_live");
    expect(definition).toContain("networking_auth_required");
  }
});
