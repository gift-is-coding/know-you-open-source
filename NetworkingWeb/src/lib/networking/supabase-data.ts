import { profilePageFixture } from "./fixtures";
import { buildAgentHome, type NetworkingAgentHome } from "./agent-home";
import {
  buildNetworkingE2EAgentHome,
  getNetworkingE2EActivities,
  getNetworkingE2EItems,
  getNetworkingE2EProfilePage,
  getNetworkingE2EProfiles,
  isNetworkingE2EStoreEnabled,
  readNetworkingE2EState
} from "./e2e-store";
import { getLocalDemoNetwork } from "./local-demo-state";
import { defaultNetworkingPlatformID, isNetworkingPlatformID } from "./platforms";
import type { NetworkingAgentActivity } from "./community-agent-loop";
import type { NetworkingCommunityMembership, NetworkingInteractionEvent } from "./community-agent-loop";
import type {
  NetworkingAvatarStyle,
  NetworkingComposerProfile,
  NetworkingContentItem,
  NetworkingProfilePage,
  NetworkingProfileWorkspace
} from "./types";
import { hasSupabaseEnv } from "@/src/lib/supabase/env";
import { createClient } from "@/src/lib/supabase/server";

type PersonRow = {
  id: string;
  display_name: string;
  handle: string;
};

type ProfileRow = {
  id: string;
  label: string;
  slug: string;
  scenario_id?: string | null;
  scenario_description?: string | null;
  avatar_seed?: string | null;
  avatar_style?: NetworkingAvatarStyle | null;
  platform_ids?: string[] | null;
  summary?: string | null;
  body?: string | null;
  is_published?: boolean | null;
};

type ContentRow = {
  id: string;
  platform_id?: string | null;
  body: string;
  author_type: "human" | "ai";
  created_at: string;
  person_id?: string;
  post_id?: string;
  parent_comment_id?: string | null;
  client_decision_id?: string | null;
  people: PersonRow | PersonRow[] | null;
  profiles: ProfileRow | ProfileRow[] | null;
};

type AgentActivityRow = {
  id: string;
  platform_id: string;
  person_id: string;
  profile_id: string;
  activity_type: "auto_comment" | "skipped" | string;
  public_reference_type: "post" | "comment" | string | null;
  public_reference_id: string | null;
  summary: string;
  reason_code?: string | null;
  metadata?: Record<string, string | number | boolean | null> | null;
  created_at: string;
};

type MembershipRow = {
  community_id: string;
  person_id: string;
  profile_id: string;
  status: NetworkingCommunityMembership["status"];
  policy?: NetworkingCommunityMembership["policy"] | null;
  last_heartbeat_at?: string | null;
  last_candidate_seen_at?: string | null;
};

type InteractionEventRow = {
  id: string;
  platform_id: string;
  person_id: string;
  profile_id: string;
  event_type: NetworkingInteractionEvent["eventType"] | string;
  post_id?: string | null;
  comment_id?: string | null;
  actor_person_id?: string | null;
  actor_profile_id?: string | null;
  read_at?: string | null;
  created_at: string;
};

export async function getPublicSquareItems(platformID?: string): Promise<NetworkingContentItem[]> {
  const normalizedPlatformID = normalizePlatformID(platformID);

  if (isNetworkingE2EStoreEnabled()) {
    return getNetworkingE2EItems(normalizedPlatformID);
  }

  if (!hasSupabaseEnv()) {
    return getLocalDemoNetwork().items.filter((item) => item.platformID === normalizedPlatformID);
  }

  try {
    const supabase = await createClient();
    let postsQuery = supabase
      .from("posts")
      .select(
        "id, platform_id, body, author_type, created_at, people(id, display_name, handle), profiles(id, label, slug, scenario_id, scenario_description, avatar_seed, avatar_style, platform_ids, summary, is_published)"
      )
      .eq("is_public", true)
      .order("created_at", { ascending: false })
      .limit(50);

    let commentsQuery = supabase
      .from("comments")
      .select(
        "id, post_id, parent_comment_id, client_decision_id, platform_id, body, author_type, created_at, people(id, display_name, handle), profiles(id, label, slug, scenario_id, scenario_description, avatar_seed, avatar_style, platform_ids, summary, is_published)"
      )
      .eq("is_public", true)
      .order("created_at", { ascending: false })
      .limit(50);

    postsQuery = postsQuery.eq("platform_id", normalizedPlatformID);
    commentsQuery = commentsQuery.eq("platform_id", normalizedPlatformID);

    const [postsResult, commentsResult] = await Promise.all([postsQuery, commentsQuery]);

    if (postsResult.error || commentsResult.error) {
      return [];
    }

    const items = [
      ...(postsResult.data ?? []).map((row) => mapContentRow(row as ContentRow, "post")),
      ...(commentsResult.data ?? []).map((row) => mapContentRow(row as ContentRow, "comment"))
    ].filter((item): item is NetworkingContentItem => Boolean(item));

    return items;
  } catch {
    return [];
  }
}

