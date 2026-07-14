create or replace function public.networking_authorize_device(
    p_person_id uuid, p_device_id text, p_display_name text,
    p_device_token_hash text, p_agent_token_hash text, p_agent_token_label text
)
returns public.networking_devices
language plpgsql
security invoker
set search_path = ''
as $$
declare
    current_user_id uuid := (select auth.uid());
    existing_device public.networking_devices;
    result public.networking_devices;
begin
    if current_user_id is null then raise exception 'networking_auth_required'; end if;
    if not exists (
        select 1 from public.people
        where people.id = p_person_id and people.user_id = current_user_id
    ) then raise exception 'networking_person_not_owned'; end if;
    if char_length(trim(p_device_id)) not between 1 and 128
       or char_length(trim(p_display_name)) not between 1 and 120
       or char_length(trim(p_agent_token_label)) not between 1 and 120
       or p_device_token_hash !~ '^[0-9a-f]{64}$'
       or p_agent_token_hash !~ '^[0-9a-f]{64}$' then
        raise exception 'networking_invalid_device';
    end if;

    perform pg_advisory_xact_lock(hashtext('networking-device'), hashtext(current_user_id::text));
    select * into existing_device from public.networking_devices
    where user_id = current_user_id and device_id = trim(p_device_id);

    if (existing_device.id is null or existing_device.revoked_at is not null)
       and (select count(*) from public.networking_devices
            where user_id = current_user_id and revoked_at is null) >= 3 then
        raise exception 'networking_device_limit_reached';
    end if;

    if existing_device.agent_token_hash is not null then
        update public.agent_tokens set revoked_at = now()
        where token_hash = existing_device.agent_token_hash and revoked_at is null
          and person_id in (select id from public.people where user_id = current_user_id);
    end if;

    insert into public.agent_tokens (person_id, label, token_hash, scope)
    values (p_person_id, trim(p_agent_token_label), p_agent_token_hash, array['profile:write']::text[]);

    if existing_device.id is not null then
        update public.networking_devices
        set display_name = trim(p_display_name), credential_hash = p_device_token_hash,
            agent_token_hash = p_agent_token_hash, last_active_at = now(), revoked_at = null
        where id = existing_device.id returning * into result;
    else
        insert into public.networking_devices (user_id, device_id, display_name, credential_hash, agent_token_hash)
        values (current_user_id, trim(p_device_id), trim(p_display_name), p_device_token_hash, p_agent_token_hash)
        returning * into result;
    end if;
    return result;
end;
$$;

revoke all on function public.networking_authorize_device(uuid, text, text, text, text, text) from public, anon;
grant execute on function public.networking_authorize_device(uuid, text, text, text, text, text) to authenticated;
