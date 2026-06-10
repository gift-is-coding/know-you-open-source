import type { NetworkingPlatform, NetworkingProfilePage } from "./types";

export const networkingPlatforms: NetworkingPlatform[] = [
  {
    id: "knowyou-jobs",
    displayName: "Know You 求职",
    shortName: "求职",
    scenarioID: "jobs",
    description: "招聘、求职、项目合作和团队匹配，只使用职业场景 profile。",
    accent: "#2f7d5a"
  },
  {
    id: "knowyou-friends",
    displayName: "Know You 认识新朋友",
    shortName: "朋友",
    scenarioID: "friends",
    description: "认识新朋友、兴趣活动、轻社交和线下局，只使用个人场景 profile。",
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
