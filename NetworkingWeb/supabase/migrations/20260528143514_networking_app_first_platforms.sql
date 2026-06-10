alter table public.profiles
    add column if not exists scenario_id text not null default 'jobs',
    add column if not exists scenario_description text not null default '',
    add column if not exists avatar_seed text not null default '',
    add column if not exists avatar_style text not null default 'initials',
    add column if not exists platform_ids text[] not null default array['knowyou-jobs']::text[];

update public.profiles
set
    scenario_id = coalesce(nullif(scenario_id, ''), 'jobs'),
    avatar_seed = coalesce(nullif(avatar_seed, ''), slug),
    avatar_style = coalesce(nullif(avatar_style, ''), 'initials'),
    platform_ids = case
        when platform_ids is null or cardinality(platform_ids) = 0 then array['knowyou-jobs']::text[]
        else platform_ids
    end;

alter table public.profiles
    drop constraint if exists profiles_avatar_style_check;
alter table public.profiles
    add constraint profiles_avatar_style_check
    check (avatar_style in ('initials', 'gradient'));

alter table public.profiles
    drop constraint if exists profiles_scenario_id_check;
alter table public.profiles
    add constraint profiles_scenario_id_check
    check (scenario_id in ('jobs', 'friends'));

alter table public.profiles
    drop constraint if exists profiles_platform_ids_known_check;
alter table public.profiles
    add constraint profiles_platform_ids_known_check
    check (
        platform_ids <@ array['knowyou-jobs', 'knowyou-friends']::text[]
        and cardinality(platform_ids) > 0
    );

alter table public.posts
    add column if not exists platform_id text not null default 'knowyou-jobs';
alter table public.comments
    add column if not exists platform_id text not null default 'knowyou-jobs';
alter table public.agent_activity
    add column if not exists platform_id text not null default 'knowyou-jobs';
alter table public.public_interaction_events
    add column if not exists platform_id text not null default 'knowyou-jobs';

alter table public.posts
    drop constraint if exists posts_platform_id_check;
alter table public.posts
    add constraint posts_platform_id_check
    check (platform_id in ('knowyou-jobs', 'knowyou-friends'));

alter table public.comments
    drop constraint if exists comments_platform_id_check;
alter table public.comments
    add constraint comments_platform_id_check
    check (platform_id in ('knowyou-jobs', 'knowyou-friends'));

alter table public.agent_activity
    drop constraint if exists agent_activity_platform_id_check;
alter table public.agent_activity
    add constraint agent_activity_platform_id_check
    check (platform_id in ('knowyou-jobs', 'knowyou-friends'));

alter table public.public_interaction_events
    drop constraint if exists public_interaction_events_platform_id_check;
alter table public.public_interaction_events
    add constraint public_interaction_events_platform_id_check
    check (platform_id in ('knowyou-jobs', 'knowyou-friends'));

create index if not exists profiles_scenario_id_idx on public.profiles(scenario_id);
create index if not exists posts_platform_created_idx on public.posts(platform_id, created_at desc);
create index if not exists comments_platform_created_idx on public.comments(platform_id, created_at desc);
create index if not exists agent_activity_platform_created_idx on public.agent_activity(platform_id, created_at desc);
create index if not exists public_interaction_events_platform_created_idx
    on public.public_interaction_events(platform_id, created_at desc);

alter policy "owners can insert posts"
    on public.posts
    with check (
        exists (
            select 1 from public.people
            where people.id = posts.person_id
              and people.user_id = (select auth.uid())
        )
        and exists (
            select 1 from public.profiles
            where profiles.id = posts.profile_id
              and profiles.person_id = posts.person_id
              and posts.platform_id = any(profiles.platform_ids)
        )
    );

alter policy "owners can update posts"
    on public.posts
    using (
        exists (
            select 1 from public.people
            where people.id = posts.person_id
              and people.user_id = (select auth.uid())
        )
    )
    with check (
        exists (
            select 1 from public.people
            where people.id = posts.person_id
              and people.user_id = (select auth.uid())
        )
        and exists (
            select 1 from public.profiles
            where profiles.id = posts.profile_id
              and profiles.person_id = posts.person_id
              and posts.platform_id = any(profiles.platform_ids)
        )
    );

alter policy "owners can insert comments"
    on public.comments
    with check (
        exists (
            select 1 from public.people
            where people.id = comments.person_id
              and people.user_id = (select auth.uid())
        )
        and exists (
            select 1 from public.profiles
            where profiles.id = comments.profile_id
              and profiles.person_id = comments.person_id
              and comments.platform_id = any(profiles.platform_ids)
        )
        and exists (
            select 1 from public.posts
            where posts.id = comments.post_id
              and posts.is_public
              and posts.platform_id = comments.platform_id
        )
    );

alter policy "owners can update comments"
    on public.comments
    using (
        exists (
            select 1 from public.people
            where people.id = comments.person_id
              and people.user_id = (select auth.uid())
        )
    )
    with check (
        exists (
            select 1 from public.people
            where people.id = comments.person_id
              and people.user_id = (select auth.uid())
        )
        and exists (
            select 1 from public.profiles
            where profiles.id = comments.profile_id
              and profiles.person_id = comments.person_id
              and comments.platform_id = any(profiles.platform_ids)
        )
        and exists (
            select 1 from public.posts
            where posts.id = comments.post_id
              and posts.platform_id = comments.platform_id
        )
    );

alter policy "owners can insert own agent activity"
    on public.agent_activity
    with check (
        exists (
            select 1 from public.people
            where people.id = agent_activity.person_id
              and people.user_id = (select auth.uid())
        )
        and (
            agent_activity.profile_id is null
            or exists (
                select 1 from public.profiles
                where profiles.id = agent_activity.profile_id
                  and profiles.person_id = agent_activity.person_id
                  and agent_activity.platform_id = any(profiles.platform_ids)
            )
        )
    );

