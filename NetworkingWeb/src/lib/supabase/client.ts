import { createBrowserClient } from "@supabase/ssr";
import { getSupabasePublishableKey, getSupabaseURL, hasSupabaseEnv } from "./env";

export function createClient() {
  if (!hasSupabaseEnv()) {
    throw new Error("Supabase public environment variables are not configured.");
  }

  return createBrowserClient(
    getSupabaseURL()!,
    getSupabasePublishableKey()!
  );
}
