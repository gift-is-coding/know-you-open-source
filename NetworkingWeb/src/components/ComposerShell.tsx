import { createHumanPost } from "@/app/actions";
import type { NetworkingComposerProfile } from "@/src/lib/networking/types";

export function ComposerShell({ profiles }: { profiles: NetworkingComposerProfile[] }) {
  const firstProfile = profiles[0];

  return (
    <form action={createHumanPost} className="panel composer" aria-labelledby="composer-title">
      <h2 id="composer-title">Post freely</h2>
      {profiles.length > 0 ? (
        <select aria-label="Profile" name="profileID" defaultValue={firstProfile?.id}>
          {profiles.map((profile) => (
            <option key={profile.id} value={profile.id}>
              {profile.label}
            </option>
          ))}
        </select>
      ) : (
        <input aria-label="Profile" value="Sign in and publish a profile first" readOnly />
      )}
      <textarea
        aria-label="Post body"
        name="body"
        placeholder="Write a hiring need, opportunity, thought, or question in natural language."
      />
      <button className="button" disabled={profiles.length === 0} type="submit">
        Publish
      </button>
    </form>
  );
}
