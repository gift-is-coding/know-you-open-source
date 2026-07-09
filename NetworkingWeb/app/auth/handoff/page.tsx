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
      const accessToken = params.get("access_token");
      const refreshToken = params.get("refresh_token");
      const platform = params.get("platform") ?? "knowyou-jobs";

      history.replaceState(null, "", "/auth/handoff");

      if (!accessToken || !refreshToken) {
        setMessage("Open this page from the KnowYou App to continue.");
        return;
      }

      try {
        const supabase = createClient();
        const { error } = await supabase.auth.setSession({
          access_token: accessToken,
          refresh_token: refreshToken
        });

        if (error) {
          setMessage("Could not connect this App session. Return to KnowYou and try again.");
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
        <p className="lede">{message}</p>
      </section>
    </main>
  );
}
