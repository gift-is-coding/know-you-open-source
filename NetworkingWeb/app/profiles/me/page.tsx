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
          <h1 className="h1">先在 App 里开启，再发布公开 profile。</h1>
          <p className="lede">MVP 使用 Supabase anonymous sign-in 承接 App 一键开启；My Wiki 生成草稿仍然发生在本地。</p>
          <Link className="btn primary" href="/auth">
            开启
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
            <p className="eyebrow">Profiles · My Wiki + LLM + 人工确认</p>
            <h1 className="h1">每个场景一个 profile，平台绑定后长期使用。</h1>
            <p className="lede">
              Prompt 决定场景，My Wiki 提供上下文，LLM 生成草稿；只有确认后的公开 summary 会同步到平台。
            </p>
          </div>
          <span className="kbd">local first</span>
        </header>

        <form action={saveProfile} className="draft-panel">
          <div className="draft-panel-head">
            <div>
              <div className="title">发布 profile</div>
              <div className="src">generated from prompt + My Wiki, human approved</div>
            </div>
            <label className="toggle">
              <input defaultChecked={firstProfile?.published ?? false} name="isPublished" type="checkbox" />
              <span className="track" />
              <span>公开</span>
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
              <input defaultValue={firstProfile?.label ?? "职业/求职"} name="label" placeholder="Profile label" />
            </label>
            <label>
              Slug
              <input defaultValue={firstProfile?.slug ?? "jobs"} name="slug" placeholder="profile-slug" />
            </label>
            <label>
              Scenario
              <select defaultValue={firstProfile?.scenarioID ?? "jobs"} name="scenarioID">
                <option value="jobs">职业/求职</option>
                <option value="friends">认识新朋友</option>
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
                defaultValue={firstProfile?.scenarioDescription ?? "面向招聘、求职、项目合作，强调正在做什么、能负责什么、想找谁。"}
                name="scenarioDescription"
                placeholder="这个 profile 用在哪个场景"
              />
            </label>
            <label className="wide">
              Public summary
              <textarea defaultValue={firstProfile?.summary ?? ""} name="summary" placeholder="短公开摘要" />
            </label>
            <label className="wide">
              Long body
              <textarea name="body" placeholder="更长的公开 profile 内容。MVP 可以为空。" />
            </label>
          </div>
          <div className="draft-actions">
            {workspace.usesFixtureData ? <span className="hint">fixture preview · 未写入远端</span> : null}
            <button className="btn primary" type="submit">
              Save profile
            </button>
          </div>
        </form>
      </section>
    </main>
  );
}
