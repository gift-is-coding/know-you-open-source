import { describe, expect, it } from "vitest";
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";

const checkedRoots = [
  "app",
  "src/components",
  "src/lib/networking/platforms.ts",
  "src/lib/networking/supabase-data.ts",
  "src/lib/networking/agent-home.ts"
];

describe("networking web copy contract", () => {
  it("keeps the public Web UI in English", () => {
    const offenders = checkedRoots.flatMap((root) => collectSourceFiles(join(process.cwd(), root)))
      .flatMap((file) => {
        const source = readFileSync(file, "utf8");
        const lines = source.split("\n");
        return lines.flatMap((line, index) => /[\u4e00-\u9fff]/.test(line)
          ? [`${relative(process.cwd(), file)}:${index + 1}:${line.trim()}`]
          : []
        );
      });

    expect(offenders).toEqual([]);
  });

  it("uses one compact community switcher instead of duplicate platform cards", () => {
    const pageSource = readFileSync(join(process.cwd(), "app/page.tsx"), "utf8");
    const cssSource = readFileSync(join(process.cwd(), "app/globals.css"), "utf8");

    expect(pageSource).toContain("community-switcher");
    expect(pageSource).not.toContain("platform-tabs");
    expect(cssSource).toContain(".community-switcher");
    expect(cssSource).not.toContain(".platform-tabs");
  });

  it("keeps the primary navigation app-first with no demo profile or editable drafts links", () => {
    const layoutSource = readFileSync(join(process.cwd(), "app/layout.tsx"), "utf8");

    expect(layoutSource).toContain("IdentityChip");
    expect(layoutSource).toContain('href="/"');
    expect(layoutSource).not.toContain("/profiles/shuhan");
    expect(layoutSource).not.toContain("/profiles/me");
    expect(layoutSource).not.toContain("My Profiles");
  });

  it("makes /profiles/me read-only instead of a web profile editor", () => {
    const actionsSource = readFileSync(join(process.cwd(), "app/actions.ts"), "utf8");
    const profileMeSource = readFileSync(join(process.cwd(), "app/profiles/me/page.tsx"), "utf8");

    expect(actionsSource).not.toContain("export async function saveProfile");
    expect(actionsSource).not.toContain("/profiles/me?status=");
    expect(profileMeSource).not.toContain("saveProfile");
    expect(profileMeSource).not.toContain("<form");
    expect(profileMeSource).toContain("read-only");
  });

  it("uses a client-side square tab component so community switches do not server-render the whole page", () => {
    const pageSource = readFileSync(join(process.cwd(), "app/page.tsx"), "utf8");
    const squareTabsSource = readFileSync(join(process.cwd(), "src/components/SquareTabs.tsx"), "utf8");

    expect(pageSource).toContain("SquareTabs");
    expect(pageSource).toContain("Promise.all");
    expect(pageSource).toContain("knowyou-jobs");
    expect(pageSource).toContain("knowyou-friends");
    expect(squareTabsSource).toContain('"use client"');
    expect(squareTabsSource).toContain("router.replace");
    expect(squareTabsSource).not.toContain("<Link");
  });

  it("implements App handoff auth by setting the Supabase session from a URL fragment and clearing it", () => {
    const handoffSource = readFileSync(join(process.cwd(), "app/auth/handoff/page.tsx"), "utf8");

    expect(handoffSource).toContain('"use client"');
    expect(handoffSource).toContain("setSession");
    expect(handoffSource).toContain("history.replaceState");
    expect(handoffSource).toContain("access_token");
    expect(handoffSource).toContain("refresh_token");
  });

  it("keeps /auth as an App-first explanation with no anonymous debug sign-in", () => {
    const authSource = readFileSync(join(process.cwd(), "app/auth/page.tsx"), "utf8");

    expect(authSource).toContain("machine user");
    expect(authSource).not.toContain("signInAnonymously");
    expect(authSource).not.toContain("Debug: create anonymous identity");
  });

  it("filters legacy low-information agent notes out of the public feed", () => {
    const pageSource = readFileSync(join(process.cwd(), "app/page.tsx"), "utf8");

    expect(pageSource).toContain("isLowInformationAgentNote");
    expect(pageSource).toContain("this looks relevant because");
    expect(pageSource).toContain("i will keep the public reply lightweight");
  });
});

function collectSourceFiles(path: string): string[] {
  if (!statSync(path).isDirectory()) {
    return [path];
  }

  return readdirSync(path)
    .flatMap((entry) => collectSourceFiles(join(path, entry)))
    .filter((file) => /\.(css|tsx?|jsx?)$/.test(file));
}
