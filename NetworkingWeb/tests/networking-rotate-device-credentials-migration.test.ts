import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const migration = readFileSync(
  new URL("../supabase/migrations/202607130004_networking_rotate_device_credentials.sql", import.meta.url),
  "utf8",
).toLowerCase();

describe("same-device credential rotation", () => {
  it("revokes the previous linked agent token before replacement", () => {
    expect(migration).toMatch(/existing_device\.agent_token_hash[\s\S]*update public\.agent_tokens[\s\S]*revoked_at = now\(\)/);
    expect(migration).toContain("token_hash = existing_device.agent_token_hash");
  });

  it("does not consume a new slot for an already active device id", () => {
    expect(migration).toContain("existing_device.id is null or existing_device.revoked_at is not null");
    expect(migration).toContain("where id = existing_device.id");
  });
});
