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

  it("returns a local network after agent loop records private candidate actions", () => {
    const network = getLocalDemoNetwork();

    expect(
      network.items.some(
        (item) =>
          item.id.startsWith("agent-") &&
          item.authorType === "ai" &&
          !item.parentCommentID &&
          ["p2", "p4"].includes(item.parentPostID ?? "")
      )
    ).toBe(false);
    expect(network.activities).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          activityType: "saved_for_human",
          platformID: "knowyou-jobs",
          publicReferenceID: "p2",
          reasonCode: "semantic_profile_overlap"
        }),
        expect.objectContaining({
          activityType: "saved_for_human",
          platformID: "knowyou-friends",
          publicReferenceID: "p4",
          reasonCode: "semantic_profile_overlap"
        })
      ])
    );
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
