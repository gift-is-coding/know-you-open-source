drop policy if exists "owners can insert own agent tokens" on public.agent_tokens;

revoke insert on table public.agent_tokens from public, anon, authenticated;

alter function public.networking_authorize_device(uuid, text, text, text, text, text)
    security definer;

revoke all on function public.networking_authorize_device(uuid, text, text, text, text, text) from public, anon;
grant execute on function public.networking_authorize_device(uuid, text, text, text, text, text) to authenticated;
