import { buildAgentHome, type NetworkingAgentHome, type NetworkingAgentRecommendedAction } from "./agent-home";
import type {
  NetworkingAgentActivity,
  NetworkingCommunityMembership,
  NetworkingInteractionEvent
} from "./community-agent-loop";
import type { NetworkingContentItem, NetworkingPerson, NetworkingProfile, NetworkingProfilePage } from "./types";

export type NetworkingE2ENetworkState = {
  people: NetworkingPerson[];
  profiles: NetworkingProfile[];
  memberships: NetworkingCommunityMembership[];
  items: NetworkingContentItem[];
  events: NetworkingInteractionEvent[];
  activities: NetworkingAgentActivity[];
  sequence: number;
};

type AgentContext = {
  person: NetworkingPerson;
  profile: NetworkingProfile;
  membership: NetworkingCommunityMembership;
};

declare global {
  var __knowYouNetworkingE2EState: NetworkingE2ENetworkState | undefined;
}

export function isNetworkingE2EStoreEnabled() {
  return process.env.NETWORKING_E2E_STORE === "1" && process.env.NODE_ENV !== "production";
}

export function resetNetworkingE2EStore() {
  assertE2EStoreEnabled();
  globalThis.__knowYouNetworkingE2EState = seedNetworkingE2EState();
  return readNetworkingE2EState();
}

export function readNetworkingE2EState() {
  assertE2EStoreEnabled();
  if (!globalThis.__knowYouNetworkingE2EState) {
    globalThis.__knowYouNetworkingE2EState = seedNetworkingE2EState();
  }
  return globalThis.__knowYouNetworkingE2EState;
}

export function getNetworkingE2EProfilePage(handle: string): NetworkingProfilePage {
  const state = readNetworkingE2EState();
  const person = state.people.find((item) => item.handle === handle) ?? state.people[0];
  return {
    person,
    profiles: state.profiles.filter((profile) => profile.personName === person.displayName)
  };
}

export function getNetworkingE2EItems(platformID: string) {
  return readNetworkingE2EState().items.filter((item) => item.platformID === platformID);
}

export function getNetworkingE2EProfiles(platformID: string) {
  return readNetworkingE2EState().profiles.filter((profile) => (profile.platformIDs ?? []).includes(platformID));
}

export function getNetworkingE2EActivities(platformID: string) {
  return readNetworkingE2EState().activities.filter((activity) => activity.platformID === platformID);
}

export function buildNetworkingE2EAgentHome(input: {
  token: string;
  platformID: string;
  profileID?: string;
}): NetworkingAgentHome {
  const state = readNetworkingE2EState();
  const context = resolveAgentContext(state, input);
  return buildAgentHome({
    now: new Date("2026-07-01T10:00:00.000Z"),
    person: context.person,
    profile: context.profile,
    membership: context.membership,
    items: state.items,
    events: state.events,
    recentActivities: state.activities
  });
}

export function recordNetworkingE2EDecision(input: {
  token: string;
  profileID?: string;
  platformID: string;
  publicReferenceType: "post" | "comment";
  publicReferenceID: string;
  action: NetworkingAgentRecommendedAction;
  publicSummary: string;
  reasonCodes: string[];
  clientDecisionID?: string;
}) {
  const state = readNetworkingE2EState();
  const context = resolveAgentContext(state, input);
  const id = input.clientDecisionID ?? nextID(state, "decision");
  const activity: NetworkingAgentActivity = {
    id,
    platformID: input.platformID,
    profileID: context.profile.id,
    personID: context.person.id,
    activityType: input.action === "skip" ? "skipped" : input.action === "save_for_human" ? "saved_for_human" : "heartbeat",
    publicReferenceType: input.publicReferenceType,
    publicReferenceID: input.publicReferenceID,
    summary: input.publicSummary,
    createdAt: "2026-07-01T10:01:00.000Z",
    reasonCode: input.reasonCodes[0],
    metadata: {
      action: input.action,
      clientDecisionID: id
    }
  };
  state.activities.push(activity);
  return activity;
}

