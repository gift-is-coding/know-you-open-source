import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const migration = readFileSync(
  new URL("../supabase/migrations/20260712083702_networking_verified_devices.sql", import.meta.url),
  "utf8",
).toLowerCase();

describe("networking verified devices migration", () => {
  it("creates an owner-scoped device table with RLS", () => {
    expect(migration).toContain("create table public.networking_devices");
    expect(migration).toContain("user_id uuid not null references auth.users(id)");
    expect(migration).toContain("enable row level security");
    expect(migration).toContain("(select auth.uid()) = user_id");
    expect(migration).toContain("credential_hash text not null unique");
  });

  it("registers at most three active devices transactionally", () => {
    expect(migration).toContain("pg_advisory_xact_lock");
    expect(migration).toMatch(/count\(\*\)[\s\S]*>= 3/);
    expect(migration).toContain("networking_device_limit_reached");
    expect(migration).toContain("credential_hash ~ '^[0-9a-f]{64}$'");
  });

  it("exposes owner validated register list and revoke RPCs only to authenticated users", () => {
    expect(migration).toContain("networking_register_device");
    expect(migration).toContain("networking_list_devices");
    expect(migration).toContain("networking_revoke_device");
    expect(migration).toContain("revoke all on function");
    expect(migration).toContain("from public, anon");
    expect(migration).toContain("grant execute on function");
    expect(migration).toContain("to authenticated");
    expect(migration).toContain("revoked_at is null");
  });
});
