create table if not exists public.communities (
    id text primary key check (id in ('knowyou-jobs', 'knowyou-friends')),
    display_name text not null,
    description text not null default '',
    scenario_id text not null check (scenario_id in ('jobs', 'friends')),
    created_at timestamptz not null default now()
);

insert into public.communities(id, display_name, description, scenario_id)
values
    ('knowyou-jobs', 'Know You 求职', '招聘、求职、项目合作和团队匹配。', 'jobs'),
    ('knowyou-friends', 'Know You 认识新朋友', '认识新朋友、兴趣活动、轻社交和线下局。', 'friends')
on conflict (id) do update
set
    display_name = excluded.display_name,
    description = excluded.description,
    scenario_id = excluded.scenario_id;

alter table public.comments
    add column if not exists parent_comment_id uuid references public.comments(id) on delete cascade,
    add column if not exists client_decision_id text;

alter table public.agent_activity
    add column if not exists reason_code text,
    add column if not exists metadata jsonb not null default '{}'::jsonb;

alter table public.public_interaction_events
    add column if not exists read_at timestamptz,
    add column if not exists actor_person_id uuid references public.people(id) on delete set null,
    add column if not exists actor_profile_id uuid references public.profiles(id) on delete set null;

alter table public.agent_tokens
    add column if not exists scope text[] not null default array['profile:write']::text[];

alter table public.community_memberships
    add column if not exists policy jsonb not null default '{
        "autoComment": true,
        "dailyAutoCommentLimit": 8,
        "commentCooldownSeconds": 20,
        "riskyContentAction": "save_for_human"
    }'::jsonb,
    add column if not exists last_heartbeat_at timestamptz,
    add column if not exists last_candidate_seen_at timestamptz;

alter table public.community_memberships
    drop constraint if exists community_memberships_policy_default;
alter table public.community_memberships
    add constraint community_memberships_policy_default
    check (
        policy ? 'autoComment'
        and policy ? 'dailyAutoCommentLimit'
        and policy ? 'commentCooldownSeconds'
        and policy ? 'riskyContentAction'
    );

create unique index if not exists comments_agent_decision_unique
    on public.comments(profile_id, post_id, coalesce(parent_comment_id, '00000000-0000-0000-0000-000000000000'::uuid), client_decision_id)
    where author_type = 'ai' and client_decision_id is not null;

create index if not exists comments_parent_comment_created_idx
    on public.comments(parent_comment_id, created_at asc)
    where parent_comment_id is not null;
create index if not exists public_interaction_events_unread_idx
    on public.public_interaction_events(profile_id, platform_id, created_at desc)
    where read_at is null;

alter table public.communities enable row level security;

grant select on public.communities to anon, authenticated;

drop policy if exists "communities public read" on public.communities;
create policy "communities public read"
    on public.communities for select
    using (true);

drop function if exists public.networking_agent_create_comment(text, uuid, uuid, text, text);
drop function if exists public.networking_agent_create_comment(text, uuid, uuid, uuid, text, text, text);
drop function if exists private.networking_agent_create_comment_impl(text, uuid, uuid, text, text);
drop function if exists private.networking_agent_create_comment_impl(text, uuid, uuid, uuid, text, text, text);

