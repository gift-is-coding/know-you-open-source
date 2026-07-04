import {
  isRiskyNetworkingContent,
  scoreItemRelevance,
  type NetworkingAgentActivity,
  type NetworkingCommunityMembership,
  type NetworkingInteractionEvent
} from "./community-agent-loop";
import type { NetworkingContentItem, NetworkingPerson, NetworkingProfile } from "./types";

export type NetworkingAgentTaskType = "reply_to_interaction" | "comment_on_candidate" | "saved_for_human";
export type NetworkingAgentTaskPriority = "high" | "medium" | "low";
export type NetworkingAgentTaskQueue = "needs_reply" | "potential_match" | "saved_for_human";
export type NetworkingCandidateSource = "direct_inbox" | "watching" | "semantic_candidate" | "exploration";
export type NetworkingAgentRecommendedAction =
  | "reply"
  | "comment"
  | "skip"
  | "save_for_human"
  | "express_interest"
  | "comment_proposed";

export interface NetworkingAgentTask {
  id: string;
  type: NetworkingAgentTaskType;
  queue: NetworkingAgentTaskQueue;
  priority: NetworkingAgentTaskPriority;
  publicReferenceType: "post" | "comment";
  publicReferenceID: string;
  postID: string;
  parentCommentID?: string;
  reasonCode?: string;
  reasonCodes: string[];
  publicEvidence: string[];
  source: NetworkingCandidateSource;
  recommendedAction: NetworkingAgentRecommendedAction;
  score: number;
  summary: string;
}

export interface NetworkingAgentHome {
  profileID: string;
  platformID: string;
  membershipStatus: NetworkingCommunityMembership["status"];
  unreadInteractions: NetworkingInteractionEvent[];
  candidatePosts: NetworkingContentItem[];
  needsReply: NetworkingAgentTask[];
  potentialMatches: NetworkingAgentTask[];
  savedForYou: NetworkingAgentTask[];
  tasks: NetworkingAgentTask[];
  rateLimit: {
    dailyRemaining: number;
    cooldownRemainingSeconds: number;
  };
}

export interface AgentHeartbeatInput {
  now: Date;
  person: NetworkingPerson;
  profile: NetworkingProfile;
  membership: NetworkingCommunityMembership;
  items: NetworkingContentItem[];
  events: NetworkingInteractionEvent[];
  recentActivities: NetworkingAgentActivity[];
}

export interface AgentHeartbeatResult {
  items: NetworkingContentItem[];
  events: NetworkingInteractionEvent[];
  activities: NetworkingAgentActivity[];
  home: NetworkingAgentHome;
}

const defaultPolicy = {
  autoComment: true,
  dailyAutoCommentLimit: 8,
  commentCooldownSeconds: 20,
  semanticCandidateDailyLimit: 20,
  explorationDailyLimit: 3,
  humanPostAIReplySlots: 5,
  aiPostAIReplySlots: 1,
  riskyContentAction: "save_for_human" as const
};

export function buildAgentHome(input: AgentHeartbeatInput): NetworkingAgentHome {
  const policy = input.membership.policy ?? defaultPolicy;
  const unreadInteractions = input.events.filter(
    (event) =>
      !event.readAt &&
      event.platformID === input.membership.communityID &&
      event.profileID === input.profile.id &&
      event.personID === input.person.id &&
      (event.eventType === "new_comment_on_my_post" || event.eventType === "reply_to_my_comment")
  );
  const dailyRemaining = Math.max(policy.dailyAutoCommentLimit - countTodayAgentWrites(input), 0);
  const candidates = candidateTasks(input, dailyRemaining);
  const needsReply = unreadInteractions.map((event) => ({
    id: `task-${event.id}`,
    type: "reply_to_interaction" as const,
    queue: "needs_reply" as const,
    priority: "high" as const,
    publicReferenceType: "comment" as const,
    publicReferenceID: event.commentID ?? event.postID ?? event.id,
    postID: event.postID ?? "",
    parentCommentID: event.commentID,
    source: "direct_inbox" as const,
    recommendedAction: "reply" as const,
    score: 100,
    reasonCode: "direct_inbox",
    reasonCodes: ["direct_inbox", event.eventType],
    publicEvidence: [`${event.eventType} on ${event.postID ?? event.commentID ?? event.id}`],
    summary: "Reply to a new interaction on my public content."
  }));
  const tasks: NetworkingAgentTask[] = [
    ...needsReply,
    ...candidates.potentialMatches,
    ...candidates.savedForYou
  ];

  return {
    profileID: input.profile.id,
    platformID: input.membership.communityID,
    membershipStatus: input.membership.status,
    unreadInteractions,
    candidatePosts: candidates.potentialMatches.map((task) => task.item),
    needsReply,
    potentialMatches: candidates.potentialMatches.map(stripCandidateItem),
    savedForYou: candidates.savedForYou.map(stripCandidateItem),
    tasks: tasks.map(stripCandidateItem),
    rateLimit: {
      dailyRemaining,
      cooldownRemainingSeconds: cooldownRemainingSeconds(input)
    }
  };
}