export async function getPublicProfilePageForPlatform(platformID?: string): Promise<NetworkingProfilePage> {
  const normalizedPlatformID = normalizePlatformID(platformID);

  if (isNetworkingE2EStoreEnabled()) {
    return getNetworkingE2EProfilePage("shuhan");
  }

  if (!hasSupabaseEnv()) {
    const network = getLocalDemoNetwork();
    const profile = network.profiles.find((item) => (item.platformIDs ?? []).includes(normalizedPlatformID)) ?? network.profiles[0];
    const person = network.people.find((item) => item.displayName === profile.personName) ?? profilePageFixture.person;
    return {
      person,
      profiles: network.profiles.filter((item) => item.personName === person.displayName)
    };
  }

  try {
    const supabase = await createClient();
    const { data: firstProfiles, error } = await supabase
      .from("profiles")
      .select("id, person_id, label, slug, scenario_id, scenario_description, avatar_seed, avatar_style, platform_ids, summary, is_published, people(id, display_name, handle)")
      .eq("is_published", true)
      .contains("platform_ids", [normalizedPlatformID])
      .order("updated_at", { ascending: false })
      .limit(1);

    if (error || !firstProfiles || firstProfiles.length === 0) {
      return emptyProfilePage(normalizedPlatformID);
    }

    const firstProfile = firstProfiles[0] as ProfileRow & { person_id?: string; people: PersonRow | PersonRow[] | null };
    const person = first(firstProfile.people);
    if (!person || !firstProfile.person_id) {
      return emptyProfilePage(normalizedPlatformID);
    }

    const { data: profiles, error: profilesError } = await supabase
      .from("profiles")
      .select("id, label, slug, scenario_id, scenario_description, avatar_seed, avatar_style, platform_ids, summary, is_published")
      .eq("person_id", firstProfile.person_id)
      .eq("is_published", true)
      .contains("platform_ids", [normalizedPlatformID])
      .order("updated_at", { ascending: false });

    if (profilesError) {
      return emptyProfilePage(normalizedPlatformID);
    }

    return {
      person: mapPerson(person),
      profiles: profiles
        .map((profile) => mapProfile(profile as ProfileRow, person.display_name))
        .filter((profile) => (profile.platformIDs ?? []).includes(normalizedPlatformID))
    };
  } catch {
    return emptyProfilePage(normalizedPlatformID);
  }
}

export async function getPublicProfilePage(handle: string): Promise<NetworkingProfilePage> {
  if (isNetworkingE2EStoreEnabled()) {
    return getNetworkingE2EProfilePage(handle);
  }

  if (!hasSupabaseEnv()) {
    const network = getLocalDemoNetwork();
    const person = network.people.find((item) => item.handle === handle) ?? profilePageFixture.person;
    return {
      person,
      profiles: network.profiles.filter((profile) => profile.personName === person.displayName)
    };
  }

  try {
    const supabase = await createClient();
    const { data: person, error: personError } = await supabase
      .from("people")
      .select("id, display_name, handle")
      .eq("handle", handle)
      .single();

    if (personError || !person) {
      return emptyProfilePage(defaultNetworkingPlatformID, handle);
    }

    const { data: profiles, error: profilesError } = await supabase
      .from("profiles")
      .select("id, label, slug, scenario_id, scenario_description, avatar_seed, avatar_style, platform_ids, summary, is_published")
      .eq("person_id", person.id)
      .eq("is_published", true)
      .order("updated_at", { ascending: false });

    if (profilesError) {
      return emptyProfilePage(defaultNetworkingPlatformID, handle);
    }

    return {
      person: mapPerson(person as PersonRow),
      profiles: (profiles ?? []).map((profile) => mapProfile(profile as ProfileRow, person.display_name as string))
    };
  } catch {
    return emptyProfilePage(defaultNetworkingPlatformID, handle);
  }
}

