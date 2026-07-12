import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const migration = readFileSync(
  new URL("../../../supabase/migrations/202607120003_networking_agent_autonomy.sql", import.meta.url),
  "utf8"
);

describe("networking agent autonomy migration", () => {
  it("adds balanced policy defaults without changing RPC signatures", () => {
    expect(migration).toContain('"autonomyMode": "balanced"');
    expect(migration).toContain('"dailyAutoPostLimit": 2');
    expect(migration).toContain('"dailyProactiveCommentLimit": 10');
    expect(migration).toContain('"dailyAutoReplyLimit": 20');
    expect(migration).toContain("jsonb_strip_nulls");
  });

  it("enforces action budgets, cooldown, and thread depth for AI writes", () => {
    expect(migration).toContain("networking_enforce_agent_comment_autonomy");
    expect(migration).toContain("daily proactive-comment limit reached");
    expect(migration).toContain("daily reply limit reached");
    expect(migration).toContain("agent comment cooldown active");
    expect(migration).toContain("autonomous thread turn limit reached");
    expect(migration).toContain("unfamiliar-person cooldown active");
    expect(migration).toContain("target_person_id");
    expect(migration).toContain("before insert on public.comments");
    expect(migration).toContain("pg_advisory_xact_lock");
    expect(migration).toContain("active networking membership required");
  });

  it("atomically applies every mode-owned budget when the owner changes mode", () => {
    expect(migration).toContain("networking_update_autonomy_mode");
    expect(migration).toContain("dailyProactiveCommentLimit");
    expect(migration).toContain("dailyAutoReplyLimit");
    expect(migration).toContain("maxAutonomousThreadTurns");
    expect(migration).toContain("unfamiliarPersonCooldownHours");
    expect(migration).toContain("p_mode = 'active'");
    expect(migration).toContain("from public, anon");
    expect(migration).toContain("to authenticated");
    expect(migration).toContain("security invoker");
  });

  it("returns persisted useful outcomes from Agent Home", () => {
    const homeModeMigration = readFileSync(
      new URL("../../../supabase/migrations/202607120006_networking_agent_relationship_cooldown_home_mode.sql", import.meta.url),
      "utf8"
    );

    expect(homeModeMigration).toContain("'usefulReturns'");
    expect(homeModeMigration).toContain("public.agent_activity");
    expect(homeModeMigration).toContain("person_review");
  });
});
