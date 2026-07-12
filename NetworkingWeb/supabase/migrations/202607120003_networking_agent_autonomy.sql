-- Expand profile-agent autonomy while keeping hard write limits on the server.

alter table public.community_memberships
    alter column policy set default '{
        "autonomyMode": "balanced",
        "autoPost": true,
        "autoComment": true,
        "autoReply": true,
        "dailyAutoPostLimit": 2,
        "dailyProactiveCommentLimit": 10,
        "dailyAutoReplyLimit": 20,
        "heartbeatMinMinutes": 120,
        "heartbeatMaxMinutes": 180,
        "maxAutonomousThreadTurns": 5,
        "unfamiliarPersonCooldownHours": 48,
        "commentCooldownSeconds": 30,
        "riskyContentAction": "save_for_human"
    }'::jsonb;

update public.community_memberships
set policy = '{
        "autonomyMode": "balanced",
        "autoPost": true,
        "autoComment": true,
        "autoReply": true,
        "dailyAutoPostLimit": 2,
        "dailyProactiveCommentLimit": 10,
        "dailyAutoReplyLimit": 20,
        "heartbeatMinMinutes": 120,
        "heartbeatMaxMinutes": 180,
        "maxAutonomousThreadTurns": 5,
        "unfamiliarPersonCooldownHours": 48,
        "commentCooldownSeconds": 30,
        "riskyContentAction": "save_for_human"
    }'::jsonb || jsonb_strip_nulls(policy);

alter table public.community_memberships
    drop constraint if exists community_memberships_policy_default;
alter table public.community_memberships
    add constraint community_memberships_policy_default check (
        policy ? 'autonomyMode'
        and policy ? 'autoComment'
        and (policy ? 'dailyAutoCommentLimit' or policy ? 'dailyProactiveCommentLimit')
        and policy ? 'commentCooldownSeconds'
        and policy ? 'riskyContentAction'
    );

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

drop trigger if exists networking_agent_comment_autonomy_guard on public.comments;
create trigger networking_agent_comment_autonomy_guard
before insert on public.comments
for each row execute function private.networking_enforce_agent_comment_autonomy();

create or replace function private.networking_enforce_agent_post_autonomy()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    membership_policy jsonb;
    daily_limit integer;
    used_today integer;
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
    daily_limit := coalesce((membership_policy ->> 'dailyAutoPostLimit')::integer, 2);

    select count(*) into used_today
    from public.posts
    where posts.profile_id = new.profile_id
      and posts.platform_id = new.platform_id
      and posts.author_type = 'ai'
      and posts.created_at >= date_trunc('day', now());
    if used_today >= daily_limit then
        raise exception 'daily auto-post limit reached';
    end if;
    return new;
end;
$$;

drop trigger if exists networking_agent_post_autonomy_guard on public.posts;
create trigger networking_agent_post_autonomy_guard
before insert on public.posts
for each row execute function private.networking_enforce_agent_post_autonomy();

revoke execute on function private.networking_enforce_agent_comment_autonomy() from public;
revoke execute on function private.networking_enforce_agent_post_autonomy() from public;

create or replace function public.networking_update_autonomy_mode(
    p_profile_id uuid,
    p_platform_id text,
    p_mode text
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
    mode_policy jsonb;
begin
    if p_mode not in ('conservative', 'balanced', 'active') then
        raise exception 'invalid networking autonomy mode';
    end if;
    mode_policy := case
        when p_mode = 'conservative' then '{
            "autonomyMode":"conservative","dailyAutoPostLimit":1,
            "dailyProactiveCommentLimit":4,"dailyAutoReplyLimit":8,
            "heartbeatMinMinutes":240,"heartbeatMaxMinutes":360,
            "maxAutonomousThreadTurns":3,"unfamiliarPersonCooldownHours":72,
            "commentCooldownSeconds":45
        }'::jsonb
        when p_mode = 'active' then '{
            "autonomyMode":"active","dailyAutoPostLimit":4,
            "dailyProactiveCommentLimit":20,"dailyAutoReplyLimit":40,
            "heartbeatMinMinutes":60,"heartbeatMaxMinutes":120,
            "maxAutonomousThreadTurns":8,"unfamiliarPersonCooldownHours":24,
            "commentCooldownSeconds":20
        }'::jsonb
        else '{
            "autonomyMode":"balanced","dailyAutoPostLimit":2,
            "dailyProactiveCommentLimit":10,"dailyAutoReplyLimit":20,
            "heartbeatMinMinutes":120,"heartbeatMaxMinutes":180,
            "maxAutonomousThreadTurns":5,"unfamiliarPersonCooldownHours":48,
            "commentCooldownSeconds":30
        }'::jsonb
    end;

    update public.community_memberships
    set policy = policy || mode_policy
    where community_id = p_platform_id
      and profile_id = p_profile_id
      and person_id in (
          select people.id from public.people
          where people.user_id = auth.uid()
      );
    if not found then
        raise exception 'networking membership not found';
    end if;
end;
$$;

revoke execute on function public.networking_update_autonomy_mode(uuid, text, text) from public, anon;
grant execute on function public.networking_update_autonomy_mode(uuid, text, text) to authenticated;
