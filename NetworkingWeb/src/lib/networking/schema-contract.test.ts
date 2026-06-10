import { describe, expect, it } from "vitest";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { networkingSchemaContract } from "./schema-contract";

const migrationsDir = join(process.cwd(), "supabase/migrations");
const migrationSQL = readdirSync(migrationsDir)
  .filter((file) => file.endsWith(".sql"))
  .sort()
  .map((file) => readFileSync(join(migrationsDir, file), "utf8"))
  .join("\n");

describe("networking schema contract", () => {
  it("requires every public table to have row level security enabled", () => {
    expect(networkingSchemaContract.tables.map((table) => [table.name, table.rls])).toEqual([
      ["people", true],
      ["profiles", true],
      ["posts", true],
      ["comments", true],
      ["agent_activity", true],
      ["agent_tokens", true],
      ["public_interaction_events", true]
    ]);
  });

  it("models app-first platform fields for profiles and public activity", () => {
    const profileColumns = networkingSchemaContract.tables.find((table) => table.name === "profiles")?.columns ?? [];
    const postColumns = networkingSchemaContract.tables.find((table) => table.name === "posts")?.columns ?? [];
    const commentColumns = networkingSchemaContract.tables.find((table) => table.name === "comments")?.columns ?? [];
    const activityColumns = networkingSchemaContract.tables.find((table) => table.name === "agent_activity")?.columns ?? [];
    const eventColumns = networkingSchemaContract.tables.find((table) => table.name === "public_interaction_events")?.columns ?? [];

    expect(profileColumns).toEqual(expect.arrayContaining(["scenario_id", "avatar_seed", "avatar_style"]));
    expect(postColumns).toContain("platform_id");
    expect(commentColumns).toContain("platform_id");
    expect(activityColumns).toContain("platform_id");
    expect(eventColumns).toContain("platform_id");
  });

  it("keeps private My Wiki reasoning out of platform tables", () => {
    const columns = networkingSchemaContract.tables.flatMap((table) =>
      table.columns.map((column) => `${table.name}.${column}`)
    );

    expect(columns).not.toContain("profiles.private_my_wiki_evidence");
    expect(columns).not.toContain("agent_activity.private_match_reason");
    expect(networkingSchemaContract.privateFieldsStayLocal).toEqual([
      "myWikiEvidence",
      "profileDraft",
      "matchReason"
    ]);
  });

  it("documents public read and authenticated write policies", () => {
    expect(networkingSchemaContract.policySummary).toContain(
      "Public read is limited to published profiles and public posts/comments."
    );
    expect(networkingSchemaContract.policySummary).toContain(
      "Writes require an authenticated owner or a local KnowYou agent acting for that owner."
    );
  });

  it("constrains public post and comment visibility to published profile boundaries", () => {
    expect(migrationSQL).toContain("and profiles.person_id = posts.person_id");
    expect(migrationSQL).toContain("and profiles.is_published");
    expect(migrationSQL).toContain("and profiles.person_id = comments.person_id");
  });

  it("prevents owner writes from mixing another person's profile with a post or comment", () => {
    expect(migrationSQL).toContain("where profiles.id = posts.profile_id");
    expect(migrationSQL).toContain("where profiles.id = comments.profile_id");
    expect(migrationSQL).toContain("and profiles.person_id = comments.person_id");
  });

  it("keeps public interaction events tied to exactly one public reference", () => {
    expect(migrationSQL).toContain("constraint public_interaction_events_single_reference check");
    expect(migrationSQL).toContain("(post_id is not null and comment_id is null)");
    expect(migrationSQL).toContain("(post_id is null and comment_id is not null)");
    expect(migrationSQL).toContain("where posts.id = public_interaction_events.post_id");
    expect(migrationSQL).toContain("where comments.id = public_interaction_events.comment_id");
    expect(migrationSQL).toContain("and comments.is_public");
  });

  it("supports local KnowYou agent token writes through explicit AI RPC functions", () => {
    expect(migrationSQL).toContain("create schema if not exists extensions");
    expect(migrationSQL).toContain('create extension if not exists "pgcrypto" with schema extensions');
    expect(migrationSQL).toContain("create table if not exists public.agent_tokens");
    expect(migrationSQL).toContain("token_hash text not null unique");
    expect(migrationSQL).toContain("create schema if not exists private");
    expect(migrationSQL).toContain("create or replace function private.networking_agent_create_post_impl");
    expect(migrationSQL).toContain("create or replace function private.networking_agent_create_comment_impl");
    expect(migrationSQL).toContain("create or replace function public.networking_agent_create_post");
    expect(migrationSQL).toContain("security invoker");
    expect(migrationSQL).toContain("set search_path = ''");
    expect(migrationSQL).toContain("p_platform_id text");
    expect(migrationSQL).toContain("values (resolved_person_id, p_target_profile_id, p_platform_id, 'ai'");
    expect(migrationSQL).toContain("extensions.digest(p_token, 'sha256')");
    expect(migrationSQL).toContain("if length(trim(coalesce(p_body, ''))) = 0 then");
  });

  it("documents anonymous App activation as authenticated owner writes", () => {
    expect(networkingSchemaContract.authModes).toEqual(["supabaseAnonymous"]);
    expect(networkingSchemaContract.policySummary).toContain(
      "App activation uses Supabase anonymous sign-in, which writes as authenticated owner."
    );
    expect(migrationSQL).toContain("knowyou-jobs");
    expect(migrationSQL).toContain("knowyou-friends");
  });

  it("keeps security definer agent logic out of the exposed public schema", () => {
    const publicCreatePostStart = migrationSQL.indexOf(
      "create or replace function public.networking_agent_create_post"
    );
    const privateCreatePostStart = migrationSQL.indexOf(
      "create or replace function private.networking_agent_create_post_impl"
    );

    expect(privateCreatePostStart).toBeGreaterThan(-1);
    expect(publicCreatePostStart).toBeGreaterThan(-1);
    expect(
      migrationSQL.slice(privateCreatePostStart, publicCreatePostStart)
    ).toContain("security definer");
    expect(
      migrationSQL.slice(publicCreatePostStart, publicCreatePostStart + 500)
    ).not.toContain("security definer");
  });

  it("keeps RLS and foreign-key indexes advisor-friendly for the public schema", () => {
    expect(migrationSQL).toContain("people.user_id = (select auth.uid())");
    expect(migrationSQL).toContain("posts_profile_id_idx on public.posts(profile_id)");
    expect(migrationSQL).toContain("comments_profile_id_idx on public.comments(profile_id)");
    expect(migrationSQL).toContain("agent_activity_profile_id_idx on public.agent_activity(profile_id)");
    expect(migrationSQL).toContain("agent_tokens_profile_id_idx on public.agent_tokens(profile_id)");
    expect(migrationSQL).toContain(
      "public_interaction_events_comment_id_idx\n    on public.public_interaction_events(comment_id)"
    );
    expect(migrationSQL).toContain("profiles are readable when published or owned");
  });
});