type CandidateTaskWithItem = NetworkingAgentTask & { item: NetworkingContentItem };
type InternalAgentTask = NetworkingAgentTask | CandidateTaskWithItem;

function stripCandidateItem(task: InternalAgentTask): NetworkingAgentTask {
  if ("item" in task) {
    return {
      id: task.id,
      type: task.type,
      queue: task.queue,
      priority: task.priority,
      publicReferenceType: task.publicReferenceType,
      publicReferenceID: task.publicReferenceID,
      postID: task.postID,
      parentCommentID: task.parentCommentID,
      reasonCode: task.reasonCode,
      reasonCodes: task.reasonCodes,
      publicEvidence: task.publicEvidence,
      source: task.source,
      recommendedAction: task.recommendedAction,
      score: task.score,
      summary: task.summary
    };
  }

  return task;
}

function candidateTasks(input: AgentHeartbeatInput, dailyRemaining: number) {
  const candidatePosts = input.items
    .filter((item) => item.kind === "post")
    .filter((item) => item.platformID === input.membership.communityID)
    .filter((item) => item.person.id !== input.person.id)
    .filter((item) => !hasExistingAgentComment(input.items, item.id, input.profile.id))
    .filter((item) => !hasOpenAction(input.recentActivities, item.id, input.profile.id))
    .map((item) => ({ item, relevance: scoreItemRelevance(input.profile, item) }))
    .sort((left, right) => {
      if (right.relevance !== left.relevance) {
        return right.relevance - left.relevance;
      }
      return Date.parse(right.item.createdAt) - Date.parse(left.item.createdAt);
    });

  const semanticCandidates = candidatePosts.filter((candidate) => candidate.relevance > 0).slice(0, defaultPolicy.semanticCandidateDailyLimit);
  const explorationCandidates = candidatePosts
    .filter((candidate) => candidate.relevance <= 0)
    .slice(0, defaultPolicy.explorationDailyLimit)
    .map((candidate) => ({ ...candidate, exploration: true }));
  const potentialMatches: CandidateTaskWithItem[] = [];
  const savedForYou: CandidateTaskWithItem[] = [];

  for (const candidate of [...semanticCandidates, ...explorationCandidates]) {
    const task = taskForCandidate(input, candidate.item, candidate.relevance, Boolean("exploration" in candidate && candidate.exploration));
    const hasSlots = remainingAgentReplySlots(input.items, candidate.item) > 0;
    const isRisky = isRiskyNetworkingContent(candidate.item.body);
    const shouldSave = isRisky || !hasSlots || dailyRemaining <= 0 || task.source === "exploration";
    if (shouldSave) {
      const reasonCode = isRisky ? "risky_content" : !hasSlots ? "reply_slots_full" : dailyRemaining <= 0 ? "daily_limit" : "exploration_sample";
      savedForYou.push({
        ...task,
        type: "saved_for_human",
        queue: task.source === "exploration" ? "potential_match" : "saved_for_human",
        priority: task.source === "exploration" ? "low" : "medium",
        recommendedAction: "save_for_human",
        reasonCode,
        reasonCodes: [...new Set([...task.reasonCodes, reasonCode])],
        summary:
          task.source === "exploration"
            ? "This exploration sample may be useful; save it for human review."
            : "This candidate needs human review."
      });
    } else {
      potentialMatches.push(task);
    }
  }

  return {
    potentialMatches: [
      ...potentialMatches,
      ...savedForYou.filter((task) => task.source === "exploration")
    ].slice(0, defaultPolicy.semanticCandidateDailyLimit + defaultPolicy.explorationDailyLimit),
    savedForYou: savedForYou.filter((task) => task.source !== "exploration")
  };
}

