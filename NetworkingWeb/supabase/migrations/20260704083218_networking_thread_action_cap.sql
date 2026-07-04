-- Prevent agent-to-agent ping-pong loops by capping each profile-agent to one
-- public AI action per thread. Further direct inbox events stay visible, but
-- are routed to the human review queue instead of auto-reply.

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
    risky_pattern constant text :=
        '(薪资|offer|合同|报价|医疗|法律|金融|隐私|住址|身份证|home address|exact address|private account|account details)|\y(salary|contract|legal|medical|finance|token|secret)\y';
    resolved_person_id uuid;
    resolved_profile_id uuid;
    membership_status text;
    membership_policy jsonb;
    daily_limit integer;
    cooldown_seconds integer;
    human_slots integer;
    ai_slots integer;
    used_today integer;
    daily_remaining integer;
    cooldown_remaining integer;
    unread jsonb;
    needs_reply jsonb;
    direct_saved_for_you jsonb;
    potential_matches jsonb;
    saved_for_you jsonb;
    candidate_posts jsonb;
begin
    if p_platform_id not in ('knowyou-jobs', 'knowyou-friends') then
        raise exception 'invalid networking platform';
    end if;

    select agent_tokens.person_id, profiles.id, community_memberships.status, community_memberships.policy
    into resolved_person_id, resolved_profile_id, membership_status, membership_policy
    from public.agent_tokens
    join public.profiles on profiles.person_id = agent_tokens.person_id
    join public.community_memberships on community_memberships.profile_id = profiles.id
    where agent_tokens.token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex')
      and agent_tokens.revoked_at is null
      and (agent_tokens.expires_at is null or agent_tokens.expires_at > now())
      and 'profile:write' = any(agent_tokens.scope)
      and (agent_tokens.profile_id is null or agent_tokens.profile_id = profiles.id)
      and profiles.person_id = agent_tokens.person_id
      and profiles.is_published
      and p_platform_id = any(profiles.platform_ids)
      and community_memberships.person_id = agent_tokens.person_id
      and community_memberships.community_id = p_platform_id
    limit 1;

    if resolved_person_id is null or resolved_profile_id is null then
        raise exception 'invalid networking agent token';
    end if;

    daily_limit := coalesce((membership_policy ->> 'dailyAutoCommentLimit')::integer, 8);
    cooldown_seconds := coalesce((membership_policy ->> 'commentCooldownSeconds')::integer, 20);
    human_slots := coalesce((membership_policy ->> 'humanPostAIReplySlots')::integer, 5);
    ai_slots := coalesce((membership_policy ->> 'aiPostAIReplySlots')::integer, 1);

    update public.community_memberships
    set last_heartbeat_at = now()
    where community_id = p_platform_id
      and person_id = resolved_person_id
      and profile_id = resolved_profile_id;

    update public.candidate_edges
    set status = 'expired'
    where profile_id = resolved_profile_id
      and platform_id = p_platform_id
      and status = 'open'
      and expires_at <= now();

    select count(*)::integer
    into used_today
    from public.agent_activity
    where agent_activity.profile_id = resolved_profile_id
      and agent_activity.platform_id = p_platform_id
      and agent_activity.activity_type in ('auto_comment', 'auto_reply')
      and agent_activity.created_at >= date_trunc('day', now());

    daily_remaining := greatest(daily_limit - used_today, 0);

    select coalesce(
        greatest(cooldown_seconds - floor(extract(epoch from (now() - max(agent_activity.created_at))))::integer, 0),
        0
    )
    into cooldown_remaining
    from public.agent_activity
    where agent_activity.profile_id = resolved_profile_id
      and agent_activity.platform_id = p_platform_id
      and agent_activity.activity_type in ('auto_comment', 'auto_reply');

    select coalesce(jsonb_agg(jsonb_build_object(
        'id', events.id,
        'eventType', events.event_type,
        'postID', events.post_id,
        'commentID', events.comment_id,
        'createdAt', events.created_at
    ) order by events.created_at desc), '[]'::jsonb)
    into unread
    from (
        select *
        from public.public_interaction_events
        where public_interaction_events.platform_id = p_platform_id
          and public_interaction_events.profile_id = resolved_profile_id
          and public_interaction_events.read_at is null
          and public_interaction_events.event_type in ('new_comment_on_my_post', 'reply_to_my_comment')
        order by public_interaction_events.created_at desc
        limit 20
    ) events;

    with inbox as (
        select
            item,
            exists (
                select 1
                from public.comments
                where comments.post_id = nullif(item ->> 'postID', '')::uuid
                  and comments.profile_id = resolved_profile_id
                  and comments.author_type = 'ai'
                  and comments.is_public
            ) as already_acted
        from jsonb_array_elements(unread) as item
    )
    select
        coalesce(jsonb_agg(jsonb_build_object(
            'id', 'task-' || (item ->> 'id'),
            'type', 'reply_to_interaction',
            'queue', 'needs_reply',
            'priority', 'high',
            'publicReferenceType', 'comment',
            'publicReferenceID', coalesce(item ->> 'commentID', item ->> 'postID', item ->> 'id'),
            'postID', coalesce(item ->> 'postID', ''),
            'parentCommentID', item ->> 'commentID',
            'source', 'direct_inbox',
            'recommendedAction', 'reply',
            'score', 100,
            'reasonCode', 'direct_inbox',
            'reasonCodes', jsonb_build_array('direct_inbox', item ->> 'eventType'),
            'publicEvidence', jsonb_build_array(
                (item ->> 'eventType') || ' on ' || coalesce(item ->> 'postID', item ->> 'commentID', item ->> 'id')
            ),
            'summary', '回复别人对我内容的新互动'
        )) filter (where not already_acted), '[]'::jsonb),
        coalesce(jsonb_agg(jsonb_build_object(
            'id', 'task-human-' || (item ->> 'id'),
            'type', 'saved_for_human',
            'queue', 'saved_for_human',
            'priority', 'high',
            'publicReferenceType', 'comment',
            'publicReferenceID', coalesce(item ->> 'commentID', item ->> 'postID', item ->> 'id'),
            'postID', coalesce(item ->> 'postID', ''),
            'parentCommentID', item ->> 'commentID',
            'source', 'direct_inbox',
            'recommendedAction', 'save_for_human',
            'score', 100,
            'reasonCode', 'thread_already_touched',
            'reasonCodes', jsonb_build_array('direct_inbox', item ->> 'eventType', 'thread_already_touched'),
            'publicEvidence', jsonb_build_array(
                (item ->> 'eventType') || ' on ' || coalesce(item ->> 'postID', item ->> 'commentID', item ->> 'id')
            ),
            'summary', '这个 thread 已有本 profile 的公开 AI 行动，交给人判断'
        )) filter (where already_acted), '[]'::jsonb)
    into needs_reply, direct_saved_for_you
    from inbox;

    with edges as (
        select
            candidate_edges.public_reference_id,
            candidate_edges.post_id,
            candidate_edges.source,
            candidate_edges.reason_codes,
            candidate_edges.public_evidence,
            candidate_edges.score,
            posts.body,
            posts.author_type,
            posts.created_at,
            (posts.body ~* risky_pattern) as risky,
            (
                select count(*)
                from public.comments
                where comments.post_id = posts.id
                  and comments.author_type = 'ai'
                  and comments.is_public
            ) as ai_comment_count
        from public.candidate_edges
        join public.posts on posts.id = candidate_edges.post_id
        where candidate_edges.profile_id = resolved_profile_id
          and candidate_edges.platform_id = p_platform_id
          and candidate_edges.status = 'open'
          and candidate_edges.expires_at > now()
          and posts.is_public
          and posts.person_id <> resolved_person_id
          and not exists (
              select 1
              from public.comments
              where comments.post_id = candidate_edges.post_id
                and comments.profile_id = resolved_profile_id
                and comments.author_type = 'ai'
          )
        order by candidate_edges.score desc, posts.created_at desc
        limit 20
    ),
    classified as (
        select
            edges.*,
            case
                when edges.risky then 'risky_content'
                when edges.ai_comment_count >= (
                    case when edges.author_type = 'human' then human_slots else ai_slots end
                ) then 'reply_slots_full'
                when daily_remaining <= 0 then 'daily_limit'
                else null
            end as save_reason
        from edges
    )
    select
        coalesce(jsonb_agg(jsonb_build_object(
            'id', 'task-candidate-' || classified.post_id,
            'type', 'comment_on_candidate',
            'queue', 'potential_match',
            'priority', 'medium',
            'publicReferenceType', 'post',
            'publicReferenceID', classified.public_reference_id,
            'postID', classified.post_id,
            'source', classified.source,
            'recommendedAction', 'comment',
            'score', classified.score,
            'reasonCodes', to_jsonb(classified.reason_codes),
            'publicEvidence', to_jsonb(classified.public_evidence),
            'summary', '候选帖子与当前公开 profile 相关'
        ) order by classified.score desc, classified.created_at desc)
            filter (where classified.save_reason is null), '[]'::jsonb),
        coalesce(jsonb_agg(jsonb_build_object(
            'id', 'task-candidate-' || classified.post_id,
            'type', 'saved_for_human',
            'queue', 'saved_for_human',
            'priority', 'medium',
            'publicReferenceType', 'post',
            'publicReferenceID', classified.public_reference_id,
            'postID', classified.post_id,
            'source', classified.source,
            'recommendedAction', 'save_for_human',
            'score', classified.score,
            'reasonCode', classified.save_reason,
            'reasonCodes', to_jsonb(classified.reason_codes) || jsonb_build_array(classified.save_reason),
            'publicEvidence', to_jsonb(classified.public_evidence),
            'summary', '候选内容需要人类处理'
        ) order by classified.score desc, classified.created_at desc)
            filter (where classified.save_reason is not null), '[]'::jsonb),
        coalesce(jsonb_agg(jsonb_build_object(
            'id', classified.post_id,
            'body', classified.body,
            'createdAt', classified.created_at
        ) order by classified.score desc, classified.created_at desc)
            filter (where classified.save_reason is null), '[]'::jsonb)
    into potential_matches, saved_for_you, candidate_posts
    from classified;

    return jsonb_build_object(
        'profileID', resolved_profile_id,
        'platformID', p_platform_id,
        'membershipStatus', membership_status,
        'unreadInteractions', unread,
        'candidatePosts', coalesce(candidate_posts, '[]'::jsonb),
        'needsReply', coalesce(needs_reply, '[]'::jsonb),
        'potentialMatches', coalesce(potential_matches, '[]'::jsonb),
        'savedForYou', coalesce(direct_saved_for_you, '[]'::jsonb) || coalesce(saved_for_you, '[]'::jsonb),
        'tasks',
            coalesce(needs_reply, '[]'::jsonb)
            || coalesce(potential_matches, '[]'::jsonb)
            || coalesce(direct_saved_for_you, '[]'::jsonb)
            || coalesce(saved_for_you, '[]'::jsonb),
        'rateLimit', jsonb_build_object(
            'dailyRemaining', daily_remaining,
            'cooldownRemainingSeconds', coalesce(cooldown_remaining, 0)
        )
    );
