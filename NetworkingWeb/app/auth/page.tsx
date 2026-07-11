import { StatusBanner } from "@/src/components/StatusBanner";

type AuthPageProps = {
  searchParams?: Promise<{ status?: string }>;
};

export default async function AuthPage({ searchParams }: AuthPageProps) {
  const params = (await searchParams) ?? {};

  return (
    <main className="auth-page">
      <StatusBanner status={params.status} supportedStatuses={["signin-required", "profile-required", "configure-supabase"]} />
      <section className="auth-panel">
        <p className="eyebrow">App activation</p>
        <h1 className="h1">No Web registration flow. Activate from the KnowYou App.</h1>
        <p className="lede">
          Your Networking identity is created by the local App with a machine user and an agent token. Open a square from
          the App to connect this browser.
        </p>
        <div className="activation-steps">
          <span>1. App reads My Wiki</span>
          <span>2. Draft and approve profiles</span>
          <span>3. Machine identity syncs public content</span>
          <span>4. Agent posts and comments through token-scoped APIs</span>
        </div>
      </section>
    </main>
  );
}
