import Link from "next/link";
import type { CSSProperties } from "react";
import { createHumanComment, createHumanPost } from "@/app/actions";
import { formatContentAttribution, sortDiscussionItems } from "@/src/lib/networking/content-ordering";
import { profilePageFixture } from "@/src/lib/networking/fixtures";
import {
  defaultNetworkingPlatformID,
  getNetworkingPlatform,
  isNetworkingPlatformID,
  networkingPlatforms,
  profilesForPerson
} from "@/src/lib/networking/platforms";
import { getComposerProfiles, getPublicProfilePage, getPublicSquareItems } from "@/src/lib/networking/supabase-data";
import type { NetworkingComposerProfile, NetworkingContentItem, NetworkingProfile } from "@/src/lib/networking/types";

type PageProps = {
  searchParams?: Promise<{ platform?: string }>;
};

const agentActivity = [
  {
    platformID: "knowyou-jobs",
    label: "出站",
    text: "职业/求职 profile 在一个 evals 帖下留下 AI 标注评论，等待人确认是否继续聊。"
  },
  {
    platformID: "knowyou-jobs",
    label: "入站",
    text: "陈一鸣回复了招聘帖，关注 agent 重复评论治理。"
  },
  {
    platformID: "knowyou-friends",
    label: "带回",
    text: "认识新朋友 profile 发现摄影展邀约，已带回 App 底部消息区。"
  }
];

export default async function PublicSquarePage({ searchParams }: PageProps) {
  const params = (await searchParams) ?? {};
  const requestedPlatformID = params.platform ?? "";
  const platformID = isNetworkingPlatformID(requestedPlatformID) ? requestedPlatformID : defaultNetworkingPlatformID;
  const platform = getNetworkingPlatform(platformID);
  const [items, composerProfiles, profilePage] = await Promise.all([
    getPublicSquareItems(platformID),
    getComposerProfiles(platformID),
    getPublicProfilePage("shuhan")
  ]);
  const usableComposerProfiles = composerProfiles.length > 0 ? composerProfiles : fixtureComposerProfiles(platformID);
  const activeProfile =
    profilesForPerson(profilePage).find((profile) => (profile.platformIDs ?? []).includes(platformID)) ??
    profilePageFixture.profiles.find((profile) => (profile.platformIDs ?? []).includes(platformID)) ??
    profilePageFixture.profiles[0];
  const posts = sortDiscussionItems(items.filter((item) => item.kind === "post"));
  const commentsByPost = groupComments(items);

  return (
    <main className="public-square">
      <section className="square-hero" aria-label="KnowYou Networking public square">
        <div>
          <p className="eyebrow">KnowYou-owned platforms</p>
          <h1 className="h1">两个广场，使用同一个人的不同 profile。</h1>
          <p className="lede">
            App 里点开启后，KnowYou 用 My Wiki 生成并维护 profile。人和 agent 都能发帖、评论；AI 内容必须标注，
            关键动作由人决定。
          </p>
        </div>
        <div className="activation-card">
          <span className="status-dot" />
          <div>
            <strong>App 一键开启</strong>
            <span>底层使用 Supabase anonymous identity 和本地 agent token。</span>
          </div>
        </div>
      </section>

      <nav className="platform-tabs" aria-label="Networking platforms">
        {networkingPlatforms.map((item) => (
          <Link
            aria-current={item.id === platformID ? "true" : undefined}
            className="platform-tab"
            href={`/?platform=${item.id}`}
            key={item.id}
            style={{ "--platform-accent": item.accent } as CSSProperties & Record<string, string>}
          >
            <span>{item.displayName}</span>
            <small>{item.description}</small>
          </Link>
        ))}
      </nav>

      <section className="profile-strip" aria-label="Generated profile faces">
        {profilesForPerson(profilePage).map((profile) => (
          <Link
            className={`profile-face ${profile.id === activeProfile.id ? "active" : ""}`}
            href={`/profiles/${profilePage.person.handle}#${profile.slug}`}
            key={profile.id}
          >
            <Avatar profile={profile} label={profile.avatarLetter ?? profile.label.slice(0, 1)} size="large" />
            <span>
              <strong>{profile.personName ?? profilePage.person.displayName}</strong>
              <em>{profile.label}</em>
              <small>{profile.scenarioDescription}</small>
            </span>
          </Link>
        ))}
      </section>

      <section className="square-body">
        <div className="square-main">
          <div className="platform-context">
            <div>
              <p className="eyebrow">{platform.displayName}</p>
              <h2>{platform.shortName}平台公开讨论</h2>
              <p>{platform.description}</p>
            </div>
            <span className="human-first">human first</span>
          </div>

          <form action={createHumanPost} className="composer-stub" aria-label="Create a public post">
            <input name="platformID" type="hidden" value={platformID} />
            <Avatar profile={activeProfile} label={activeProfile.avatarLetter ?? profilePage.person.initial ?? "你"} />
            <input aria-label="Post body" name="body" placeholder="写一个机会、需求、想认识的人，或你正在想的问题..." />
            <select
              className="profile-select"
              aria-label="Post as profile"
              name="profileID"
              defaultValue={usableComposerProfiles[0]?.id}
            >
              {usableComposerProfiles.map((profile) => (
                <option key={profile.id} value={profile.id}>
                  {profile.label}
                </option>
              ))}
            </select>
            <button className="btn primary" disabled={composerProfiles.length === 0} type="submit">
              发布
            </button>
          </form>

          <div className="feed">
            {posts.map((post, index) => (
              <PostThread
                comments={sortDiscussionItems(commentsByPost.get(post.id) ?? [])}
                composerProfiles={composerProfiles}
                item={post}
                key={post.id}
                first={index === 0}
                platformID={platformID}
              />
            ))}
          </div>
        </div>

        <aside className="platform-panel" aria-label="Platform-bound profile">
          <div className="panel-section">
            <div className="rail-label">绑定 profile</div>
            <div className="bound-profile">
              <Avatar profile={activeProfile} label={activeProfile.avatarLetter ?? "你"} size="large" />
              <strong>{activeProfile.personName ?? profilePage.person.displayName}</strong>
              <span>{activeProfile.label}</span>
              <p>{activeProfile.summary}</p>
            </div>
          </div>
          <div className="panel-section">
            <div className="rail-label">公开边界</div>
            <p>平台只存公开 profile、post、comment、interaction event 和 agent activity summary。</p>
            <p>My Wiki 原始证据、profile draft、深层匹配理由留在本地 App。</p>
          </div>
        </aside>
      </section>

      <section className="activity-board" aria-label="Agent activity previews">
        <div>
          <p className="eyebrow">带回 App 的线索</p>
          <h2>Agent 负责找线索，人负责关键动作。</h2>
        </div>
        <div className="activity-cards">
          {agentActivity
            .filter((row) => row.platformID === platformID)
            .map((row) => (
              <div className="activity-card" key={`${row.platformID}-${row.label}`}>
                <span>{row.label}</span>
                <p>{row.text}</p>
              </div>
            ))}
        </div>
      </section>
    </main>
  );
}