create or replace function private.networking_agent_create_comment_impl(
    p_token text,
    p_target_post_id uuid,
    p_parent_comment_id uuid,
    p_target_profile_id uuid,
    p_platform_id text,
    p_body text,
    p_client_decision_id text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    resolved_person_id uuid;
    new_comment_id uuid;
begin
    if p_platform_id not in ('knowyou-jobs', 'knowyou-friends') then
        raise exception 'invalid networking platform';
    end if;

    if length(trim(coalesce(p_body, ''))) = 0 then
        raise exception 'empty networking agent body';
    end if;

    select agent_tokens.person_id into resolved_person_id
    from public.agent_tokens
    join public.profiles on profiles.id = p_target_profile_id
    join public.posts on posts.id = p_target_post_id
    join public.community_memberships on community_memberships.profile_id = p_target_profile_id
    where agent_tokens.token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex')
      and agent_tokens.revoked_at is null
      and (agent_tokens.expires_at is null or agent_tokens.expires_at > now())
      and 'profile:write' = any(agent_tokens.scope)
      and (agent_tokens.profile_id is null or agent_tokens.profile_id = p_target_profile_id)
      and profiles.person_id = agent_tokens.person_id
      and profiles.is_published
      and p_platform_id = any(profiles.platform_ids)
      and posts.is_public
      and posts.platform_id = p_platform_id
      and community_memberships.person_id = agent_tokens.person_id
      and community_memberships.community_id = p_platform_id
      and community_memberships.status = 'active'
      and (
          p_parent_comment_id is null
          or exists (
              select 1 from public.comments
              where comments.id = p_parent_comment_id
                and comments.post_id = p_target_post_id
                and comments.platform_id = p_platform_id
                and comments.is_public
          )
      )
    limit 1;

    if resolved_person_id is null then
        raise exception 'invalid networking agent token';
    end if;

    insert into public.comments(
        post_id,
        parent_comment_id,
        person_id,
        profile_id,
        platform_id,
        author_type,
        body,
        is_public,
        client_decision_id
    )
    values (
        p_target_post_id,
        p_parent_comment_id,
        resolved_person_id,
        p_target_profile_id,
        p_platform_id,
        'ai',
        trim(coalesce(p_body, '')),
        true,
        nullif(trim(coalesce(p_client_decision_id, '')), '')
    )
    on conflict do nothing
    returning id into new_comment_id;

    if new_comment_id is null then
        select comments.id into new_comment_id
        from public.comments
        where comments.profile_id = p_target_profile_id
          and comments.post_id = p_target_post_id
          and coalesce(comments.parent_comment_id, '00000000-0000-0000-0000-000000000000'::uuid)
              = coalesce(p_parent_comment_id, '00000000-0000-0000-0000-000000000000'::uuid)
          and comments.client_decision_id = nullif(trim(coalesce(p_client_decision_id, '')), '')
        limit 1;
    end if;

    update public.agent_tokens
    set last_used_at = now()
    where token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex');

    update public.community_memberships
    set last_heartbeat_at = now()
    where community_id = p_platform_id
      and profile_id = p_target_profile_id
      and person_id = resolved_person_id;

    insert into public.agent_activity(
        person_id,
        profile_id,
        platform_id,
        activity_type,
        public_reference_type,
        public_reference_id,
        summary,
        metadata
    )
    values (
        resolved_person_id,
        p_target_profile_id,
        p_platform_id,
        case when p_parent_comment_id is null then 'auto_comment' else 'auto_reply' end,
        'comment',
        new_comment_id,
        left(trim(coalesce(p_body, '')), 240),
        jsonb_build_object('clientDecisionID', p_client_decision_id)
    );

    return new_comment_id;
end;
$$;

create or replace function public.networking_agent_create_comment(
    p_token text,
    p_target_post_id uuid,
    p_parent_comment_id uuid,
    p_target_profile_id uuid,
    p_platform_id text,
    p_body text,
    p_client_decision_id text
)
returns uuid
language sql
security invoker
set search_path = ''
as $$
    select private.networking_agent_create_comment_impl(
        p_token,
        p_target_post_id,
        p_parent_comment_id,
        p_target_profile_id,
        p_platform_id,
        p_body,
        p_client_decision_id
    );
$$;

revoke execute on function private.networking_agent_create_comment_impl(text, uuid, uuid, uuid, text, text, text) from public;
grant execute on function private.networking_agent_create_comment_impl(text, uuid, uuid, uuid, text, text, text) to anon, authenticated;
grant execute on function public.networking_agent_create_comment(text, uuid, uuid, uuid, text, text, text) to anon, authenticated;
