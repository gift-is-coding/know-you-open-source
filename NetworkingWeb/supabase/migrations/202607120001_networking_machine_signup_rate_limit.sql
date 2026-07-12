create table if not exists public.networking_machine_signup_attempts (
    id uuid primary key default gen_random_uuid(),
    source_hash text not null,
    attempted_at timestamptz not null default now()
);

alter table public.networking_machine_signup_attempts enable row level security;
revoke all on table public.networking_machine_signup_attempts from anon, authenticated;

create index if not exists networking_machine_signup_attempts_source_time_idx
    on public.networking_machine_signup_attempts (source_hash, attempted_at desc);

create or replace function public.networking_register_machine_signup_attempt(
    p_source_hash text,
    p_hourly_limit integer default 5
) returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    recent_attempts integer;
begin
    if length(p_source_hash) < 32 or p_hourly_limit < 1 or p_hourly_limit > 20 then
        return false;
    end if;

    perform pg_advisory_xact_lock(hashtextextended(p_source_hash, 0));

    delete from public.networking_machine_signup_attempts
    where attempted_at < now() - interval '24 hours';

    select count(*) into recent_attempts
    from public.networking_machine_signup_attempts
    where source_hash = p_source_hash
      and attempted_at >= now() - interval '1 hour';

    if recent_attempts >= p_hourly_limit then
        return false;
    end if;

    insert into public.networking_machine_signup_attempts (source_hash)
    values (p_source_hash);
    return true;
end;
$$;

revoke all on function public.networking_register_machine_signup_attempt(text, integer) from public, anon, authenticated;
grant execute on function public.networking_register_machine_signup_attempt(text, integer) to service_role;

