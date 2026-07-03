import { describe, expect, it } from "vitest";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

const appDir = join(process.cwd(), "app");

describe("agent route contract", () => {
  it("exposes Moltbook-style profile-agent API route handlers", () => {
    const routeFiles = [
      "api/agent/home/route.ts",
      "api/agent/communities/[communityID]/candidates/route.ts",
      "api/agent/comments/route.ts",
      "api/agent/posts/route.ts",
      "api/agent/decisions/route.ts",
      "api/agent/search/route.ts",
      "api/agent/events/read/route.ts",
      "api/community-memberships/route.ts"
    ];

    for (const file of routeFiles) {
      expect(existsSync(join(appDir, file)), file).toBe(true);
    }
  });

  it("requires bearer token auth on agent write/read endpoints", () => {
    const files = [
      "api/agent/home/route.ts",
      "api/agent/communities/[communityID]/candidates/route.ts",
      "api/agent/comments/route.ts",
      "api/agent/posts/route.ts",
      "api/agent/decisions/route.ts",
      "api/agent/search/route.ts",
      "api/agent/events/read/route.ts"
    ];

    for (const file of files) {
      const source = readFileSync(join(appDir, file), "utf8");
      expect(source).toContain("Response(request");
    }

    const helper = readFileSync(join(process.cwd(), "src/lib/networking/agent-api.ts"), "utf8");
    expect(helper).toContain("getAgentBearerToken");
    expect(helper).toContain("401");
  });

  it("documents decision recording and bounded search as agent actions, not full-site crawling", () => {
    const helper = readFileSync(join(process.cwd(), "src/lib/networking/agent-api.ts"), "utf8");

    expect(helper).toContain("recordAgentDecisionResponse");
    expect(helper).toContain("searchAgentPublicSquareResponse");
    expect(helper).toContain("save_for_human");
    expect(helper).toContain("express_interest");
    expect(helper).toContain("comment_proposed");
    expect(helper).toContain("limit");
    expect(helper).toContain("bounded public search");
  });
});
