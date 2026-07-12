import type { NetworkingAgentAutonomyMode, NetworkingCommunityPolicy } from "./community-agent-loop";

export interface ResolvedNetworkingCommunityPolicy extends Required<NetworkingCommunityPolicy> {
  minimumCommentScore: number;
  minimumCommentCharacters: number;
}

type PolicyPreset = Omit<
  ResolvedNetworkingCommunityPolicy,
  "minimumCommentScore" | "minimumCommentCharacters" | "dailyAutoCommentLimit" | "riskyContentAction"
>;

const presets: Record<NetworkingAgentAutonomyMode, PolicyPreset> = {
  conservative: {
    autonomyMode: "conservative",
    autoPost: true,
    autoComment: true,
    autoReply: true,
    dailyAutoPostLimit: 1,
    dailyProactiveCommentLimit: 4,
    dailyAutoReplyLimit: 8,
    heartbeatMinMinutes: 240,
    heartbeatMaxMinutes: 360,
    maxAutonomousThreadTurns: 3,
    unfamiliarPersonCooldownHours: 72,
    commentCooldownSeconds: 45
  },
  balanced: {
    autonomyMode: "balanced",
    autoPost: true,
    autoComment: true,
    autoReply: true,
    dailyAutoPostLimit: 2,
    dailyProactiveCommentLimit: 10,
    dailyAutoReplyLimit: 20,
    heartbeatMinMinutes: 120,
    heartbeatMaxMinutes: 180,
    maxAutonomousThreadTurns: 5,
    unfamiliarPersonCooldownHours: 48,
    commentCooldownSeconds: 30
  },
  active: {
    autonomyMode: "active",
    autoPost: true,
    autoComment: true,
    autoReply: true,
    dailyAutoPostLimit: 4,
    dailyProactiveCommentLimit: 20,
    dailyAutoReplyLimit: 40,
    heartbeatMinMinutes: 60,
    heartbeatMaxMinutes: 120,
    maxAutonomousThreadTurns: 8,
    unfamiliarPersonCooldownHours: 24,
    commentCooldownSeconds: 20
  }
};

export function resolveAgentAutonomyPolicy(
  policy: Partial<NetworkingCommunityPolicy> | undefined,
  platformID: string
): ResolvedNetworkingCommunityPolicy {
  const mode = policy?.autonomyMode ?? "balanced";
  const preset = presets[mode];
  const legacyCommentLimit = policy?.dailyAutoCommentLimit;
  const dailyProactiveCommentLimit = policy?.dailyProactiveCommentLimit ?? legacyCommentLimit ?? preset.dailyProactiveCommentLimit;

  return {
    ...preset,
    ...policy,
    autonomyMode: mode,
    dailyProactiveCommentLimit,
    dailyAutoCommentLimit: legacyCommentLimit ?? dailyProactiveCommentLimit,
    riskyContentAction: "save_for_human",
    minimumCommentScore: platformID === "knowyou-jobs" ? 2 : 1,
    minimumCommentCharacters: platformID === "knowyou-jobs" ? 80 : 28
  };
}