export async function getComposerProfiles(platformID?: string): Promise<NetworkingComposerProfile[]> {
  const normalizedPlatformID = normalizePlatformID(platformID);

  if (isNetworkingE2EStoreEnabled()) {
    return getNetworkingE2EProfiles(normalizedPlatformID).map(({ id, label, platformIDs }) => ({
      id,
      label,
      platformIDs
    }));
  }

  if (!hasSupabaseEnv()) {
    return getLocalDemoNetwork().profiles
      .filter((profile) => (profile.platformIDs ?? []).includes(normalizedPlatformID))
      .map(({ id, label, platformIDs }) => ({ id, label, platformIDs }));
  }

  try {
    const supabase = await createClient();
    const {
      data: { user }
    } = await supabase.auth.getUser();

    if (!user) {
      return [];
    }

    const { data: person } = await supabase
      .from("people")
      .select("id")
      .eq("user_id", user.id)
      .single();

    if (!person) {
      return [];
    }

    const { data: memberships } = await supabase
      .from("community_memberships")
      .select("profile_id")
      .eq("community_id", normalizedPlatformID)
      .eq("person_id", person.id)
      .eq("status", "active");
    const activeProfileIDs = (memberships ?? []).map((membership) => membership.profile_id as string);
    if (activeProfileIDs.length === 0) {
      return [];
    }

    const { data: profiles } = await supabase
      .from("profiles")
      .select("id, label, platform_ids")
      .eq("person_id", person.id)
      .eq("is_published", true)
      .contains("platform_ids", [normalizedPlatformID])
      .in("id", activeProfileIDs)
      .order("updated_at", { ascending: false });

    return (profiles ?? []).map((profile) => ({
      id: profile.id as string,
      label: profile.label as string,
      platformIDs: (profile.platform_ids as string[] | null) ?? [normalizedPlatformID]
    }));
  } catch {
    return [];
  }
}

export async function getViewerProfilePageForPlatform(platformID?: string): Promise<NetworkingProfilePage> {
  const normalizedPlatformID = normalizePlatformID(platformID);

  if (isNetworkingE2EStoreEnabled()) {
    return getNetworkingE2EProfilePage("shuhan");
  }

  if (!hasSupabaseEnv()) {
    return getPublicProfilePageForPlatform(normalizedPlatformID);
  }

  const workspace = await getMyProfileWorkspace();
  if (!workspace.person) {
    return emptyProfilePage(normalizedPlatformID);
  }

  return {
    person: workspace.person,
    profiles: workspace.profiles.filter(
      (profile) => profile.published !== false && (profile.platformIDs ?? []).includes(normalizedPlatformID)
    )
  };
}

export async function getAgentActivities(platformID?: string): Promise<NetworkingAgentActivity[]> {
  const normalizedPlatformID = normalizePlatformID(platformID);

  if (isNetworkingE2EStoreEnabled()) {
    return getNetworkingE2EActivities(normalizedPlatformID);
  }

  if (!hasSupabaseEnv()) {
    return getLocalDemoNetwork().activities.filter((activity) => activity.platformID === normalizedPlatformID);
  }

  try {
    const supabase = await createClient();
    const { data, error } = await supabase
      .from("agent_activity")
      .select("id, platform_id, person_id, profile_id, activity_type, public_reference_type, public_reference_id, summary, reason_code, metadata, created_at")
      .eq("platform_id", normalizedPlatformID)
      .order("created_at", { ascending: false })
      .limit(12);

    if (error) {
      return [];
    }

    return (data ?? []).map((row) => mapAgentActivity(row as AgentActivityRow));
  } catch {
    return [];
  }
}

