create table public.networking_devices (
    id uuid primary key default extensions.gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    device_id text not null,
    display_name text not null,
    credential_hash text not null unique,
    last_active_at timestamptz not null default now(),
    revoked_at timestamptz,
    created_at timestamptz not null default now(),
    constraint networking_devices_device_id_length check (char_length(device_id) between 1 and 128),
    constraint networking_devices_display_name_length check (char_length(display_name) between 1 and 120),
    constraint networking_devices_credential_hash_format check (credential_hash ~ '^[0-9a-f]{64}$'),
    unique (user_id, device_id)
);

alter table public.networking_devices enable row level security;

create policy "owners can read networking devices"
    on public.networking_devices for select
    to authenticated
    using ((select auth.uid()) = user_id);

create policy "owners can insert networking devices"
    on public.networking_devices for insert
    to authenticated
    with check ((select auth.uid()) = user_id);

create policy "owners can update networking devices"
    on public.networking_devices for update
    to authenticated
    using ((select auth.uid()) = user_id)
    with check ((select auth.uid()) = user_id);

grant select, insert, update on public.networking_devices to authenticated;

create or replace function public.networking_register_device(
    p_device_id text,
    p_display_name text,
    p_token_hash text
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
       or p_token_hash !~ '^[0-9a-f]{64}$' then
        raise exception 'networking_invalid_device';
    end if;

    perform pg_advisory_xact_lock(hashtextextended(current_user_id::text, 0));

    select * into result
    from public.networking_devices
    where user_id = current_user_id
      and device_id = trim(p_device_id);

    if found then
        if result.revoked_at is null then
            raise exception 'networking_device_already_registered';
        end if;
        if (select count(*) from public.networking_devices
            where user_id = current_user_id and revoked_at is null) >= 3 then
            raise exception 'networking_device_limit_reached';
        end if;
        update public.networking_devices
        set display_name = trim(p_display_name),
            credential_hash = p_token_hash,
            last_active_at = now(),
            revoked_at = null
        where id = result.id
        returning * into result;
        return result;
    end if;

    if (select count(*) from public.networking_devices
        where user_id = current_user_id and revoked_at is null) >= 3 then
        raise exception 'networking_device_limit_reached';
    end if;

    insert into public.networking_devices (user_id, device_id, display_name, credential_hash)
    values (current_user_id, trim(p_device_id), trim(p_display_name), p_token_hash)
    returning * into result;
    return result;
end;
$$;

create or replace function public.networking_list_devices()
returns setof public.networking_devices
language sql
security invoker
set search_path = ''
stable
as $$
    select *
    from public.networking_devices
    where user_id = (select auth.uid())
    order by created_at desc;
$$;

create or replace function public.networking_revoke_device(p_device_id text)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
    if (select auth.uid()) is null then
        raise exception 'networking_auth_required';
    end if;
    update public.networking_devices
    set revoked_at = now()
    where user_id = (select auth.uid())
      and device_id = p_device_id
      and revoked_at is null;
end;
$$;

revoke all on function public.networking_register_device(text, text, text) from public, anon;
revoke all on function public.networking_list_devices() from public, anon;
revoke all on function public.networking_revoke_device(text) from public, anon;
grant execute on function public.networking_register_device(text, text, text) to authenticated;
grant execute on function public.networking_list_devices() to authenticated;
grant execute on function public.networking_revoke_device(text) to authenticated;
