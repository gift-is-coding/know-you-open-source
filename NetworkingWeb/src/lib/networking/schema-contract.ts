export interface NetworkingTableContract {
  name: string;
  rls: boolean;
  columns: string[];
}

export const networkingSchemaContract = {
  tables: [
    {
      name: "people",
      rls: true,
      columns: ["id", "user_id", "display_name", "handle", "created_at", "updated_at"]
    },
    {
      name: "profiles",
      rls: true,
      columns: [
        "id",
        "person_id",
        "slug",
        "label",
        "scenario_id",
        "scenario_description",
        "avatar_seed",
        "avatar_style",
        "platform_ids",
        "summary",
        "body",
        "is_published",
        "created_at",
        "updated_at"
      ]
    },
    {
      name: "posts",
      rls: true,
      columns: [
        "id",
        "person_id",
        "profile_id",
        "platform_id",
        "author_type",
        "body",
        "is_public",
        "created_at",
        "updated_at"
      ]
    },
    {
      name: "comments",
      rls: true,
      columns: [
        "id",
        "post_id",
        "person_id",
        "profile_id",
        "platform_id",
        "author_type",
        "body",
        "is_public",
        "created_at",
        "updated_at"
      ]
    },
    {
      name: "agent_activity",
      rls: true,
      columns: [
        "id",
        "person_id",
        "profile_id",
        "platform_id",
        "activity_type",
        "public_reference_type",
        "public_reference_id",
        "summary",
        "created_at"
      ]
    },
    {
      name: "agent_tokens",
      rls: true,
      columns: [
        "id",
        "person_id",
        "profile_id",
        "label",
        "token_hash",
        "expires_at",
        "revoked_at",
        "last_used_at",
        "created_at"
      ]
    },
    {
      name: "public_interaction_events",
      rls: true,
      columns: [
        "id",
        "person_id",
        "profile_id",
        "platform_id",
        "event_type",
        "post_id",
        "comment_id",
        "created_at"
      ]
    }
  ] satisfies NetworkingTableContract[],
  authModes: ["supabaseAnonymous"],
  privateFieldsStayLocal: ["myWikiEvidence", "profileDraft", "matchReason"],
  policySummary:
    "Public read is limited to published profiles and public posts/comments. Writes require an authenticated owner or a local KnowYou agent acting for that owner. App activation uses Supabase anonymous sign-in, which writes as authenticated owner."
};
