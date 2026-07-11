import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const source = readFileSync(join(process.cwd(), "src/lib/networking/supabase-data.ts"), "utf8");

describe("networking Supabase data contract", () => {
  it("does not mask real Supabase public-square failures with fixture content", () => {
    const publicSquareStart = source.indexOf("export async function getPublicSquareItems");
    const publicSquareEnd = source.indexOf("export async function getPublicProfilePageForPlatform");
    expect(publicSquareStart).toBeGreaterThan(-1);
    expect(publicSquareEnd).toBeGreaterThan(publicSquareStart);

    const publicSquareSource = source.slice(publicSquareStart, publicSquareEnd);
    expect(publicSquareSource).not.toContain("publicSquareFixture");
    expect(publicSquareSource).toContain("return [];");
    expect(publicSquareSource).toContain("return items;");
  });

  it("uses demo data only when Supabase env is absent, never when configured tables are empty", () => {
    const publicSquareStart = source.indexOf("export async function getPublicSquareItems");
    const publicSquareEnd = source.indexOf("export async function getPublicProfilePageForPlatform");
    const publicSquareSource = source.slice(publicSquareStart, publicSquareEnd);

    expect(publicSquareSource).toContain("if (!hasSupabaseEnv())");
    expect(publicSquareSource).toContain("getLocalDemoNetwork()");
    expect(publicSquareSource).not.toContain("items.length > 0 ? items");
    expect(publicSquareSource).not.toContain("?? publicSquareFixture");
  });

  it("uses the current community to choose the public profile shown on the square", () => {
    expect(source).toContain("getPublicProfilePageForPlatform");
    expect(source).toContain(".contains(\"platform_ids\", [normalizedPlatformID])");
    expect(source).toContain(".eq(\"person_id\", firstProfile.person_id)");
    expect(source).toContain("emptyProfilePage(normalizedPlatformID)");
  });

  it("scopes the agent home preview to the signed-in viewer instead of any active member", () => {
    const agentHomeStart = source.indexOf("export async function getAgentHomePreview");
    const agentHomeEnd = source.indexOf("async function loadMyProfileWorkspace");
    expect(agentHomeStart).toBeGreaterThan(-1);
    expect(agentHomeEnd).toBeGreaterThan(agentHomeStart);

    const agentHomeSource = source.slice(agentHomeStart, agentHomeEnd);
    expect(agentHomeSource).toContain("getMyProfileWorkspace()");
    expect(agentHomeSource).toContain(".eq(\"person_id\", workspace.person.id)");
    expect(agentHomeSource).toContain(".eq(\"community_id\", normalizedPlatformID)");
    expect(agentHomeSource).not.toContain(".eq(\"status\", \"active\")\n      .limit(1)");
  });

  it("shows composer profiles only for the viewer's active membership in the selected community", () => {
    const start = source.indexOf("export async function getComposerProfiles");
    const end = source.indexOf("export async function getViewerProfilePageForPlatform");
    const composerSource = source.slice(start, end);

    expect(composerSource).toContain('.from("community_memberships")');
    expect(composerSource).toContain("getMyProfileWorkspace()");
    expect(composerSource).toContain('.eq("community_id", normalizedPlatformID)');
    expect(composerSource).toContain('.eq("person_id", workspace.person.id)');
    expect(composerSource).toContain('.eq("status", "active")');
    expect(composerSource).toContain('activeProfileIDs.includes(profile.id)');
  });

  it("memoizes the signed-in workspace once per server render", () => {
    expect(source).toContain('import { cache } from "react"');
    expect(source).toContain("async function loadMyProfileWorkspace");
    expect(source).toContain("export const getMyProfileWorkspace = cache(loadMyProfileWorkspace)");
  });
});
