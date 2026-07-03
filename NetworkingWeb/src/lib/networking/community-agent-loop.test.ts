import { describe, expect, it } from "vitest";
import { runCommunityAgentLoop } from "./community-agent-loop";
import type { NetworkingContentItem, NetworkingPerson, NetworkingProfile } from "./types";

const shuhan: NetworkingPerson = {
  id: "person-shuhan",
  displayName: "林书涵",
  handle: "shuhan",
  initial: "林"
};

const shuhanJobs: NetworkingProfile = {
  id: "profile-shuhan-jobs",
  personName: "林书涵",
  label: "职业/求职",
  slug: "jobs",
  scenarioID: "jobs",
  platformIDs: ["knowyou-jobs"],
  summary: "做 KnowYou、agent runtime、SwiftUI、Next.js 和 Supabase。"
};

const shuhanFriends: NetworkingProfile = {
  id: "profile-shuhan-friends",
  personName: "林书涵",
  label: "认识新朋友",
  slug: "friends",
  scenarioID: "friends",
  platformIDs: ["knowyou-friends"],
  summary: "喜欢摄影展、城市散步、电影和小范围聊天。"
};

const posts: NetworkingContentItem[] = [
  {
    id: "post-career",
    kind: "post",
    platformID: "knowyou-jobs",
    authorType: "human",
    body: "找一个会做 agent runtime、Next.js 和 Supabase 的 founding engineer。",
    createdAt: "2026-06-12T08:00:00.000Z",
    person: { id: "person-a", displayName: "周思齐", handle: "siqi", initial: "周" },
    profile: {
      id: "profile-siqi-jobs",
      label: "职业/求职",
      slug: "jobs",
      platformIDs: ["knowyou-jobs"],
      summary: "想找 agent safety 相关机会。"
    }
  },
  {
    id: "post-friends",
    kind: "post",
    platformID: "knowyou-friends",
    authorType: "human",
    body: "周末想找人一起看摄影展，然后城市散步。",
    createdAt: "2026-06-12T09:00:00.000Z",
    person: { id: "person-b", displayName: "许安然", handle: "anran", initial: "许" },
    profile: {
      id: "profile-anran-friends",
      label: "认识新朋友",
      slug: "friends",
      platformIDs: ["knowyou-friends"],
      summary: "喜欢展览和城市散步。"
    }
  }
];

describe("runCommunityAgentLoop", () => {
  it("auto-comments only when a joined profile matches a post in the same community", () => {
    const result = runCommunityAgentLoop({
      now: new Date("2026-06-12T10:00:00.000Z"),
      people: [shuhan],
      profiles: [shuhanJobs],
      memberships: [
        {
          communityID: "knowyou-jobs",
          profileID: "profile-shuhan-jobs",
          personID: "person-shuhan",
          status: "active"
        }
      ],
      items: posts
    });

    expect(result.items.some((item) => item.kind === "comment" && item.parentPostID === "post-career" && item.authorType === "ai")).toBe(true);
    expect(result.items.some((item) => item.kind === "comment" && item.parentPostID === "post-friends" && item.authorType === "ai")).toBe(false);
  });

  it("does not duplicate an agent comment for the same profile and post", () => {
    const first = runCommunityAgentLoop({
      now: new Date("2026-06-12T10:00:00.000Z"),
      people: [shuhan],
      profiles: [shuhanJobs],
      memberships: [
        {
          communityID: "knowyou-jobs",
          profileID: "profile-shuhan-jobs",
          personID: "person-shuhan",
          status: "active"
        }
      ],
      items: posts
    });

    const second = runCommunityAgentLoop({
      now: new Date("2026-06-12T10:05:00.000Z"),
      people: [shuhan],
      profiles: [shuhanJobs],
      memberships: [
        {
          communityID: "knowyou-jobs",
          profileID: "profile-shuhan-jobs",
          personID: "person-shuhan",
          status: "active"
        }
      ],
      items: first.items
    });

    expect(second.items.filter((item) => item.kind === "comment" && item.parentPostID === "post-career" && item.profile.id === "profile-shuhan-jobs")).toHaveLength(1);
  });

  it("records activity for each safe auto-comment", () => {
    const result = runCommunityAgentLoop({
      now: new Date("2026-06-12T10:00:00.000Z"),
      people: [shuhan],
      profiles: [shuhanJobs, shuhanFriends],
      memberships: [
        {
          communityID: "knowyou-jobs",
          profileID: "profile-shuhan-jobs",
          personID: "person-shuhan",
          status: "active"
        },
        {
          communityID: "knowyou-friends",
          profileID: "profile-shuhan-friends",
          personID: "person-shuhan",
          status: "active"
        }
      ],
      items: posts
    });

    expect(result.activities.map((activity) => activity.activityType)).toEqual(["auto_comment", "auto_comment"]);
    expect(result.activities.map((activity) => activity.platformID)).toEqual(["knowyou-jobs", "knowyou-friends"]);
  });
});