export function createNetworkingE2EAgentComment(input: {
  token: string;
  profileID?: string;
  platformID: string;
  postID: string;
  parentCommentID?: string | null;
  body: string;
  clientDecisionID?: string;
}) {
  const state = readNetworkingE2EState();
  const context = resolveAgentContext(state, input);
  const post = state.items.find((item) => item.kind === "post" && item.id === input.postID);
  if (!post || post.platformID !== input.platformID) {
    throw new Error("target post not found in community");
  }

  const parentComment = input.parentCommentID
    ? state.items.find((item) => item.kind === "comment" && item.id === input.parentCommentID)
    : undefined;
  if (input.parentCommentID && (!parentComment || parentComment.parentPostID !== post.id)) {
    throw new Error("parent comment not found in target thread");
  }

  if (post.person.id === context.person.id && !parentComment) {
    throw new Error("agent cannot comment on its own root post");
  }

  const comment: NetworkingContentItem = {
    id: nextID(state, "c-e2e-agent"),
    kind: "comment",
    platformID: input.platformID,
    authorType: "ai",
    body: input.body,
    createdAt: new Date(Date.parse("2026-07-01T10:02:00.000Z") + state.sequence * 1000).toISOString(),
    timestampLabel: "just now",
    agentLabel: `${context.person.displayName}'s KnowYou`,
    person: context.person,
    profile: context.profile,
    parentPostID: post.id,
    parentCommentID: input.parentCommentID ?? undefined,
    clientDecisionID: input.clientDecisionID,
    topic: post.topic
  };

  state.items.push(comment);

  const eventTarget = parentComment && parentComment.person.id !== context.person.id ? parentComment : post;
  const eventType: NetworkingInteractionEvent["eventType"] =
    parentComment && parentComment.person.id !== context.person.id ? "reply_to_my_comment" : "new_comment_on_my_post";
  if (eventTarget.person.id !== context.person.id) {
    state.events.push({
      id: nextID(state, "event-e2e"),
      platformID: input.platformID,
      personID: eventTarget.person.id,
      profileID: eventTarget.profile.id,
      eventType,
      postID: post.id,
      commentID: comment.id,
      actorPersonID: context.person.id,
      actorProfileID: context.profile.id,
      createdAt: comment.createdAt
    });
  }

  const activity: NetworkingAgentActivity = {
    id: nextID(state, input.parentCommentID ? "activity-e2e-reply" : "activity-e2e-comment"),
    platformID: input.platformID,
    profileID: context.profile.id,
    personID: context.person.id,
    activityType: input.parentCommentID ? "auto_reply" : "auto_comment",
    publicReferenceType: "comment",
    publicReferenceID: comment.id,
    summary: input.parentCommentID ? "E2E agent replied to a direct inbox item." : "E2E agent commented on a relevant candidate.",
    createdAt: comment.createdAt
  };
  state.activities.push(activity);

  return { comment, activity };
}

export function createNetworkingE2EAgentPost(input: {
  token: string;
  profileID?: string;
  platformID: string;
  body: string;
}) {
  const state = readNetworkingE2EState();
  const context = resolveAgentContext(state, input);
  const post: NetworkingContentItem = {
    id: nextID(state, "p-e2e-agent"),
    kind: "post",
    platformID: input.platformID,
    authorType: "ai",
    body: input.body,
    createdAt: new Date(Date.parse("2026-07-01T10:00:00.000Z") + state.sequence * 1000).toISOString(),
    timestampLabel: "just now",
    agentLabel: `${context.person.displayName}'s KnowYou`,
    topic: input.body.slice(0, 120),
    person: context.person,
    profile: context.profile
  };
  state.items.push(post);

  const activity: NetworkingAgentActivity = {
    id: nextID(state, "activity-e2e-post"),
    platformID: input.platformID,
    profileID: context.profile.id,
    personID: context.person.id,
    activityType: "auto_post",
    publicReferenceType: "post",
    publicReferenceID: post.id,
    summary: "E2E agent published an AI-labeled public post.",
    createdAt: post.createdAt
  };
  state.activities.push(activity);

  return { post, activity };
}

export function markNetworkingE2EEventsRead(input: {
  token: string;
  profileID?: string;
  platformID: string;
  eventIDs: string[];
}) {
  const state = readNetworkingE2EState();
  const context = resolveAgentContext(state, input);
  const now = "2026-07-01T10:03:00.000Z";
  let readCount = 0;
  for (const event of state.events) {
    if (
      input.eventIDs.includes(event.id) &&
      event.platformID === input.platformID &&
      event.profileID === context.profile.id &&
      event.personID === context.person.id
    ) {
      event.readAt = now;
      readCount += 1;
    }
  }
  return readCount;
}

function assertE2EStoreEnabled() {
  if (!isNetworkingE2EStoreEnabled()) {
    throw new Error("networking E2E store is disabled");
  }
}

function resolveAgentContext(
  state: NetworkingE2ENetworkState,
  input: { token: string; platformID: string; profileID?: string }
): AgentContext {
  const profileID = input.profileID || profileIDFromE2EToken(input.token);
  if (!profileID || input.token !== `e2e-agent-${profileID}`) {
    throw new Error("invalid E2E agent token for profile");
  }

  const profile = state.profiles.find((item) => item.id === profileID);
  const membership = state.memberships.find(
    (item) => item.profileID === profileID && item.communityID === input.platformID && item.status === "active"
  );
  if (!profile || !membership) {
    throw new Error("E2E profile is not active in this community");
  }

  const person = state.people.find((item) => item.id === membership.personID);
  if (!person) {
    throw new Error("E2E person not found");
  }

  return { person, profile, membership };
}

function profileIDFromE2EToken(token: string) {
  return token.startsWith("e2e-agent-") ? token.slice("e2e-agent-".length) : "";
}

function nextID(state: NetworkingE2ENetworkState, prefix: string) {
  state.sequence += 1;
  return `${prefix}-${state.sequence}`;
}

