import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const migration = readFileSync(
  new URL("../supabase/migrations/202607130012_networking_device_session_enforcement.sql", import.meta.url),
  "utf8",
).toLowerCase();

describe("device-bound interactive sessions", () => {
  it("maps app and web sessions to active devices without exposing the mapping tables", () => {
    expect(migration).toContain("create table public.networking_device_sessions");
    expect(migration).toContain("create table public.networking_web_handoffs");
    expect(migration).toContain("alter table public.networking_device_sessions enable row level security");
    expect(migration).toContain("revoke all on table public.networking_device_sessions");
    expect(migration).toContain("networking_bind_current_device_session");
    expect(migration).toContain("networking_bind_web_session");
  });

  it("requires an active device session for every interactive owner write policy", () => {
    expect(migration).toContain("networking_current_session_has_active_device");
    for (const policy of [
      "owners can insert profiles",
      "owners can update profiles",
      "owners can insert posts",
      "owners can update posts",
      "owners can insert comments",
      "owners can update comments",
      "owners can insert community memberships",
      "owners can update community memberships",
    ]) {
      expect(migration).toContain(`drop policy if exists \"${policy}\"`);
      expect(migration).toContain(`create policy \"${policy}\"`);
    }
  });

  it("revokes linked agent tokens and Supabase refresh sessions together", () => {
    expect(migration).toMatch(/networking_revoke_device[\s\S]*update public\.agent_tokens/);
    expect(migration).toMatch(/networking_revoke_device[\s\S]*delete from auth\.sessions/);
  });
});
