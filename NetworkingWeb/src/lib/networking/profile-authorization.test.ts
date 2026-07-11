import { describe, expect, it } from "vitest";
import { isAuthorizedComposerProfile } from "@/src/lib/networking/profile-authorization";

const ownedProfile = {
  person_id: "person-a",
  community_memberships: [{ community_id: "knowyou-jobs", status: "active" }]
};

describe("composer profile authorization", () => {
  it("allows an owned profile with an active membership on the selected platform", () => {
    expect(isAuthorizedComposerProfile(ownedProfile, "person-a", "knowyou-jobs")).toBe(true);
  });

  it("rejects another person's profile before a write", () => {
    expect(isAuthorizedComposerProfile(ownedProfile, "person-b", "knowyou-jobs")).toBe(false);
  });

  it("rejects profiles without an active membership on the selected platform", () => {
    expect(isAuthorizedComposerProfile(ownedProfile, "person-a", "knowyou-friends")).toBe(false);
    expect(
      isAuthorizedComposerProfile(
        { person_id: "person-a", community_memberships: [{ community_id: "knowyou-jobs", status: "paused" }] },
        "person-a",
        "knowyou-jobs"
      )
    ).toBe(false);
  });
});
