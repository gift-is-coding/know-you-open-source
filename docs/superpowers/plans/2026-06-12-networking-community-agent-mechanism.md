# Networking Community Agent Mechanism Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an end-to-end local Networking community loop where pre-generated profiles join communities and automatically comment as AI-labeled agents.

**Architecture:** Keep Supabase paths intact, but replace fixture-only local mode with a demo state store plus a deterministic local agent loop. The loop reads community memberships and posts, filters relevant candidates, writes AI comments, and records agent activity without exposing private My Wiki evidence.

**Tech Stack:** Next.js 16, React 19, TypeScript, Vitest, local JSON demo storage, existing NetworkingWeb Supabase interfaces.

---

### Task 1: Community Agent Domain Tests

**Files:**
- Create: `NetworkingWeb/src/lib/networking/community-agent-loop.test.ts`
- Create: `NetworkingWeb/src/lib/networking/community-agent-loop.ts`

- [ ] **Step 1: Write failing tests**

```ts
import { describe, expect, it } from "vitest";
import { runCommunityAgentLoop } from "./community-agent-loop";
import type { NetworkingContentItem, NetworkingProfile } from "./types";

const shuhanJobs: NetworkingProfile = {
  id: "profile-shuhan-jobs",
  personName: "林书涵",
  label: "职业/求职",
  slug: "jobs",
  scenarioID: "jobs",
  platformIDs: ["knowyou-jobs"],
  summary: "做 KnowYou、agent runtime、SwiftUI、Next.js 和 Supabase。"
};

const shuhanFriends: NetworkingProfile = {
  id: "profile-shuhan-friends",
  personName: "林书涵",
  label: "认识新朋友",
  slug: "friends",
  scenarioID: "friends",
  platformIDs: ["knowyou-friends"],
  summary: "喜欢摄影展、城市散步、电影和小范围聊天。"
};

const posts: NetworkingContentItem[] = [
  {
    id: "post-career",
    kind: "post",
    platformID: "knowyou-jobs",
    authorType: "human",
    body: "找一个会做 agent runtime、Next.js 和 Supabase 的 founding engineer。",
    createdAt: "2026-06-12T08:00:00.000Z",
    person: { id: "person-a", displayName: "周思齐", handle: "siqi" },
    profile: { id: "profile-siqi-jobs", label: "职业/求职", slug: "jobs", platformIDs: ["knowyou-jobs"] }
  },
  {
    id: "post-friends",
    kind: "post",
    platformID: "knowyou-friends",
    authorType: "human",
    body: "周末想找人一起看摄影展，然后城市散步。",
    createdAt: "2026-06-12T09:00:00.000Z",
    person: { id: "person-b", displayName: "许安然", handle: "anran" },
    profile: { id: "profile-anran-friends", label: "认识新朋友", slug: "friends", platformIDs: ["knowyou-friends"] }
  }
];

describe("runCommunityAgentLoop", () => {
  it("auto-comments only when a joined profile matches a post in the same community", () => {
    const result = runCommunityAgentLoop({
      now: new Date("2026-06-12T10:00:00.000Z"),
      people: [{ id: "person-shuhan", displayName: "林书涵", handle: "shuhan" }],
      profiles: [shuhanJobs],
      memberships: [{ communityID: "knowyou-jobs", profileID: "profile-shuhan-jobs", personID: "person-shuhan", status: "active" }],
      items: posts
    });

    expect(result.items.some((item) => item.kind === "comment" && item.parentPostID === "post-career" && item.authorType === "ai")).toBe(true);
    expect(result.items.some((item) => item.kind === "comment" && item.parentPostID === "post-friends" && item.authorType === "ai")).toBe(false);
  });

  it("does not duplicate an agent comment for the same profile and post", () => {
    const first = runCommunityAgentLoop({
      now: new Date("2026-06-12T10:00:00.000Z"),
      people: [{ id: "person-shuhan", displayName: "林书涵", handle: "shuhan" }],
      profiles: [shuhanJobs],
      memberships: [{ communityID: "knowyou-jobs", profileID: "profile-shuhan-jobs", personID: "person-shuhan", status: "active" }],
      items: posts
    });

    const second = runCommunityAgentLoop({
      now: new Date("2026-06-12T10:05:00.000Z"),
      people: [{ id: "person-shuhan", displayName: "林书涵", handle: "shuhan" }],
      profiles: [shuhanJobs],
      memberships: [{ communityID: "knowyou-jobs", profileID: "profile-shuhan-jobs", personID: "person-shuhan", status: "active" }],
      items: first.items
    });

    expect(second.items.filter((item) => item.kind === "comment" && item.parentPostID === "post-career" && item.profile.id === "profile-shuhan-jobs")).toHaveLength(1);
  });

  it("records activity for scanned communities and auto comments", () => {
    const result = runCommunityAgentLoop({
      now: new Date("2026-06-12T10:00:00.000Z"),
      people: [{ id: "person-shuhan", displayName: "林书涵", handle: "shuhan" }],
      profiles: [shuhanJobs, shuhanFriends],
      memberships: [
        { communityID: "knowyou-jobs", profileID: "profile-shuhan-jobs", personID: "person-shuhan", status: "active" },
        { communityID: "knowyou-friends", profileID: "profile-shuhan-friends", personID: "person-shuhan", status: "active" }
      ],
      items: posts
    });

    expect(result.activities.map((activity) => activity.activityType)).toEqual(["auto_comment", "auto_comment"]);
    expect(result.activities.map((activity) => activity.platformID)).toEqual(["knowyou-jobs", "knowyou-friends"]);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd NetworkingWeb && npm test -- --run src/lib/networking/community-agent-loop.test.ts`

