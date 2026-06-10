export type NetworkingAuthorType = "human" | "ai";
export type NetworkingContentKind = "post" | "comment";
export type NetworkingAvatarStyle = "initials" | "gradient";

export interface NetworkingPlatform {
  id: string;
  displayName: string;
  shortName: string;
  scenarioID: string;
  description: string;
  accent: string;
}

export interface NetworkingPerson {
  id: string;
  displayName: string;
  handle: string;
  initial?: string;
  tagline?: string;
}

export interface NetworkingProfile {
  id: string;
  personName?: string;
  label: string;
  slug: string;
  summary?: string;
  published?: boolean;
  englishLabel?: string;
  avatarLetter?: string;
  avatarBg?: string;
  avatarSeed?: string;
  avatarStyle?: NetworkingAvatarStyle;
  scenarioID?: string;
  scenarioDescription?: string;
  platformIDs?: string[];
  autoUpdate?: boolean;
}

export interface NetworkingContentItem {
  id: string;
  kind: NetworkingContentKind;
  platformID: string;
  authorType: NetworkingAuthorType;
  body: string;
  createdAt: string;
  person: NetworkingPerson;
  profile: NetworkingProfile;
  parentPostID?: string;
  topic?: string;
  timestampLabel?: string;
  agentLabel?: string;
}

export interface NetworkingProfilePage {
  person: NetworkingPerson;
  profiles: NetworkingProfile[];
}

export interface NetworkingComposerProfile {
  id: string;
  label: string;
  platformIDs?: string[];
}

export interface NetworkingProfileWorkspace {
  person?: NetworkingPerson;
  profiles: NetworkingProfile[];
  needsSignIn: boolean;
  usesFixtureData: boolean;
}
