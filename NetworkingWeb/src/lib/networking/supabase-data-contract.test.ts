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
});
