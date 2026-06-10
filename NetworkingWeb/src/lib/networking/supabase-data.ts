import { profilePageFixture, publicSquareFixture } from "./fixtures";
import { defaultNetworkingPlatformID, isNetworkingPlatformID } from "./platforms";
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
  people: PersonRow | PersonRow[] | null;
  profiles: ProfileRow | ProfileRow[] | null;
};

export async function getPublicSquareItems(platformID?: string): Promise<NetworkingContentItem[]> {
  const normalizedPlatformID = normalizePlatformID(platformID);

  if (!hasSupabaseEnv()) {
    return publicSquareFixture.filter((item) => item.platformID === normalizedPlatformID);
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
        "id, post_id, platform_id, body, author_type, created_at, people(id, display_name, handle), profiles(id, label, slug, scenario_id, scenario_description, avatar_seed, avatar_style, platform_ids, summary, is_published)"
      )
      .eq("is_public", true)
      .order("created_at", { ascending: false })
      .limit(50);

    postsQuery = postsQuery.eq("platform_id", normalizedPlatformID);
    commentsQuery = commentsQuery.eq("platform_id", normalizedPlatformID);

    const [postsResult, commentsResult] = await Promise.all([postsQuery, commentsQuery]);

    if (postsResult.error || commentsResult.error) {
      return publicSquareFixture.filter((item) => item.platformID === normalizedPlatformID);
    }

    const items = [
      ...(postsResult.data ?? []).map((row) => mapContentRow(row as ContentRow, "post")),
      ...(commentsResult.data ?? []).map((row) => mapContentRow(row as ContentRow, "comment"))
    ].filter((item): item is NetworkingContentItem => Boolean(item));

    return items.length > 0 ? items : publicSquareFixture.filter((item) => item.platformID === normalizedPlatformID);
  } catch {
    return publicSquareFixture.filter((item) => item.platformID === normalizedPlatformID);
  }
}

export async function getPublicProfilePage(handle: string): Promise<NetworkingProfilePage> {
  if (!hasSupabaseEnv()) {
    return profilePageFixture;
  }

  try {
    const supabase = await createClient();
    const { data: person, error: personError } = await supabase
      .from("people")
      .select("id, display_name, handle")
      .eq("handle", handle)
      .single();

    if (personError || !person) {
      return profilePageFixture;
    }

    const { data: profiles, error: profilesError } = await supabase
      .from("profiles")
      .select("id, label, slug, scenario_id, scenario_description, avatar_seed, avatar_style, platform_ids, summary, is_published")
      .eq("person_id", person.id)
      .eq("is_published", true)
      .order("updated_at", { ascending: false });

    if (profilesError) {
      return profilePageFixture;
    }

    return {
      person: mapPerson(person as PersonRow),
      profiles: (profiles ?? []).map((profile) => mapProfile(profile as ProfileRow, person.display_name as string))
    };
  } catch {
    return profilePageFixture;
  }
}

export async function getComposerProfiles(platformID?: string): Promise<NetworkingComposerProfile[]> {
  const normalizedPlatformID = normalizePlatformID(platformID);

  if (!hasSupabaseEnv()) {
    return profilePageFixture.profiles
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

    const { data: profiles } = await supabase
      .from("profiles")
      .select("id, label, platform_ids")
      .eq("person_id", person.id)
      .eq("is_published", true)
      .contains("platform_ids", [normalizedPlatformID])
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
    parentPostID: row.post_id
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
  const fallbackLabel = scenarioID === "friends" ? "认识新朋友" : "职业/求职";

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
    avatarLetter: scenarioID === "friends" ? "友" : "职",
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
