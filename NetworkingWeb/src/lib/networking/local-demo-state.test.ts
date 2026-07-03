import { describe, expect, it } from "vitest";
import { bootstrapLocalDemoState, getLocalDemoNetwork } from "./local-demo-state";

describe("local demo networking state", () => {
  it("bootstraps two communities with active profile-agent memberships", () => {
    const state = bootstrapLocalDemoState();

    expect(state.memberships).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          communityID: "knowyou-jobs",
          profileID: "profile-shuhan-jobs",
          status: "active"
        }),
        expect.objectContaining({
          communityID: "knowyou-friends",
          profileID: "profile-shuhan-friends",
          status: "active"
        })
      ])
    );
    expect(state.profiles.length).toBeGreaterThanOrEqual(4);
  });

  it("returns a local network after agent loop writes visible AI comments", () => {
    const network = getLocalDemoNetwork();

    const jobsAgentComment = network.items.find(
      (item) =>
        item.kind === "comment" &&
        item.id.startsWith("agent-") &&
        item.platformID === "knowyou-jobs" &&
        item.authorType === "ai" &&
        item.profile.id === "profile-shuhan-jobs"
    );
    const friendsAgentComment = network.items.find(
      (item) =>
        item.kind === "comment" &&
        item.id.startsWith("agent-") &&
        item.platformID === "knowyou-friends" &&
        item.authorType === "ai" &&
        item.profile.id === "profile-shuhan-friends"
    );

    expect(jobsAgentComment?.parentPostID).toBe("p2");
    expect(friendsAgentComment?.parentPostID).toBe("p4");
    expect(network.activities.map((activity) => activity.activityType)).toContain("auto_comment");
  });

  it("does not create cross-community agent comments", () => {
    const network = getLocalDemoNetwork();

    expect(
      network.items.some(
        (item) =>
          item.kind === "comment" &&
          item.platformID === "knowyou-friends" &&
          item.profile.id === "profile-shuhan-jobs"
      )
    ).toBe(false);
  });
});
