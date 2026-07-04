import Link from "next/link";
import { saveProfile } from "@/app/actions";
import { networkingPlatforms } from "@/src/lib/networking/platforms";
import { getMyProfileWorkspace } from "@/src/lib/networking/supabase-data";

export default async function MyProfilesPage() {
  const workspace = await getMyProfileWorkspace();
  const firstProfile = workspace.profiles[0];

  if (workspace.needsSignIn) {
    return (
      <main className="page">
        <section className="center">
          <p className="eyebrow">Local profile cockpit</p>
          <h1 className="h1">Activate in the App before publishing public profiles.</h1>
          <p className="lede">The MVP uses Supabase anonymous sign-in for App activation; My Wiki profile drafting still happens locally.</p>
          <Link className="btn primary" href="/auth">
            Activate
          </Link>
        </section>
      </main>
    );
  }

  return (
    <main className="page">
      <aside className="rail-left">
        <section className="group">
          <div className="rail-label">Generated profiles</div>
          <div className="draft-list">
            {workspace.profiles.map((profile, index) => (
              <button aria-current={index === 0 ? "true" : undefined} className="draft-row" key={profile.id} type="button">
                <span>
                  <span className="name">{profile.label}</span>
                  <span className="blurb">{profile.summary}</span>
                </span>
                <span className="ts">{profile.published ? "live" : "draft"}</span>
              </button>
            ))}
          </div>
        </section>
      </aside>

      <section className="center">
        <header className="square-head">
          <div>
            <p className="eyebrow">Profiles · My Wiki + LLM + human approval</p>
            <h1 className="h1">One profile per scene, then bind it to a community.</h1>
            <p className="lede">
              The prompt defines the scene, My Wiki provides context, and the LLM drafts the profile. Only approved public summaries sync to the platform.
            </p>
          </div>
          <span className="kbd">local first</span>
        </header>

        <form action={saveProfile} className="draft-panel">
          <div className="draft-panel-head">
            <div>
              <div className="title">Publish profile</div>
              <div className="src">generated from prompt + My Wiki, human approved</div>
            </div>
            <label className="toggle">
              <input defaultChecked={firstProfile?.published ?? false} name="isPublished" type="checkbox" />
              <span className="track" />
              <span>Public</span>
            </label>
          </div>
          <div className="form-grid">
            <label>
              Display name
              <input defaultValue={workspace.person?.displayName ?? "Lin Shuhan"} name="displayName" placeholder="Display name" />
            </label>
            <label>
              Handle
              <input defaultValue={workspace.person?.handle ?? "shuhan"} name="handle" placeholder="handle" />
            </label>
            <label>
              Profile label
              <input defaultValue={firstProfile?.label ?? "Career / Hiring"} name="label" placeholder="Profile label" />
            </label>
            <label>
              Slug
              <input defaultValue={firstProfile?.slug ?? "jobs"} name="slug" placeholder="profile-slug" />
            </label>
            <label>
              Scenario
              <select defaultValue={firstProfile?.scenarioID ?? "jobs"} name="scenarioID">
                <option value="jobs">Career / Hiring</option>
                <option value="friends">Friends / Social</option>
              </select>
            </label>
            <label>
              Platform IDs
              <input
                defaultValue={(firstProfile?.platformIDs ?? [networkingPlatforms[0].id]).join(",")}
                name="platformIDs"
                placeholder="knowyou-jobs"
              />
            </label>
            <label>
              Avatar seed
              <input defaultValue={firstProfile?.avatarSeed ?? "lin-shuhan-jobs"} name="avatarSeed" placeholder="avatar seed" />
            </label>
            <label>
              Avatar style
              <select defaultValue={firstProfile?.avatarStyle ?? "gradient"} name="avatarStyle">
                <option value="gradient">gradient</option>
                <option value="initials">initials</option>
              </select>
            </label>
            <label className="wide">
              Scenario description
              <textarea
                defaultValue={firstProfile?.scenarioDescription ?? "For hiring, job search, project collaboration, and explaining what this person can own."}
                name="scenarioDescription"
                placeholder="Where this profile should be used"
              />
            </label>
            <label className="wide">
              Public summary
              <textarea defaultValue={firstProfile?.summary ?? ""} name="summary" placeholder="Short public summary" />
            </label>
            <label className="wide">
              Long body
              <textarea name="body" placeholder="Longer public profile body. This can be empty in the MVP." />
            </label>
          </div>
          <div className="draft-actions">
            {workspace.usesFixtureData ? <span className="hint">fixture preview · not written to the remote platform</span> : null}
            <button className="btn primary" type="submit">
              Save profile
            </button>
          </div>
        </form>
      </section>
    </main>
  );
}
