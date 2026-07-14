import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "@supabase/supabase-js";

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return json({ error: "method not allowed" }, { status: 405 });
  }

  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const authorization = request.headers.get("authorization") ?? "";
  const accessToken = authorization.startsWith("Bearer ") ? authorization.slice(7) : "";
  if (!supabaseURL || !serviceRoleKey || !anonKey) {
    return json({ error: "web handoff is not configured" }, { status: 503 });
  }
  if (!accessToken) {
    return json({ error: "authentication required" }, { status: 401 });
  }

  const admin = createClient(supabaseURL, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false }
  });
  const { data: userData, error: userError } = await admin.auth.getUser(accessToken);
  const email = userData.user?.email;
  if (userError || !email) {
    return json({ error: "invalid session" }, { status: 401 });
  }

  const body = await request.json().catch(() => ({})) as Record<string, unknown>;
  const deviceID = typeof body.device_id === "string" ? body.device_id : "";
  const deviceToken = typeof body.device_token === "string" ? body.device_token : "";
  if (!deviceID || !deviceToken) {
    return json({ error: "device authorization required" }, { status: 403 });
  }

  const handoffSecret = `${crypto.randomUUID()}${crypto.randomUUID()}`.replaceAll("-", "");
  const userClient = createClient(supabaseURL, anonKey, {
    auth: { autoRefreshToken: false, persistSession: false },
    global: { headers: { Authorization: `Bearer ${accessToken}` } }
  });
  const { error: handoffError } = await userClient.rpc("networking_create_web_handoff", {
    p_device_id: deviceID,
    p_device_token_hash: await sha256(deviceToken),
    p_secret_hash: await sha256(handoffSecret)
  });
  if (handoffError) {
    return json({ error: "device authorization required" }, { status: 403 });
  }

  const { data, error } = await admin.auth.admin.generateLink({ type: "magiclink", email });
  const tokenHash = data?.properties?.hashed_token;
  if (error || !tokenHash) {
    return json({ error: "handoff could not be created" }, { status: 503 });
  }

  return json({ token_hash: tokenHash, handoff_secret: handoffSecret });
});

async function sha256(value: string) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

function json(body: Record<string, unknown>, init: ResponseInit = {}) {
  return new Response(JSON.stringify(body), {
    ...init,
    headers: { "content-type": "application/json", ...init.headers }
  });
}
