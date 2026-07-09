export interface NetworkingTableContract {
  name: string;
  rls: boolean;
  columns: string[];
}

export const networkingSchemaContract = {
  tables: [
    {
      name: "communities",
      rls: true,
      columns: ["id", "display_name", "description", "scenario_id", "created_at"]
    },
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
        "parent_comment_id",
        "person_id",
        "profile_id",
        "platform_id",
        "author_type",
        "body",
        "is_public",
        "client_decision_id",
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
        "reason_code",
        "metadata",
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
        "scope",
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
        "actor_person_id",
        "actor_profile_id",
        "read_at",
        "created_at"
      ]
    },
    {
      name: "community_memberships",
      rls: true,
      columns: [
        "id",
        "community_id",
        "person_id",
        "profile_id",
        "status",
        "policy",
        "joined_at",
        "last_seen_at",
        "last_heartbeat_at",
        "last_candidate_seen_at"
      ]
    },
    {
      name: "candidate_edges",
      rls: true,
      columns: [
        "id",
        "person_id",
        "profile_id",
        "platform_id",
        "source",
        "public_reference_type",
        "public_reference_id",
        "post_id",
        "comment_id",
        "reason_codes",
        "public_evidence",
        "score",
        "status",
        "expires_at",
        "created_at"
      ]
    },
    {
      name: "agent_decisions",
      rls: true,
      columns: [
        "id",
        "person_id",
        "profile_id",
        "platform_id",
        "action",
        "public_reference_type",
        "public_reference_id",
        "post_id",
        "comment_id",
        "public_summary",
        "reason_codes",
        "client_decision_id",
        "created_at"
      ]
    }
  ] satisfies NetworkingTableContract[],
  authModes: ["supabaseMachineUser"],
  privateFieldsStayLocal: ["myWikiEvidence", "profileDraft", "matchReason"],
  policySummary:
    "Public read is limited to published profiles and public posts/comments. Writes require an authenticated owner or a local KnowYou agent acting for that owner. App activation uses a Supabase machine user, which writes as authenticated owner."
};
