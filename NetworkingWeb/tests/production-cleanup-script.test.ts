import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";

const source = readFileSync(new URL("../scripts/cleanup-production-e2e.mjs", import.meta.url), "utf8");

describe("production E2E cleanup script", () => {
  it("is dry-run by default and requires explicit destructive confirmation", () => {
    expect(source).toContain('process.argv.includes("--execute")');
    expect(source).toContain("CONFIRM_NETWORKING_E2E_DELETE");
    expect(source).toContain("SUPABASE_SERVICE_ROLE_KEY");
    expect(source).toContain("DRY RUN");
  });

  it("uses narrow E2E markers and excludes known real production evidence", () => {
    expect(source).toContain("e2e-knowyou-");
    expect(source).toContain("ky_e2e_");
    expect(source).toContain("eeeeeeee-");
    expect(source).toContain("tianfu-wu");
    expect(source).toContain("fb291511-a07d-49e9-96ad-403f6336662c");
    expect(source).toContain("!protectedPostIDs.has(comment.post_id)");
    expect(source).not.toContain("delete().neq");
  });
});
