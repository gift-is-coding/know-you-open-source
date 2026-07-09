import Link from "next/link";
import { networkingPlatforms } from "@/src/lib/networking/platforms";
import { getMyProfileWorkspace } from "@/src/lib/networking/supabase-data";

export default async function MyProfilesPage() {
  const workspace = await getMyProfileWorkspace();

  if (workspace.needsSignIn) {
    return (
      <main className="page">
        <section className="center">
          <p className="eyebrow">App-first profiles</p>
          <h1 className="h1">Open KnowYou to publish profiles.</h1>
          <p className="lede">
            This web page is read-only. Profile generation, redaction, and approval stay inside the KnowYou App.
          </p>
          <Link className="btn primary" href="/auth">
            Continue from App
          </Link>
        </section>
      </main>
    );
  }

  return (
    <main className="page">
      <section className="center">
        <header className="square-head">
          <div>
            <p className="eyebrow">Read-only profile cockpit</p>
            <h1 className="h1">Profiles are managed in the KnowYou App.</h1>
            <p className="lede">
              The web square shows approved public profiles only. Drafting, editing, and sensitive matching reasons remain local to the App.
            </p>
          </div>
          <span className="kbd">read-only</span>
        </header>

        <div className="readonly-profile-grid">
          {workspace.profiles.length > 0 ? workspace.profiles.map((profile) => (
            <article className="readonly-profile-card" key={profile.id}>
              <div className="draft-panel-head">
                <div>
                  <div className="title">{profile.label}</div>
                  <div className="src">{profile.published ? "public profile" : "not public"}</div>
                </div>
                <span className="kbd">{profile.scenarioID ?? "profile"}</span>
              </div>
              <p>{profile.summary || "No public summary has been approved yet."}</p>
              <div className="readonly-platforms">
                {(profile.platformIDs ?? []).map((platformID) => {
                  const platform = networkingPlatforms.find((item) => item.id === platformID);
                  return platform ? <span key={platform.id}>{platform.displayName}</span> : null;
                })}
              </div>
              {workspace.person ? (
                <Link className="btn ghost" href={`/profiles/${workspace.person.handle}#${profile.slug}`}>
                  View public page
                </Link>
              ) : null}
            </article>
          )) : (
            <div className="empty-feed">
              <strong>No approved public profiles yet.</strong>
              <span>Generate and approve one in the KnowYou App, then it will appear here.</span>
            </div>
          )}
        </div>
      </section>
    </main>
  );
}
