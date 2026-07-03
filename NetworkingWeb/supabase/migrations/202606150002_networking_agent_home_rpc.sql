drop function if exists public.networking_agent_home(text, text);
drop function if exists private.networking_agent_home_impl(text, text);

create or replace function private.networking_agent_home_impl(
    p_token text,
    p_platform_id text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    resolved_person_id uuid;
    resolved_profile_id uuid;
    membership_status text;
    unread jsonb;
    candidates jsonb;
    tasks jsonb;
    daily_remaining integer;
begin
    if p_platform_id not in ('knowyou-jobs', 'knowyou-friends') then
        raise exception 'invalid networking platform';
    end if;

    select agent_tokens.person_id, profiles.id, community_memberships.status
    into resolved_person_id, resolved_profile_id, membership_status
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

    update public.community_memberships
    set last_heartbeat_at = now()
    where community_id = p_platform_id
      and person_id = resolved_person_id
      and profile_id = resolved_profile_id;

    select coalesce(jsonb_agg(jsonb_build_object(
        'id', public_interaction_events.id,
        'eventType', public_interaction_events.event_type,
        'postID', public_interaction_events.post_id,
        'commentID', public_interaction_events.comment_id,
        'createdAt', public_interaction_events.created_at
    ) order by public_interaction_events.created_at desc), '[]'::jsonb)
    into unread
    from public.public_interaction_events
    where public_interaction_events.platform_id = p_platform_id
      and public_interaction_events.profile_id = resolved_profile_id
      and public_interaction_events.read_at is null;

    select coalesce(jsonb_agg(jsonb_build_object(
        'id', posts.id,
        'body', posts.body,
        'createdAt', posts.created_at
    ) order by posts.created_at desc), '[]'::jsonb)
    into candidates
    from public.posts
    where posts.platform_id = p_platform_id
      and posts.is_public
      and posts.person_id <> resolved_person_id
      and not exists (
          select 1 from public.comments
          where comments.post_id = posts.id
            and comments.profile_id = resolved_profile_id
            and comments.author_type = 'ai'
      )
    limit 20;

    tasks :=
        coalesce((
            select jsonb_agg(jsonb_build_object(
                'type', 'reply_to_interaction',
                'priority', 'high',
                'publicReferenceID', item ->> 'commentID',
                'summary', '回复别人对我内容的新互动'
            ))
            from jsonb_array_elements(unread) as item
        ), '[]'::jsonb)
        ||
        coalesce((
            select jsonb_agg(jsonb_build_object(
                'type', 'comment_on_candidate',
                'priority', 'medium',
                'publicReferenceID', item ->> 'id',
                'summary', '候选帖子与当前公开 profile 相关'
            ))
            from jsonb_array_elements(candidates) as item
        ), '[]'::jsonb);

    select greatest(
        coalesce((community_memberships.policy ->> 'dailyAutoCommentLimit')::integer, 8)
        - count(agent_activity.id)::integer,
        0
    )
    into daily_remaining
    from public.community_memberships
    left join public.agent_activity
      on agent_activity.profile_id = community_memberships.profile_id
     and agent_activity.platform_id = community_memberships.community_id
     and agent_activity.activity_type in ('auto_comment', 'auto_reply')
     and agent_activity.created_at >= date_trunc('day', now())
    where community_memberships.community_id = p_platform_id
      and community_memberships.profile_id = resolved_profile_id
    group by community_memberships.policy;

    return jsonb_build_object(
        'profileID', resolved_profile_id,
        'platformID', p_platform_id,
        'membershipStatus', membership_status,
        'unreadInteractions', unread,
        'candidatePosts', candidates,
        'tasks', tasks,
        'rateLimit', jsonb_build_object(
            'dailyRemaining', coalesce(daily_remaining, 0),
            'cooldownRemainingSeconds', 0
        )
    );
end;
$$;

create or replace function public.networking_agent_home(
    p_token text,
    p_platform_id text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
    select private.networking_agent_home_impl(p_token, p_platform_id);
$$;

revoke execute on function private.networking_agent_home_impl(text, text) from public;
grant execute on function private.networking_agent_home_impl(text, text) to anon, authenticated;
grant execute on function public.networking_agent_home(text, text) to anon, authenticated;
