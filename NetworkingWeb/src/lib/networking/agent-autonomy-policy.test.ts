import { describe, expect, it } from "vitest";
import { resolveAgentAutonomyPolicy } from "./agent-autonomy-policy";

describe("resolveAgentAutonomyPolicy", () => {
  it.each([
    ["conservative", 1, 4, 8, 3, 72],
    ["balanced", 2, 10, 20, 5, 48],
    ["active", 4, 20, 40, 8, 24]
  ] as const)("resolves %s mode budgets", (mode, posts, comments, replies, turns, strangerCooldown) => {
    const policy = resolveAgentAutonomyPolicy({ autonomyMode: mode }, "knowyou-friends");

    expect(policy).toMatchObject({
      autonomyMode: mode,
      dailyAutoPostLimit: posts,
      dailyProactiveCommentLimit: comments,
      dailyAutoReplyLimit: replies,
      maxAutonomousThreadTurns: turns,
      unfamiliarPersonCooldownHours: strangerCooldown
    });
  });

  it("defaults to balanced and preserves explicit legacy limits", () => {
    const policy = resolveAgentAutonomyPolicy(
      { autoComment: true, dailyAutoCommentLimit: 7, commentCooldownSeconds: 45, riskyContentAction: "save_for_human" },
      "knowyou-jobs"
    );

    expect(policy.autonomyMode).toBe("balanced");
    expect(policy.dailyProactiveCommentLimit).toBe(7);
    expect(policy.dailyAutoCommentLimit).toBe(7);
    expect(policy.commentCooldownSeconds).toBe(45);
  });

  it("requires denser career comments while allowing lighter friends comments", () => {
    const friends = resolveAgentAutonomyPolicy(undefined, "knowyou-friends");
    const jobs = resolveAgentAutonomyPolicy(undefined, "knowyou-jobs");

    expect(friends.minimumCommentScore).toBeLessThan(jobs.minimumCommentScore);
    expect(friends.minimumCommentCharacters).toBeLessThan(jobs.minimumCommentCharacters);
  });

  it("uses bounded heartbeat windows for every mode", () => {
    const conservative = resolveAgentAutonomyPolicy({ autonomyMode: "conservative" }, "knowyou-friends");
    const balanced = resolveAgentAutonomyPolicy({ autonomyMode: "balanced" }, "knowyou-friends");
    const active = resolveAgentAutonomyPolicy({ autonomyMode: "active" }, "knowyou-friends");

    expect([conservative.heartbeatMinMinutes, conservative.heartbeatMaxMinutes]).toEqual([240, 360]);
    expect([balanced.heartbeatMinMinutes, balanced.heartbeatMaxMinutes]).toEqual([120, 180]);
    expect([active.heartbeatMinMinutes, active.heartbeatMaxMinutes]).toEqual([60, 120]);
  });
});
