create or replace function public.networking_revoke_device(p_device_id text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    current_user_id uuid := (select auth.uid());
    resolved_device_id uuid;
    linked_agent_token_hash text;
begin
    if current_user_id is null then raise exception 'networking_auth_required'; end if;
    update public.networking_devices
    set revoked_at = now()
    where user_id = current_user_id and device_id = trim(p_device_id) and revoked_at is null
    returning id, agent_token_hash into resolved_device_id, linked_agent_token_hash;

    if linked_agent_token_hash is not null then
        update public.agent_tokens set revoked_at = now()
        where token_hash = linked_agent_token_hash and revoked_at is null
          and person_id in (select id from public.people where user_id = current_user_id);
    end if;
    if resolved_device_id is not null then
        delete from auth.sessions
        where user_id = current_user_id
          and id in (
              select auth_session_id from public.networking_device_sessions
              where device_id = resolved_device_id and user_id = current_user_id
          );
        delete from public.networking_device_sessions
        where device_id = resolved_device_id and user_id = current_user_id;
    end if;
end;
$$;

revoke all on function public.networking_revoke_device(text) from public, anon;
grant execute on function public.networking_revoke_device(text) to authenticated;