function taskForCandidate(input: AgentHeartbeatInput, post: NetworkingContentItem, relevance: number, exploration: boolean): CandidateTaskWithItem {
  const evidence = publicEvidenceFor(input.profile, post);
  const source: NetworkingCandidateSource = exploration ? "exploration" : "semantic_candidate";
  const reasonCodes = exploration
    ? ["exploration_sample", "watching_community"]
    : ["semantic_profile_overlap", "watching_community"];

  return {
    id: `task-candidate-${post.id}`,
    type: "comment_on_candidate",
    queue: "potential_match",
    priority: exploration ? "low" : "medium",
    publicReferenceType: "post",
    publicReferenceID: post.id,
    postID: post.id,
    source,
    recommendedAction: exploration ? "save_for_human" : "comment",
    score: relevance,
    reasonCodes,
    publicEvidence: evidence,
    summary: exploration ? "A small exploration sample delivered by the platform." : "Candidate post matches this public profile.",
    item: post
  };
}

function publicEvidenceFor(profile: NetworkingProfile, post: NetworkingContentItem) {
  const snippets = [profile.summary, post.topic, post.body, post.profile.summary]
    .filter((value): value is string => Boolean(value && value.trim().length > 0))
    .map((value) => value.trim());
  return [...new Set(snippets)].slice(0, 4);
}

function remainingAgentReplySlots(items: NetworkingContentItem[], post: NetworkingContentItem) {
  const limit = post.authorType === "human" ? defaultPolicy.humanPostAIReplySlots : defaultPolicy.aiPostAIReplySlots;
  const count = items.filter((item) => item.kind === "comment" && item.parentPostID === post.id && item.authorType === "ai").length;
  return Math.max(limit - count, 0);
}

function hasOpenAction(activities: NetworkingAgentActivity[], postID: string, profileID: string) {
  return activities.some(
    (activity) =>
      activity.profileID === profileID &&
      activity.publicReferenceID === postID &&
      ["auto_comment", "auto_reply", "saved_for_human"].includes(activity.activityType)
  );
}

export function runAgentHeartbeat(input: AgentHeartbeatInput): AgentHeartbeatResult {
  const home = buildAgentHome(input);
  const heartbeat = activity(input, "heartbeat", "post", input.membership.communityID, "Profile-agent heartbeat checked current tasks.");

  if (input.membership.status !== "active") {
    return { items: input.items, events: input.events, activities: [heartbeat], home };
  }

  if (home.rateLimit.dailyRemaining <= 0) {
    return {
      items: input.items,
      events: input.events,
      activities: [heartbeat, activity(input, "rate_limited", "post", input.membership.communityID, "Daily auto-comment limit reached.", "daily_limit")],
      home
    };
  }

  const replyTask = home.tasks.find((task) => task.type === "reply_to_interaction");
  if (replyTask) {
    const target = input.items.find((item) => item.id === replyTask.publicReferenceID);
    if (target && isRiskyNetworkingContent(target.body)) {
      return saveForHuman(input, home, replyTask, "risky_content");
    }

    const reply = buildAgentComment(input, replyTask.postID, replyTask.parentCommentID);
    return {
      items: [...input.items, reply],
      events: markTaskEventRead(input.events, replyTask, input.now),
      activities: [heartbeat, activity(input, "auto_reply", "comment", reply.id, `Auto-replied to ${target?.person.displayName ?? "the other person"}'s comment.`)],
      home
    };
  }

  const savedTask = home.savedForYou[0];
  if (savedTask) {
    return saveForHuman(input, home, savedTask, savedTask.reasonCode ?? "saved_for_human");
  }

  const candidateTask = home.tasks.find((task) => task.type === "comment_on_candidate");
  if (!candidateTask) {
    return { items: input.items, events: input.events, activities: [heartbeat], home };
  }

  if (candidateTask.reasonCode === "risky_content") {
    return saveForHuman(input, home, candidateTask, "risky_content");
  }

  const comment = buildAgentComment(input, candidateTask.postID);
  return {
    items: [...input.items, comment],
    events: [
      ...input.events,
      {
        id: `event-${comment.id}`,
        platformID: input.membership.communityID,
        personID: input.person.id,
        profileID: input.profile.id,
        eventType: "agent_commented",
        postID: candidateTask.postID,
        commentID: comment.id,
        actorPersonID: input.person.id,
        actorProfileID: input.profile.id,
        createdAt: input.now.toISOString()
      }
    ],
    activities: [heartbeat, activity(input, "auto_comment", "comment", comment.id, "Auto-commented on a relevant candidate post.")],
    home
  };
}

