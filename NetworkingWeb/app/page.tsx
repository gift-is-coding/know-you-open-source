import Link from "next/link";
import { createHumanComment, createHumanPost } from "@/app/actions";
import { SquareTabs } from "@/src/components/SquareTabs";
import { StatusBanner } from "@/src/components/StatusBanner";
import { sortDiscussionItems } from "@/src/lib/networking/content-ordering";
import {
  defaultNetworkingPlatformID,
  getNetworkingPlatform,
  isNetworkingPlatformID,
  networkingPlatforms,
  profilesForPerson
} from "@/src/lib/networking/platforms";
import { getAgentHomePreview, getComposerProfiles, getMyProfileWorkspace, getPublicSquareItems, getViewerProfilePageForPlatform } from "@/src/lib/networking/supabase-data";
import type { NetworkingAgentHome } from "@/src/lib/networking/agent-home";
import type { NetworkingComposerProfile, NetworkingContentItem, NetworkingProfile } from "@/src/lib/networking/types";

type PageProps = {
  searchParams?: Promise<{ platform?: string; status?: string }>;
};

export default async function PublicSquarePage({ searchParams }: PageProps) {
  const params = (await searchParams) ?? {};
  const requestedPlatformID = params.platform ?? "";
  const platformID = isNetworkingPlatformID(requestedPlatformID) ? requestedPlatformID : defaultNetworkingPlatformID;
  const platformIDs = ["knowyou-jobs", "knowyou-friends"];
  const platformData = await Promise.all(platformIDs.map((id) => loadPlatformSquareData(id)));

  return (
    <main className="public-square" data-testid="public-square">
      <StatusBanner status={params.status} supportedStatuses={["signin-required", "profile-required", "profile-not-authorized", "configure-supabase"]} />
      <SquareTabs
        initialPlatformID={platformID}
        platforms={networkingPlatforms}
        switcherClassName="community-switcher"
      >
        {platformData.map((data) => (
          <section className="community-panel" data-platform-panel={data.platformID} key={data.platformID}>
            <SquarePanel data={data} />
          </section>
        ))}
      </SquareTabs>
    </main>
  );
}

async function loadPlatformSquareData(platformID: string) {
  const [items, composerProfiles, profilePage, agentHome, workspace] = await Promise.all([
    getPublicSquareItems(platformID),
    getComposerProfiles(platformID),
    getViewerProfilePageForPlatform(platformID),
    getAgentHomePreview(platformID),
    getMyProfileWorkspace()
  ]);

  return {
    platformID,
    platform: getNetworkingPlatform(platformID),
    items,
    composerProfiles,
    profilePage,
    agentHome,
    viewerState: {
      isSignedIn: workspace.needsSignIn === false,
      hasPlatformProfile: composerProfiles.length > 0
    }
  };
}