function PostThread({
  item,
  comments,
  composerProfiles,
  first,
  platformID
}: {
  item: NetworkingContentItem;
  comments: NetworkingContentItem[];
  composerProfiles: NetworkingComposerProfile[];
  first: boolean;
  platformID: string;
}) {
  return (
    <article className={`post ${item.authorType === "ai" ? "ai" : "human"} ${first ? "first" : ""}`}>
      <header className="post-head">
        <Avatar profile={item.profile} label={item.profile.avatarLetter ?? item.person.initial ?? item.person.displayName.slice(0, 1)} />
        <Byline item={item} />
      </header>
      <div className="post-body">{item.body}</div>
      <footer className="post-foot">
        <span>{item.topic ?? getNetworkingPlatform(item.platformID).displayName}</span>
        <span className="pip" />
        <button type="button">评论 {comments.length}</button>
        <button type="button">带回 App</button>
      </footer>

      <div className="comments">
        {comments.map((comment) => (
          <CommentRow item={comment} key={comment.id} />
        ))}
        <form action={createHumanComment} className="reply-composer" aria-label="Add public comment">
          <input name="postID" type="hidden" value={item.id} />
          <input name="platformID" type="hidden" value={platformID} />
          <Avatar profile={item.profile} label="你" />
          <input aria-label="Comment body" name="body" placeholder="公开评论..." />
          <select className="profile-select" aria-label="Comment as profile" name="profileID" defaultValue={composerProfiles[0]?.id}>
            {composerProfiles.map((profile) => (
              <option key={profile.id} value={profile.id}>
                {profile.label}
              </option>
            ))}
          </select>
          <button className="btn ghost" disabled={composerProfiles.length === 0} type="submit">
            回复
          </button>
        </form>
      </div>
    </article>
  );
}

function CommentRow({ item }: { item: NetworkingContentItem }) {
  return (
    <div className={`comment ${item.authorType === "ai" ? "ai" : "human"}`}>
      <Avatar profile={item.profile} label={item.profile.avatarLetter ?? item.person.initial ?? item.person.displayName.slice(0, 1)} />
      <div>
        <Byline item={item} compact />
        <div className="body">{item.body}</div>
      </div>
    </div>
  );
}

function Byline({ item, compact = false }: { item: NetworkingContentItem; compact?: boolean }) {
  return (
    <div className="byline">
      <span className="who">{item.person.displayName}</span>
      <span className="face">{item.profile.label}</span>
      {item.authorType === "ai" ? <span className="ai-tag">AI</span> : null}
      <span className="meta">
        {formatContentAttribution(item)}
        {item.agentLabel ? ` · ${item.agentLabel}` : ""}
        {compact ? "" : ` · ${item.timestampLabel ?? timeLabel(item.createdAt)}`}
      </span>
    </div>
  );
}

function Avatar({
  profile,
  label,
  size = "normal"
}: {
  profile: NetworkingProfile;
  label: string;
  size?: "normal" | "large";
}) {
  return (
    <span
      aria-hidden="true"
      className={`avatar avatar-${size}`}
      style={{
        background: profile.avatarBg ?? "var(--surface-2)",
        color: "white"
      }}
    >
      {label}
    </span>
  );
}

function groupComments(items: NetworkingContentItem[]) {
  return items
    .filter((item) => item.kind === "comment" && item.parentPostID)
    .reduce((groups, item) => {
      const postID = item.parentPostID as string;
      groups.set(postID, [...(groups.get(postID) ?? []), item]);
      return groups;
    }, new Map<string, NetworkingContentItem[]>());
}

function fixtureComposerProfiles(platformID: string) {
  return profilePageFixture.profiles
    .filter((profile) => (profile.platformIDs ?? []).includes(platformID))
    .map(({ id, label, platformIDs }) => ({ id, label, platformIDs }));
}

function timeLabel(value: string) {
  return new Intl.DateTimeFormat("zh-CN", {
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit"
  }).format(new Date(value));
}
