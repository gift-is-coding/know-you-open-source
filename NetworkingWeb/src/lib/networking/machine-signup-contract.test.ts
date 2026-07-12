import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const migration = readFileSync(join(process.cwd(), "supabase/migrations/202607120001_networking_machine_signup_rate_limit.sql"), "utf8");
const idempotencyMigration = readFileSync(join(process.cwd(), "supabase/migrations/202607120002_networking_machine_signup_idempotency.sql"), "utf8");
const edgeFunction = readFileSync(join(process.cwd(), "supabase/functions/networking-machine-signup/index.ts"), "utf8");

describe("restricted machine signup", () => {
  it("enforces an atomic service-role-only activation rate limit", () => {
    expect(migration).toContain("networking_machine_signup_attempts");
    expect(migration).toContain("pg_advisory_xact_lock");
    expect(migration).toContain("networking_register_machine_signup_attempt");
    expect(migration).toContain("grant execute");
    expect(migration).toContain("to service_role");
    expect(migration).toContain("revoke all");
    expect(migration).toContain("interval '1 hour'");
    expect(idempotencyMigration).toContain("p_identity_hash");
    expect(idempotencyMigration).toContain("p_global_hourly_limit");
    expect(idempotencyMigration).toContain("networking-machine-signup-global");
    expect(idempotencyMigration).toContain("where identity_hash = p_identity_hash");
  });

  it("validates machine credentials and creates confirmed users through the admin API", () => {
    expect(edgeFunction).toContain("users\\.knowyou\\.app");
    expect(edgeFunction).toContain("cf-connecting-ip");
    expect(edgeFunction).not.toContain("x-forwarded-for");
    expect(edgeFunction).toContain("networking_register_machine_signup_attempt");
    expect(edgeFunction).toContain("auth.admin.createUser");
    expect(edgeFunction).toContain("email_confirm: true");
    expect(edgeFunction).toContain("status: 429");
    expect(edgeFunction).toContain('Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")');
    expect(edgeFunction).not.toContain("serviceRoleKey }");
  });
});