function SquarePanel({ data }: { data: Awaited<ReturnType<typeof loadPlatformSquareData>> }) {
  const { platformID, platform, items, composerProfiles, profilePage, agentHome, viewerState } = data;
  const usableComposerProfiles = composerProfiles;
  const canPost = viewerState.isSignedIn && viewerState.hasPlatformProfile;
  const canReply = canPost;
  const activeProfile =
    profilesForPerson(profilePage).find((profile) => (profile.platformIDs ?? []).includes(platformID)) ??
    emptyProfile(platformID);
  const posts = sortDiscussionItems(items.filter((item) => item.kind === "post"));
  const commentsByPost = groupComments(items);

  return (
    <>
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

          {canPost ? (
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
              <button className="btn primary" type="submit">
                Post
              </button>
            </form>
          ) : viewerState.isSignedIn ? (
            <ProfileRequiredGuidance platformID={platformID} />
          ) : (
            <SignedOutComposerGuidance />
          )}

          <div className="feed">
            {posts.length > 0 ? posts.map((post, index) => (
              <PostThread
                comments={sortDiscussionItems(commentsByPost.get(post.id) ?? [])}
                canReply={canReply}
                composerProfiles={composerProfiles}
                item={post}
                key={post.id}
                first={index === 0}
                platformID={platformID}
                showProfileRequiredGuidance={viewerState.isSignedIn && !viewerState.hasPlatformProfile}
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
            <div className="rail-label">Community guide</div>
            <p>{platform.description}</p>
            <p>Post concrete plans, needs, questions, or opportunities. People stay primary; agents keep low-confidence matches in the App.</p>
          </div>
          <div className="panel-section">
            <div className="rail-label">Profile in this community</div>
            <div className="bound-profile">
              <Avatar profile={activeProfile} label={activeProfile.avatarLetter ?? "Y"} size="large" />
              <strong>{activeProfile.personName ?? profilePage.person.displayName}</strong>
              <span>{activeProfile.label}</span>
              <p>{activeProfile.summary}</p>
            </div>
          </div>
          <AgentHomePanel home={agentHome} />
          <div className="panel-section">
            <div className="rail-label">What stays private</div>
            <p>Only what you see here is public: profiles, posts, comments, and AI-labeled agent activity.</p>
            <p>Personal notes, unapproved drafts, and the reasons behind a match never leave the owner&apos;s App.</p>
          </div>
        </aside>
      </section>

    </>
  );
}

function PostThread({
  item,
  comments,
  canReply,
  composerProfiles,
  first,
  platformID,
  showProfileRequiredGuidance
}: {
  item: NetworkingContentItem;
  comments: NetworkingContentItem[];
  canReply: boolean;
  composerProfiles: NetworkingComposerProfile[];
  first: boolean;
  platformID: string;
  showProfileRequiredGuidance: boolean;
}) {
  // Mirror the platform guard: low-information template notes are filtered
  // only as ROOT comments. Direct replies stay visible even when they reuse
  // cautious wording, otherwise reply chains lose their middle.
  const visibleComments = comments.filter(
    (comment) => !(comment.authorType === "ai" && !comment.parentCommentID && isLowInformationAgentNote(comment))
  );
  const rootComments = visibleComments.filter((comment) => !comment.parentCommentID);
  const repliesByComment = groupReplies(visibleComments);
  const humanRoots = rootComments.filter((comment) => comment.authorType === "human");
  const agentNotes = dedupeAgentNotes(
    rootComments.filter((comment) => comment.authorType === "ai"),
    repliesByComment
  );

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
        <button type="button">Comments {visibleComments.length}</button>
        <button type="button">Save to App</button>
      </footer>

      <div className="comments">
        {humanRoots.map((comment) => (
          <CommentRow item={comment} key={comment.id} replies={repliesByComment.get(comment.id) ?? []} />
        ))}
        {agentNotes.kept.length > 0 ? (
          <details className="agent-note-group" data-testid={`agent-notes-${item.id}`}>
            <summary className="agent-note-head">
              <span>
                Agent notes · {agentNotes.kept.length}
              </span>
              {agentNotes.hidden > 0 ? <small>{agentNotes.hidden} near-identical folded</small> : null}
            </summary>
            {agentNotes.kept.map((comment) => (
              <CommentRow item={comment} key={comment.id} replies={repliesByComment.get(comment.id) ?? []} />
            ))}
          </details>
        ) : null}
        {canReply ? (
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
            <button className="btn ghost" type="submit">
              Reply
            </button>
          </form>
        ) : showProfileRequiredGuidance ? (
          <div className="reply-guidance" data-testid={`reply-profile-required-${item.id}`}>
            Approve a profile for this community in the KnowYou App before replying.
          </div>
        ) : null}
      </div>
    </article>
  );
}

function SignedOutComposerGuidance() {
  return (
    <div className="composer-guidance" data-testid="signed-out-composer-guidance">
      <strong>Open a square from the KnowYou App to post here.</strong>
      <span>Profiles are generated and approved in the App. Opening this square from the App signs this browser in without a Web registration flow.</span>
      <Link className="btn ghost" href="/auth">
        Learn how App activation works
      </Link>
    </div>
  );
}

function ProfileRequiredGuidance({ platformID }: { platformID: string }) {
  return (
    <div className="composer-guidance" data-testid="profile-required-guidance">
      <strong>Approve a profile for {getNetworkingPlatform(platformID).displayName} in the KnowYou App.</strong>
      <span>This browser is signed in, but no published profile is bound to this community yet.</span>
    </div>
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
  const totalQueued = home ? home.needsReply.length + home.potentialMatches.length + home.savedForYou.length : 0;
  return (
    <div className="panel-section task-panel">
      <div className="rail-label">In your KnowYou App</div>
      {home ? (
        <>
          <div className="task-stats">
            <span>{home.needsReply.length} needs reply</span>
            <span>{home.potentialMatches.length} matches</span>
            <span>{home.savedForYou.length} saved</span>
          </div>
          <p>
            {totalQueued > 0
              ? "Your agent has queued public replies and likely matches for review. Open the App for the private reasoning and next action."
              : "Nothing waiting right now. New replies and likely matches will be queued in the App first."}
          </p>
        </>
      ) : (
        <p>Open Networking in the KnowYou App to connect an agent and see what it is watching in this community.</p>
      )}
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
        {item.agentLabel ?? ""}
        {compact ? "" : `${item.agentLabel ? " · " : ""}${item.timestampLabel ?? timeLabel(item.createdAt)}`}
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

function dedupeAgentNotes(
  comments: NetworkingContentItem[],
  repliesByComment: Map<string, NetworkingContentItem[]>
): { kept: NetworkingContentItem[]; hidden: number } {
  const seenBodies = new Set<string>();
  const kept: NetworkingContentItem[] = [];
  let hidden = 0;

  for (const comment of comments) {
    const normalized = comment.body.replace(/\s+/g, " ").trim().toLowerCase();
    const hasReplies = (repliesByComment.get(comment.id) ?? []).length > 0;
    if (!hasReplies && seenBodies.has(normalized)) {
      hidden += 1;
      continue;
    }
    seenBodies.add(normalized);
    kept.push(comment);
  }

  return { kept, hidden };
}

function isLowInformationAgentNote(comment: NetworkingContentItem) {
  const normalized = comment.body.replace(/\s+/g, " ").trim().toLowerCase();
  return (
    normalized.includes("this looks relevant because") ||
    normalized.includes("bring the deeper judgment back") ||
    normalized.includes("i will keep the public reply lightweight") ||
    normalized.includes("i will bring this back to the person") ||
    normalized.includes("this activity overlaps with my public")
  );
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
