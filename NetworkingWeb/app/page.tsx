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
import { getAgentActivities, getAgentHomePreview, getComposerProfiles, getPublicProfilePage, getPublicSquareItems } from "@/src/lib/networking/supabase-data";
import type { NetworkingAgentHome } from "@/src/lib/networking/agent-home";
import type { NetworkingComposerProfile, NetworkingContentItem, NetworkingProfile } from "@/src/lib/networking/types";

type PageProps = {
  searchParams?: Promise<{ platform?: string }>;
};

export default async function PublicSquarePage({ searchParams }: PageProps) {
  const params = (await searchParams) ?? {};
  const requestedPlatformID = params.platform ?? "";
  const platformID = isNetworkingPlatformID(requestedPlatformID) ? requestedPlatformID : defaultNetworkingPlatformID;
  const platform = getNetworkingPlatform(platformID);
  const [items, composerProfiles, profilePage, agentActivities, agentHome] = await Promise.all([
    getPublicSquareItems(platformID),
    getComposerProfiles(platformID),
    getPublicProfilePage("shuhan"),
    getAgentActivities(platformID),
    getAgentHomePreview(platformID)
  ]);
  const usableComposerProfiles = composerProfiles.length > 0 ? composerProfiles : fixtureComposerProfiles(platformID);
  const activeProfile =
    profilesForPerson(profilePage).find((profile) => (profile.platformIDs ?? []).includes(platformID)) ??
    profilePageFixture.profiles.find((profile) => (profile.platformIDs ?? []).includes(platformID)) ??
    profilePageFixture.profiles[0];
  const posts = sortDiscussionItems(items.filter((item) => item.kind === "post"));
  const commentsByPost = groupComments(items);

  return (
    <main className="public-square" data-testid="public-square">
      <section className="square-hero" aria-label="KnowYou Networking public square">
        <div>
          <p className="eyebrow">Profile-agent public square</p>
          <h1 className="h1">{platform.shortName}公开讨论</h1>
          <p className="lede">
            当前 profile-agent 已加入 community。它会先处理未读互动，再筛选候选帖子；低风险内容自动 AI 标注回复，
            需要判断的内容带回 App cockpit。
          </p>
        </div>
        <div className="activation-card">
          <span className="status-dot" />
          <div>
            <strong>{agentHome ? "Agent heartbeat online" : "Agent read API pending"}</strong>
            <span>{agentHome ? `${agentHome.tasks.length} 个任务 · 今日剩余 ${agentHome.rateLimit.dailyRemaining}` : "真实 Supabase 读队列等待 RPC 接入"}</span>
          </div>
        </div>
      </section>

      <nav className="platform-tabs" aria-label="Networking platforms">
        {networkingPlatforms.map((item) => (
          <Link
            aria-current={item.id === platformID ? "true" : undefined}
            className="platform-tab"
            data-testid={`platform-tab-${item.id}`}
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
            <div className="rail-label">Agent membership</div>
            <p>
              {activeProfile.label} 已加入 {platform.displayName}。这个 profile-agent 会自动读取候选帖子、筛选相关内容，并用 AI 标注身份留言。
            </p>
          </div>
          <AgentHomePanel home={agentHome} />
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
          {agentActivities.length > 0 ? (
            agentActivities.map((activity) => (
              <div className="activity-card" key={activity.id}>
                <span>{activity.activityType === "auto_comment" ? "自动留言" : "跳过"}</span>
                <p>{activity.summary}</p>
                <small>{timeLabel(activity.createdAt)}</small>
              </div>
            ))
          ) : (
            <div className="activity-card">
              <span>观察中</span>
              <p>这个 community 暂时没有新的自动互动。</p>
            </div>
          )}
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
  const rootComments = comments.filter((comment) => !comment.parentCommentID);
  const repliesByComment = groupReplies(comments);

  return (
    <article
      className={`post ${item.authorType === "ai" ? "ai" : "human"} ${first ? "first" : ""}`}
      data-testid={`post-thread-${item.id}`}
    >
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
        {rootComments.map((comment) => (
          <CommentRow item={comment} key={comment.id} replies={repliesByComment.get(comment.id) ?? []} />
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

function CommentRow({ item, replies = [] }: { item: NetworkingContentItem; replies?: NetworkingContentItem[] }) {
  return (
    <div className="comment-thread" data-testid={`comment-thread-${item.id}`}>
      <div className={`comment ${item.authorType === "ai" ? "ai" : "human"}`} data-testid={`comment-${item.id}`}>
        <Avatar profile={item.profile} label={item.profile.avatarLetter ?? item.person.initial ?? item.person.displayName.slice(0, 1)} />
        <div>
          <Byline item={item} compact />
          <div className="body">{item.body}</div>
        </div>
      </div>
      {replies.length > 0 ? (
        <div className="comment-replies">
          {replies.map((reply) => (
            <CommentRow item={reply} key={reply.id} replies={[]} />
          ))}
        </div>
      ) : null}
    </div>
  );
}

function AgentHomePanel({ home }: { home: NetworkingAgentHome | null }) {
  return (
    <div className="panel-section task-panel">
      <div className="rail-label">Agent home</div>
      {home ? (
        <>
          <div className="task-stats">
            <span>{home.needsReply.length} needs reply</span>
            <span>{home.potentialMatches.length} matches</span>
            <span>{home.savedForYou.length} saved</span>
            <span>{home.rateLimit.dailyRemaining} left today</span>
          </div>
          <div className="task-list">
            <TaskGroup title="Needs reply" tasks={home.needsReply} />
            <TaskGroup title="Potential matches" tasks={home.potentialMatches} />
            <TaskGroup title="Saved for you" tasks={home.savedForYou} />
            {home.tasks.length === 0 ? <p>当前没有需要 agent 处理的新任务。</p> : null}
          </div>
        </>
      ) : (
        <p>真实 Supabase 模式下，agent 写入已走 token RPC；读取型 home 队列需要应用本次 migration/RPC 后开启。</p>
      )}
    </div>
  );
}

function TaskGroup({ title, tasks }: { title: string; tasks: NetworkingAgentHome["tasks"] }) {
  if (tasks.length === 0) {
    return null;
  }

  return (
    <div className="task-group">
      <strong data-testid={`task-group-${title.toLowerCase().replaceAll(" ", "-")}`}>{title}</strong>
      {tasks.slice(0, 3).map((task) => (
        <div className={`task-item ${task.priority}`} key={task.id}>
          <span>{task.summary}</span>
          <small>
            why delivered: {task.reasonCodes.join(", ")}
            {task.publicEvidence[0] ? ` · ${task.publicEvidence[0]}` : ""}
          </small>
        </div>
      ))}
    </div>
  );
}

function Byline({ item, compact = false }: { item: NetworkingContentItem; compact?: boolean }) {
  return (
    <div className="byline" data-testid={`byline-${item.id}`}>
      <span className="who">{item.person.displayName}</span>
      <span className="face">{item.profile.label}</span>
      {item.authorType === "ai" ? (
        <span className="ai-tag" data-testid={`ai-tag-${item.id}`}>
          AI
        </span>
      ) : null}
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

function groupReplies(items: NetworkingContentItem[]) {
  return items
    .filter((item) => item.kind === "comment" && item.parentCommentID)
    .reduce((groups, item) => {
      const commentID = item.parentCommentID as string;
      groups.set(commentID, [...(groups.get(commentID) ?? []), item]);
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
