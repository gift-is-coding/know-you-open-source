"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { defaultNetworkingPlatformID, isNetworkingPlatformID } from "@/src/lib/networking/platforms";
import { hasSupabaseEnv } from "@/src/lib/supabase/env";
import { createClient } from "@/src/lib/supabase/server";
import type { SupabaseClient } from "@supabase/supabase-js";

export async function createHumanPost(formData: FormData) {
  if (!hasSupabaseEnv()) {
    redirect("/auth?status=configure-supabase");
  }

  const profileID = String(formData.get("profileID") ?? "");
  const platformID = normalizePlatformID(String(formData.get("platformID") ?? ""));
  const body = String(formData.get("body") ?? "").trim();

  if (!profileID || !body) {
    redirect("/?compose=missing-fields");
  }

  const supabase = await createClient();
  const person = await getCurrentPerson(supabase);

  const { error } = await supabase.from("posts").insert({
    person_id: person.id,
    profile_id: profileID,
    platform_id: platformID,
    author_type: "human",
    body,
    is_public: true
  });

  if (error) {
    redirect("/?compose=failed");
  }

  revalidatePath("/");
  redirect(`/?platform=${platformID}`);
}

export async function createHumanComment(formData: FormData) {
  if (!hasSupabaseEnv()) {
    redirect("/auth?status=configure-supabase");
  }

  const postID = String(formData.get("postID") ?? "");
  const profileID = String(formData.get("profileID") ?? "");
  const platformID = normalizePlatformID(String(formData.get("platformID") ?? ""));
  const body = String(formData.get("body") ?? "").trim();

  if (!postID || !profileID || !body) {
    redirect("/?comment=missing-fields");
  }

  const supabase = await createClient();
  const person = await getCurrentPerson(supabase);

  const { error } = await supabase.from("comments").insert({
    post_id: postID,
    person_id: person.id,
    profile_id: profileID,
    platform_id: platformID,
    author_type: "human",
    body,
    is_public: true
  });

  if (error) {
    redirect("/?comment=failed");
  }

  revalidatePath("/");
  redirect(`/?platform=${platformID}`);
}

export async function saveProfile(formData: FormData) {
  if (!hasSupabaseEnv()) {
    redirect("/auth?status=configure-supabase");
  }

  const displayName = String(formData.get("displayName") ?? "").trim();
  const handle = normalizeSlug(String(formData.get("handle") ?? ""));
  const label = String(formData.get("label") ?? "").trim();
  const slug = normalizeSlug(String(formData.get("slug") ?? label));
  const scenarioID = normalizeScenarioID(String(formData.get("scenarioID") ?? ""));
  const scenarioDescription = String(formData.get("scenarioDescription") ?? "").trim();
  const avatarSeed = String(formData.get("avatarSeed") ?? slug).trim() || slug;
  const avatarStyle = normalizeAvatarStyle(String(formData.get("avatarStyle") ?? ""));
  const platformIDs = normalizePlatformIDs(String(formData.get("platformIDs") ?? ""));
  const summary = String(formData.get("summary") ?? "").trim();
  const body = String(formData.get("body") ?? "").trim();
  const isPublished = formData.get("isPublished") === "on";

  if (!displayName || !handle || !label || !slug) {
    redirect("/profiles/me?status=missing-fields");
  }

  const supabase = await createClient();
  const {
    data: { user }
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/auth?status=signin-required");
  }

  const { data: person, error: personError } = await supabase
    .from("people")
    .upsert(
      {
        user_id: user.id,
        display_name: displayName,
        handle
      },
      { onConflict: "user_id" }
    )
    .select("id")
    .single();

  if (personError || !person) {
    redirect("/profiles/me?status=person-failed");
  }

  const { error: profileError } = await supabase.from("profiles").upsert(
    {
      person_id: person.id,
      slug,
      label,
      scenario_id: scenarioID,
      scenario_description: scenarioDescription,
      avatar_seed: avatarSeed,
      avatar_style: avatarStyle,
      platform_ids: platformIDs,
      summary,
      body,
      is_published: isPublished
    },
    { onConflict: "person_id,slug" }
  );

  if (profileError) {
    redirect("/profiles/me?status=profile-failed");
  }

  revalidatePath("/");
  revalidatePath(`/profiles/${handle}`);
  redirect(`/profiles/${handle}`);
}

async function getCurrentPerson(supabase: SupabaseClient) {
  const {
    data: { user }
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/auth?status=signin-required");
  }

  const { data: person } = await supabase
    .from("people")
    .select("id")
    .eq("user_id", user.id)
    .single();

  if (!person) {
    redirect("/profiles/me?status=profile-required");
  }

  return person;
}

function normalizeSlug(value: string) {
  return value
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
}

function normalizePlatformID(value: string) {
  return isNetworkingPlatformID(value) ? value : defaultNetworkingPlatformID;
}

function normalizePlatformIDs(value: string) {
  const platformIDs = value
    .split(",")
    .map((item) => item.trim())
    .filter(isNetworkingPlatformID);

  return platformIDs.length > 0 ? platformIDs : [defaultNetworkingPlatformID];
}

function normalizeScenarioID(value: string) {
  return value === "friends" ? "friends" : "jobs";
}

function normalizeAvatarStyle(value: string) {
  return value === "gradient" ? "gradient" : "initials";
}
