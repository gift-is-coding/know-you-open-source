import { readFileSync } from "node:fs";
import { parse } from "comment-json";
import { describe, expect, it } from "vitest";

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
      "opennextjs-cloudflare build && opennextjs-cloudflare deploy"
    );
    expect(wranglerConfig.main).toBe(".open-next/worker.js");
    expect(wranglerConfig.assets.directory).toBe(".open-next/assets");
    expect(wranglerConfig.compatibility_flags).toContain("nodejs_compat");
  });

  it("routes production traffic through the requested hostname", () => {
    expect(wranglerConfig.routes).toContainEqual({
      pattern: "networking.giiift.site",
      custom_domain: true
    });
    expect(wranglerConfig.vars?.NETWORKING_E2E_STORE).toBeUndefined();
  });
});
