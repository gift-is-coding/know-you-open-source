import { runAgentHeartbeat } from "./agent-home";
import {
  runCommunityAgentLoop,
  type NetworkingAgentActivity,
  type NetworkingCommunityMembership,
  type NetworkingInteractionEvent
} from "./community-agent-loop";
import { profilePageFixture, publicSquareFixture } from "./fixtures";
import type { NetworkingContentItem, NetworkingPerson, NetworkingProfile } from "./types";

export interface LocalDemoNetworkingState {
  people: NetworkingPerson[];
  profiles: NetworkingProfile[];
  memberships: NetworkingCommunityMembership[];
  items: NetworkingContentItem[];
  events: NetworkingInteractionEvent[];
  activities: NetworkingAgentActivity[];
}

const demoNow = new Date("2026-06-12T10:00:00.000Z");

export function bootstrapLocalDemoState(): LocalDemoNetworkingState {
  const extraPeople: NetworkingPerson[] = [
    { id: "person-siqi", displayName: "周思齐", handle: "siqi", initial: "周" },
    { id: "person-yiming", displayName: "陈一鸣", handle: "yiming", initial: "陈" },
    { id: "person-anran", displayName: "许安然", handle: "anran", initial: "许" }
  ];

  const extraProfiles: NetworkingProfile[] = [
    {
      id: "profile-siqi-jobs",
      personName: "周思齐",
      label: "职业/求职",
      englishLabel: "Jobs",
      slug: "jobs",
      scenarioID: "jobs",
      scenarioDescription: "想找 evals、interpretability、agent safety 工作。",
      platformIDs: ["knowyou-jobs"],
      published: true,
      avatarLetter: "职",
      avatarBg: "#386aa0",
      avatarSeed: "zhou-siqi-jobs",
      avatarStyle: "gradient",
      summary: "在找 evals、interpretability、agent safety 和调试相关机会。"
    },
    {
      id: "profile-yiming-jobs",
      personName: "陈一鸣",
      label: "职业/求职",
      englishLabel: "Jobs",
      slug: "jobs",
      scenarioID: "jobs",
      scenarioDescription: "关注 agent 平台治理和产品工程。",
      platformIDs: ["knowyou-jobs"],
      published: true,
      avatarLetter: "职",
      avatarBg: "#5d5f9f",
      avatarSeed: "chen-yiming-jobs",
      avatarStyle: "gradient",
      summary: "做 agent 平台治理、产品工程、社区规则和重复评论治理。"
    },
    {
      id: "profile-anran-friends",
      personName: "许安然",
      label: "认识新朋友",
      englishLabel: "Friends",
      slug: "friends",
      scenarioID: "friends",
      scenarioDescription: "喜欢线下小活动、摄影展和周末城市散步。",
      platformIDs: ["knowyou-friends"],
      published: true,
      avatarLetter: "友",
      avatarBg: "#9a7b2f",
      avatarSeed: "xu-anran-friends",
      avatarStyle: "gradient",
      summary: "喜欢摄影展、城市散步、安静咖啡店和小范围聊天。"
    }
  ];

  const people = [profilePageFixture.person, ...extraPeople];
  const profiles = [...profilePageFixture.profiles, ...extraProfiles];
  const memberships: NetworkingCommunityMembership[] = [
    {
      communityID: "knowyou-jobs",
      profileID: "profile-shuhan-jobs",
      personID: "person-shuhan",
      status: "active",
      policy: defaultPolicy()
    },
    {
      communityID: "knowyou-friends",
      profileID: "profile-shuhan-friends",
      personID: "person-shuhan",
      status: "active",
      policy: defaultPolicy()
    },
    {
      communityID: "knowyou-jobs",
      profileID: "profile-siqi-jobs",
      personID: "person-siqi",
      status: "active",
      policy: defaultPolicy()
    },
    {
      communityID: "knowyou-jobs",
      profileID: "profile-yiming-jobs",
      personID: "person-yiming",
      status: "active",
      policy: defaultPolicy()
    },
    {
      communityID: "knowyou-friends",
      profileID: "profile-anran-friends",
      personID: "person-anran",
      status: "active",
      policy: defaultPolicy()
    }
  ];

  const demoItems: NetworkingContentItem[] = [
    ...publicSquareFixture,
    {
      id: "p4",
      kind: "post",
      platformID: "knowyou-friends",
      authorType: "human",
      body: "这周想找两三个人看一场老电影，然后在附近城市散步聊天。",
      createdAt: "2026-06-12T07:40:00.000Z",
      timestampLabel: "今天 · 15:40",
      topic: "电影 / 城市散步",
      person: { id: "person-yiming", displayName: "陈一鸣", handle: "yiming", initial: "陈" },
      profile: {
        id: "profile-yiming-friends",
        personName: "陈一鸣",
        label: "认识新朋友",
        englishLabel: "Friends",
        slug: "friends",
        scenarioID: "friends",
        scenarioDescription: "想认识喜欢电影、城市散步和小范围聊天的人。",
        platformIDs: ["knowyou-friends"],
        published: true,
        avatarLetter: "友",
        avatarBg: "#5d5f9f",
        avatarSeed: "chen-yiming-friends",
        avatarStyle: "gradient",
        summary: "想认识喜欢电影和城市散步的新朋友。"
      }
    },
    {
      id: "p4-c1",
      kind: "comment",
      platformID: "knowyou-friends",
      authorType: "human",
      body: "我也想看这场电影，如果是两三个人的小范围聊天我会比较自在。",
      createdAt: "2026-06-12T08:10:00.000Z",
      timestampLabel: "今天 · 16:10",
      person: { id: "person-anran", displayName: "许安然", handle: "anran", initial: "许" },
      profile: extraProfiles[2],
      parentPostID: "p4"
    }
  ];
  const events: NetworkingInteractionEvent[] = [
    {
      id: "event-p4-c1",
      platformID: "knowyou-friends",
      personID: "person-shuhan",
      profileID: "profile-shuhan-friends",
      eventType: "reply_to_my_comment",
      postID: "p4",
      commentID: "p4-c1",
      actorPersonID: "person-anran",
      actorProfileID: "profile-anran-friends",
      createdAt: "2026-06-12T08:10:00.000Z"
    }
  ];

  return {
    people,
    profiles,
    memberships,
    items: demoItems,
    events,
    activities: []
  };
}

export function getLocalDemoNetwork(): LocalDemoNetworkingState {
  const state = bootstrapLocalDemoState();
  const loop = runCommunityAgentLoop({
    now: demoNow,
    people: state.people,
    profiles: state.profiles,
    memberships: state.memberships,
    items: state.items
  });
  const membership = state.memberships.find((item) => item.profileID === "profile-shuhan-friends");
  const profile = state.profiles.find((item) => item.id === "profile-shuhan-friends");
  const person = state.people.find((item) => item.id === "person-shuhan");
  const heartbeat =
    membership && profile && person
      ? runAgentHeartbeat({
          now: new Date("2026-06-12T10:05:00.000Z"),
          person,
          profile,
          membership,
          items: loop.items,
          events: state.events,
          recentActivities: loop.activities
        })
      : { items: loop.items, events: state.events, activities: [] };

  return {
    ...state,
    items: heartbeat.items,
    events: heartbeat.events,
    activities: [...loop.activities, ...heartbeat.activities]
  };
}

function defaultPolicy() {
  return {
    autoComment: true,
    dailyAutoCommentLimit: 8,
    commentCooldownSeconds: 20,
    riskyContentAction: "save_for_human" as const
  };
}
