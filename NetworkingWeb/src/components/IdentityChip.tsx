import Link from "next/link";
import { getMyProfileWorkspace } from "@/src/lib/networking/supabase-data";

export async function IdentityChip() {
  const workspace = await getMyProfileWorkspace();
  const person = workspace.person;
  const initial = person?.initial ?? person?.displayName.slice(0, 1) ?? "K";

  if (workspace.needsSignIn || !person) {
    return (
      <Link className="me-chip" href="/auth">
        <span className="avatar">K</span>
        <span className="name">Open App</span>
      </Link>
    );
  }

  return (
    <Link className="me-chip" href={`/profiles/${person.handle}`}>
      <span className="avatar">{initial}</span>
      <span className="name">{person.displayName}</span>
    </Link>
  );
}
