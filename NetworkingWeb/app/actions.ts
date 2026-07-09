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
  const parentCommentID = normalizeOptionalID(String(formData.get("parentCommentID") ?? ""));
  const body = String(formData.get("body") ?? "").trim();

  if (!postID || !profileID || !body) {
    redirect("/?comment=missing-fields");
  }

  const supabase = await createClient();
  const person = await getCurrentPerson(supabase);

  const { error } = await supabase.from("comments").insert({
    post_id: postID,
    parent_comment_id: parentCommentID,
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
    redirect("/?status=profile-required");
  }

  return person;
}

function normalizePlatformID(value: string) {
  return isNetworkingPlatformID(value) ? value : defaultNetworkingPlatformID;
}

function normalizeOptionalID(value: string) {
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}