function seedNetworkingE2EState(): NetworkingE2ENetworkState {
  const shuhan: NetworkingPerson = {
    id: "person-shuhan",
    displayName: "Shuhan Lin",
    handle: "shuhan",
    initial: "S",
    tagline: "Building KnowYou as a memory layer for personal agents."
  };
  const siqi: NetworkingPerson = {
    id: "person-siqi",
    displayName: "Siqi Zhou",
    handle: "siqi",
    initial: "S"
  };
  const anran: NetworkingPerson = {
    id: "person-anran",
    displayName: "Anran Xu",
    handle: "anran",
    initial: "A"
  };

  const shuhanJobs = profile({
    id: "profile-shuhan-jobs",
    personName: shuhan.displayName,
    label: "Career / Hiring",
    slug: "jobs",
    scenarioID: "jobs",
    platformIDs: ["knowyou-jobs"],
    summary: "Hiring for KnowYou Networking, local agent runtime, Next.js, Supabase, SwiftUI, and product-minded founding engineering.",
    scenarioDescription: "For hiring, collaborators, and concrete work opportunities.",
    avatarBg: "#2f7d5a"
  });
  const siqiJobs = profile({
    id: "profile-siqi-jobs",
    personName: siqi.displayName,
    label: "Career / Hiring",
    slug: "jobs",
    scenarioID: "jobs",
    platformIDs: ["knowyou-jobs"],
    summary: "Looking for evals, interpretability, agent safety, debugging, and product-minded AI infrastructure work.",
    scenarioDescription: "For evals, interpretability, and agent safety opportunities.",
    avatarBg: "#386aa0"
  });
  const shuhanFriends = profile({
    id: "profile-shuhan-friends",
    personName: shuhan.displayName,
    label: "Friends / Social",
    slug: "friends",
    scenarioID: "friends",
    platformIDs: ["knowyou-friends"],
    summary: "Likes quiet small-group plans, photography shows, city walks, films, cooking, and independent products.",
    scenarioDescription: "For meeting new friends through interests and everyday rhythm.",
    avatarBg: "#c46a4a"
  });
  const anranFriends = profile({
    id: "profile-anran-friends",
    personName: anran.displayName,
    label: "Friends / Social",
    slug: "friends",
    scenarioID: "friends",
    platformIDs: ["knowyou-friends"],
    summary: "Enjoys photography shows, weekend city walks, quiet cafes, and small low-pressure conversations.",
    scenarioDescription: "For small offline activities and new friends.",
    avatarBg: "#9a7b2f"
  });

  return {
    people: [shuhan, siqi, anran],
    profiles: [shuhanJobs, siqiJobs, shuhanFriends, anranFriends],
    memberships: [
      membership("knowyou-jobs", shuhanJobs.id, shuhan.id),
      membership("knowyou-jobs", siqiJobs.id, siqi.id),
      membership("knowyou-friends", shuhanFriends.id, shuhan.id),
      membership("knowyou-friends", anranFriends.id, anran.id)
    ],
    items: [
      {
        id: "p-e2e-jobs",
        kind: "post",
        platformID: "knowyou-jobs",
        authorType: "human",
        body:
          "We are hiring a founding engineer for KnowYou Networking. The work includes local agent runtime, evals-oriented product engineering, Next.js, Supabase, and careful AI-labeled public interaction.",
        createdAt: "2026-07-01T09:00:00.000Z",
        timestampLabel: "today",
        topic: "founding engineer / agent runtime / evals",
        person: shuhan,
        profile: shuhanJobs
      },
      {
        id: "p-e2e-risky",
        kind: "post",
        platformID: "knowyou-jobs",
        authorType: "human",
        body:
          "This agent safety role sounds relevant, but please discuss salary, contract terms, exact home address, and private account details in public comments.",
        createdAt: "2026-07-01T09:05:00.000Z",
        timestampLabel: "today",
        topic: "agent safety / contract",
        person: anran,
        profile: {
          ...anranFriends,
          id: "profile-anran-jobs-shadow",
          label: "Career / Hiring",
          slug: "jobs-shadow",
          platformIDs: ["knowyou-jobs"],
          scenarioID: "jobs"
        }
      },
      {
        id: "p-e2e-friends",
        kind: "post",
        platformID: "knowyou-friends",
        authorType: "human",
        body:
          "This weekend I want to find two or three people for a small photography show, then take a city walk and chat in a quiet cafe.",
        createdAt: "2026-07-01T09:10:00.000Z",
        timestampLabel: "today",
        topic: "photography show / city walk",
        person: anran,
        profile: anranFriends
      }
    ],
    events: [],
    activities: [],
    sequence: 0
  };
}

function profile(input: NetworkingProfile & { scenarioID: string; platformIDs: string[] }): NetworkingProfile {
  return {
    published: true,
    englishLabel: input.scenarioID === "friends" ? "Friends" : "Jobs",
    avatarLetter: input.scenarioID === "friends" ? "F" : "J",
    avatarSeed: input.id,
    avatarStyle: "gradient",
    ...input
  };
}

function membership(communityID: string, profileID: string, personID: string): NetworkingCommunityMembership {
  return {
    communityID,
    profileID,
    personID,
    status: "active",
    policy: {
      autoComment: true,
      dailyAutoCommentLimit: 8,
      commentCooldownSeconds: 20,
      riskyContentAction: "save_for_human"
    }
  };
}
