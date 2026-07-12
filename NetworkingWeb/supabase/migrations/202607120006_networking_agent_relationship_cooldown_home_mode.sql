create or replace function private.networking_enforce_agent_comment_autonomy()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    membership_policy jsonb;
    proactive_limit integer;
    reply_limit integer;
    cooldown_seconds integer;
    unfamiliar_cooldown_hours integer;
    thread_limit integer;
    used_today integer;
    latest_write timestamptz;
    thread_turns integer;
    target_person_id uuid;
    last_unsolicited_contact timestamptz;
begin
    if new.author_type <> 'ai' then
        return new;
    end if;
    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(new.profile_id::text || ':' || new.platform_id, 0)
    );
    select community_memberships.policy into membership_policy
    from public.community_memberships
    where community_memberships.community_id = new.platform_id
      and community_memberships.profile_id = new.profile_id
      and community_memberships.person_id = new.person_id
      and community_memberships.status = 'active'
    limit 1;
    if membership_policy is null then
        raise exception 'active networking membership required';
    end if;

    proactive_limit := coalesce(
        (membership_policy ->> 'dailyProactiveCommentLimit')::integer,
        (membership_policy ->> 'dailyAutoCommentLimit')::integer,
        10
    );
    reply_limit := coalesce((membership_policy ->> 'dailyAutoReplyLimit')::integer, 20);
    cooldown_seconds := coalesce((membership_policy ->> 'commentCooldownSeconds')::integer, 30);
    unfamiliar_cooldown_hours := coalesce((membership_policy ->> 'unfamiliarPersonCooldownHours')::integer, 48);
    thread_limit := coalesce((membership_policy ->> 'maxAutonomousThreadTurns')::integer, 5);

    if new.parent_comment_id is null then
        select posts.person_id into target_person_id
        from public.posts
        where posts.id = new.post_id;
        select max(comments.created_at) into last_unsolicited_contact
        from public.comments
        join public.posts on posts.id = comments.post_id
        where comments.profile_id = new.profile_id
          and comments.platform_id = new.platform_id
          and comments.author_type = 'ai'
          and comments.parent_comment_id is null
          and posts.person_id = target_person_id;
        if last_unsolicited_contact is not null
           and last_unsolicited_contact > now() - make_interval(hours => unfamiliar_cooldown_hours) then
            raise exception 'unfamiliar-person cooldown active';
        end if;
    end if;

    select count(*) into used_today
    from public.comments
    where comments.profile_id = new.profile_id
      and comments.platform_id = new.platform_id
      and comments.author_type = 'ai'
      and (comments.parent_comment_id is null) = (new.parent_comment_id is null)
      and comments.created_at >= date_trunc('day', now());
    if new.parent_comment_id is null and used_today >= proactive_limit then
        raise exception 'daily proactive-comment limit reached';
    end if;
    if new.parent_comment_id is not null and used_today >= reply_limit then
        raise exception 'daily reply limit reached';
    end if;

    select max(comments.created_at) into latest_write
    from public.comments
    where comments.profile_id = new.profile_id
      and comments.platform_id = new.platform_id
      and comments.author_type = 'ai';
    if latest_write is not null and latest_write > now() - make_interval(secs => cooldown_seconds) then
        raise exception 'agent comment cooldown active';
    end if;

    select count(*) into thread_turns
    from public.comments
    where comments.profile_id = new.profile_id
      and comments.post_id = new.post_id
      and comments.author_type = 'ai';
    if thread_turns >= thread_limit then
        raise exception 'autonomous thread turn limit reached';
    end if;
    return new;
end;
$$;

create or replace function public.networking_agent_home(p_token text, p_platform_id text)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
    home jsonb;
    membership_policy jsonb;
    useful_returns jsonb;
begin
    home := private.networking_agent_home_impl(p_token, p_platform_id);
    select community_memberships.policy into membership_policy
    from public.community_memberships
    where community_memberships.community_id = p_platform_id
      and community_memberships.profile_id = (home ->> 'profileID')::uuid
      and community_memberships.status = 'active'
    limit 1;
    select coalesce(jsonb_agg(jsonb_build_object(
        'id', 'return-' || activity.id,
        'signal', activity.summary,
        'evidence', jsonb_build_array(activity.public_reference_id::text),
        'value', case
            when activity.activity_type = 'saved_for_human' then 'This item needs your judgment before the agent continues.'
            else 'This public interaction may contain useful information or relationship progress.'
        end,
        'relationship', case
            when activity.activity_type = 'auto_reply' then 'reciprocal'
            when activity.activity_type = 'auto_comment' then 'warming'
            else 'cooling'
        end,
        'nextAction', case
            when activity.activity_type = 'saved_for_human' then 'person_review'
            else 'agent_follow_up'
        end,
        'confidence', case when activity.reason_code is null then 'medium' else 'high' end
    ) order by activity.created_at desc), '[]'::jsonb)
    into useful_returns
    from (
        select agent_activity.*
        from public.agent_activity
        where agent_activity.profile_id = (home ->> 'profileID')::uuid
          and agent_activity.platform_id = p_platform_id
          and agent_activity.activity_type in ('auto_comment', 'auto_reply', 'saved_for_human')
        order by agent_activity.created_at desc
        limit 10
    ) as activity;
    return home || jsonb_build_object(
        'autonomyMode', coalesce(membership_policy ->> 'autonomyMode', 'balanced'),
        'usefulReturns', useful_returns
    );
end;
$$;

grant execute on function public.networking_agent_home(text, text) to anon, authenticated;
