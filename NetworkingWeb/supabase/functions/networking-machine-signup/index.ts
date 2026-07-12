import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "@supabase/supabase-js";

const machineEmailPattern = /^knw-[a-z0-9-]+-[a-f0-9]{32}@users\.knowyou\.app$/;
const machinePasswordPattern = /^knw_[a-f0-9]{32}$/;

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return json({ error: "method not allowed" }, { status: 405 });
  }

  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseURL || !serviceRoleKey) {
    return json({ error: "machine signup is not configured" }, { status: 503 });
  }

  let body: { email?: string; password?: string };
  try {
    body = await request.json();
  } catch {
    return json({ error: "invalid JSON" }, { status: 400 });
  }

  const email = body.email?.trim().toLowerCase() ?? "";
  const password = body.password ?? "";
  if (!machineEmailPattern.test(email) || !machinePasswordPattern.test(password)) {
    return json({ error: "invalid KnowYou machine identity" }, { status: 400 });
  }

  const source = request.headers.get("cf-connecting-ip") || request.headers.get("x-real-ip") || "unknown";
  const sourceHash = await sha256(`${serviceRoleKey}:${source}`);
  const identityHash = await sha256(`${serviceRoleKey}:${email}`);
  const admin = createClient(supabaseURL, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false }
  });

  const { data: allowed, error: rateError } = await admin.rpc(
    "networking_register_machine_signup_attempt",
    { p_source_hash: sourceHash, p_identity_hash: identityHash, p_hourly_limit: 5, p_global_hourly_limit: 50 }
  );
  if (rateError) {
    return json({ error: "machine signup temporarily unavailable" }, { status: 503 });
  }
  if (!allowed) {
    return json({ error: "machine signup rate limit exceeded" }, { status: 429 });
  }

  const { data, error } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: { identity_type: "knowyou_machine" }
  });

  if (error) {
    const alreadyExists = error.code === "email_exists" || error.message.toLowerCase().includes("already");
    if (alreadyExists) {
      return json({ created: false, alreadyExists: true });
    }
    return json({ error: "machine identity could not be created" }, { status: 422 });
  }

  return json({ created: true, userID: data.user.id });
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
