import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const migration = readFileSync(
  new URL("../supabase/migrations/202607130007_networking_device_mutations_rpc_only.sql", import.meta.url),
  "utf8",
).toLowerCase();

describe("device mutation boundary", () => {
  it("removes direct device and token mutation policies", () => {
    expect(migration).toContain('drop policy if exists "owners can insert networking devices"');
    expect(migration).toContain('drop policy if exists "owners can update networking devices"');
    expect(migration).toContain('drop policy if exists "owners can revoke own agent tokens"');
  });

  it("revokes direct writes while preserving authenticated revoke RPC access", () => {
    expect(migration).toMatch(/revoke insert, update, delete, truncate, references, trigger[\s\S]*public\.networking_devices/);
    expect(migration).toMatch(/revoke insert, update, delete, truncate, references, trigger[\s\S]*public\.agent_tokens/);
    expect(migration).toContain("alter function public.networking_revoke_device(text) security definer");
    expect(migration).toContain("grant execute on function public.networking_revoke_device(text) to authenticated");
  });
});
