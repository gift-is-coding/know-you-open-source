import type { NetworkingContentItem, NetworkingPerson, NetworkingProfile } from "./types";

export type NetworkingCommunityMembershipStatus = "active" | "paused" | "limited";
export type NetworkingAgentActivityType =
  | "heartbeat"
  | "auto_post"
  | "auto_comment"
  | "auto_reply"
  | "skipped"
  | "saved_for_human"
  | "rate_limited"
  | "safety_blocked";
export type NetworkingInteractionEventType =
  | "new_comment_on_my_post"
  | "reply_to_my_comment"
  | "agent_commented"
  | "candidate_found"
  | "human_action_required"
  | "read";

export interface NetworkingCommunityPolicy {
  autoComment: boolean;
  dailyAutoCommentLimit: number;
  commentCooldownSeconds: number;
  riskyContentAction: "save_for_human";
}

export interface NetworkingCommunityMembership {
  communityID: string;
  profileID: string;
  personID: string;
  status: NetworkingCommunityMembershipStatus;
  policy?: NetworkingCommunityPolicy;
  lastHeartbeatAt?: string;
  lastCandidateSeenAt?: string;
}

export interface NetworkingAgentActivity {
  id: string;
  platformID: string;
  profileID: string;
  personID: string;
  activityType: NetworkingAgentActivityType;
  publicReferenceType: "post" | "comment";
  publicReferenceID: string;
  summary: string;
  createdAt: string;
  reasonCode?: string;
  metadata?: Record<string, string | number | boolean | null>;
}

export interface NetworkingInteractionEvent {
  id: string;
  platformID: string;
  personID: string;
  profileID: string;
  eventType: NetworkingInteractionEventType;
  postID?: string;
  commentID?: string;
  actorPersonID?: string;
  actorProfileID?: string;
  createdAt: string;
  readAt?: string;
}

export interface CommunityAgentLoopInput {
  now: Date;
  people: NetworkingPerson[];
  profiles: NetworkingProfile[];
  memberships: NetworkingCommunityMembership[];
  items: NetworkingContentItem[];
}

export interface CommunityAgentLoopResult {
  items: NetworkingContentItem[];
  activities: NetworkingAgentActivity[];
}

const minimumOverlap = 1;

export function runCommunityAgentLoop(input: CommunityAgentLoopInput): CommunityAgentLoopResult {
  const nextItems = [...input.items];
  const activities: NetworkingAgentActivity[] = [];
  const posts = nextItems.filter((item) => item.kind === "post");

  for (const membership of input.memberships) {
    if (membership.status !== "active") {
      continue;
    }

    const profile = input.profiles.find((item) => item.id === membership.profileID);
    const person = input.people.find((item) => item.id === membership.personID);

    if (!profile || !person) {
      continue;
    }

    for (const post of posts) {
      if (post.platformID !== membership.communityID || post.person.id === person.id) {
        continue;
      }

      if (hasExistingAgentComment(nextItems, post.id, profile.id)) {
        continue;
      }

      const relevance = scoreItemRelevance(profile, post);
      if (relevance < minimumOverlap || isRiskyNetworkingContent(post.body)) {
        continue;
      }

      const comment = buildAgentComment({
        now: input.now,
        person,
        profile,
        post,
        relevance
      });
      nextItems.push(comment);
      activities.push({
        id: `activity-${comment.id}`,
        platformID: post.platformID,
        profileID: profile.id,
        personID: person.id,
        activityType: "auto_comment",
        publicReferenceType: "post",
        publicReferenceID: post.id,
        summary: `${profile.label} 自动回应了 ${post.person.displayName} 的帖子。`,
        createdAt: input.now.toISOString()
      });
    }
  }

  return { items: nextItems, activities };
}

function hasExistingAgentComment(items: NetworkingContentItem[], postID: string, profileID: string) {
  return items.some(
    (item) =>
      item.kind === "comment" &&
      item.parentPostID === postID &&
      item.authorType === "ai" &&
      item.profile.id === profileID
  );
}

function buildAgentComment({
  now,
  person,
  profile,
  post,
  relevance
}: {
  now: Date;
  person: NetworkingPerson;
  profile: NetworkingProfile;
  post: NetworkingContentItem;
  relevance: number;
}): NetworkingContentItem {
  const lead = profile.scenarioID === "friends" ? "这个活动和我的公开朋友 profile 有重合" : "这个机会和我的公开职业 profile 有重合";
  const summary = profile.summary ? `我会把这条带回给主人；公开 profile 里相关的是：${profile.summary}` : "我会把这条带回给主人继续判断。";

  return {
    id: `agent-${profile.id}-${post.id}`,
    kind: "comment",
    platformID: post.platformID,
    authorType: "ai",
    body: `${lead}。${summary}`,
    createdAt: now.toISOString(),
    timestampLabel: "刚刚",
    agentLabel: `${person.displayName}'s KnowYou`,
    person,
    profile,
    parentPostID: post.id,
    topic: `auto relevance ${relevance}`
  };
}

export function scoreItemRelevance(profile: NetworkingProfile, item: NetworkingContentItem) {
  const profileTokens = tokenize([profile.label, profile.scenarioDescription, profile.summary, profile.slug].join(" "));
  const itemTokens = tokenize([item.body, item.topic, item.profile.summary].join(" "));
  let overlap = 0;

  for (const token of profileTokens) {
    if (itemTokens.has(token)) {
      overlap += 1;
    }
  }

  return overlap;
}

function tokenize(value: string) {
  const tokens = new Set<string>();
  const normalized = value.toLowerCase();
  const latinWords = normalized.match(/[a-z0-9][a-z0-9.+#-]{1,}/g) ?? [];
  for (const word of latinWords) {
    tokens.add(word);
  }

  const cjkTerms = [
    "职业",
    "求职",
    "招聘",
    "合作",
    "朋友",
    "交友",
    "摄影",
    "展览",
    "散步",
    "电影",
    "agent",
    "runtime",
    "swiftui",
    "next.js",
    "supabase"
  ];
  for (const term of cjkTerms) {
    if (normalized.includes(term)) {
      tokens.add(term);
    }
  }

  return tokens;
}

export function isRiskyNetworkingContent(value: string) {
  return /薪资|offer|合同|报价|医疗|法律|金融|隐私|住址|身份证|\bsalary\b|\bcontract\b|\blegal\b|\bmedical\b|\bfinance\b|\btoken\b|\bsecret\b|home address|exact address|private account|account details/i.test(
    value
  );
}
