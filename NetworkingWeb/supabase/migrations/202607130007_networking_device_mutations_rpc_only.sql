drop policy if exists "owners can insert networking devices" on public.networking_devices;
drop policy if exists "owners can update networking devices" on public.networking_devices;
drop policy if exists "owners can revoke own agent tokens" on public.agent_tokens;

revoke insert, update, delete, truncate, references, trigger
    on table public.networking_devices from public, anon, authenticated;
revoke insert, update, delete, truncate, references, trigger
    on table public.agent_tokens from public, anon, authenticated;

alter function public.networking_revoke_device(text) security definer;

revoke all on function public.networking_revoke_device(text) from public, anon;
grant execute on function public.networking_revoke_device(text) to authenticated;
