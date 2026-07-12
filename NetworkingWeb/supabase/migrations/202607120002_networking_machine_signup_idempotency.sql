alter table public.networking_machine_signup_attempts
    add column if not exists identity_hash text;

create unique index if not exists networking_machine_signup_attempts_identity_idx
    on public.networking_machine_signup_attempts (identity_hash)
    where identity_hash is not null;

drop function if exists public.networking_register_machine_signup_attempt(text, integer);

create or replace function public.networking_register_machine_signup_attempt(
    p_source_hash text,
    p_identity_hash text,
    p_hourly_limit integer default 5,
    p_global_hourly_limit integer default 50
) returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    recent_source_attempts integer;
    recent_global_attempts integer;
begin
    if length(p_source_hash) < 32 or length(p_identity_hash) < 32
       or p_hourly_limit < 1 or p_hourly_limit > 20
       or p_global_hourly_limit < p_hourly_limit or p_global_hourly_limit > 200 then
        return false;
    end if;

    perform pg_advisory_xact_lock(hashtextextended('networking-machine-signup-global', 0));

    if exists (
        select 1 from public.networking_machine_signup_attempts
        where identity_hash = p_identity_hash
    ) then
        return true;
    end if;

    select count(*) into recent_global_attempts
    from public.networking_machine_signup_attempts
    where attempted_at >= now() - interval '1 hour';
    if recent_global_attempts >= p_global_hourly_limit then
        return false;
    end if;

    select count(*) into recent_source_attempts
    from public.networking_machine_signup_attempts
    where source_hash = p_source_hash
      and attempted_at >= now() - interval '1 hour';
    if recent_source_attempts >= p_hourly_limit then
        return false;
    end if;

    insert into public.networking_machine_signup_attempts (source_hash, identity_hash)
    values (p_source_hash, p_identity_hash);
    return true;
end;
$$;

revoke all on function public.networking_register_machine_signup_attempt(text, text, integer, integer) from public, anon, authenticated;
grant execute on function public.networking_register_machine_signup_attempt(text, text, integer, integer) to service_role;

