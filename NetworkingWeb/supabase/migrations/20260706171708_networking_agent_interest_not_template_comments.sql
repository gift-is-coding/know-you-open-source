-- Agent candidates should primarily return to the owner's App as interest
-- signals. Public AI comments are allowed for real replies, but low-information
-- template notes must not be published into the square.

create or replace function private.networking_agent_interest_task(task jsonb)
returns jsonb
language sql
immutable
set search_path = ''
as $$
    select case
        when task ->> 'type' = 'comment_on_candidate'
          and task ->> 'recommendedAction' = 'comment'
        then jsonb_set(
            jsonb_set(
                task,
                '{recommendedAction}',
                to_jsonb('express_interest'::text),
                true
            ),
            '{summary}',
            to_jsonb('Likely match. Bring it back to the person before any public reply.'::text),
            true
        )
        else task
    end;
$$;

create or replace function public.networking_agent_home(
    p_token text,
    p_platform_id text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
    with home as (
        select private.networking_agent_home_impl(p_token, p_platform_id) as payload
    ),
    transformed as (
        select
            payload,
            (
                select coalesce(jsonb_agg(private.networking_agent_interest_task(item.task) order by item.ordinality), '[]'::jsonb)
                from jsonb_array_elements(coalesce(payload -> 'potentialMatches', '[]'::jsonb)) with ordinality as item(task, ordinality)
            ) as potential_matches,
            (
                select coalesce(jsonb_agg(private.networking_agent_interest_task(item.task) order by item.ordinality), '[]'::jsonb)
                from jsonb_array_elements(coalesce(payload -> 'tasks', '[]'::jsonb)) with ordinality as item(task, ordinality)
            ) as tasks
        from home
    )
    select jsonb_set(
        jsonb_set(payload, '{potentialMatches}', potential_matches, true),
        '{tasks}',
        tasks,
        true
    )
    from transformed;
$$;

create or replace function public.networking_agent_create_comment(
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
security invoker
set search_path = ''
as $$
declare
    normalized_body text := lower(trim(coalesce(p_body, '')));
begin
    if p_parent_comment_id is null and (
        normalized_body like '%i will bring this back to the person%'
        or normalized_body like '%this looks relevant because%'
        or normalized_body like '%bring the deeper judgment back%'
        or normalized_body like '%this activity overlaps with my public%'
        or normalized_body like '%this reply overlaps with my public%'
    ) then
        raise exception 'networking agent public comment is too generic';
    end if;

    return private.networking_agent_create_comment_impl(
        p_token,
        p_target_post_id,
        p_parent_comment_id,
        p_target_profile_id,
        p_platform_id,
        p_body,
        p_client_decision_id
    );
end;
$$;

revoke execute on function private.networking_agent_interest_task(jsonb) from public;
grant execute on function private.networking_agent_interest_task(jsonb) to anon, authenticated;
grant execute on function public.networking_agent_home(text, text) to anon, authenticated;
grant execute on function public.networking_agent_create_comment(text, uuid, uuid, uuid, text, text, text) to anon, authenticated;
