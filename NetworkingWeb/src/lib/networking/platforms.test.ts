import { describe, expect, it } from "vitest";
import { networkingPlatforms, profilesForPerson } from "./platforms";
import { profilePageFixture, publicSquareFixture } from "./fixtures";

describe("networking platforms", () => {
  it("ships only the two Know You-owned platforms in V1", () => {
    expect(networkingPlatforms.map((platform) => platform.id)).toEqual([
      "knowyou-jobs",
      "knowyou-friends"
    ]);
    expect(networkingPlatforms.map((platform) => platform.displayName)).toEqual([
      "Know You Careers",
      "Find Your Friends"
    ]);
  });

  it("keeps multiple profile faces under one fixed person name", () => {
    expect(profilePageFixture.person.displayName).toBe("林书涵");
    expect(profilePageFixture.profiles.map((profile) => profile.personName)).toEqual([
      "林书涵",
      "林书涵"
    ]);
    expect(profilePageFixture.profiles.map((profile) => profile.avatarSeed)).toEqual([
      "lin-shuhan-jobs",
      "lin-shuhan-friends"
    ]);
  });

  it("maps public posts and comments to one of the two platforms", () => {
    const allowedPlatformIDs = networkingPlatforms.map((platform) => platform.id);

    expect(publicSquareFixture.every((item) => allowedPlatformIDs.includes(item.platformID))).toBe(true);
  });

  it("returns profile faces for the current person with platform scenarios", () => {
    const faces = profilesForPerson(profilePageFixture);

    expect(faces.map((face) => face.scenarioID)).toEqual(["jobs", "friends"]);
    expect(faces.map((face) => face.platformIDs)).toEqual([
      ["knowyou-jobs"],
      ["knowyou-friends"]
    ]);
  });
});
