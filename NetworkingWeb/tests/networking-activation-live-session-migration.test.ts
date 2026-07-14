import { readFileSync } from "node:fs";
import { expect, it } from "vitest";

const migration = readFileSync(
  new URL("../supabase/migrations/202607140002_networking_activation_requires_live_session.sql", import.meta.url),
  "utf8",
).toLowerCase();

it("rejects activation from a signed but server-revoked Supabase session", () => {
  expect(migration).toContain("current_session_id uuid");
  expect(migration).toContain("select 1 from auth.sessions");
  expect(migration).toContain("sessions.id = current_session_id");
  expect(migration).toContain("sessions.user_id = current_user_id");
});
