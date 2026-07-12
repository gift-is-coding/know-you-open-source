import type { NetworkingContentItem, NetworkingPerson, NetworkingProfile } from "./types";

export type NetworkingCommunityMembershipStatus = "active" | "paused" | "limited";
export type NetworkingAgentAutonomyMode = "conservative" | "balanced" | "active";
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
  autonomyMode?: NetworkingAgentAutonomyMode;
  autoPost?: boolean;
  autoComment?: boolean;
  autoReply?: boolean;
  dailyAutoPostLimit?: number;
  dailyProactiveCommentLimit?: number;
  dailyAutoReplyLimit?: number;
  dailyAutoCommentLimit?: number;
  heartbeatMinMinutes?: number;
  heartbeatMaxMinutes?: number;
  maxAutonomousThreadTurns?: number;
  unfamiliarPersonCooldownHours?: number;
  commentCooldownSeconds?: number;
  riskyContentAction?: "save_for_human";
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
  recentActivities?: NetworkingAgentActivity[];
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

      if (hasExistingAgentAction(nextItems, input.recentActivities ?? [], post.id, profile.id)) {
        continue;
      }

      const relevance = scoreItemRelevance(profile, post);
      if (relevance < minimumOverlap || isRiskyNetworkingContent(post.body)) {
        continue;
      }

      activities.push({
        id: `activity-candidate-${profile.id}-${post.id}`,
        platformID: post.platformID,
        profileID: profile.id,
        personID: person.id,
        activityType: "saved_for_human",
        publicReferenceType: "post",
        publicReferenceID: post.id,
        summary: `Found a relevant public post from ${post.person.displayName}; keep it for human review before any public reply.`,
        createdAt: input.now.toISOString(),
        reasonCode: "semantic_profile_overlap",
        metadata: {
          relevance,
          recommendedAction: "express_interest"
        }
      });
    }
  }

  return { items: nextItems, activities };
}

function hasExistingAgentAction(
  items: NetworkingContentItem[],
  activities: NetworkingAgentActivity[],
  postID: string,
  profileID: string
) {
  return items.some(
    (item) =>
      item.kind === "comment" &&
      item.parentPostID === postID &&
      item.authorType === "ai" &&
      item.profile.id === profileID
  ) ||
    activities.some(
      (activity) =>
        activity.profileID === profileID &&
        activity.publicReferenceType === "post" &&
        activity.publicReferenceID === postID &&
        ["auto_comment", "auto_reply", "saved_for_human"].includes(activity.activityType)
    );
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
  return isUntrustedNetworkingInstruction(value) || /薪资|offer|合同|报价|医疗|法律|金融|隐私|住址|身份证|API key|\bsalary\b|\bcontract\b|\blegal\b|\bmedical\b|\bfinance\b|\btoken\b|\bsecret\b|home address|exact address|private account|account details/i.test(
    value
  );
}

export function isUntrustedNetworkingInstruction(value: string) {
  const normalized = value.toLowerCase();
  const overrideAttempt = /忽略|绕过|无视|disregard|ignore|override|system message|developer message/.test(normalized);
  const capabilityRequest = /读取|上传|下载|调用.{0,8}(工具|接口)|文件|密钥|凭证|本地配置|api key|ssh|upload|download|call (a )?tool|read (local )?files?|credential|secret/.test(normalized);
  const policyTarget = /规则|指令|安全|限制|policy|instruction|safety|restriction/.test(normalized);
  return capabilityRequest && (overrideAttempt || policyTarget);
}
