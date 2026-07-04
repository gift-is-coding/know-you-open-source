import type { NetworkingPlatform, NetworkingProfilePage } from "./types";

export const networkingPlatforms: NetworkingPlatform[] = [
  {
    id: "knowyou-jobs",
    displayName: "Know You Careers",
    shortName: "Careers",
    scenarioID: "jobs",
    description: "Jobs, hiring, project collaboration, and team matching through a career-facing profile.",
    accent: "#2f7d5a"
  },
  {
    id: "knowyou-friends",
    displayName: "Find Your Friends",
    shortName: "Friends",
    scenarioID: "friends",
    description: "New friends, shared interests, small activities, and everyday social discovery through a personal profile.",
    accent: "#c46a4a"
  }
];

export const defaultNetworkingPlatformID = networkingPlatforms[0].id;

export function isNetworkingPlatformID(value: string): value is "knowyou-jobs" | "knowyou-friends" {
  return networkingPlatforms.some((platform) => platform.id === value);
}

export function getNetworkingPlatform(platformID: string) {
  return networkingPlatforms.find((platform) => platform.id === platformID) ?? networkingPlatforms[0];
}

export function profilesForPerson(page: NetworkingProfilePage) {
  return page.profiles
    .filter((profile) => profile.published !== false)
    .sort((left, right) => scenarioRank(left.scenarioID) - scenarioRank(right.scenarioID));
}

function scenarioRank(value?: string) {
  const index = networkingPlatforms.findIndex((platform) => platform.scenarioID === value);
  return index === -1 ? Number.MAX_SAFE_INTEGER : index;
}
