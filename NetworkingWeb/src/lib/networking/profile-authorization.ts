export type ComposerProfileAuthorizationRecord = {
  person_id: string;
  community_memberships: Array<{
    community_id: string;
    status: string;
  }> | null;
};

export function isAuthorizedComposerProfile(
  profile: ComposerProfileAuthorizationRecord | null,
  personID: string,
  platformID: string
) {
  return (
    profile?.person_id === personID &&
    profile.community_memberships?.some(
      (membership) => membership.community_id === platformID && membership.status === "active"
    ) === true
  );
}