Expected: FAIL because `community-agent-loop.ts` does not exist.

- [ ] **Step 3: Implement minimal domain loop**

Create `community-agent-loop.ts` with types for `NetworkingCommunityMembership`, `NetworkingAgentActivity`, `CommunityAgentLoopInput`, and `runCommunityAgentLoop`. Implement deterministic matching from profile summary plus post body tokens, community isolation, duplicate prevention, AI comment creation, and activity records.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd NetworkingWeb && npm test -- --run src/lib/networking/community-agent-loop.test.ts`

Expected: PASS.

### Task 2: Local Demo State Store

**Files:**
- Create: `NetworkingWeb/src/lib/networking/local-demo-state.test.ts`
- Create: `NetworkingWeb/src/lib/networking/local-demo-state.ts`
- Modify: `NetworkingWeb/src/lib/networking/fixtures.ts`

- [ ] **Step 1: Write failing tests**

Add tests that `bootstrapLocalDemoState()` includes two communities, multiple mock profile-agents, active memberships, and that `getLocalDemoNetwork()` returns items after the agent loop has written AI comments.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd NetworkingWeb && npm test -- --run src/lib/networking/local-demo-state.test.ts`

Expected: FAIL because the store does not exist.

- [ ] **Step 3: Implement local demo state**

Implement a JSON-compatible state with people, profiles, memberships, items, and activities. The store should initialize from current fixtures, add at least two other mock people/profiles, run `runCommunityAgentLoop`, and expose `getLocalDemoNetwork()`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd NetworkingWeb && npm test -- --run src/lib/networking/local-demo-state.test.ts`

Expected: PASS.

### Task 3: Wire Local Mode Into Data Layer and UI

**Files:**
- Modify: `NetworkingWeb/src/lib/networking/supabase-data.ts`
- Modify: `NetworkingWeb/src/lib/networking/types.ts`
- Modify: `NetworkingWeb/app/page.tsx`
- Modify: `NetworkingWeb/app/globals.css`
- Modify: `NetworkingWeb/README.md`

- [ ] **Step 1: Update data layer tests**

Extend existing tests or add focused tests to assert that local mode returns AI comments created by the agent loop and exposes activity summaries.

- [ ] **Step 2: Implement data-layer wiring**

When `hasSupabaseEnv()` is false, `getPublicSquareItems`, `getPublicProfilePage`, and `getComposerProfiles` should read from `getLocalDemoNetwork()`.

- [ ] **Step 3: Render agent activity and membership state**

Show active profile-agent membership and recent auto comments in the page panel. Keep AI labels visible as `person + profile + AI`.

- [ ] **Step 4: Update README**

Document that local mode is now a runnable demo network with automatic profile-agent comments, not just static fixtures.

### Task 4: Verification and Local Launch

**Files:**
- No required source edits unless verification reveals failures.

- [ ] **Step 1: Run focused tests**

Run:

```bash
cd NetworkingWeb
npm test -- --run src/lib/networking/community-agent-loop.test.ts src/lib/networking/local-demo-state.test.ts src/lib/networking/content-ordering.test.ts src/lib/networking/platforms.test.ts
```

Expected: PASS.

- [ ] **Step 2: Run typecheck and build**

Run:

```bash
cd NetworkingWeb
npm run typecheck
npm run build
```

Expected: PASS.

- [ ] **Step 3: Start local web server**

Run: `cd NetworkingWeb && npm run dev -- --hostname 127.0.0.1 --port 3027`

Expected: dev server listens on `http://127.0.0.1:3027`.

- [ ] **Step 4: Browser verification**

Open `http://127.0.0.1:3027/?platform=knowyou-jobs` and `http://127.0.0.1:3027/?platform=knowyou-friends`. Confirm both pages show active profile-agent memberships, AI-labeled comments, and agent activity.
