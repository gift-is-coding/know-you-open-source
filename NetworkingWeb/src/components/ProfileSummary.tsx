import type { NetworkingProfilePage } from "@/src/lib/networking/types";

export function ProfileSummary({ page }: { page: NetworkingProfilePage }) {
  const heading = `${page.person.displayName}'s profiles`;

  return (
    <section className="panel" aria-labelledby="profile-summary-title">
      <h2 id="profile-summary-title">{heading}</h2>
      <div className="profile-list">
        {page.profiles.map((profile) => (
          <span className="pill human" key={profile.id}>
            {profile.label}
          </span>
        ))}
      </div>
    </section>
  );
}
