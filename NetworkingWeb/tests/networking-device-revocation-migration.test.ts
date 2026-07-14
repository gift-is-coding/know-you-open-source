import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const migration = readFileSync(
  new URL("../supabase/migrations/202607130001_networking_device_token_revocation.sql", import.meta.url),
  "utf8",
).toLowerCase();

describe("networking device credential revocation", () => {
  it("binds each device to its agent token without storing plaintext", () => {
    expect(migration).toContain("agent_token_hash text");
    expect(migration).toContain("p_agent_token_hash text");
    expect(migration).toContain("agent_token_hash = p_agent_token_hash");
    expect(migration).toContain("^[0-9a-f]{64}$");
  });

  it("revokes the linked agent token in the same device revoke RPC", () => {
    expect(migration).toMatch(/update public\.agent_tokens[\s\S]*set revoked_at = now\(\)/);
    expect(migration).toContain("token_hash = linked_agent_token_hash");
    expect(migration).toContain("and revoked_at is null");
  });

  it("does not return revoked devices as occupied slots", () => {
    expect(migration).toMatch(/networking_list_devices\(\)[\s\S]*revoked_at is null/);
  });
});
