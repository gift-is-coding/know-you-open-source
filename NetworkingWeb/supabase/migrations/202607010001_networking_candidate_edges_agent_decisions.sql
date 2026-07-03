create table if not exists public.candidate_edges (
    id uuid primary key default extensions.gen_random_uuid(),
    person_id uuid not null references public.people(id) on delete cascade,
    profile_id uuid not null references public.profiles(id) on delete cascade,
    platform_id text not null references public.communities(id) on delete cascade,
    source text not null,
    public_reference_type text not null check (public_reference_type in ('post', 'comment')),
    public_reference_id text not null,
    post_id uuid references public.posts(id) on delete cascade,
    comment_id uuid references public.comments(id) on delete cascade,
    reason_codes text[] not null default '{}',
    public_evidence text[] not null default '{}',
    score double precision not null default 0,
    status text not null default 'open' check (status in ('open', 'delivered', 'dismissed', 'expired')),
    expires_at timestamptz not null default now() + interval '7 days',
    created_at timestamptz not null default now(),
    constraint candidate_edges_known_source check (
        source in ('direct_inbox', 'watching', 'semantic_candidate', 'exploration')
    ),
    constraint candidate_edges_single_reference check (
        post_id is not null
        or comment_id is not null
    )
);

create unique index if not exists candidate_edges_profile_platform_reference_unique
    on public.candidate_edges(profile_id, platform_id, public_reference_type, public_reference_id);

create index if not exists candidate_edges_profile_platform_status_idx
    on public.candidate_edges(profile_id, platform_id, status, created_at desc);

alter table public.candidate_edges enable row level security;

drop policy if exists "candidate edges are readable by owner" on public.candidate_edges;
create policy "candidate edges are readable by owner"
    on public.candidate_edges for select
    using (
        exists (
            select 1 from public.people
            where people.id = candidate_edges.person_id
              and people.user_id = (select auth.uid())
        )
    );

create table if not exists public.agent_decisions (
    id uuid primary key default extensions.gen_random_uuid(),
    person_id uuid not null references public.people(id) on delete cascade,
    profile_id uuid not null references public.profiles(id) on delete cascade,
    platform_id text not null references public.communities(id) on delete cascade,
    action text not null check (action in ('skip', 'save_for_human', 'express_interest', 'comment_proposed', 'comment', 'reply')),
    public_reference_type text not null check (public_reference_type in ('post', 'comment')),
    public_reference_id text not null,
    post_id uuid references public.posts(id) on delete cascade,
    comment_id uuid references public.comments(id) on delete cascade,
    public_summary text not null default '',
    reason_codes text[] not null default '{}',
    client_decision_id text not null,
    created_at timestamptz not null default now()
);

create unique index if not exists agent_decisions_client_decision_unique
    on public.agent_decisions(profile_id, platform_id, client_decision_id);

create index if not exists agent_decisions_profile_platform_created_idx
    on public.agent_decisions(profile_id, platform_id, created_at desc);

alter table public.agent_decisions enable row level security;

drop policy if exists "agent decisions are readable by owner" on public.agent_decisions;
create policy "agent decisions are readable by owner"
    on public.agent_decisions for select
    using (
        exists (
            select 1 from public.people
            where people.id = agent_decisions.person_id
              and people.user_id = (select auth.uid())
        )
    );

drop function if exists public.networking_agent_record_decision(text, uuid, text, text, text, text, text, text[], text);
drop function if exists private.networking_agent_record_decision_impl(text, uuid, text, text, text, text, text, text[], text);