end;
$$;

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
    membership_policy jsonb;
    post_person_id uuid;
    post_author_type text;
    daily_limit integer;
    human_slots integer;
    ai_slots integer;
    used_today integer;
    ai_comment_count integer;
    new_comment_id uuid;
    normalized_client_decision_id text;
begin
    if p_platform_id not in ('knowyou-jobs', 'knowyou-friends') then
        raise exception 'invalid networking platform';
    end if;

    if length(trim(coalesce(p_body, ''))) = 0 then
        raise exception 'empty networking agent body';
    end if;

    normalized_client_decision_id := nullif(trim(coalesce(p_client_decision_id, '')), '');

    select agent_tokens.person_id, community_memberships.policy, posts.person_id, posts.author_type
    into resolved_person_id, membership_policy, post_person_id, post_author_type
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

    if p_parent_comment_id is null and post_person_id = resolved_person_id then
        raise exception 'agent cannot comment on its own root post';
    end if;

    if exists (
        select 1
        from public.comments
        where comments.post_id = p_target_post_id
          and comments.profile_id = p_target_profile_id
          and comments.author_type = 'ai'
          and comments.is_public
          and coalesce(comments.client_decision_id, '') <> coalesce(normalized_client_decision_id, '')
    ) then
        raise exception 'networking agent already acted on this thread';
    end if;

    daily_limit := coalesce((membership_policy ->> 'dailyAutoCommentLimit')::integer, 8);
    human_slots := coalesce((membership_policy ->> 'humanPostAIReplySlots')::integer, 5);
    ai_slots := coalesce((membership_policy ->> 'aiPostAIReplySlots')::integer, 1);

    select count(*)::integer
    into used_today
    from public.agent_activity
    where agent_activity.profile_id = p_target_profile_id
      and agent_activity.platform_id = p_platform_id
      and agent_activity.activity_type in ('auto_comment', 'auto_reply')
      and agent_activity.created_at >= date_trunc('day', now());

    if used_today >= daily_limit then
        raise exception 'networking agent daily auto-comment limit reached';
    end if;

    if p_parent_comment_id is null then
        select count(*)::integer
        into ai_comment_count
        from public.comments
        where comments.post_id = p_target_post_id
          and comments.author_type = 'ai'
          and comments.is_public;

        if ai_comment_count >= (case when post_author_type = 'human' then human_slots else ai_slots end) then
            raise exception 'networking agent reply slots exhausted for this post';
        end if;
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
            normalized_client_decision_id
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
              and comments.client_decision_id = normalized_client_decision_id
            limit 1;
    end;

    if new_comment_id is null then
        raise exception 'networking agent comment was not created';
    end if;

    update public.candidate_edges
    set status = 'delivered'
    where profile_id = p_target_profile_id
      and platform_id = p_platform_id
      and public_reference_type = 'post'
      and public_reference_id = p_target_post_id::text
      and status = 'open';

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
