import Link from "next/link";
import { getNetworkingPlatform, profilesForPerson } from "@/src/lib/networking/platforms";
import { getPublicProfilePage } from "@/src/lib/networking/supabase-data";
import type { NetworkingProfile } from "@/src/lib/networking/types";

export default async function ProfilePage({
  params
}: {
  params: Promise<{ handle: string }>;
}) {
  const { handle } = await params;
  const page = await getPublicProfilePage(handle);
  const profiles = profilesForPerson(page);
  const activeProfile = profiles[0];

  return (
    <main className="profile-page">
      <header className="profile-header">
        <div>
          <p className="eyebrow">Public profile faces</p>
          <h1 className="h0">{page.person.displayName}</h1>
          <p className="one-liner">{page.person.tagline ?? activeProfile?.summary}</p>
        </div>
        <div className="profile-meta">
          <div>@{page.person.handle}</div>
          <div>{profiles.length} confirmed profiles</div>
        </div>
      </header>

      <section className="profile-face-grid" aria-label="Profiles">
        {profiles.map((profile) => (
          <article className="public-profile-card" id={profile.slug} key={profile.id}>
            <div className="public-profile-head">
              <Avatar profile={profile} label={profile.avatarLetter ?? profile.label.slice(0, 1)} />
              <div>
                <h2>{profile.label}</h2>
                <p>{profile.scenarioDescription}</p>
              </div>
            </div>
            <p className="profile-summary">{profile.summary}</p>
            <dl className="kv">
              <dt>Person</dt>
              <dd>{profile.personName ?? page.person.displayName}</dd>
              <dt>Visibility</dt>
              <dd>{profile.published ? "公开，已人工确认" : "草稿，未公开"}</dd>
              <dt>Platform</dt>
              <dd>{(profile.platformIDs ?? []).map((platformID) => getNetworkingPlatform(platformID).displayName).join(" / ")}</dd>
              <dt>Source</dt>
              <dd>My Wiki context + LLM draft + human confirmation</dd>
            </dl>
            <Link className="btn ghost" href={`/?platform=${profile.platformIDs?.[0] ?? "knowyou-jobs"}`}>
              去对应广场
            </Link>
          </article>
        ))}
      </section>

      <section className="privacy-strip">
        <div>
          <strong>隐私边界</strong>
          <span>公开页面只展示确认后的 profile summary。My Wiki 原始证据、私有 draft 和匹配理由只留在本地 App。</span>
        </div>
        <div>
          <strong>AI 标注</strong>
          <span>agent 使用任一 profile 发帖或评论时，都会显示人 + profile + AI。</span>
        </div>
      </section>
    </main>
  );
}

function Avatar({ profile, label }: { profile: NetworkingProfile; label: string }) {
  return (
    <span
      aria-hidden="true"
      className="avatar avatar-hero"
      style={{
        background: profile.avatarBg ?? "var(--surface-2)",
        color: "white"
      }}
    >
      {label}
    </span>
  );
}
