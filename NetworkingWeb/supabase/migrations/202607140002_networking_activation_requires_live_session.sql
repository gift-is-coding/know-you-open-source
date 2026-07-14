create or replace function public.networking_begin_activation(
    p_display_name text,
    p_handle text,
    p_device_id text,
    p_device_display_name text,
    p_device_token_hash text,
    p_agent_token_hash text,
    p_agent_token_label text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    current_user_id uuid := (select auth.uid());
    current_session_id uuid := nullif(auth.jwt() ->> 'session_id', '')::uuid;
    result_person_id uuid;
begin
    if current_user_id is null or current_session_id is null or not exists (
        select 1 from auth.sessions
        where sessions.id = current_session_id and sessions.user_id = current_user_id
    ) then
        raise exception 'networking_auth_required';
    end if;
    if char_length(trim(p_display_name)) not between 1 and 120
       or char_length(trim(p_handle)) not between 1 and 80 then
        raise exception 'networking_invalid_person';
    end if;

    insert into public.people (user_id, display_name, handle)
    values (current_user_id, trim(p_display_name), trim(p_handle))
    on conflict (user_id) do update
    set display_name = excluded.display_name,
        handle = excluded.handle,
        updated_at = now()
    returning id into result_person_id;

    perform public.networking_authorize_device(
        result_person_id,
        p_device_id,
        p_device_display_name,
        p_device_token_hash,
        p_agent_token_hash,
        p_agent_token_label
    );

    return result_person_id;
end;
$$;

revoke all on function public.networking_begin_activation(text, text, text, text, text, text, text)
    from public, anon;
grant execute on function public.networking_begin_activation(text, text, text, text, text, text, text)
    to authenticated;
