create or replace function private.networking_agent_create_comment_impl(
    p_token text,
    p_target_post_id uuid,
    p_parent_comment_id uuid,
    p_target_profile_id uuid,
    p_platform_id text,
    p_body text,
    p_client_decision_id text
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
    join public.community_memberships on community_memberships.profile_id = p_target_profile_id
    where agent_tokens.token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex')
      and agent_tokens.revoked_at is null
      and (agent_tokens.expires_at is null or agent_tokens.expires_at > now())
      and 'profile:write' = any(agent_tokens.scope)
      and (agent_tokens.profile_id is null or agent_tokens.profile_id = p_target_profile_id)
      and profiles.person_id = agent_tokens.person_id
      and profiles.is_published
      and p_platform_id = any(profiles.platform_ids)
      and posts.is_public
      and posts.platform_id = p_platform_id
      and community_memberships.person_id = agent_tokens.person_id
      and community_memberships.community_id = p_platform_id
      and community_memberships.status = 'active'
      and (
          p_parent_comment_id is null
          or exists (
              select 1 from public.comments
              where comments.id = p_parent_comment_id
                and comments.post_id = p_target_post_id
                and comments.platform_id = p_platform_id
                and comments.is_public
          )
      )
    limit 1;

    if resolved_person_id is null then
        raise exception 'invalid networking agent token';
    end if;

    begin
        insert into public.comments(
            post_id,
            parent_comment_id,
            person_id,
            profile_id,
            platform_id,
            author_type,
            body,
            is_public,
            client_decision_id
        )
        values (
            p_target_post_id,
            p_parent_comment_id,
            resolved_person_id,
            p_target_profile_id,
            p_platform_id,
            'ai',
            trim(coalesce(p_body, '')),
            true,
            nullif(trim(coalesce(p_client_decision_id, '')), '')
        )
        returning id into new_comment_id;
    exception
        when unique_violation then
            select comments.id into new_comment_id
            from public.comments
            where comments.profile_id = p_target_profile_id
              and comments.post_id = p_target_post_id
              and coalesce(comments.parent_comment_id, '00000000-0000-0000-0000-000000000000'::uuid)
                  = coalesce(p_parent_comment_id, '00000000-0000-0000-0000-000000000000'::uuid)
              and comments.client_decision_id = nullif(trim(coalesce(p_client_decision_id, '')), '')
            limit 1;
    end;

    if new_comment_id is null then
        raise exception 'networking agent comment was not created';
    end if;

    update public.agent_tokens
    set last_used_at = now()
    where token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex');

    update public.community_memberships
    set last_heartbeat_at = now()
    where community_id = p_platform_id
      and profile_id = p_target_profile_id
      and person_id = resolved_person_id;

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
        case when p_parent_comment_id is null then 'auto_comment' else 'auto_reply' end,
        'comment',
        new_comment_id,
        left(trim(coalesce(p_body, '')), 240),
        jsonb_build_object('clientDecisionID', p_client_decision_id)
    );

    return new_comment_id;
end;
$$;

grant execute on function private.networking_agent_create_comment_impl(text, uuid, uuid, uuid, text, text, text) to anon, authenticated;