function buildAgentComment(input: AgentHeartbeatInput, postID: string, parentCommentID?: string): NetworkingContentItem {
  const post = input.items.find((item) => item.id === postID);
  const lead = parentCommentID ? "This reply overlaps with my public friends profile" : "This activity overlaps with my public friends profile";
  return {
    id: `agent-${input.profile.id}-${parentCommentID ?? postID}`,
    kind: "comment",
    platformID: input.membership.communityID,
    authorType: "ai",
    body: `${lead}. I will bring this back to the person for judgment; the relevant public profile context is: ${input.profile.summary ?? "shared interests and topic overlap"}.`,
    createdAt: input.now.toISOString(),
    timestampLabel: "just now",
    agentLabel: `${input.person.displayName}'s KnowYou`,
    person: input.person,
    profile: input.profile,
    parentPostID: postID,
    parentCommentID,
    clientDecisionID: `${input.profile.id}:${postID}:${parentCommentID ?? "root"}`,
    topic: post?.topic ?? "agent heartbeat"
  };
}

function saveForHuman(input: AgentHeartbeatInput, home: NetworkingAgentHome, task: NetworkingAgentTask, reasonCode: string): AgentHeartbeatResult {
  return {
    items: input.items,
    events: [
      ...input.events,
      {
        id: `event-human-${input.profile.id}-${task.publicReferenceID}`,
        platformID: input.membership.communityID,
        personID: input.person.id,
        profileID: input.profile.id,
        eventType: "human_action_required",
        postID: task.postID,
        commentID: task.parentCommentID,
        createdAt: input.now.toISOString()
      }
    ],
    activities: [
      activity(input, "heartbeat", "post", input.membership.communityID, "Profile-agent heartbeat checked current tasks."),
      activity(input, "saved_for_human", task.publicReferenceType, task.publicReferenceID, "Candidate content needs human review.", reasonCode)
    ],
    home
  };
}

function activity(
  input: AgentHeartbeatInput,
  activityType: NetworkingAgentActivity["activityType"],
  publicReferenceType: NetworkingAgentActivity["publicReferenceType"],
  publicReferenceID: string,
  summary: string,
  reasonCode?: string
): NetworkingAgentActivity {
  return {
    id: `activity-${activityType}-${input.profile.id}-${publicReferenceID}`,
    platformID: input.membership.communityID,
    profileID: input.profile.id,
    personID: input.person.id,
    activityType,
    publicReferenceType,
    publicReferenceID,
    summary,
    createdAt: input.now.toISOString(),
    reasonCode
  };
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

function countTodayAgentWrites(input: AgentHeartbeatInput) {
  const today = input.now.toISOString().slice(0, 10);
  return input.recentActivities.filter(
    (activity) =>
      activity.profileID === input.profile.id &&
      (activity.activityType === "auto_comment" || activity.activityType === "auto_reply") &&
      activity.createdAt.startsWith(today)
  ).length;
}

function cooldownRemainingSeconds(input: AgentHeartbeatInput) {
  const policy = input.membership.policy ?? defaultPolicy;
  const latest = input.recentActivities
    .filter((activity) => activity.profileID === input.profile.id && (activity.activityType === "auto_comment" || activity.activityType === "auto_reply"))
    .sort((left, right) => Date.parse(right.createdAt) - Date.parse(left.createdAt))[0];
  if (!latest) {
    return 0;
  }

  const elapsed = Math.floor((input.now.getTime() - Date.parse(latest.createdAt)) / 1000);
  return Math.max(policy.commentCooldownSeconds - elapsed, 0);
}

function markTaskEventRead(events: NetworkingInteractionEvent[], task: NetworkingAgentTask, now: Date) {
  return events.map((event) =>
    event.commentID === task.parentCommentID || event.postID === task.postID ? { ...event, readAt: now.toISOString() } : event
  );
}
