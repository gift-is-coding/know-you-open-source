create table public.networking_device_sessions (
    device_id uuid not null references public.networking_devices(id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    auth_session_id uuid not null unique,
    created_at timestamptz not null default now(),
    primary key (device_id, auth_session_id)
);

create table public.networking_web_handoffs (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    device_id uuid not null references public.networking_devices(id) on delete cascade,
    secret_hash text not null unique check (secret_hash ~ '^[0-9a-f]{64}$'),
    expires_at timestamptz not null default (now() + interval '5 minutes'),
    consumed_at timestamptz,
    created_at timestamptz not null default now()
);

alter table public.networking_device_sessions enable row level security;
alter table public.networking_web_handoffs enable row level security;
revoke all on table public.networking_device_sessions from public, anon, authenticated;
revoke all on table public.networking_web_handoffs from public, anon, authenticated;

create or replace function public.networking_current_session_has_active_device()
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
    select exists (
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

create or replace function public.networking_authorize_device(
    p_person_id uuid, p_device_id text, p_display_name text,
    p_device_token_hash text, p_agent_token_hash text, p_agent_token_label text
)
returns public.networking_devices
language plpgsql
security definer
set search_path = ''
as $$
declare
    current_user_id uuid := (select auth.uid());
    current_session_id uuid := nullif(auth.jwt() ->> 'session_id', '')::uuid;
    existing_device public.networking_devices;
    result public.networking_devices;
begin
    if current_user_id is null or current_session_id is null then
        raise exception 'networking_auth_required';
    end if;
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

    insert into public.networking_device_sessions (device_id, user_id, auth_session_id)
    values (result.id, current_user_id, current_session_id)
    on conflict (auth_session_id) do update
    set device_id = excluded.device_id, user_id = excluded.user_id, created_at = now();
    return result;
end;
$$;

revoke all on function public.networking_authorize_device(uuid, text, text, text, text, text)
    from public, anon, authenticated;

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
    if current_user_id is null or current_session_id is null then
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
    if current_user_id is null or current_session_id is null then
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
    if current_user_id is null or current_session_id is null then
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
    end if;
end;
$$;

revoke all on function public.networking_revoke_device(text) from public, anon;
grant execute on function public.networking_revoke_device(text) to authenticated;

drop policy if exists "owners can insert profiles" on public.profiles;
create policy "owners can insert profiles" on public.profiles for insert
with check (public.networking_current_session_has_active_device() and exists (
    select 1 from public.people where people.id = profiles.person_id and people.user_id = auth.uid()
));
drop policy if exists "owners can update profiles" on public.profiles;
create policy "owners can update profiles" on public.profiles for update
using (public.networking_current_session_has_active_device() and exists (
    select 1 from public.people where people.id = profiles.person_id and people.user_id = auth.uid()
))
with check (public.networking_current_session_has_active_device() and exists (
    select 1 from public.people where people.id = profiles.person_id and people.user_id = auth.uid()
));

drop policy if exists "owners can insert posts" on public.posts;
create policy "owners can insert posts" on public.posts for insert
with check (public.networking_current_session_has_active_device()
    and exists (select 1 from public.people where people.id = posts.person_id and people.user_id = auth.uid())
    and exists (select 1 from public.profiles where profiles.id = posts.profile_id and profiles.person_id = posts.person_id));
drop policy if exists "owners can update posts" on public.posts;
create policy "owners can update posts" on public.posts for update
using (public.networking_current_session_has_active_device()
    and exists (select 1 from public.people where people.id = posts.person_id and people.user_id = auth.uid()))
with check (public.networking_current_session_has_active_device()
    and exists (select 1 from public.people where people.id = posts.person_id and people.user_id = auth.uid())
    and exists (select 1 from public.profiles where profiles.id = posts.profile_id and profiles.person_id = posts.person_id));

drop policy if exists "owners can insert comments" on public.comments;
create policy "owners can insert comments" on public.comments for insert
with check (public.networking_current_session_has_active_device()
    and exists (select 1 from public.people where people.id = comments.person_id and people.user_id = auth.uid())
    and exists (select 1 from public.profiles where profiles.id = comments.profile_id and profiles.person_id = comments.person_id)
    and exists (select 1 from public.posts where posts.id = comments.post_id and posts.is_public));
drop policy if exists "owners can update comments" on public.comments;
create policy "owners can update comments" on public.comments for update
using (public.networking_current_session_has_active_device()
    and exists (select 1 from public.people where people.id = comments.person_id and people.user_id = auth.uid()))
with check (public.networking_current_session_has_active_device()
    and exists (select 1 from public.people where people.id = comments.person_id and people.user_id = auth.uid())
    and exists (select 1 from public.profiles where profiles.id = comments.profile_id and profiles.person_id = comments.person_id));

drop policy if exists "owners can insert community memberships" on public.community_memberships;
create policy "owners can insert community memberships" on public.community_memberships for insert
with check (public.networking_current_session_has_active_device() and exists (
    select 1 from public.people join public.profiles on profiles.person_id = people.id
    where people.user_id = auth.uid() and people.id = community_memberships.person_id
      and profiles.id = community_memberships.profile_id
));
drop policy if exists "owners can update community memberships" on public.community_memberships;
create policy "owners can update community memberships" on public.community_memberships for update
using (public.networking_current_session_has_active_device() and exists (
    select 1 from public.people where people.id = community_memberships.person_id and people.user_id = auth.uid()
))
with check (public.networking_current_session_has_active_device() and exists (
    select 1 from public.people join public.profiles on profiles.person_id = people.id
    where people.user_id = auth.uid() and people.id = community_memberships.person_id
      and profiles.id = community_memberships.profile_id
));
