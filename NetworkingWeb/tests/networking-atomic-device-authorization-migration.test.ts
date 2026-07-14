import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const migration = readFileSync(
  new URL("../supabase/migrations/202607130002_networking_atomic_device_authorization.sql", import.meta.url),
  "utf8",
).toLowerCase();

describe("atomic networking device authorization", () => {
  it("creates the agent token and device in one owner-scoped transaction", () => {
    expect(migration).toContain("networking_authorize_device");
    expect(migration).toContain("insert into public.agent_tokens");
    expect(migration).toContain("insert into public.networking_devices");
    expect(migration).toContain("people.user_id = current_user_id");
    expect(migration).toContain("pg_advisory_xact_lock");
  });

  it("prevents one agent token from being linked to multiple devices", () => {
    expect(migration).toContain("create unique index");
    expect(migration).toContain("user_id, agent_token_hash");
    expect(migration).toContain("where agent_token_hash is not null");
  });

  it("is unavailable to anonymous callers", () => {
    expect(migration).toContain("revoke all on function public.networking_authorize_device");
    expect(migration).toContain("from public, anon");
    expect(migration).toContain("to authenticated");
  });
});
