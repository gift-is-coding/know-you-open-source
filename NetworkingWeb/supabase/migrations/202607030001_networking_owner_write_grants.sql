-- 20260612154500 revoked all DML from anon/authenticated to force agent writes
-- through security-definer RPCs, but that also cut off the authenticated owner
-- paths the web app uses directly (saveProfile, human posts/comments, membership
-- activation, App token registration). Restore table-level grants for
-- authenticated only; RLS policies still gate row access. anon stays read-only.

grant insert, update on public.people to authenticated;
grant insert, update on public.profiles to authenticated;
grant insert, update on public.posts to authenticated;
grant insert, update on public.comments to authenticated;
grant insert, update on public.community_memberships to authenticated;
grant insert, update on public.agent_tokens to authenticated;
grant select on public.agent_tokens to authenticated;

-- community_memberships had RLS enabled with only a public-read policy, so even
-- with grants restored the owner upsert in /api/community-memberships would be
-- rejected. Owners may only bind communities to profiles they own.

drop policy if exists "owners can insert community memberships" on public.community_memberships;
create policy "owners can insert community memberships"
    on public.community_memberships for insert
    with check (
        exists (
            select 1
            from public.people
            join public.profiles on profiles.person_id = people.id
            where people.user_id = (select auth.uid())
              and people.id = community_memberships.person_id
              and profiles.id = community_memberships.profile_id
        )
    );

drop policy if exists "owners can update community memberships" on public.community_memberships;
create policy "owners can update community memberships"
    on public.community_memberships for update
    using (
        exists (
            select 1 from public.people
            where people.id = community_memberships.person_id
              and people.user_id = (select auth.uid())
        )
    )
    with check (
        exists (
            select 1
            from public.people
            join public.profiles on profiles.person_id = people.id
            where people.user_id = (select auth.uid())
              and people.id = community_memberships.person_id
              and profiles.id = community_memberships.profile_id
        )
    );
