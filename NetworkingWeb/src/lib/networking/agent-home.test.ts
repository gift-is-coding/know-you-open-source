import { describe, expect, it } from "vitest";
import { buildAgentHome, runAgentHeartbeat } from "./agent-home";
import type {
  NetworkingAgentActivity,
  NetworkingCommunityMembership,
  NetworkingInteractionEvent
} from "./community-agent-loop";
import type { NetworkingContentItem, NetworkingPerson, NetworkingProfile } from "./types";

const now = new Date("2026-06-15T08:00:00.000Z");

const shuhan: NetworkingPerson = {
  id: "person-shuhan",
  displayName: "林书涵",
  handle: "shuhan",
  initial: "林"
};

const shuhanFriends: NetworkingProfile = {
  id: "profile-shuhan-friends",
  personName: "林书涵",
  label: "认识新朋友",
  slug: "friends",
  scenarioID: "friends",
  scenarioDescription: "认识喜欢电影、摄影和城市散步的新朋友。",
  platformIDs: ["knowyou-friends"],
  summary: "喜欢摄影展、电影、城市散步和小范围聊天。"
};

const membership: NetworkingCommunityMembership = {
  communityID: "knowyou-friends",
  profileID: shuhanFriends.id,
  personID: shuhan.id,
  status: "active",
  policy: {
    autoComment: true,
    dailyAutoCommentLimit: 2,
    commentCooldownSeconds: 20,
    riskyContentAction: "save_for_human"
  }
};

const otherProfile: NetworkingProfile = {
  id: "profile-anran-friends",
  personName: "许安然",
  label: "认识新朋友",
  slug: "friends",
  scenarioID: "friends",
  platformIDs: ["knowyou-friends"],
  summary: "喜欢摄影展和城市散步。"
};

const post: NetworkingContentItem = {
  id: "post-friends",
  kind: "post",
  platformID: "knowyou-friends",
  authorType: "human",
  body: "周末想找两三个人一起看摄影展，然后城市散步。",
  createdAt: "2026-06-15T07:30:00.000Z",
  person: { id: "person-anran", displayName: "许安然", handle: "anran", initial: "许" },
  profile: otherProfile
};

function heartbeatInput(overrides: Partial<Parameters<typeof runAgentHeartbeat>[0]> = {}) {
  return {
    now,
    person: shuhan,
    profile: shuhanFriends,
    membership,
    items: [post],
    events: [],
    recentActivities: [],
    ...overrides
  };
}

