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
