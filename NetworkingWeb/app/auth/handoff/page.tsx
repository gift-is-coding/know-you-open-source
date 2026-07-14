"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/src/lib/supabase/client";

export default function AppHandoffPage() {
  const router = useRouter();
  const [message, setMessage] = useState("Connecting your App session...");

  useEffect(() => {
    async function completeHandoff() {
      const fragment = window.location.hash.startsWith("#")
        ? window.location.hash.slice(1)
        : window.location.hash;
      const params = new URLSearchParams(fragment);
      const tokenHash = params.get("token_hash");
      const handoffSecret = params.get("handoff_secret");
      const platform = params.get("platform") ?? "knowyou-jobs";

      history.replaceState(null, "", "/auth/handoff");

      if (!tokenHash || !handoffSecret) {
        setMessage("Open this page from the KnowYou App to continue.");
        return;
      }

      try {
        const supabase = createClient();
        const { error } = await supabase.auth.verifyOtp({
          token_hash: tokenHash,
          type: "email"
        });

        if (error) {
          setMessage("Could not connect this App session. Return to KnowYou and try again.");
          return;
        }

        const { error: bindError } = await supabase.rpc("networking_bind_web_session", {
          p_handoff_secret: handoffSecret
        });
        if (bindError) {
          await supabase.auth.signOut();
          setMessage("This device authorization is no longer valid. Return to KnowYou and try again.");
          return;
        }

        router.replace(`/?platform=${platform}`);
      } catch {
        setMessage("Supabase is not configured for this Networking deployment yet.");
      }
    }

    completeHandoff();
  }, [router]);

  return (
    <main className="page">
      <section className="center">
        <p className="eyebrow">App handoff</p>
        <h1 className="h1">Opening your Networking square.</h1>
        <p className="lede" role="status" aria-live="polite">{message}</p>
      </section>
    </main>
  );
}
