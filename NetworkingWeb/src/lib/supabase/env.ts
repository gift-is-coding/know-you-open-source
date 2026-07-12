export function hasSupabaseEnv() {
  const configured = Boolean(getSupabaseURL() && getSupabasePublishableKey());
  if (process.env.NODE_ENV === "production" && !configured) {
    requireProductionSupabaseEnv();
  }
  return configured;
}

export function requireProductionSupabaseEnv() {
  if (!getSupabaseURL() || !getSupabasePublishableKey()) {
    throw new Error("Networking production requires Supabase URL and publishable key; demo fallback is disabled.");
  }
}

export function getSupabaseURL() {
  return process.env.NEXT_PUBLIC_SUPABASE_URL;
}

export function getSupabasePublishableKey() {
  return process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
}