create or replace function private.networking_agent_record_decision_impl(
    p_token text,
    p_target_profile_id uuid,
    p_platform_id text,
    p_public_reference_type text,
    p_public_reference_id text,
    p_action text,
    p_public_summary text,
    p_reason_codes text[],
    p_client_decision_id text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    resolved_person_id uuid;
    resolved_post_id uuid;
    resolved_comment_id uuid;
    new_decision_id uuid;
begin
    if p_platform_id not in ('knowyou-jobs', 'knowyou-friends') then
        raise exception 'invalid networking platform';
    end if;

    if p_action not in ('skip', 'save_for_human', 'express_interest', 'comment_proposed', 'comment', 'reply') then
        raise exception 'invalid networking agent decision action';
    end if;

    select agent_tokens.person_id into resolved_person_id
    from public.agent_tokens
    join public.profiles on profiles.id = p_target_profile_id
    join public.community_memberships on community_memberships.profile_id = p_target_profile_id
    where agent_tokens.token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex')
      and agent_tokens.revoked_at is null
      and (agent_tokens.expires_at is null or agent_tokens.expires_at > now())
      and 'profile:write' = any(agent_tokens.scope)
      and (agent_tokens.profile_id is null or agent_tokens.profile_id = p_target_profile_id)
      and profiles.person_id = agent_tokens.person_id
      and profiles.is_published
      and p_platform_id = any(profiles.platform_ids)
      and community_memberships.person_id = agent_tokens.person_id
      and community_memberships.community_id = p_platform_id
      and community_memberships.status = 'active'
    limit 1;

    if resolved_person_id is null then
        raise exception 'invalid networking agent token';
    end if;

    if p_public_reference_type = 'post' then
        select posts.id into resolved_post_id
        from public.posts
        where posts.id::text = p_public_reference_id
          and posts.platform_id = p_platform_id
          and posts.is_public
        limit 1;
    elsif p_public_reference_type = 'comment' then
        select comments.post_id, comments.id into resolved_post_id, resolved_comment_id
        from public.comments
        where comments.id::text = p_public_reference_id
          and comments.platform_id = p_platform_id
          and comments.is_public
        limit 1;
    else
        raise exception 'invalid public reference type';
    end if;

    insert into public.agent_decisions(
        person_id,
        profile_id,
        platform_id,
        action,
        public_reference_type,
        public_reference_id,
        post_id,
        comment_id,
        public_summary,
        reason_codes,
        client_decision_id
    )
    values (
        resolved_person_id,
        p_target_profile_id,
        p_platform_id,
        p_action,
        p_public_reference_type,
        p_public_reference_id,
        resolved_post_id,
        resolved_comment_id,
        left(trim(coalesce(p_public_summary, '')), 500),
        coalesce(p_reason_codes, '{}'),
        nullif(trim(coalesce(p_client_decision_id, '')), '')
    )
    on conflict (profile_id, platform_id, client_decision_id) do update
    set
        action = excluded.action,
        public_summary = excluded.public_summary,
        reason_codes = excluded.reason_codes
    returning id into new_decision_id;

    update public.candidate_edges
    set status = case
        when p_action = 'skip' then 'dismissed'
        else 'delivered'
    end
    where profile_id = p_target_profile_id
      and platform_id = p_platform_id
      and public_reference_type = p_public_reference_type
      and public_reference_id = p_public_reference_id;

    insert into public.agent_activity(
        person_id,
        profile_id,
        platform_id,
        activity_type,
        public_reference_type,
        public_reference_id,
        summary,
        reason_code,
        metadata
    )
    values (
        resolved_person_id,
        p_target_profile_id,
        p_platform_id,
        case
            when p_action in ('comment', 'reply') then 'auto_comment'
            when p_action = 'skip' then 'skipped'
            else 'saved_for_human'
        end,
        p_public_reference_type,
        coalesce(resolved_comment_id, resolved_post_id),
        left(trim(coalesce(p_public_summary, '')), 240),
        coalesce(p_reason_codes[1], p_action),
        jsonb_build_object(
            'clientDecisionID', p_client_decision_id,
            'action', p_action,
            'publicReferenceID', p_public_reference_id
        )
    );

    update public.agent_tokens
    set last_used_at = now()
    where token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex');

    return new_decision_id;
end;
$$;

create or replace function public.networking_agent_record_decision(
    p_token text,
    p_target_profile_id uuid,
    p_platform_id text,
    p_public_reference_type text,
    p_public_reference_id text,
    p_action text,
    p_public_summary text,
    p_reason_codes text[],
    p_client_decision_id text
)
returns uuid
language sql
security invoker
set search_path = ''
as $$
    select private.networking_agent_record_decision_impl(
        p_token,
        p_target_profile_id,
        p_platform_id,
        p_public_reference_type,
        p_public_reference_id,
        p_action,
        p_public_summary,
        p_reason_codes,
        p_client_decision_id
    );
$$;

revoke execute on function private.networking_agent_record_decision_impl(text, uuid, text, text, text, text, text, text[], text) from public;
grant execute on function private.networking_agent_record_decision_impl(text, uuid, text, text, text, text, text, text[], text) to anon, authenticated;
grant execute on function public.networking_agent_record_decision(text, uuid, text, text, text, text, text, text[], text) to anon, authenticated;
