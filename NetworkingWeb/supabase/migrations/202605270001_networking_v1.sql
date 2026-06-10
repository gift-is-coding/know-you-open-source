create schema if not exists extensions;
create extension if not exists "pgcrypto" with schema extensions;

create table if not exists public.people (
    id uuid primary key default extensions.gen_random_uuid(),
    user_id uuid not null unique references auth.users(id) on delete cascade,
    display_name text not null,
    handle text not null unique,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table if not exists public.profiles (
    id uuid primary key default extensions.gen_random_uuid(),
    person_id uuid not null references public.people(id) on delete cascade,
    slug text not null,
    label text not null,
    summary text not null default '',
    body text not null default '',
    is_published boolean not null default false,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (person_id, slug)
);

do $$
begin
    create type public.networking_author_type as enum ('human', 'ai');
exception
    when duplicate_object then null;
end $$;

create table if not exists public.posts (
    id uuid primary key default extensions.gen_random_uuid(),
    person_id uuid not null references public.people(id) on delete cascade,
    profile_id uuid not null references public.profiles(id) on delete restrict,
    author_type public.networking_author_type not null,
    body text not null,
    is_public boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table if not exists public.comments (
    id uuid primary key default extensions.gen_random_uuid(),
    post_id uuid not null references public.posts(id) on delete cascade,
    person_id uuid not null references public.people(id) on delete cascade,
    profile_id uuid not null references public.profiles(id) on delete restrict,
    author_type public.networking_author_type not null,
    body text not null,
    is_public boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table if not exists public.agent_activity (
    id uuid primary key default extensions.gen_random_uuid(),
    person_id uuid not null references public.people(id) on delete cascade,
    profile_id uuid references public.profiles(id) on delete set null,
    activity_type text not null,
    public_reference_type text,
    public_reference_id uuid,
    summary text not null default '',
    created_at timestamptz not null default now()
);

create table if not exists public.agent_tokens (
    id uuid primary key default extensions.gen_random_uuid(),
    person_id uuid not null references public.people(id) on delete cascade,
    profile_id uuid references public.profiles(id) on delete cascade,
    label text not null default 'Local KnowYou agent',
    token_hash text not null unique,
    expires_at timestamptz,
    revoked_at timestamptz,
    last_used_at timestamptz,
    created_at timestamptz not null default now()
);

create table if not exists public.public_interaction_events (
    id uuid primary key default extensions.gen_random_uuid(),
    person_id uuid not null references public.people(id) on delete cascade,
    profile_id uuid references public.profiles(id) on delete set null,
    event_type text not null,
    post_id uuid references public.posts(id) on delete cascade,
    comment_id uuid references public.comments(id) on delete cascade,
    created_at timestamptz not null default now(),
    constraint public_interaction_events_single_reference check (
        (post_id is not null and comment_id is null)
        or (post_id is null and comment_id is not null)
    )
);

alter table public.people enable row level security;
alter table public.profiles enable row level security;
alter table public.posts enable row level security;
alter table public.comments enable row level security;
alter table public.agent_activity enable row level security;
alter table public.agent_tokens enable row level security;
alter table public.public_interaction_events enable row level security;

create policy "people are publicly readable"
    on public.people for select
    using (true);

create policy "people insert own row"
    on public.people for insert
    with check (auth.uid() = user_id);

create policy "people update own row"
    on public.people for update
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

create policy "published profiles are publicly readable"
    on public.profiles for select
    using (is_published);

create policy "owners can read all own profiles"
    on public.profiles for select
    using (
        exists (
            select 1 from public.people
            where people.id = profiles.person_id
              and people.user_id = auth.uid()
        )
    );

create policy "owners can insert profiles"
    on public.profiles for insert
    with check (
        exists (
            select 1 from public.people
            where people.id = profiles.person_id
              and people.user_id = auth.uid()
        )
    );

create policy "owners can update profiles"
    on public.profiles for update
    using (
        exists (
            select 1 from public.people
            where people.id = profiles.person_id
              and people.user_id = auth.uid()
        )
    )
    with check (
        exists (
            select 1 from public.people
            where people.id = profiles.person_id
              and people.user_id = auth.uid()
        )
    );

create policy "public posts are publicly readable"
    on public.posts for select
    using (
        is_public
        and exists (
            select 1 from public.profiles
            where profiles.id = posts.profile_id
              and profiles.person_id = posts.person_id
              and profiles.is_published
        )
    );

create policy "owners can insert posts"
    on public.posts for insert
    with check (
        exists (
            select 1 from public.people
            where people.id = posts.person_id
              and people.user_id = auth.uid()
        )
        and exists (
            select 1 from public.profiles
            where profiles.id = posts.profile_id
              and profiles.person_id = posts.person_id
        )
    );

create policy "owners can update posts"
    on public.posts for update
    using (
        exists (
            select 1 from public.people
            where people.id = posts.person_id
              and people.user_id = auth.uid()
        )
    )
    with check (
        exists (
            select 1 from public.people
            where people.id = posts.person_id
              and people.user_id = auth.uid()
        )
        and exists (
            select 1 from public.profiles
            where profiles.id = posts.profile_id
              and profiles.person_id = posts.person_id
        )
    );

create policy "public comments are publicly readable"
    on public.comments for select
    using (
        is_public
        and exists (
            select 1 from public.posts
            join public.profiles on profiles.id = posts.profile_id
            where posts.id = comments.post_id
              and posts.is_public
              and profiles.is_published
        )
        and exists (
            select 1 from public.profiles
            where profiles.id = comments.profile_id
              and profiles.person_id = comments.person_id
              and profiles.is_published
        )
    );

create policy "owners can insert comments"
    on public.comments for insert
    with check (
        exists (
            select 1 from public.people
            where people.id = comments.person_id
              and people.user_id = auth.uid()
        )
        and exists (
            select 1 from public.profiles
            where profiles.id = comments.profile_id
              and profiles.person_id = comments.person_id
        )
        and exists (
            select 1 from public.posts
            where posts.id = comments.post_id
              and posts.is_public
        )
    );

create policy "owners can update comments"
    on public.comments for update
    using (
        exists (
            select 1 from public.people
            where people.id = comments.person_id
              and people.user_id = auth.uid()
        )
    )
    with check (
        exists (
            select 1 from public.people
            where people.id = comments.person_id
              and people.user_id = auth.uid()
        )
        and exists (
            select 1 from public.profiles
            where profiles.id = comments.profile_id
              and profiles.person_id = comments.person_id
        )
    );

create policy "owners can read own agent activity"
    on public.agent_activity for select
    using (
        exists (
            select 1 from public.people
            where people.id = agent_activity.person_id
              and people.user_id = auth.uid()
        )
    );

create policy "owners can insert own agent activity"
    on public.agent_activity for insert
    with check (
        exists (
            select 1 from public.people
            where people.id = agent_activity.person_id
              and people.user_id = auth.uid()
        )
        and (
            agent_activity.profile_id is null
            or exists (
                select 1 from public.profiles
                where profiles.id = agent_activity.profile_id
                  and profiles.person_id = agent_activity.person_id
            )
        )
    );

create policy "owners can read own agent tokens"
    on public.agent_tokens for select
    using (
        exists (
            select 1 from public.people
            where people.id = agent_tokens.person_id
              and people.user_id = auth.uid()
        )
    );

create policy "owners can insert own agent tokens"
    on public.agent_tokens for insert
    with check (
        exists (
            select 1 from public.people
            where people.id = agent_tokens.person_id
              and people.user_id = auth.uid()
        )
        and (
            agent_tokens.profile_id is null
            or exists (
                select 1 from public.profiles
                where profiles.id = agent_tokens.profile_id
                  and profiles.person_id = agent_tokens.person_id
            )
        )
    );

create policy "owners can revoke own agent tokens"
    on public.agent_tokens for update
    using (
        exists (
            select 1 from public.people
            where people.id = agent_tokens.person_id
              and people.user_id = auth.uid()
        )
    )
    with check (
        exists (
            select 1 from public.people
            where people.id = agent_tokens.person_id
              and people.user_id = auth.uid()
        )
    );

create policy "public interaction events are publicly readable"
    on public.public_interaction_events for select
    using (true);

create policy "owners can insert public interaction events"
    on public.public_interaction_events for insert
    with check (
        exists (
            select 1 from public.people
            where people.id = public_interaction_events.person_id
              and people.user_id = auth.uid()
        )
        and (
            public_interaction_events.profile_id is null
            or exists (
                select 1 from public.profiles
                where profiles.id = public_interaction_events.profile_id
                  and profiles.person_id = public_interaction_events.person_id
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
                      and posts.is_public
                      and profiles.is_published
                )
            )
        )
    );

create index if not exists people_user_id_idx on public.people(user_id);
create index if not exists profiles_person_id_idx on public.profiles(person_id);
create index if not exists posts_person_profile_created_idx on public.posts(person_id, profile_id, created_at desc);
create index if not exists comments_post_created_idx on public.comments(post_id, created_at desc);
create index if not exists comments_person_profile_created_idx on public.comments(person_id, profile_id, created_at desc);
create index if not exists agent_activity_person_created_idx on public.agent_activity(person_id, created_at desc);
create index if not exists agent_tokens_person_profile_idx on public.agent_tokens(person_id, profile_id);
create index if not exists public_interaction_events_person_created_idx
    on public.public_interaction_events(person_id, created_at desc);

create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to anon, authenticated;

create or replace function private.networking_agent_create_post_impl(
    p_token text,
    p_target_profile_id uuid,
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
    limit 1;

    if resolved_person_id is null then
        raise exception 'invalid networking agent token';
    end if;

    insert into public.posts(person_id, profile_id, author_type, body, is_public)
    values (resolved_person_id, p_target_profile_id, 'ai', trim(coalesce(p_body, '')), true)
    returning id into new_post_id;

    update public.agent_tokens
    set last_used_at = now()
    where token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex');

    insert into public.agent_activity(person_id, profile_id, activity_type, public_reference_type, public_reference_id, summary)
    values (resolved_person_id, p_target_profile_id, 'post_created', 'post', new_post_id, left(trim(coalesce(p_body, '')), 240));

    return new_post_id;
end;
$$;

create or replace function private.networking_agent_create_comment_impl(
    p_token text,
    p_target_post_id uuid,
    p_target_profile_id uuid,
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
      and posts.is_public
    limit 1;

    if resolved_person_id is null then
        raise exception 'invalid networking agent token';
    end if;

    insert into public.comments(post_id, person_id, profile_id, author_type, body, is_public)
    values (p_target_post_id, resolved_person_id, p_target_profile_id, 'ai', trim(coalesce(p_body, '')), true)
    returning id into new_comment_id;

    update public.agent_tokens
    set last_used_at = now()
    where token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex');

    insert into public.agent_activity(person_id, profile_id, activity_type, public_reference_type, public_reference_id, summary)
    values (resolved_person_id, p_target_profile_id, 'comment_created', 'comment', new_comment_id, left(trim(coalesce(p_body, '')), 240));

    return new_comment_id;
end;
$$;

create or replace function public.networking_agent_create_post(
    p_token text,
    p_target_profile_id uuid,
    p_body text
)
returns uuid
language sql
security invoker
set search_path = ''
as $$
    select private.networking_agent_create_post_impl(p_token, p_target_profile_id, p_body);
$$;

create or replace function public.networking_agent_create_comment(
    p_token text,
    p_target_post_id uuid,
    p_target_profile_id uuid,
    p_body text
)
returns uuid
language sql
security invoker
set search_path = ''
as $$
    select private.networking_agent_create_comment_impl(p_token, p_target_post_id, p_target_profile_id, p_body);
$$;

revoke execute on function private.networking_agent_create_post_impl(text, uuid, text) from public;
revoke execute on function private.networking_agent_create_comment_impl(text, uuid, uuid, text) from public;
grant execute on function private.networking_agent_create_post_impl(text, uuid, text) to anon, authenticated;
grant execute on function private.networking_agent_create_comment_impl(text, uuid, uuid, text) to anon, authenticated;
grant execute on function public.networking_agent_create_post(text, uuid, text) to anon, authenticated;
grant execute on function public.networking_agent_create_comment(text, uuid, uuid, text) to anon, authenticated;
