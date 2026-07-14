import { readFileSync } from "node:fs";
import { expect, it } from "vitest";

const migration = readFileSync(
  new URL("../supabase/migrations/202607140003_networking_all_device_rpcs_require_live_session.sql", import.meta.url),
  "utf8",
).toLowerCase();

it("requires a server-live session for device gates and every session-binding RPC", () => {
  expect(migration).toContain("create or replace function public.networking_current_session_is_live");
  expect(migration).toContain("select 1 from auth.sessions");
  for (const functionName of [
    "networking_current_session_has_active_device",
    "networking_bind_current_device_session",
    "networking_create_web_handoff",
    "networking_bind_web_session",
  ]) {
    const start = migration.indexOf(`create or replace function public.${functionName}`);
    expect(start).toBeGreaterThan(-1);
    const definition = migration.slice(start, migration.indexOf("$$;", start) + 3);
    expect(definition).toContain("networking_current_session_is_live");
  }
});
