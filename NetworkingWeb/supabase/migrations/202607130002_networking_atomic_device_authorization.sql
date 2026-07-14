create unique index if not exists networking_devices_owner_agent_token_unique
    on public.networking_devices (user_id, agent_token_hash)
    where agent_token_hash is not null;

drop function if exists public.networking_register_device(text, text, text, text);

create or replace function public.networking_authorize_device(
    p_person_id uuid,
    p_device_id text,
    p_display_name text,
    p_device_token_hash text,
    p_agent_token_hash text,
    p_agent_token_label text
)
returns public.networking_devices
language plpgsql
security invoker
set search_path = ''
as $$
declare
    current_user_id uuid := (select auth.uid());
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
    if exists (
        select 1 from public.networking_devices
        where user_id = current_user_id and device_id = trim(p_device_id)
    ) then
        raise exception 'networking_device_already_authorized';
    end if;
    if (select count(*) from public.networking_devices
        where user_id = current_user_id and revoked_at is null) >= 3 then
        raise exception 'networking_device_limit_reached';
    end if;

    insert into public.agent_tokens (person_id, label, token_hash, scope)
    values (p_person_id, trim(p_agent_token_label), p_agent_token_hash, array['profile:write']::text[]);

    insert into public.networking_devices (user_id, device_id, display_name, credential_hash, agent_token_hash)
    values (current_user_id, trim(p_device_id), trim(p_display_name), p_device_token_hash, p_agent_token_hash)
    returning * into result;
    return result;
end;
$$;

revoke all on function public.networking_authorize_device(uuid, text, text, text, text, text) from public, anon;
grant execute on function public.networking_authorize_device(uuid, text, text, text, text, text) to authenticated;
