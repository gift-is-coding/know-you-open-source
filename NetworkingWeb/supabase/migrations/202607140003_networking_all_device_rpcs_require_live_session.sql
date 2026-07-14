create or replace function public.networking_current_session_is_live()
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
    select exists (
        select 1 from auth.sessions
        where sessions.id = nullif(auth.jwt() ->> 'session_id', '')::uuid
          and sessions.user_id = (select auth.uid())
    );
$$;

revoke all on function public.networking_current_session_is_live() from public, anon;
grant execute on function public.networking_current_session_is_live() to authenticated;

create or replace function public.networking_current_session_has_active_device()
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
    select public.networking_current_session_is_live() and exists (
        select 1
        from public.networking_device_sessions
        join public.networking_devices
          on networking_devices.id = networking_device_sessions.device_id
        where networking_device_sessions.user_id = (select auth.uid())
          and networking_device_sessions.auth_session_id = nullif(auth.jwt() ->> 'session_id', '')::uuid
          and networking_devices.user_id = (select auth.uid())
          and networking_devices.revoked_at is null
    );
$$;

revoke all on function public.networking_current_session_has_active_device() from public, anon;
grant execute on function public.networking_current_session_has_active_device() to authenticated;

create or replace function public.networking_bind_current_device_session(
    p_device_id text,
    p_device_token_hash text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    current_user_id uuid := (select auth.uid());
    current_session_id uuid := nullif(auth.jwt() ->> 'session_id', '')::uuid;
    resolved_device_id uuid;
begin
    if current_user_id is null or current_session_id is null
       or not public.networking_current_session_is_live() then
        raise exception 'networking_auth_required';
    end if;
    select id into resolved_device_id
    from public.networking_devices
    where user_id = current_user_id
      and device_id = trim(p_device_id)
      and credential_hash = p_device_token_hash
      and revoked_at is null;
    if resolved_device_id is null then raise exception 'networking_device_not_authorized'; end if;

    insert into public.networking_device_sessions (device_id, user_id, auth_session_id)
    values (resolved_device_id, current_user_id, current_session_id)
    on conflict (auth_session_id) do update
    set device_id = excluded.device_id, user_id = excluded.user_id, created_at = now();
end;
$$;

revoke all on function public.networking_bind_current_device_session(text, text) from public, anon;
grant execute on function public.networking_bind_current_device_session(text, text) to authenticated;

create or replace function public.networking_create_web_handoff(
    p_device_id text,
    p_device_token_hash text,
    p_secret_hash text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    current_user_id uuid := (select auth.uid());
    current_session_id uuid := nullif(auth.jwt() ->> 'session_id', '')::uuid;
    resolved_device_id uuid;
    result uuid;
begin
    if current_user_id is null or current_session_id is null
       or not public.networking_current_session_is_live() then
        raise exception 'networking_auth_required';
    end if;
    if p_secret_hash !~ '^[0-9a-f]{64}$' then raise exception 'networking_invalid_handoff'; end if;
    select networking_devices.id into resolved_device_id
    from public.networking_devices
    join public.networking_device_sessions
      on networking_device_sessions.device_id = networking_devices.id
    where networking_devices.user_id = current_user_id
      and networking_devices.device_id = trim(p_device_id)
      and networking_devices.credential_hash = p_device_token_hash
      and networking_devices.revoked_at is null
      and networking_device_sessions.user_id = current_user_id
      and networking_device_sessions.auth_session_id = current_session_id;
    if resolved_device_id is null then raise exception 'networking_device_not_authorized'; end if;

    insert into public.networking_web_handoffs (user_id, device_id, secret_hash)
    values (current_user_id, resolved_device_id, p_secret_hash)
    returning id into result;
    return result;
end;
$$;

revoke all on function public.networking_create_web_handoff(text, text, text) from public, anon;
grant execute on function public.networking_create_web_handoff(text, text, text) to authenticated;

create or replace function public.networking_bind_web_session(p_handoff_secret text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    current_user_id uuid := (select auth.uid());
    current_session_id uuid := nullif(auth.jwt() ->> 'session_id', '')::uuid;
    resolved_handoff public.networking_web_handoffs;
begin
    if current_user_id is null or current_session_id is null
       or not public.networking_current_session_is_live() then
        raise exception 'networking_auth_required';
    end if;
    select * into resolved_handoff
    from public.networking_web_handoffs
    where user_id = current_user_id
      and secret_hash = encode(extensions.digest(p_handoff_secret, 'sha256'), 'hex')
      and consumed_at is null
      and expires_at > now()
    for update;
    if resolved_handoff.id is null or not exists (
        select 1 from public.networking_devices
        where id = resolved_handoff.device_id
          and user_id = current_user_id
          and revoked_at is null
    ) then raise exception 'networking_invalid_handoff'; end if;

    update public.networking_web_handoffs set consumed_at = now()
    where id = resolved_handoff.id;
    insert into public.networking_device_sessions (device_id, user_id, auth_session_id)
    values (resolved_handoff.device_id, current_user_id, current_session_id)
    on conflict (auth_session_id) do update
    set device_id = excluded.device_id, user_id = excluded.user_id, created_at = now();
end;
$$;

revoke all on function public.networking_bind_web_session(text) from public, anon;
grant execute on function public.networking_bind_web_session(text) to authenticated;
