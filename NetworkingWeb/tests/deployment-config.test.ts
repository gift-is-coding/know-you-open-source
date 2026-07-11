import { readFileSync } from "node:fs";
import { parse } from "comment-json";
import { describe, expect, it } from "vitest";
import { spawnSync } from "node:child_process";

interface DeploymentConfig {
  main: string;
  assets: { directory: string };
  compatibility_flags: string[];
  routes: Array<{ pattern: string; custom_domain: boolean }>;
  vars?: Record<string, string>;
}

const packageJSON = JSON.parse(readFileSync(new URL("../package.json", import.meta.url), "utf8"));
const wranglerConfig = parse(
  readFileSync(new URL("../wrangler.jsonc", import.meta.url), "utf8"),
  undefined,
  true
) as unknown as DeploymentConfig;

describe("production deployment configuration", () => {
  it("builds through the Cloudflare OpenNext adapter", () => {
    expect(packageJSON.scripts["deploy:cloudflare"]).toBe(
      "node scripts/require-supabase-env.mjs production && opennextjs-cloudflare build && opennextjs-cloudflare deploy"
    );
    expect(wranglerConfig.main).toBe(".open-next/worker.js");
    expect(wranglerConfig.assets.directory).toBe(".open-next/assets");
    expect(wranglerConfig.compatibility_flags).toContain("nodejs_compat");
    expect(packageJSON.scripts.build).toBe("node scripts/require-supabase-env.mjs production && next build");
    expect(packageJSON.scripts["preview:cloudflare"]).toContain("require-supabase-env.mjs production");
  });

  it("fails deployment before building when Supabase env is missing", () => {
    const result = spawnSync(process.execPath, ["scripts/require-supabase-env.mjs", "production"], {
      cwd: new URL("..", import.meta.url),
      env: { NODE_ENV: "test", PATH: process.env.PATH ?? "", NETWORKING_IGNORE_ENV_LOCAL: "1" },
      encoding: "utf8"
    });

    expect(result.status).not.toBe(0);
    expect(result.stderr).toContain("NEXT_PUBLIC_SUPABASE_URL");
  });

  it("rejects the production Supabase project for local development", () => {
    const result = spawnSync(process.execPath, ["scripts/require-supabase-env.mjs", "development"], {
      cwd: new URL("..", import.meta.url),
      env: {
        NODE_ENV: "test",
        PATH: process.env.PATH ?? "",
        NEXT_PUBLIC_SUPABASE_URL: "https://jevgtiamxlkucjqpbekn.supabase.co",
        NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: "sb_publishable_test"
      },
      encoding: "utf8"
    });

    expect(result.status).not.toBe(0);
    expect(result.stderr).toContain("refusing production Supabase for local development");
  });

  it("makes production Supabase configuration fail closed in server code", () => {
    const envSource = readFileSync(new URL("../src/lib/supabase/env.ts", import.meta.url), "utf8");
    expect(envSource).toContain("requireProductionSupabaseEnv");
    expect(envSource).toContain('process.env.NODE_ENV === "production"');
    expect(envSource).toContain("throw new Error");
  });

  it("routes production traffic through the requested hostname", () => {
    expect(wranglerConfig.routes).toContainEqual({
      pattern: "networking.giiift.site",
      custom_domain: true
    });
    expect(wranglerConfig.vars?.NETWORKING_E2E_STORE).toBeUndefined();
  });
});
