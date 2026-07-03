export function hasSupabaseEnv() {
  return Boolean(getSupabaseURL() && getSupabasePublishableKey());
}

export function getSupabaseURL() {
  return process.env.NEXT_PUBLIC_SUPABASE_URL;
}

export function getSupabasePublishableKey() {
  return process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
}
