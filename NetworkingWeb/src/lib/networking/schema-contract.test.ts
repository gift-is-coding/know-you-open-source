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
      ["communities", true],
      ["people", true],
      ["profiles", true],
      ["posts", true],
      ["comments", true],
      ["agent_activity", true],
      ["agent_tokens", true],
      ["public_interaction_events", true],
      ["community_memberships", true],
      ["candidate_edges", true],
      ["agent_decisions", true]
    ]);
  });

  it("models app-first platform fields for profiles and public activity", () => {
    const profileColumns = networkingSchemaContract.tables.find((table) => table.name === "profiles")?.columns ?? [];
    const postColumns = networkingSchemaContract.tables.find((table) => table.name === "posts")?.columns ?? [];
    const commentColumns = networkingSchemaContract.tables.find((table) => table.name === "comments")?.columns ?? [];
    const membershipColumns = networkingSchemaContract.tables.find((table) => table.name === "community_memberships")?.columns ?? [];
    const activityColumns = networkingSchemaContract.tables.find((table) => table.name === "agent_activity")?.columns ?? [];
    const eventColumns = networkingSchemaContract.tables.find((table) => table.name === "public_interaction_events")?.columns ?? [];
    const edgeColumns = networkingSchemaContract.tables.find((table) => table.name === "candidate_edges")?.columns ?? [];
    const decisionColumns = networkingSchemaContract.tables.find((table) => table.name === "agent_decisions")?.columns ?? [];

    expect(profileColumns).toEqual(expect.arrayContaining(["scenario_id", "avatar_seed", "avatar_style"]));
    expect(postColumns).toContain("platform_id");
    expect(commentColumns).toEqual(expect.arrayContaining(["platform_id", "parent_comment_id", "client_decision_id"]));
    expect(membershipColumns).toEqual(expect.arrayContaining(["policy", "last_heartbeat_at", "last_candidate_seen_at"]));
    expect(activityColumns).toEqual(expect.arrayContaining(["platform_id", "reason_code", "metadata"]));
    expect(eventColumns).toEqual(expect.arrayContaining(["platform_id", "read_at", "actor_person_id", "actor_profile_id"]));
    expect(edgeColumns).toEqual(expect.arrayContaining(["source", "reason_codes", "public_evidence", "score", "expires_at"]));
    expect(decisionColumns).toEqual(expect.arrayContaining(["action", "public_summary", "reason_codes", "client_decision_id"]));
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

  it("keeps public interaction events tied to valid public references", () => {
    expect(migrationSQL).toContain("constraint public_interaction_events_single_reference check");
    expect(migrationSQL).toContain("post_id is not null");
    expect(migrationSQL).toContain("or comment_id is not null");
    expect(migrationSQL).toContain("public_interaction_events_comment_matches_post");
    expect(migrationSQL).toContain("foreign key (comment_id, post_id)");
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
    expect(migrationSQL).toContain("p_parent_comment_id uuid");
    expect(migrationSQL).toContain("p_client_decision_id text");
    expect(migrationSQL).toContain("create or replace function public.networking_agent_home");
    expect(migrationSQL).toContain("create or replace function public.networking_agent_mark_events_read");
    expect(migrationSQL).toContain("values (resolved_person_id, p_target_profile_id, p_platform_id, 'ai'");
    expect(migrationSQL).toContain("extensions.digest(p_token, 'sha256')");
    expect(migrationSQL).toContain("if length(trim(coalesce(p_body, ''))) = 0 then");
  });

  it("exposes the platform-scoped agent post RPC used by the web API", () => {
    const publicCreatePostStart = migrationSQL.lastIndexOf(
      "create or replace function public.networking_agent_create_post"
    );
    const privateCreatePostStart = migrationSQL.lastIndexOf(
      "create or replace function private.networking_agent_create_post_impl"
    );
    expect(privateCreatePostStart).toBeGreaterThan(-1);
    expect(publicCreatePostStart).toBeGreaterThan(-1);

    const publicCreatePost = migrationSQL.slice(publicCreatePostStart, publicCreatePostStart + 520);
    const privateCreatePost = migrationSQL.slice(privateCreatePostStart, publicCreatePostStart);
    expect(publicCreatePost).toContain("p_token text");
    expect(publicCreatePost).toContain("p_target_profile_id uuid");
    expect(publicCreatePost).toContain("p_platform_id text");
    expect(publicCreatePost).toContain("p_body text");
    expect(publicCreatePost).toContain(
      "private.networking_agent_create_post_impl(p_token, p_target_profile_id, p_platform_id, p_body)"
    );
    expect(privateCreatePost).toContain("p_platform_id = any(profiles.platform_ids)");
    expect(privateCreatePost).toContain("join public.community_memberships");
    expect(privateCreatePost).toContain("community_memberships.status = 'active'");
    expect(privateCreatePost).toContain("dailyAutoPostLimit");
    expect(privateCreatePost).toContain("networking agent daily auto-post limit reached");
    expect(privateCreatePost).toContain("'auto_post'");
    expect(migrationSQL).toContain("grant execute on function public.networking_agent_create_post(text, uuid, text, text)");
  });

  it("models profile-agent community heartbeat and event state", () => {
    expect(migrationSQL).toContain("create table if not exists public.communities");
    expect(migrationSQL).toContain("insert into public.communities");
    expect(migrationSQL).toContain("parent_comment_id uuid references public.comments(id)");
    expect(migrationSQL).toContain("read_at timestamptz");
    expect(migrationSQL).toContain("reason_code text");
    expect(migrationSQL).toContain("metadata jsonb");
    expect(migrationSQL).toContain("scope text[]");
    expect(migrationSQL).toContain("comments_agent_decision_unique");
    expect(migrationSQL).toContain("drop index if exists public.comments_post_profile_author_unique");
    expect(migrationSQL).toContain("community_memberships_policy_default");
  });

  it("models write-time candidate fanout and agent decisions without storing private reasoning", () => {
    expect(migrationSQL).toContain("create table if not exists public.candidate_edges");
    expect(migrationSQL).toContain("create table if not exists public.agent_decisions");
    expect(migrationSQL).toContain("candidate_edges_profile_platform_reference_unique");
    expect(migrationSQL).toContain("agent_decisions_client_decision_unique");
    expect(migrationSQL).toContain("reason_codes text[] not null default '{}'");
    expect(migrationSQL).toContain("public_evidence text[] not null default '{}'");
    expect(migrationSQL).not.toContain("private_reason");
    expect(migrationSQL).not.toContain("my_wiki_evidence");
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

  it("restores owner write grants after the platform-wide revoke", () => {
    const revokeStart = migrationSQL.indexOf("revoke insert, update, delete, truncate, references, trigger");
    expect(revokeStart).toBeGreaterThan(-1);

    const afterRevoke = migrationSQL.slice(revokeStart);
    expect(afterRevoke).toContain("grant insert, update on public.people to authenticated");
    expect(afterRevoke).toContain("grant insert, update on public.profiles to authenticated");
    expect(afterRevoke).toContain("grant insert, update on public.posts to authenticated");
    expect(afterRevoke).toContain("grant insert, update on public.comments to authenticated");
    expect(afterRevoke).toContain("grant insert, update on public.community_memberships to authenticated");
    expect(afterRevoke).toContain("grant insert, update on public.agent_tokens to authenticated");
    expect(afterRevoke).toContain("grant select on public.agent_tokens to authenticated");
  });

  it("lets owners activate and update their own community memberships", () => {
    expect(migrationSQL).toContain("owners can insert community memberships");
    expect(migrationSQL).toContain("owners can update community memberships");
    expect(migrationSQL).toContain("and profiles.id = community_memberships.profile_id");
  });

  it("fans out public posts to candidate edges at write time", () => {
    expect(migrationSQL).toContain("create or replace function private.networking_fanout_candidate_edges");
    expect(migrationSQL).toContain("create trigger networking_posts_candidate_fanout");
    expect(migrationSQL).toContain("after insert on public.posts");
    expect(migrationSQL).toContain(
      "on conflict (profile_id, platform_id, public_reference_type, public_reference_id) do nothing"
    );
  });

  it("fans out public comments and replies to recipient agent inbox events", () => {
    expect(migrationSQL).toContain("create or replace function private.networking_create_comment_interaction_events");
    expect(migrationSQL).toContain("create trigger networking_comments_interaction_events");
    expect(migrationSQL).toContain("after insert on public.comments");
    expect(migrationSQL).toContain("'new_comment_on_my_post'");
    expect(migrationSQL).toContain("'reply_to_my_comment'");
    expect(migrationSQL).toContain("parent_comment.person_id <> new.person_id");
  });

  it("returns the three agent home queues from candidate edges with a working cap", () => {
    const homeImplStart = migrationSQL.lastIndexOf("create or replace function private.networking_agent_home_impl");
    expect(homeImplStart).toBeGreaterThan(-1);

    const homeImpl = migrationSQL.slice(homeImplStart);
    expect(homeImpl).toContain("'needsReply'");
    expect(homeImpl).toContain("'potentialMatches'");
    expect(homeImpl).toContain("'savedForYou'");
    expect(homeImpl).toContain("from public.candidate_edges");
    expect(homeImpl).toContain("join public.profiles on profiles.person_id = agent_tokens.person_id");
    expect(homeImpl).toContain("(agent_tokens.profile_id is null or agent_tokens.profile_id = profiles.id)");
    expect(homeImpl).toContain("limit 20");
    expect(migrationSQL).toContain("to_jsonb('express_interest'::text)");
    expect(homeImpl).toContain("'reply_slots_full'");
    expect(homeImpl).toContain("'risky_content'");
    expect(homeImpl).toContain("'daily_limit'");
  });

  it("enforces daily limits, reply slots, and self-comment rules server-side", () => {
    const commentImplStart = migrationSQL.lastIndexOf(
      "create or replace function private.networking_agent_create_comment_impl"
    );
    expect(commentImplStart).toBeGreaterThan(-1);

    const commentImpl = migrationSQL.slice(commentImplStart);
    expect(commentImpl).toContain("networking agent daily auto-comment limit reached");
    expect(commentImpl).toContain("networking agent reply slots exhausted for this post");
    expect(commentImpl).toContain("agent cannot comment on its own root post");
    expect(migrationSQL).toContain("networking agent public comment is too generic");
  });

  it("prevents agent-to-agent ping-pong by routing repeated thread actions to humans", () => {
    const homeImplStart = migrationSQL.lastIndexOf("create or replace function private.networking_agent_home_impl");
    const commentImplStart = migrationSQL.lastIndexOf(
      "create or replace function private.networking_agent_create_comment_impl"
    );
    expect(homeImplStart).toBeGreaterThan(-1);
    expect(commentImplStart).toBeGreaterThan(-1);

    const homeImpl = migrationSQL.slice(homeImplStart, commentImplStart);
    const commentImpl = migrationSQL.slice(commentImplStart);
    expect(homeImpl).toContain("thread_already_touched");
    expect(homeImpl).toContain("这个 thread 已有本 profile 的公开 AI 行动，交给人判断");
    expect(commentImpl).toContain("networking agent already acted on this thread");
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
