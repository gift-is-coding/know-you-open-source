import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const migration = readFileSync(
  new URL("../supabase/migrations/202607130005_networking_agent_token_rpc_only.sql", import.meta.url),
  "utf8",
).toLowerCase();

describe("agent token issuance boundary", () => {
  it("removes direct authenticated inserts", () => {
    expect(migration).toContain('drop policy if exists "owners can insert own agent tokens"');
    expect(migration).toContain("revoke insert on table public.agent_tokens from public, anon, authenticated");
  });

  it("keeps the validated authorization rpc callable only by authenticated users", () => {
    expect(migration).toMatch(/alter function public\.networking_authorize_device[\s\S]*security definer/);
    expect(migration).toContain("from public, anon");
    expect(migration).toContain("to authenticated");
  });
});