export async function getAgentHomePreview(platformID?: string): Promise<NetworkingAgentHome | null> {
  const normalizedPlatformID = normalizePlatformID(platformID);

  if (isNetworkingE2EStoreEnabled()) {
    const state = readNetworkingE2EState();
    const membership = state.memberships.find((item) => item.communityID === normalizedPlatformID && item.personID === "person-shuhan");
    if (!membership) {
      return null;
    }
    return buildNetworkingE2EAgentHome({
      token: `e2e-agent-${membership.profileID}`,
      platformID: normalizedPlatformID,
      profileID: membership.profileID
    });
  }

  if (!hasSupabaseEnv()) {
    const network = getLocalDemoNetwork();
    const membership = network.memberships.find((item) => item.communityID === normalizedPlatformID && item.status === "active");
    if (!membership) {
      return null;
    }
    const person = network.people.find((item) => item.id === membership.personID);
    const profile = network.profiles.find((item) => item.id === membership.profileID);
    if (!person || !profile) {
      return null;
    }
    return buildAgentHome({
      now: new Date("2026-06-12T10:10:00.000Z"),
      person,
      profile,
      membership,
      items: network.items,
      events: network.events,
      recentActivities: network.activities
    });
  }

  try {
    const supabase = await createClient();
    const {
      data: { user }
    } = await supabase.auth.getUser();

    if (!user) {
      return null;
    }

    const { data: person } = await supabase
      .from("people")
      .select("id, display_name, handle")
      .eq("user_id", user.id)
      .maybeSingle();

    if (!person) {
      return null;
    }

    const { data: membership } = await supabase
      .from("community_memberships")
      .select("community_id, person_id, profile_id, status, policy, last_heartbeat_at, last_candidate_seen_at")
      .eq("community_id", normalizedPlatformID)
      .eq("person_id", person.id)
      .eq("status", "active")
      .maybeSingle();

    if (!membership) {
      return null;
    }

    const profileResult = await supabase
        .from("profiles")
        .select("id, label, slug, scenario_id, scenario_description, avatar_seed, avatar_style, platform_ids, summary, is_published")
        .eq("id", membership.profile_id)
        .eq("is_published", true)
        .contains("platform_ids", [normalizedPlatformID])
        .maybeSingle();

    if (!profileResult.data) {
      return null;
    }
    const profile = profileResult.data as ProfileRow;

    const { data: events } = await supabase
      .from("public_interaction_events")
      .select("id, platform_id, person_id, profile_id, event_type, post_id, comment_id, actor_person_id, actor_profile_id, read_at, created_at")
      .eq("platform_id", normalizedPlatformID)
      .eq("profile_id", profile.id)
      .order("created_at", { ascending: false })
      .limit(20);

    const [items, recentActivities] = await Promise.all([
      getPublicSquareItems(normalizedPlatformID),
      getAgentActivities(normalizedPlatformID)
    ]);

    return buildAgentHome({
      now: new Date(),
      person: mapPerson(person as PersonRow),
      profile: mapProfile(profile, person.display_name),
      membership: mapMembership(membership as MembershipRow),
      items,
      events: (events ?? []).map((event) => mapInteractionEvent(event as InteractionEventRow)),
      recentActivities
    });
  } catch {
    return null;
  }
}

export async function getMyProfileWorkspace(): Promise<NetworkingProfileWorkspace> {
  if (!hasSupabaseEnv()) {
    return {
      person: profilePageFixture.person,
      profiles: profilePageFixture.profiles,
      needsSignIn: false,
      usesFixtureData: true
    };
  }

  try {
    const supabase = await createClient();
    const {
      data: { user }
    } = await supabase.auth.getUser();

    if (!user) {
      return {
        profiles: [],
        needsSignIn: true,
        usesFixtureData: false
      };
    }

    const { data: person } = await supabase
      .from("people")
      .select("id, display_name, handle")
      .eq("user_id", user.id)
      .maybeSingle();

    if (!person) {
      return {
        profiles: [],
        needsSignIn: false,
        usesFixtureData: false
      };
    }

    const { data: profiles } = await supabase
      .from("profiles")
      .select("id, label, slug, scenario_id, scenario_description, avatar_seed, avatar_style, platform_ids, summary, body, is_published")
      .eq("person_id", person.id)
      .order("updated_at", { ascending: false });

    return {
      person: mapPerson(person as PersonRow),
      profiles: (profiles ?? []).map((profile) => mapProfile(profile as ProfileRow, person.display_name as string)),
      needsSignIn: false,
      usesFixtureData: false
    };
  } catch {
    return {
      profiles: [],
      needsSignIn: true,
      usesFixtureData: false
    };
  }
}

function mapContentRow(row: ContentRow, kind: "post" | "comment"): NetworkingContentItem | null {
  const person = first(row.people);
  const profile = first(row.profiles);

  if (!person || !profile) {
    return null;
  }

  const mappedPerson = mapPerson(person);

  return {
    id: row.id,
    kind,
    platformID: normalizePlatformID(row.platform_id ?? defaultNetworkingPlatformID),
    authorType: row.author_type,
    body: row.body,
    createdAt: row.created_at,
    person: mappedPerson,
    profile: mapProfile(profile, mappedPerson.displayName),
    parentPostID: row.post_id,
    parentCommentID: row.parent_comment_id ?? undefined,
    clientDecisionID: row.client_decision_id ?? undefined
  };
}

