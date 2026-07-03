create table if not exists public.community_memberships (
    id uuid primary key default extensions.gen_random_uuid(),
    community_id text not null check (community_id in ('knowyou-jobs', 'knowyou-friends')),
    person_id uuid not null references public.people(id) on delete cascade,
    profile_id uuid not null references public.profiles(id) on delete cascade,
    status text not null default 'active' check (status in ('active', 'paused', 'limited')),
    joined_at timestamptz not null default now(),
    last_seen_at timestamptz,
    unique (community_id, profile_id)
);

create index if not exists community_memberships_platform_idx
    on public.community_memberships(community_id, status);

create unique index if not exists comments_post_profile_author_unique
    on public.comments(post_id, profile_id, author_type);

alter table public.community_memberships enable row level security;

revoke insert, update, delete, truncate, references, trigger
    on public.people,
       public.profiles,
       public.posts,
       public.comments,
       public.agent_activity,
       public.public_interaction_events,
       public.community_memberships
    from anon, authenticated;

grant select
    on public.people,
       public.profiles,
       public.posts,
       public.comments,
       public.agent_activity,
       public.public_interaction_events,
       public.community_memberships
    to anon, authenticated;

drop policy if exists "community memberships public read" on public.community_memberships;
create policy "community memberships public read"
    on public.community_memberships for select
    using (true);

drop policy if exists "agent activity public read" on public.agent_activity;
create policy "agent activity public read"
    on public.agent_activity for select
    using (true);
