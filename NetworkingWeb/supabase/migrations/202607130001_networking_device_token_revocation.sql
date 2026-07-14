alter table public.networking_devices
    add column if not exists agent_token_hash text
    constraint networking_devices_agent_token_hash_format
    check (agent_token_hash is null or agent_token_hash ~ '^[0-9a-f]{64}$');

drop function if exists public.networking_register_device(text, text, text);

create function public.networking_register_device(
    p_device_id text,
    p_display_name text,
    p_token_hash text,
    p_agent_token_hash text
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
    if current_user_id is null then
        raise exception 'networking_auth_required';
    end if;
    if char_length(trim(p_device_id)) not between 1 and 128
       or char_length(trim(p_display_name)) not between 1 and 120
       or p_token_hash !~ '^[0-9a-f]{64}$'
       or p_agent_token_hash !~ '^[0-9a-f]{64}$' then
        raise exception 'networking_invalid_device';
    end if;
    if not exists (
        select 1 from public.agent_tokens
        join public.people on people.id = agent_tokens.person_id
        where people.user_id = current_user_id
          and agent_tokens.token_hash = p_agent_token_hash
          and agent_tokens.revoked_at is null
    ) then
        raise exception 'networking_agent_token_not_owned';
    end if;

    perform pg_advisory_xact_lock(hashtextextended(current_user_id::text, 0));

    select * into result
    from public.networking_devices
    where user_id = current_user_id and device_id = trim(p_device_id);

    if found then
        if result.revoked_at is null then
            raise exception 'networking_device_already_registered';
        end if;
        if (select count(*) from public.networking_devices
            where user_id = current_user_id and revoked_at is null) >= 3 then
            raise exception 'networking_device_limit_reached';
        end if;
        update public.networking_devices
        set display_name = trim(p_display_name), credential_hash = p_token_hash,
            agent_token_hash = p_agent_token_hash, last_active_at = now(), revoked_at = null
        where id = result.id returning * into result;
        return result;
    end if;

    if (select count(*) from public.networking_devices
        where user_id = current_user_id and revoked_at is null) >= 3 then
        raise exception 'networking_device_limit_reached';
    end if;

    insert into public.networking_devices (user_id, device_id, display_name, credential_hash, agent_token_hash)
    values (current_user_id, trim(p_device_id), trim(p_display_name), p_token_hash, p_agent_token_hash)
    returning * into result;
    return result;
end;
$$;

create or replace function public.networking_revoke_device(p_device_id text)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
    current_user_id uuid := (select auth.uid());
    linked_agent_token_hash text;
begin
    if current_user_id is null then
        raise exception 'networking_auth_required';
    end if;
    update public.networking_devices
    set revoked_at = now()
    where user_id = current_user_id and device_id = p_device_id and revoked_at is null
    returning agent_token_hash into linked_agent_token_hash;

    if linked_agent_token_hash is not null then
        update public.agent_tokens
        set revoked_at = now()
        where token_hash = linked_agent_token_hash and revoked_at is null
          and person_id in (select id from public.people where user_id = current_user_id);
    end if;
end;
$$;

create or replace function public.networking_list_devices()
returns setof public.networking_devices
language sql
security invoker
set search_path = ''
stable
as $$
    select * from public.networking_devices
    where user_id = (select auth.uid()) and revoked_at is null
    order by created_at desc;
$$;

revoke all on function public.networking_register_device(text, text, text, text) from public, anon;
grant execute on function public.networking_register_device(text, text, text, text) to authenticated;