describe("profile-agent home and heartbeat", () => {
  it("returns an agent task queue split into needs reply, potential matches, and saved for human", () => {
    const safePost: NetworkingContentItem = {
      ...post,
      id: "post-safe",
      body: "周末想找喜欢摄影展和城市散步的人小范围聊天。"
    };
    const riskyPost: NetworkingContentItem = {
      ...post,
      id: "post-risky",
      body: "想直接交换住址、聊 offer 和合同细节。"
    };
    const event: NetworkingInteractionEvent = {
      id: "event-reply",
      platformID: "knowyou-friends",
      personID: shuhan.id,
      profileID: shuhanFriends.id,
      eventType: "reply_to_my_comment",
      postID: safePost.id,
      commentID: "comment-question",
      actorPersonID: "person-anran",
      actorProfileID: otherProfile.id,
      createdAt: "2026-06-15T07:45:00.000Z"
    };

    const home = buildAgentHome(
      heartbeatInput({
        items: [safePost, riskyPost],
        events: [event]
      })
    );

    expect(home.needsReply.map((task) => task.type)).toEqual(["reply_to_interaction"]);
    expect(home.potentialMatches.map((task) => task.publicReferenceID)).toEqual(["post-safe"]);
    expect(home.savedForYou.map((task) => task.publicReferenceID)).toEqual(["post-risky"]);
    expect(home.potentialMatches[0]).toMatchObject({
      source: "semantic_candidate",
      recommendedAction: "express_interest",
      reasonCodes: expect.arrayContaining(["semantic_profile_overlap", "watching_community"])
    });
    expect(home.potentialMatches[0].publicEvidence.join(" ")).toContain("摄影展");
    expect(JSON.stringify(home.potentialMatches[0])).not.toContain("privateReason");
  });

  it("keeps matching candidates out of public comments when a post has no remaining AI reply slots", () => {
    const existingAIComments: NetworkingContentItem[] = Array.from({ length: 5 }, (_, index) => ({
      id: `existing-ai-${index}`,
      kind: "comment",
      platformID: "knowyou-friends",
      authorType: "ai",
      body: "Existing AI reply.",
      createdAt: `2026-06-15T07:4${index}:00.000Z`,
      person: { id: `person-ai-${index}`, displayName: `AI ${index}`, handle: `ai-${index}` },
      profile: {
        id: `profile-ai-${index}`,
        label: "认识新朋友",
        slug: "friends",
        scenarioID: "friends",
        summary: "摄影展和城市散步。"
      },
      parentPostID: post.id
    }));

    const home = buildAgentHome(heartbeatInput({ items: [post, ...existingAIComments] }));

    expect(home.potentialMatches).toHaveLength(0);
    expect(home.savedForYou[0]).toMatchObject({
      publicReferenceID: post.id,
      reasonCode: "reply_slots_full",
      recommendedAction: "save_for_human"
    });
  });

  it("adds a small exploration queue after semantic candidates without letting it dominate home", () => {
    const unrelatedPosts: NetworkingContentItem[] = [1, 2, 3, 4].map((index) => ({
      id: `post-explore-${index}`,
      kind: "post",
      platformID: "knowyou-friends",
      authorType: "human",
      body: `新用户随便聊一个还没有明显重合的话题 ${index}`,
      createdAt: `2026-06-15T07:0${index}:00.000Z`,
      person: { id: `person-explore-${index}`, displayName: `用户 ${index}`, handle: `u${index}` },
      profile: {
        id: `profile-explore-${index}`,
        label: "认识新朋友",
        slug: "friends",
        scenarioID: "friends",
        summary: "公开 profile。"
      }
    }));

    const home = buildAgentHome(heartbeatInput({ items: unrelatedPosts }));

    expect(home.potentialMatches).toHaveLength(3);
    expect(home.potentialMatches.map((task) => task.source)).toEqual([
      "exploration",
      "exploration",
      "exploration"
    ]);
    expect(home.potentialMatches.every((task) => task.recommendedAction === "save_for_human")).toBe(true);
  });

  it("prioritizes unread replies on my content before public square candidates", () => {
    const event: NetworkingInteractionEvent = {
      id: "event-reply",
      platformID: "knowyou-friends",
      personID: shuhan.id,
      profileID: shuhanFriends.id,
      eventType: "reply_to_my_comment",
      postID: post.id,
      commentID: "comment-question",
      actorPersonID: "person-anran",
      actorProfileID: otherProfile.id,
      createdAt: "2026-06-15T07:45:00.000Z"
    };

    const home = buildAgentHome(heartbeatInput({ events: [event] }));

    expect(home.tasks[0]).toMatchObject({
      type: "reply_to_interaction",
      priority: "high",
      publicReferenceID: "comment-question"
    });
    expect(home.tasks[1]).toMatchObject({
      type: "comment_on_candidate",
      priority: "medium",
      publicReferenceID: post.id
    });
  });

  it("keeps matching candidates private until a person decides to reply publicly", () => {
    const result = runAgentHeartbeat(heartbeatInput());

    expect(result.items.filter((item) => item.authorType === "ai")).toHaveLength(0);
    expect(result.activities).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          activityType: "saved_for_human",
          publicReferenceID: post.id,
          reasonCode: "public_comment_not_substantive"
        })
      ])
    );
    expect(result.events).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          eventType: "human_action_required",
          postID: post.id
        })
      ])
    );
  });

  it("auto-replies to a safe unread comment with parentCommentID in the source language", () => {
    const inboundComment: NetworkingContentItem = {
      id: "comment-question",
      kind: "comment",
      platformID: "knowyou-friends",
      authorType: "human",
      body: "我也想看摄影展，你一般喜欢小范围聊天吗？",
      createdAt: "2026-06-15T07:45:00.000Z",
      person: { id: "person-anran", displayName: "许安然", handle: "anran", initial: "许" },
      profile: otherProfile,
      parentPostID: post.id
    };
    const event: NetworkingInteractionEvent = {
      id: "event-reply",
      platformID: "knowyou-friends",
      personID: shuhan.id,
      profileID: shuhanFriends.id,
      eventType: "reply_to_my_comment",
      postID: post.id,
      commentID: inboundComment.id,
      actorPersonID: inboundComment.person.id,
      actorProfileID: inboundComment.profile.id,
      createdAt: inboundComment.createdAt
    };

    const result = runAgentHeartbeat(heartbeatInput({ items: [post, inboundComment], events: [event] }));
    const reply = result.items.find((item) => item.kind === "comment" && item.authorType === "ai" && item.parentCommentID === inboundComment.id);

    expect(reply?.parentPostID).toBe(post.id);
    expect(reply?.body).toContain("谢谢");
    expect(reply?.body).toContain("公开 profile");
    expect(result.activities.map((activity) => activity.activityType)).toContain("auto_reply");
    expect(result.events.find((item) => item.id === event.id)?.readAt).toBe(now.toISOString());
  });

  it("saves risky candidates for the human instead of auto-commenting", () => {
    const riskyPost: NetworkingContentItem = {
      ...post,
      id: "post-risky",
      body: "我们直接谈 offer、薪资和合同细节吧，也可以交换住址。"
    };

    const result = runAgentHeartbeat(heartbeatInput({ items: [riskyPost] }));

    expect(result.items.filter((item) => item.authorType === "ai")).toHaveLength(0);
    expect(result.activities).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          activityType: "saved_for_human",
          reasonCode: "risky_content"
        })
      ])
    );
    expect(result.events).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          eventType: "human_action_required",
          postID: riskyPost.id
        })
      ])
    );
  });

  it("records a rate-limited activity when daily auto-comment cap is reached", () => {
    const recentActivities: NetworkingAgentActivity[] = [
      {
        id: "activity-1",
        platformID: "knowyou-friends",
        profileID: shuhanFriends.id,
        personID: shuhan.id,
        activityType: "auto_comment",
        publicReferenceType: "post",
        publicReferenceID: "older-post-1",
        summary: "already replied",
        createdAt: "2026-06-15T06:00:00.000Z"
      },
      {
        id: "activity-2",
        platformID: "knowyou-friends",
        profileID: shuhanFriends.id,
        personID: shuhan.id,
        activityType: "auto_reply",
        publicReferenceType: "comment",
        publicReferenceID: "older-comment-1",
        summary: "already replied",
        createdAt: "2026-06-15T06:10:00.000Z"
      }
    ];

    const result = runAgentHeartbeat(heartbeatInput({ recentActivities }));

    expect(result.items.filter((item) => item.authorType === "ai")).toHaveLength(0);
    expect(result.activities).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          activityType: "rate_limited",
          reasonCode: "daily_limit"
        })
      ])
    );
  });
});
