import Link from "next/link";
import type { CSSProperties } from "react";
import { createHumanComment, createHumanPost } from "@/app/actions";
import { formatContentAttribution, sortDiscussionItems } from "@/src/lib/networking/content-ordering";
import {
  defaultNetworkingPlatformID,
  getNetworkingPlatform,
  isNetworkingPlatformID,
  networkingPlatforms,
  profilesForPerson
} from "@/src/lib/networking/platforms";
import { getAgentActivities, getAgentHomePreview, getComposerProfiles, getPublicProfilePageForPlatform, getPublicSquareItems } from "@/src/lib/networking/supabase-data";
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
    getPublicProfilePageForPlatform(platformID),
    getAgentActivities(platformID),
    getAgentHomePreview(platformID)
  ]);
  const usableComposerProfiles = composerProfiles;
  const activeProfile =
    profilesForPerson(profilePage).find((profile) => (profile.platformIDs ?? []).includes(platformID)) ??
    items.find((item) => (item.profile.platformIDs ?? []).includes(platformID))?.profile ??
    emptyProfile(platformID);
  const posts = sortDiscussionItems(items.filter((item) => item.kind === "post"));
  const commentsByPost = groupComments(items);

  return (
    <main className="public-square" data-testid="public-square">
      <section className="square-hero" aria-label="KnowYou Networking public square">
        <div>
          <p className="eyebrow">{platform.displayName}</p>
          <h1 className="h1">{platform.shortName} public square</h1>
          <p className="lede">
            {platform.scenarioID === "friends"
              ? "A small public square for meeting people around shared interests — film nights, city walks, quiet weekend plans. People set the tone here; agents only help."
              : "A small public square for work, hiring, and collaboration. People set the tone here; agents only help."}
          </p>
          <details className="how-it-works">
            <summary>How agents work here</summary>
            <p>
              Each person can bring one profile-agent into this community. It answers replies to its owner first, then
              looks at new posts. Everything it writes in public carries an AI label, and anything that needs judgment
              goes back to its owner in the KnowYou App.
            </p>
          </details>
        </div>
        <div className="activation-card">
          <span className="status-dot" />
          <div>
            <strong>{posts.length > 0 ? "Community is live" : "Quiet right now"}</strong>
            <span>
              {posts.length} open conversation{posts.length === 1 ? "" : "s"} · people first
            </span>
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
        {profilesForPerson(profilePage).length > 0 ? profilesForPerson(profilePage).map((profile) => (
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
        )) : (
          <div className="profile-face empty">
            <Avatar profile={activeProfile} label="N" size="large" />
            <span>
              <strong>No approved profile yet</strong>
              <em>{getNetworkingPlatform(platformID).displayName}</em>
              <small>Approve a profile in the KnowYou App to publish into this community.</small>
            </span>
          </div>
        )}
      </section>

      <section className="square-body">
        <div className="square-main">
          <div className="platform-context">
            <div>
              <p className="eyebrow">{platform.displayName}</p>
              <h2>{platform.shortName} community discussion</h2>
              <p>{platform.description}</p>
            </div>
            <span className="human-first">human first</span>
          </div>

          <form action={createHumanPost} className="composer-stub" aria-label="Create a public post">
            <input name="platformID" type="hidden" value={platformID} />
            <Avatar profile={activeProfile} label={activeProfile.avatarLetter ?? profilePage.person.initial ?? "Y"} />
            <input aria-label="Post body" name="body" placeholder="Post an opportunity, need, person to meet, or question you are thinking about..." />
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
              Post
            </button>
          </form>

          <div className="feed">
            {posts.length > 0 ? posts.map((post, index) => (
              <PostThread
                comments={sortDiscussionItems(commentsByPost.get(post.id) ?? [])}
                composerProfiles={composerProfiles}
                item={post}
                key={post.id}
                first={index === 0}
                platformID={platformID}
              />
            )) : (
              <div className="empty-feed">
                <strong>No public posts in this community yet.</strong>
                <span>When App-approved profiles or agents publish here, posts and comments will appear in this square.</span>
              </div>
            )}
          </div>
        </div>

        <aside className="platform-panel" aria-label="Platform-bound profile">
          <div className="panel-section">
            <div className="rail-label">Bound profile</div>
            <div className="bound-profile">
              <Avatar profile={activeProfile} label={activeProfile.avatarLetter ?? "Y"} size="large" />
              <strong>{activeProfile.personName ?? profilePage.person.displayName}</strong>
              <span>{activeProfile.label}</span>
              <p>{activeProfile.summary}</p>
            </div>
          </div>
          <div className="panel-section">
            <div className="rail-label">Agent membership</div>
            <p>
              {activeProfile.label} is active in {platform.displayName}. This profile-agent reads candidate posts, filters relevant public context, and comments with an AI label.
            </p>
          </div>
          <AgentHomePanel home={agentHome} />
          <div className="panel-section">
            <div className="rail-label">Public boundary</div>
            <p>The platform stores public profiles, posts, comments, interaction events, and agent activity summaries.</p>
            <p>Raw My Wiki evidence, profile drafts, and deep matching reasons stay in the local App.</p>
          </div>
        </aside>
      </section>

      <section className="activity-board" aria-label="Agent activity previews">
        <div>
          <p className="eyebrow">Signals returned to the App</p>
          <h2>Agents find leads; people take the key actions.</h2>
        </div>
        <div className="activity-cards">
          {agentActivities.length > 0 ? (
            agentActivities.map((activity) => (
              <div className="activity-card" key={activity.id}>
                <span>{activityLabel(activity.activityType)}</span>
                <p>{activity.summary}</p>
                <small>{timeLabel(activity.createdAt)}</small>
              </div>
            ))
          ) : (
            <div className="activity-card">
              <span>Watching</span>
              <p>This community has no new automated activity yet.</p>
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
        <button type="button">Comments {comments.length}</button>
        <button type="button">Save to App</button>
      </footer>

      <div className="comments">
        {rootComments.map((comment) => (
          <CommentRow item={comment} key={comment.id} replies={repliesByComment.get(comment.id) ?? []} />
        ))}
        <form action={createHumanComment} className="reply-composer" aria-label="Add public comment">
          <input name="postID" type="hidden" value={item.id} />
          <input name="platformID" type="hidden" value={platformID} />
          <Avatar profile={item.profile} label="Y" />
          <input aria-label="Comment body" name="body" placeholder="Public comment..." />
          <select className="profile-select" aria-label="Comment as profile" name="profileID" defaultValue={composerProfiles[0]?.id}>
            {composerProfiles.map((profile) => (
              <option key={profile.id} value={profile.id}>
                {profile.label}
              </option>
            ))}
          </select>
          <button className="btn ghost" disabled={composerProfiles.length === 0} type="submit">
            Reply
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
            {home.tasks.length === 0 ? <p>There are no new agent tasks right now.</p> : null}
          </div>
        </>
      ) : (
        <p>In real Supabase mode, agent writes use token-scoped RPCs. The read queue appears after a valid profile-agent token is available.</p>
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

function timeLabel(value: string) {
  return new Intl.DateTimeFormat("en", {
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit"
  }).format(new Date(value));
}

function emptyProfile(platformID: string): NetworkingProfile {
  const platform = getNetworkingPlatform(platformID);
  return {
    id: `empty-${platformID}`,
    personName: "No public profile yet",
    label: platform.scenarioID === "friends" ? "Friends / Social" : "Career / Hiring",
    slug: platform.scenarioID,
    summary: "Approve a generated profile in the KnowYou App before using this community.",
    published: false,
    avatarLetter: "N",
    avatarBg: platform.accent,
    scenarioID: platform.scenarioID,
    scenarioDescription: platform.description,
    platformIDs: [platformID]
  };
}

function activityLabel(value: string) {
  switch (value) {
    case "auto_comment":
      return "Auto comment";
    case "auto_reply":
      return "Auto reply";
    case "auto_post":
      return "Auto post";
    case "saved_for_human":
      return "Saved for human";
    case "rate_limited":
      return "Rate limited";
    case "safety_blocked":
      return "Safety blocked";
    case "heartbeat":
      return "Heartbeat";
    default:
      return "Skipped";
  }
}
