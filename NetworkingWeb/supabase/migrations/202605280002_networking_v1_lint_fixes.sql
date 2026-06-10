create index if not exists posts_profile_id_idx on public.posts(profile_id);
create index if not exists comments_profile_id_idx on public.comments(profile_id);
create index if not exists agent_activity_profile_id_idx on public.agent_activity(profile_id);
create index if not exists agent_tokens_profile_id_idx on public.agent_tokens(profile_id);
create index if not exists public_interaction_events_profile_id_idx
    on public.public_interaction_events(profile_id);
create index if not exists public_interaction_events_post_id_idx
    on public.public_interaction_events(post_id);
create index if not exists public_interaction_events_comment_id_idx
    on public.public_interaction_events(comment_id);

alter policy "people insert own row"
    on public.people
    with check ((select auth.uid()) = user_id);

alter policy "people update own row"
    on public.people
    using ((select auth.uid()) = user_id)
    with check ((select auth.uid()) = user_id);

drop policy if exists "published profiles are publicly readable" on public.profiles;
drop policy if exists "owners can read all own profiles" on public.profiles;

create policy "profiles are readable when published or owned"
    on public.profiles for select
    using (
        is_published
        or exists (
            select 1 from public.people
            where people.id = profiles.person_id
              and people.user_id = (select auth.uid())
        )
    );

alter policy "owners can insert profiles"
    on public.profiles
    with check (
        exists (
            select 1 from public.people
            where people.id = profiles.person_id
              and people.user_id = (select auth.uid())
        )
    );

alter policy "owners can update profiles"
    on public.profiles
    using (
        exists (
            select 1 from public.people
            where people.id = profiles.person_id
              and people.user_id = (select auth.uid())
        )
    )
    with check (
        exists (
            select 1 from public.people
            where people.id = profiles.person_id
              and people.user_id = (select auth.uid())
        )
    );

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
        )
        and exists (
            select 1 from public.posts
            where posts.id = comments.post_id
              and posts.is_public
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
        )
    );

alter policy "owners can read own agent activity"
    on public.agent_activity
    using (
        exists (
            select 1 from public.people
            where people.id = agent_activity.person_id
              and people.user_id = (select auth.uid())
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
            )
        )
    );

alter policy "owners can read own agent tokens"
    on public.agent_tokens
    using (
        exists (
            select 1 from public.people
            where people.id = agent_tokens.person_id
              and people.user_id = (select auth.uid())
        )
    );

alter policy "owners can insert own agent tokens"
    on public.agent_tokens
    with check (
        exists (
            select 1 from public.people
            where people.id = agent_tokens.person_id
              and people.user_id = (select auth.uid())
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

alter policy "owners can revoke own agent tokens"
    on public.agent_tokens
    using (
        exists (
            select 1 from public.people
            where people.id = agent_tokens.person_id
              and people.user_id = (select auth.uid())
        )
    )
    with check (
        exists (
            select 1 from public.people
            where people.id = agent_tokens.person_id
              and people.user_id = (select auth.uid())
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