alter policy "owners can insert public interaction events"
    on public.public_interaction_events
    with check (
        exists (
            select 1 from public.people
            where people.id = public_interaction_events.person_id
              and people.user_id = (select auth.uid())
        )
        and (
            public_interaction_events.profile_id is null
            or exists (
                select 1 from public.profiles
                where profiles.id = public_interaction_events.profile_id
                  and profiles.person_id = public_interaction_events.person_id
                  and public_interaction_events.platform_id = any(profiles.platform_ids)
            )
        )
        and (
            (
                public_interaction_events.post_id is not null
                and exists (
                    select 1 from public.posts
                    join public.profiles on profiles.id = posts.profile_id
                    where posts.id = public_interaction_events.post_id
                      and posts.is_public
                      and posts.platform_id = public_interaction_events.platform_id
                      and profiles.is_published
                )
            )
            or (
                public_interaction_events.comment_id is not null
                and exists (
                    select 1 from public.comments
                    join public.posts on posts.id = comments.post_id
                    join public.profiles on profiles.id = comments.profile_id
                    where comments.id = public_interaction_events.comment_id
                      and comments.is_public
                      and comments.platform_id = public_interaction_events.platform_id
                      and posts.is_public
                      and posts.platform_id = public_interaction_events.platform_id
                      and profiles.is_published
                )
            )
        )
    );

drop function if exists public.networking_agent_create_post(text, uuid, text);
drop function if exists public.networking_agent_create_post(text, uuid, text, text);
drop function if exists public.networking_agent_create_comment(text, uuid, uuid, text);
drop function if exists public.networking_agent_create_comment(text, uuid, uuid, text, text);
drop function if exists private.networking_agent_create_post_impl(text, uuid, text);
drop function if exists private.networking_agent_create_post_impl(text, uuid, text, text);
drop function if exists private.networking_agent_create_comment_impl(text, uuid, uuid, text);
drop function if exists private.networking_agent_create_comment_impl(text, uuid, uuid, text, text);

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
    new_post_id uuid;
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
    where agent_tokens.token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex')
      and agent_tokens.revoked_at is null
      and (agent_tokens.expires_at is null or agent_tokens.expires_at > now())
      and (agent_tokens.profile_id is null or agent_tokens.profile_id = p_target_profile_id)
      and profiles.person_id = agent_tokens.person_id
      and profiles.is_published
      and p_platform_id = any(profiles.platform_ids)
    limit 1;

    if resolved_person_id is null then
        raise exception 'invalid networking agent token';
    end if;

    insert into public.posts(person_id, profile_id, platform_id, author_type, body, is_public)
    values (resolved_person_id, p_target_profile_id, p_platform_id, 'ai', trim(coalesce(p_body, '')), true)
    returning id into new_post_id;

    update public.agent_tokens
    set last_used_at = now()
    where token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex');

    insert into public.agent_activity(person_id, profile_id, platform_id, activity_type, public_reference_type, public_reference_id, summary)
    values (resolved_person_id, p_target_profile_id, p_platform_id, 'post_created', 'post', new_post_id, left(trim(coalesce(p_body, '')), 240));

    return new_post_id;
end;
$$;

create or replace function private.networking_agent_create_comment_impl(
    p_token text,
    p_target_post_id uuid,
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
    where agent_tokens.token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex')
      and agent_tokens.revoked_at is null
      and (agent_tokens.expires_at is null or agent_tokens.expires_at > now())
      and (agent_tokens.profile_id is null or agent_tokens.profile_id = p_target_profile_id)
      and profiles.person_id = agent_tokens.person_id
      and profiles.is_published
      and p_platform_id = any(profiles.platform_ids)
      and posts.is_public
      and posts.platform_id = p_platform_id
    limit 1;

    if resolved_person_id is null then
        raise exception 'invalid networking agent token';
    end if;

    insert into public.comments(post_id, person_id, profile_id, platform_id, author_type, body, is_public)
    values (p_target_post_id, resolved_person_id, p_target_profile_id, p_platform_id, 'ai', trim(coalesce(p_body, '')), true)
    returning id into new_comment_id;

    update public.agent_tokens
    set last_used_at = now()
    where token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex');

    insert into public.agent_activity(person_id, profile_id, platform_id, activity_type, public_reference_type, public_reference_id, summary)
    values (resolved_person_id, p_target_profile_id, p_platform_id, 'comment_created', 'comment', new_comment_id, left(trim(coalesce(p_body, '')), 240));

    return new_comment_id;
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

create or replace function public.networking_agent_create_comment(
    p_token text,
    p_target_post_id uuid,
    p_target_profile_id uuid,
    p_platform_id text,
    p_body text
)
returns uuid
language sql
security invoker
set search_path = ''
as $$
    select private.networking_agent_create_comment_impl(p_token, p_target_post_id, p_target_profile_id, p_platform_id, p_body);
$$;

revoke execute on function private.networking_agent_create_post_impl(text, uuid, text, text) from public;
revoke execute on function private.networking_agent_create_comment_impl(text, uuid, uuid, text, text) from public;
grant execute on function private.networking_agent_create_post_impl(text, uuid, text, text) to anon, authenticated;
grant execute on function private.networking_agent_create_comment_impl(text, uuid, uuid, text, text) to anon, authenticated;
grant execute on function public.networking_agent_create_post(text, uuid, text, text) to anon, authenticated;
grant execute on function public.networking_agent_create_comment(text, uuid, uuid, text, text) to anon, authenticated;
