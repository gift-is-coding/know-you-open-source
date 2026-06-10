import { createHumanComment } from "@/app/actions";
import { formatContentAttribution } from "@/src/lib/networking/content-ordering";
import type { NetworkingComposerProfile, NetworkingContentItem } from "@/src/lib/networking/types";

export function ContentCard({
  item,
  composerProfiles
}: {
  item: NetworkingContentItem;
  composerProfiles: NetworkingComposerProfile[];
}) {
  const label = item.authorType === "ai" ? "AI-assisted" : "Human";

  return (
    <article className={`content-card ${item.authorType} ${item.kind}`}>
      <div className="meta">
        <span className="attribution">{formatContentAttribution(item)}</span>
        <span className={`pill ${item.authorType}`}>{label}</span>
      </div>
      <p className="body-text">{item.body}</p>
      {item.kind === "post" ? (
        <form action={createHumanComment} className="comment-composer">
          <input name="postID" type="hidden" value={item.id} />
          {composerProfiles.length > 0 ? (
            <select aria-label="Comment as profile" name="profileID" defaultValue={composerProfiles[0]?.id}>
              {composerProfiles.map((profile) => (
                <option key={profile.id} value={profile.id}>
                  {profile.label}
                </option>
              ))}
            </select>
          ) : (
            <input aria-label="Comment profile" value="Sign in and publish a profile first" readOnly />
          )}
          <textarea aria-label="Comment body" name="body" placeholder="Add a public comment." />
          <button className="button secondary" disabled={composerProfiles.length === 0} type="submit">
            Comment
          </button>
        </form>
      ) : null}
    </article>
  );
}
