type StatusBannerProps = {
  status?: string;
  supportedStatuses?: string[];
};

const statusMessages: Record<string, string> = {
  "signin-required": "Open a square from the KnowYou App to sign this browser in before posting.",
  "profile-required": "Approve and sync a profile for this community in the KnowYou App before posting.",
  "configure-supabase": "Networking Web needs the Supabase environment before public posting is available.",
  "profile-not-authorized": "That profile cannot post in this community. Reopen the square from the KnowYou App."
};

export function StatusBanner({ status, supportedStatuses }: StatusBannerProps) {
  const supported = supportedStatuses ?? Object.keys(statusMessages);
  if (!status || !supported.includes(status)) {
    return null;
  }

  const message = statusMessages[status];
  if (!message) {
    return null;
  }

  return (
    <div className="status-banner" role="status">
      {message}
    </div>
  );
}