function mapPerson(row: PersonRow) {
  return {
    id: row.id,
    displayName: row.display_name,
    handle: row.handle,
    initial: row.display_name.slice(0, 1)
  };
}

function mapProfile(row: ProfileRow, personName?: string) {
  const scenarioID = row.scenario_id ?? "jobs";
  const fallbackLabel = scenarioID === "friends" ? "Friends / Social" : "Career / Hiring";

  return {
    id: row.id,
    personName,
    label: row.label || fallbackLabel,
    slug: row.slug,
    summary: row.summary ?? "",
    published: row.is_published ?? true,
    scenarioID,
    scenarioDescription: row.scenario_description ?? "",
    avatarSeed: row.avatar_seed ?? row.slug,
    avatarStyle: row.avatar_style ?? "initials",
    avatarLetter: scenarioID === "friends" ? "F" : "C",
    avatarBg: scenarioID === "friends" ? "#c46a4a" : "#2f7d5a",
    platformIDs: row.platform_ids ?? [scenarioID === "friends" ? "knowyou-friends" : "knowyou-jobs"]
  };
}

function first<T>(value: T | T[] | null): T | null {
  if (Array.isArray(value)) {
    return value[0] ?? null;
  }
  return value;
}

function normalizePlatformID(value?: string) {
  return value && isNetworkingPlatformID(value) ? value : defaultNetworkingPlatformID;
}

function mapAgentActivity(row: AgentActivityRow): NetworkingAgentActivity {
  return {
    id: row.id,
    platformID: normalizePlatformID(row.platform_id),
    profileID: row.profile_id,
    personID: row.person_id,
    activityType: normalizeActivityType(row.activity_type),
    publicReferenceType: row.public_reference_type === "comment" ? "comment" : "post",
    publicReferenceID: row.public_reference_id ?? "",
    summary: row.summary,
    createdAt: row.created_at,
    reasonCode: row.reason_code ?? undefined,
    metadata: row.metadata ?? undefined
  };
}

function mapMembership(row: MembershipRow): NetworkingCommunityMembership {
  return {
    communityID: normalizePlatformID(row.community_id),
    profileID: row.profile_id,
    personID: row.person_id,
    status: row.status,
    policy: row.policy ?? undefined,
    lastHeartbeatAt: row.last_heartbeat_at ?? undefined,
    lastCandidateSeenAt: row.last_candidate_seen_at ?? undefined
  };
}

function mapInteractionEvent(row: InteractionEventRow): NetworkingInteractionEvent {
  return {
    id: row.id,
    platformID: normalizePlatformID(row.platform_id),
    personID: row.person_id,
    profileID: row.profile_id,
    eventType: normalizeEventType(row.event_type),
    postID: row.post_id ?? undefined,
    commentID: row.comment_id ?? undefined,
    actorPersonID: row.actor_person_id ?? undefined,
    actorProfileID: row.actor_profile_id ?? undefined,
    readAt: row.read_at ?? undefined,
    createdAt: row.created_at
  };
}

function normalizeEventType(value: string): NetworkingInteractionEvent["eventType"] {
  const allowed: NetworkingInteractionEvent["eventType"][] = [
    "new_comment_on_my_post",
    "reply_to_my_comment",
    "agent_commented",
    "candidate_found",
    "human_action_required",
    "read"
  ];
  return allowed.includes(value as NetworkingInteractionEvent["eventType"]) ? (value as NetworkingInteractionEvent["eventType"]) : "candidate_found";
}

function normalizeActivityType(value: string): NetworkingAgentActivity["activityType"] {
  const allowed: NetworkingAgentActivity["activityType"][] = [
    "heartbeat",
    "auto_comment",
    "auto_reply",
    "skipped",
    "saved_for_human",
    "rate_limited",
    "safety_blocked"
  ];
  return allowed.includes(value as NetworkingAgentActivity["activityType"]) ? (value as NetworkingAgentActivity["activityType"]) : "auto_comment";
}

function emptyProfilePage(platformID: string, handle = "platform"): NetworkingProfilePage {
  const platform = platformID === "knowyou-friends" ? "friends" : "careers";
  return {
    person: {
      id: `empty-${platform}`,
      displayName: "No public profile yet",
      handle,
      initial: "N"
    },
    profiles: []
  };
}
