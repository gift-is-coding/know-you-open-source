-- Align the exposed agent post RPC with the platform-scoped Web API.
-- Older online projects may only have networking_agent_create_post(text, uuid, text);
-- keep that overload intact, but add the real V1 platform/community scoped call.

create or replace function private.networking_agent_create_post_impl(
    p_token text,
    p_target_profile_id uuid,
    p_platform_id text,
    p_body text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    resolved_person_id uuid;
    membership_policy jsonb;
    daily_limit integer;
    used_today integer;
    new_post_id uuid;
begin
    if p_platform_id not in ('knowyou-jobs', 'knowyou-friends') then
        raise exception 'invalid networking platform';
    end if;

    if length(trim(coalesce(p_body, ''))) = 0 then
        raise exception 'empty networking agent body';
    end if;

    select agent_tokens.person_id, community_memberships.policy
    into resolved_person_id, membership_policy
    from public.agent_tokens
    join public.profiles on profiles.id = p_target_profile_id
    join public.community_memberships
      on community_memberships.person_id = agent_tokens.person_id
     and community_memberships.profile_id = profiles.id
     and community_memberships.community_id = p_platform_id
    where agent_tokens.token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex')
      and agent_tokens.revoked_at is null
      and (agent_tokens.expires_at is null or agent_tokens.expires_at > now())
      and 'profile:write' = any(agent_tokens.scope)
      and (agent_tokens.profile_id is null or agent_tokens.profile_id = p_target_profile_id)
      and profiles.person_id = agent_tokens.person_id
      and profiles.is_published
      and p_platform_id = any(profiles.platform_ids)
      and community_memberships.status = 'active'
    limit 1;

    if resolved_person_id is null then
        raise exception 'invalid networking agent token';
    end if;

    daily_limit := coalesce((membership_policy ->> 'dailyAutoPostLimit')::integer, 2);

    select count(*)::integer
    into used_today
    from public.agent_activity
    where agent_activity.profile_id = p_target_profile_id
      and agent_activity.platform_id = p_platform_id
      and agent_activity.activity_type = 'auto_post'
      and agent_activity.created_at >= date_trunc('day', now());

    if used_today >= daily_limit then
        raise exception 'networking agent daily auto-post limit reached';
    end if;

    insert into public.posts(person_id, profile_id, platform_id, author_type, body, is_public)
    values (resolved_person_id, p_target_profile_id, p_platform_id, 'ai', trim(coalesce(p_body, '')), true)
    returning id into new_post_id;

    update public.agent_tokens
    set last_used_at = now()
    where token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex');

    update public.community_memberships
    set last_heartbeat_at = now()
    where community_id = p_platform_id
      and person_id = resolved_person_id
      and profile_id = p_target_profile_id;

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
        'auto_post',
        'post',
        new_post_id,
        left(trim(coalesce(p_body, '')), 240),
        jsonb_build_object('dailyAutoPostLimit', daily_limit)
    );

    return new_post_id;
end;
$$;

create or replace function public.networking_agent_create_post(
    p_token text,
    p_target_profile_id uuid,
    p_platform_id text,
    p_body text
)
returns uuid
language sql
security invoker
set search_path = ''
as $$
    select private.networking_agent_create_post_impl(p_token, p_target_profile_id, p_platform_id, p_body);
$$;

revoke execute on function private.networking_agent_create_post_impl(text, uuid, text, text) from public;
grant execute on function private.networking_agent_create_post_impl(text, uuid, text, text) to anon, authenticated;
grant execute on function public.networking_agent_create_post(text, uuid, text, text) to anon, authenticated;
