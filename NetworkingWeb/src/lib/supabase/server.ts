import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import { getSupabasePublishableKey, getSupabaseURL, hasSupabaseEnv } from "./env";

export async function createClient() {
  if (!hasSupabaseEnv()) {
    throw new Error("Supabase public environment variables are not configured.");
  }

  const cookieStore = await cookies();

  return createServerClient(
    getSupabaseURL()!,
    getSupabasePublishableKey()!,
    {
      cookies: {
        getAll() {
          return cookieStore.getAll();
        },
        setAll(cookiesToSet) {
          try {
            cookiesToSet.forEach(({ name, value, options }) => {
              cookieStore.set(name, value, options);
            });
          } catch {
            // Server Components cannot set cookies; Proxy/Route Handlers can.
          }
        }
      }
    }
  );
}
