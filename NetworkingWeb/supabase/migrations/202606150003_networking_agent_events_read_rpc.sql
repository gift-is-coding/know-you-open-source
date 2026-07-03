drop function if exists public.networking_agent_mark_events_read(text, text, uuid[]);
drop function if exists private.networking_agent_mark_events_read_impl(text, text, uuid[]);

create or replace function private.networking_agent_mark_events_read_impl(
    p_token text,
    p_platform_id text,
    p_event_ids uuid[]
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
    resolved_person_id uuid;
    resolved_profile_id uuid;
    updated_count integer;
begin
    if p_platform_id not in ('knowyou-jobs', 'knowyou-friends') then
        raise exception 'invalid networking platform';
    end if;

    if p_event_ids is null or cardinality(p_event_ids) = 0 then
        return 0;
    end if;

    select agent_tokens.person_id, profiles.id
    into resolved_person_id, resolved_profile_id
    from public.agent_tokens
    join public.profiles on profiles.id = agent_tokens.profile_id
    join public.community_memberships on community_memberships.profile_id = profiles.id
    where agent_tokens.token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex')
      and agent_tokens.revoked_at is null
      and (agent_tokens.expires_at is null or agent_tokens.expires_at > now())
      and 'profile:write' = any(agent_tokens.scope)
      and profiles.person_id = agent_tokens.person_id
      and profiles.is_published
      and p_platform_id = any(profiles.platform_ids)
      and community_memberships.person_id = agent_tokens.person_id
      and community_memberships.community_id = p_platform_id
    limit 1;

    if resolved_person_id is null or resolved_profile_id is null then
        raise exception 'invalid networking agent token';
    end if;

    update public.public_interaction_events
    set read_at = coalesce(read_at, now())
    where id = any(p_event_ids)
      and platform_id = p_platform_id
      and person_id = resolved_person_id
      and profile_id = resolved_profile_id;

    get diagnostics updated_count = row_count;

    update public.agent_tokens
    set last_used_at = now()
    where token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex');

    return updated_count;
end;
$$;

create or replace function public.networking_agent_mark_events_read(
    p_token text,
    p_platform_id text,
    p_event_ids uuid[]
)
returns integer
language sql
security invoker
set search_path = ''
as $$
    select private.networking_agent_mark_events_read_impl(p_token, p_platform_id, p_event_ids);
$$;

revoke execute on function private.networking_agent_mark_events_read_impl(text, text, uuid[]) from public;
grant execute on function private.networking_agent_mark_events_read_impl(text, text, uuid[]) to anon, authenticated;
grant execute on function public.networking_agent_mark_events_read(text, text, uuid[]) to anon, authenticated;
